const std = @import("std");
const search_marker = @import("search_marker.zig");
const Block = search_marker.Block;
const ID = search_marker.ID;

pub const Blocks = []Block;

pub const PendingStruct = struct {
    blocks: std.AutoHashMap(ID, Block),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PendingStruct {
        return .{
            .blocks = std.AutoHashMap(ID, Block).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn addPending(self: *PendingStruct, block: Block, reason: []const u8) !void {
        try self.blocks.put(block.id, block);
        std.log.info("Block {any} pending: {s}", .{ block.id, reason });
    }
};

pub const Updates = struct {
    updates: *std.ArrayHashMap(u64, *Blocks),
};

pub const UpdateResult = struct {
    pending: PendingStruct,
};

pub fn apply_update(store: *search_marker.BlockStoreType(), update: Updates, allocator: std.mem.Allocator) !UpdateResult {
    var result = UpdateResult{
        .pending = PendingStruct.init(allocator),
    };

    var iter = update.updates.iterator();
    while (iter.next()) |entry| {
        const blocks = entry.value_ptr.*;

        // Process blocks in order of clock
        for (blocks) |block| {
            // Try to find origin blocks
            const left_block = store.get_block_by_id(block.left_origin.?);
            const right_block = store.get_block_by_id(block.right_origin.?);

            if (left_block == null or right_block == null) {
                try result.pending.addPending(block, "Missing origin blocks");
                continue;
            }

            // TODO: Implement neighbor finding and integration
        }
    }

    return result;
}
