const std = @import("std");
const search_marker = @import("search_marker.zig");
const Block = search_marker.Block;
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

fn tryAssignNeighbors(store: *search_marker.BlockStoreType(), block: *Block) bool {
    if (block.left_origin == null or block.right_origin == null) return false;

    const left_block = store.get_block_by_id(block.left_origin.?);
    const right_block = store.get_block_by_id(block.right_origin.?);

    if (left_block == null or right_block == null) return false;

    // Only assign if blocks are consecutive
    if (left_block.?.right == right_block) {
        block.left = left_block;
        block.right = right_block;
        return true;
    }

    return false;
}

pub fn apply_update(store: *search_marker.BlockStoreType(), update: Updates, allocator: std.mem.Allocator) !UpdateResult {
    var result = UpdateResult{
        .pending = PendingStruct.init(allocator),
    };

    var iter = update.updates.iterator();
    while (iter.next()) |entry| {
        const blocks = entry.value_ptr.*;

        for (blocks.items) |block| {
            // allocate some space for this block
            const blk = try store.allocate_block(block);

            // if we cannot assign neighbors to this block, the pending struct will reference the blk pointer
            if (!tryAssignNeighbors(store, blk)) {
                try result.pending.addPending(blk);
                continue;
            }

            // if we were able to assign the neighbors, we continue with integration and the block store
            // will reference the blk pointer
            store.integrate(blk) catch |err| {
                try result.pending.addPending(blk);
                std.log.err("Integration failed for block {any}: {any}", .{ blk.id, err });
                continue;
            };

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

test "basic update application" {
    // Setup
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create marker system
    var marker_list = std.ArrayList(search_marker.Marker).init(allocator);
    var marker_system = search_marker.SearchMarkerType().init(&marker_list);
    var store = search_marker.BlockStoreType().init(allocator, &marker_system, &clk);

    // Create base document with "AB"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");

    var blocks_list = std.ArrayList(Block).init(allocator);
    defer blocks_list.deinit();

    // Create an update with block "C" to insert between A and B
    const block_c = try createTestBlock(allocator, ID.id(3, 1), "C");
    block_c.*.left_origin = store.start.?.id;
    block_c.*.right_origin = store.start.?.right.?.id;
    try blocks_list.append(block_c.*);

    var updates = std.HashMap(u64, Blocks, std.hash_map.AutoContext(u64), 90).init(allocator);
    defer updates.deinit();
    try updates.put(1, &blocks_list);

    // Apply update
    const result = try apply_update(&store, .{ .updates = &updates }, allocator);

    // Verify results
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ACB", content);
    try t.expect(result.pending.blocks.count() == 0);
}
