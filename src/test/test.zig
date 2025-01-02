const std = @import("std");

pub const std_options = struct {
    pub const log_level: std.log.Level = .info;
};

test "log" {
    std.log.err("log level error\n", .{});
    std.log.warn("log level warn\n", .{});

    std.log.info("log level info\n", .{});
    std.log.debug("log level debug\n", .{});
}
