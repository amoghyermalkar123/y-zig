const std = @import("std");
const BlockStore = @import("block_store.zig").BlockStoreType();

const DotCloud = struct {
    block_store: ?*BlockStore,

    const Self = @This();

    pub fn init(block_store: BlockStore) anyerror!Self {
        const dc = DotCloud{
            .block_store = block_store,
        };
        return dc;
    }
};
