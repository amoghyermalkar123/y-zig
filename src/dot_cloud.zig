const std = @import("std");
const BlockStore = @import("search_marker.zig").BlockStoreType();
const LOCAL_CLIENT = 1;

const DotCloud = struct {
    // map of client ids to the last clock they observed
    state_vector: std.ArrayHashMap(u64, u64),
    // underlying block store for this dot cloud
    // consists of the post conflict resolution doubly-linked list of blocks
    block_store: ?*BlockStore;

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) anyerror!Self {
        const dc = DotCloud{
            .state_vector = std.ArrayHashMap(u64, u64).init(allocator),
            .block_store = block_store,
        };
        // 1 because the monotonic clocks start from 2 so the last seen should be 1
        dc.client_blocks.putNoClobber(LOCAL_CLIENT, 1);
        return dc;
    }
};
