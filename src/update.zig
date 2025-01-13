const std = @import("std");
const search_marker = @import("search_marker.zig");
const Block = search_marker.Block;
const BlockStore = @import("search_marker.zig").BlockStoreType();
const SPECIAL_CLOCK_LEFT = search_marker.SPECIAL_CLOCK_LEFT;
const SPECIAL_CLOCK_RIGHT = search_marker.SPECIAL_CLOCK_RIGHT;
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

            // Check if we have all dependencies
            if (try store.getMissing(blk)) |missing_client| {
                // We're missing updates from this client, add to pending queue
                try result.pending.addPending(blk);
                std.log.info("Block {any} pending on updates from client {d}", .{ blk.id, missing_client });
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

test "concurrent client updates" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = try search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Insert first block 'A'
    try store.insert_text(0, "A");

    // Get the actual block A (not sentinel)
    const base_block = store.start.?.right.?;
    try t.expect(std.mem.eql(u8, base_block.content, "A"));

    // Create concurrent blocks
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block B
    const block_b = try createTestBlock(allocator, ID.id(3, 1), "B");
    block_b.* = Block{
        .id = block_b.id,
        .content = "B",
        .left_origin = base_block.id,
        .right_origin = base_block.right.?.id, // Right sentinel
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_b.*);

    // Create block C
    const block_c = try createTestBlock(allocator, ID.id(3, 2), "C");
    block_c.* = Block{
        .id = block_c.id,
        .content = "C",
        .left_origin = base_block.id,
        .right_origin = base_block.right.?.id, // Right sentinel
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

    // Debug state
    std.debug.print("\nFinal state:\n", .{});
    var current = store.start.?.right; // Skip left sentinel
    while (current != null and current.?.id.clock != SPECIAL_CLOCK_RIGHT) {
        std.debug.print("Block: content={s} id={any}\n", .{ current.?.content, current.?.id });
        current = current.?.right;
    }
    std.debug.print("Pending blocks: {any}\n", .{result.pending.blocks.count()});

    // Verify content
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ABC", content);
    try t.expect(result.pending.blocks.count() == 0);
}

test "getMissing basic checks" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = try BlockStore.init(allocator, &marker_system, &clk);

    // Add first block from client 1
    const block_a = try store.allocate_block(Block.makeFirstBlock(ID.id(1, 1), "A"));
    try store.integrate(block_a);
    try store.updateState(block_a);

    // Try to integrate block from client 2 that references block A
    const block_b = try store.allocate_block(Block.block(ID.id(1, 2), "B"));
    block_b.left_origin = block_a.id;
    block_b.right_origin = ID.SENTINEL_RIGHT;

    // Should have no missing dependencies
    try t.expectEqual(@as(?u64, null), try store.getMissing(block_b));

    // Try to integrate block that references future update
    var block_c = try store.allocate_block(Block.block(ID.id(1, 3), "C"));
    block_c.left_origin = ID.id(5, 1); // Clock 5 from client 1 which we don't have
    block_c.right_origin = ID.SENTINEL_RIGHT;

    // Should be missing updates from client 1
    try t.expectEqual(@as(?u64, 1), try store.getMissing(block_c));
}
