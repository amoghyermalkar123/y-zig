const DotCloud = @import("doc.zig").DotCloud;

pub const Updates = struct {
    updates: DotCloud,
};

// TODO: should returning pending stack
// and the caller should handle this
// (typically the caller should be the doc store)
pub fn apply_update(update: Updates) anyerror!void {}
