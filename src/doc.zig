const std = @import("std");
const DotCloud = @import("dot_cloud.zig.zig").DotCloud;

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
