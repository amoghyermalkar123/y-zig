const BlockStore = @import("blockstore.zig").BlockStore;

// Store wraps the BlockStore type
// It handles integration and operations related to updates, merges, etc
pub const Store = struct {
    blocks: BlockStore,

    pub fn new() anyerror!Store {
        const blk = try BlockStore.new();
        return Store{ .blocks = blk };
    }

    pub fn insert() !void {}
    pub fn apply_updates() !void {}
};

// test "basic" {
//     const store = Store.new();
//     store.insert();
//
//     const updates = [1]u64{1};
//     const pending = store.apply_updates(updates);
//
//     store.apply_updates(pending);
// }
