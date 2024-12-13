const std = @import("std");
const BlockStore = @import("search_marker.zig").BlockStoreType();

const LOCAL_CLIENT = 1;

// all blocks owned by the doc
pub const YDoc = struct {
    dot_cloud: *DotCloud,

    const Self = @This();

    pub fn init(dot_cloud: *DotCloud) Self {
        return Self{
            .dot_cloud = dot_cloud,
        };
    }
};

const DotCloud = struct {
    client_blocks: std.ArrayHashMap(u64, ?*BlockStore),
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) anyerror!Self {
        const dc = DotCloud{
            .client_blocks = std.ArrayHashMap(u64, ?*BlockStore).init(allocator),
        };
        dc.client_blocks.putNoClobber(LOCAL_CLIENT, null);
        return dc;
    }
};
