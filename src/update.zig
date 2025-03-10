const std = @import("std");

const Block = @import("block_store.zig").Block;
const BlockStoreType = @import("block_store.zig").BlockStoreType;
const ID = @import("block_store.zig").ID;

const SearchMarkerType = @import("search_marker.zig").SearchMarkerType;
const Marker = @import("./search_marker.zig").Marker;
const MarkerError = @import("./search_marker.zig").MarkerError;

const SENTINEL_LEFT = @import("block_store.zig").SPECIAL_CLOCK_LEFT;
const SENTINEL_RIGHT = @import("block_store.zig").SPECIAL_CLOCK_RIGHT;

const Clock = @import("global_clock.zig").MonotonicClock;

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
    }
};

pub const DeleteItem = struct {
    // Starting clock value
    clock: u64,
    // Number of items deleted in sequence
    len: u64,

    // Constructor for convenience
    pub fn item(clock: u64, len: u64) DeleteItem {
        return DeleteItem{
            .clock = clock,
            .len = len,
        };
    }
};

pub const DeleteSet = struct {
    // Maps client IDs to arrays of DeleteItems
    clients: std.AutoHashMap(u64, std.ArrayList(DeleteItem)),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) DeleteSet {
        return DeleteSet{
            .clients = std.AutoHashMap(u64, std.ArrayList(DeleteItem)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DeleteSet) void {
        var it = self.clients.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.clients.deinit();
    }

    pub fn addToDeleteSet(self: *Self, client: u64, clock: u64, length: u64) !void {
        // If length is 0, there's nothing to delete
        if (length == 0) return;

        var entry = try self.clients.getOrPut(client);
        if (!entry.found_existing) {
            // Create a new array list for this client
            entry.value_ptr.* = std.ArrayList(DeleteItem).init(self.allocator);
        }

        // Add the delete item
        try entry.value_ptr.append(DeleteItem.item(clock, length));
    }

    pub fn isDeleted(self: *Self, id: ID) bool {
        const deleteItems = self.clients.get(id.client) orelse return false;

        for (deleteItems.items) |di| {
            if (di.clock == id.clock) {
                return true;
            }
        }

        return false;
    }
};

// Updates is an incoming message from a remote peer
pub const Updates = struct {
    updates: *std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90),
    deletes: DeleteSet,
};

pub const UpdateStore = struct {
    allocator: std.mem.Allocator,
    pending: PendingStruct,
    pendingDs: DeleteSet,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        const ps = PendingStruct.init(allocator);
        const pds = DeleteSet.init(allocator);
        return .{
            .allocator = allocator,
            .pending = ps,
            .pendingDs = pds,
        };
    }

    pub fn apply_update(self: *Self, store: *BlockStoreType(), update: Updates) !void {
        // integrate updates
        var iter = update.updates.iterator();
        while (iter.next()) |entry| {
            const blocks = entry.value_ptr.*;

            for (blocks.items) |block| {
                // Allocate space for this block
                const blk = try store.allocate_block(block);

                // Check if we have all dependencies
                if (try store.getMissing(blk) != null) {
                    // We're missing updates from this client, add to pending queue
                    try self.pending.addPending(blk);
                    continue;
                }

                // Try to integrate
                store.integrate(blk) catch {
                    try self.pending.addPending(blk);
                    continue;
                };

                // Update state after successful integration
                try store.updateState(blk);
            }
        }
        // integrate deletes
        var delete_iter = update.deletes.clients.iterator();
        while (delete_iter.next()) |entry| {
            const deleted_items = entry.value_ptr.*;
            const client = entry.key_ptr.*;

            for (deleted_items.items) |remote_item| {
                const local_item = store.get_block_by_id(ID.id(remote_item.clock, client));
                if (local_item == null) continue;

                if (remote_item.clock > local_item.?.id.clock) {
                    try store.delete_text(try store.get_block_index_by_id(local_item.?.id), remote_item.len);
                }
            }
        }
        return;
    }
};

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

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Insert first block 'A'
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

    const up = Updates{
        .updates = &updates,
    };

    var us = UpdateStore.init(allocator);
    try us.apply_update(&store, up);

    // Verify content
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ACDB", content);
    try t.expect(us.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:at the end: happy-flow" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

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

    const up = Updates{
        .updates = &updates,
    };

    var us = UpdateStore.init(allocator);

    try us.apply_update(&store, up);
    // Verify content - should be ABCD since C has lower client clock than D
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ABCD", content);
    try t.expect(us.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:at the start: happy-flow" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial document: "AB"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");

    // Get base blocks
    const block_a = store.start.?;

    // Create concurrent blocks to insert at start
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block C: insert at start
    const block_c = try createTestBlock(allocator, ID.id(4, 2), "C");
    block_c.* = Block{
        .id = block_c.id,
        .content = "C",
        .left_origin = ID.id(SENTINEL_LEFT, 2), // Points to start sentinel
        .right_origin = block_a.id,
        .left = null,
        .right = null,
    };
    try blocks_list.append(block_c.*);

    var blocks_list_another = std.ArrayList(Block).init(allocator);
    defer blocks_list_another.deinit();

    // Create block D: also insert at start
    const block_d = try createTestBlock(allocator, ID.id(4, 4), "D");
    block_d.* = Block{
        .id = block_d.id,
        .content = "D",
        .left_origin = ID.id(SENTINEL_LEFT, 4),
        .right_origin = block_a.id,
        .left = null,
        .right = null,
    };
    try blocks_list_another.append(block_d.*);

    // Setup updates
    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(2, &blocks_list);
    try updates.put(4, &blocks_list_another);

    const up = Updates{
        .updates = &updates,
    };

    var us = UpdateStore.init(allocator);

    try us.apply_update(&store, up);
    // Verify content - should be CDAB since C has lower client clock than D
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "CDAB", content);
    try t.expect(us.pending.blocks.count() == 0);
}

test "apply_update: concurrent client updates:missing blocks" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial document: "A"
    try store.insert_text(0, "A");

    // Get base block
    const block_a = store.start.?;

    // Create blocks with missing dependencies
    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create block C that depends on missing block B
    const missing_block_id = ID.id(4, 2); // Block B that doesn't exist yet
    const block_c = try createTestBlock(allocator, ID.id(5, 4), "C");
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
    try updates.put(4, &blocks_list);

    const up = Updates{
        .updates = &updates,
    };

    var us = UpdateStore.init(allocator);

    try us.apply_update(&store, up);
    // Verify that block was added to pending
    try t.expect(us.pending.blocks.count() == 1);

    // Verify that the block in pending is our block C
    const block_c_in_pending = us.pending.blocks.get(block_c.id);
    try t.expect(block_c_in_pending != null);
    try t.expect(std.mem.eql(u8, block_c_in_pending.?.content, "C"));

    // Verify document content is unchanged
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "A", content);
}
