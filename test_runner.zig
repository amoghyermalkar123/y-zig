const std = @import("std");
const builtin = @import("builtin");

// ANSI escape codes for colors
pub const Color = struct {
    // Foreground colors
    pub const black = "\x1b[30m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";

    // Background colors
    pub const bg_black = "\x1b[40m";
    pub const bg_red = "\x1b[41m";
    pub const bg_green = "\x1b[42m";
    pub const bg_yellow = "\x1b[43m";
    pub const bg_blue = "\x1b[44m";
    pub const bg_magenta = "\x1b[45m";
    pub const bg_cyan = "\x1b[46m";
    pub const bg_white = "\x1b[47m";

    // Special formatting
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const italic = "\x1b[3m";
    pub const underline = "\x1b[4m";
};

pub fn main() !void {
    const out = std.io.getStdOut().writer();

    std.fmt.format(out, "{s}Starting Tests ... {s}\n", .{ Color.yellow, Color.reset }) catch return;
    for (builtin.test_functions) |t| {
        std.fmt.format(out, "{s}RUN: {s}{s}\n", .{ Color.blue, t.name, Color.reset }) catch return;
        t.func() catch |err| {
            try std.fmt.format(out, "{s}FAIL: {!}{s}\n", .{ Color.red, err, Color.reset });
            try std.fmt.format(out, "{s}----------------------------------------------------------------------------------------------------- {s}\n", .{ Color.yellow, Color.reset });
            continue;
        };
        try std.fmt.format(out, "{s}PASS{s}\n", .{ Color.green, Color.reset });
        try std.fmt.format(out, "{s}----------------------------------------------------------------------------------------------------- {s}\n", .{ Color.yellow, Color.reset });
    }
}
