const std = @import("std");
const search_marker = @import("search_marker.zig");
const Block = search_marker.Block;
const BlockStore = @import("search_marker.zig").BlockStoreType();
const SENTINEL_LEFT = @import("search_marker.zig").SPECIAL_CLOCK_LEFT;
const SENTINEL_RIGHT = @import("search_marker.zig").SPECIAL_CLOCK_RIGHT;

const Clock = @import("global_clock.zig").MonotonicClock;
const ID = search_marker.ID;

pub const Blocks = *std.ArrayList(Block);

pub const PendingStruct = struct {
    blocks: std.AutoHashMap(ID, *Block),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PendingStruct {
        return .{
            .blocks = std.AutoHashMap(ID, *Block).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn addPending(self: *PendingStruct, block: *Block) !void {
        try self.blocks.put(block.id, block);
        std.log.info("Block {any} added to pending", .{block.id});
    }
};

pub const Updates = struct {
    updates: *std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90),
};

pub const UpdateResult = struct {
    pending: PendingStruct,
};

// TODO: final check for this function, see if are yet to add anything from yjs impl and add
// the base version atleast is ready, tests passing
pub fn apply_update(allocator: std.mem.Allocator, store: *BlockStore, update: Updates) !UpdateResult {
    var result = UpdateResult{
        .pending = PendingStruct.init(allocator),
    };

    var iter = update.updates.iterator();
    while (iter.next()) |entry| {
        const blocks = entry.value_ptr.*;

        for (blocks.items) |block| {
            // Allocate space for this block
            const blk = try store.allocate_block(block);

            std.log.info("Trying Block {s}\n", .{blk.content});

            // Check if we have all dependencies
            if (try store.getMissing(blk) != null) {
                // We're missing updates from this client, add to pending queue
                try result.pending.addPending(blk);
                std.log.info("Block {any} pending on updates from client", .{blk.id});
                continue;
            }

            // Try to integrate
            store.integrate(blk) catch |err| {
                // if failed to integrate this block, add to pending queue
                try result.pending.addPending(blk);
                std.log.err("Integration failed for block {any}: {any}", .{ blk.id, err });
                continue;
            };

            // Update state after successful integration
            try store.updateState(blk);
            std.log.info("Successfully integrated block {any}", .{blk.id});
        }
    }
    return result;
}

const t = std.testing;

fn createTestBlock(allocator: std.mem.Allocator, id: ID, content: []const u8) !*Block {
    const block = try allocator.create(Block);
    block.* = Block.block(id, content);
    return block;
}

test "apply_update: concurrent client updates:in the middle: happy-flow" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Insert first block 'A'
    // TODO: figure out do we update state vector in this flow
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");

    // Get the actual block A (not sentinel)
    const base_block = store.start.?;
    try t.expect(std.mem.eql(u8, base_block.content, "A"));

    const base_blockR = store.start.?.right.?;
    try t.expect(std.mem.eql(u8, base_blockR.content, "B"));

    // Create concurrent blocks
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block B
    const block_b = try createTestBlock(allocator, ID.id(2, 2), "C");
    block_b.* = Block{
        .id = block_b.id,
        .content = "C",
        .left_origin = base_block.id,
        .right_origin = base_blockR.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_b.*);

    // Create block C
    const block_c = try createTestBlock(allocator, ID.id(2, 4), "D");
    block_c.* = Block{
        .id = block_c.id,
        .content = "D",
        .left_origin = base_block.id,
        .right_origin = base_blockR.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_c.*);

    // Setup updates
    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(1, &blocks_list);

    // Apply update
    const result = try apply_update(allocator, &store, .{ .updates = &updates });

    // Verify content
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ACDB", content);
    try t.expect(result.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:at the end: happy-flow" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial document: "AB"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");

    // Get base blocks
    const block_a = store.start.?;
    const block_b = block_a.right.?;

    // Create concurrent blocks to append at the end
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block C: should append after B
    const block_c = try createTestBlock(allocator, ID.id(2, 2), "C");
    block_c.* = Block{
        .id = block_c.id,
        .content = "C",
        .left_origin = block_b.id,
        .right_origin = ID.id(SENTINEL_RIGHT, 2), // Points to end sentinel
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_c.*);

    // Create block D: also appends after B
    const block_d = try createTestBlock(allocator, ID.id(2, 4), "D");
    block_d.* = Block{
        .id = block_d.id,
        .content = "D",
        .left_origin = block_b.id,
        .right_origin = ID.id(SENTINEL_RIGHT, 4),
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_d.*);

    // Setup updates
    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(1, &blocks_list);

    // Apply update
    const result = try apply_update(allocator, &store, .{ .updates = &updates });

    // Verify content - should be ABCD since C has lower client clock than D
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ABCD", content);
    try t.expect(result.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:at the start: happy-flow" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial document: "AB"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");

    // Get base blocks
    const block_a = store.start.?;

    // Create concurrent blocks to insert at start
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block C: insert at start
    const block_c = try createTestBlock(allocator, ID.id(2, 2), "C");
    block_c.* = Block{
        .id = block_c.id,
        .content = "C",
        .left_origin = ID.id(SENTINEL_LEFT, 2), // Points to start sentinel
        .right_origin = block_a.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_c.*);

    // Create block D: also insert at start
    const block_d = try createTestBlock(allocator, ID.id(2, 4), "D");
    block_d.* = Block{
        .id = block_d.id,
        .content = "D",
        .left_origin = ID.id(SENTINEL_LEFT, 4),
        .right_origin = block_a.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_d.*);

    // Setup updates
    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(1, &blocks_list);

    // Apply update
    const result = try apply_update(allocator, &store, .{ .updates = &updates });

    // Verify content - should be CDAB since C has lower client clock than D
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "CDAB", content);
    try t.expect(result.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:missing blocks" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial document: "A"
    try store.insert_text(0, "A");

    // Get base block
    const block_a = store.start.?;

    // Create blocks with missing dependencies
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block C that depends on missing block B
    const missing_block_id = ID.id(3, 1); // Block B that doesn't exist yet
    const block_c = try createTestBlock(allocator, ID.id(2, 2), "C");
    block_c.* = Block{
        .id = block_c.id,
        .content = "C",
        .left_origin = missing_block_id, // Points to non-existent block
        .right_origin = block_a.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_c.*);

    // Setup updates
    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(1, &blocks_list);

    // Apply update
    const result = try apply_update(allocator, &store, .{ .updates = &updates });

    // Verify that block was added to pending
    try t.expect(result.pending.blocks.count() == 1);

    // Verify that the block in pending is our block C
    const block_c_in_pending = result.pending.blocks.get(block_c.id);
    try t.expect(block_c_in_pending != null);
    try t.expect(std.mem.eql(u8, block_c_in_pending.?.content, "C"));

    // Verify document content is unchanged
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "A", content);
}
