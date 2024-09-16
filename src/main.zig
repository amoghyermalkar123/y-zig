const YDoc = @import("ydoc.zig").YDoc;
const std = @import("std");

pub fn main() anyerror!void {
    const d = try YDoc.new();
    std.debug.print("{any}", .{d});
}
