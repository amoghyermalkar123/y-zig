const BlockStore = @import("blockstore.zig").BlockStore;

// Store wraps the BlockStore type
// It handles integration and operations related to updates, merges, etc
pub const Store = struct {
    blocks: BlockStore,

    pub fn new() Store!anyerror {
        return Store{ .blocks = BlockStore.new() };
    }

    pub fn insert() !void {}
    pub fn apply_updates() !void {}
};

// test "basic" {
//     const store = Store.new();
//     store.insert();
//
//     const updates = [1]u64{1};
//     store.apply_updates(updates);
// }
