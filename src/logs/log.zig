const std = @import("std");

/// Logger configuration options
pub const LogConfig = struct {
    // Path to log file
    filepath: []const u8,
    // Maximum file size in bytes before rotation
    max_size: usize = 10 * 1024 * 1024, // 10MB default
    // Whether to append to existing file
    append: bool = true,
    // Whether to include timestamps
    timestamps: bool = true,
    // Minimum log level to write
    min_level: LogLevel = .info,
};

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    pub fn asString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

pub const Logger = struct {
    file: std.fs.File,
    mutex: std.Thread.Mutex,
    config: LogConfig,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: LogConfig) !Self {
        const file = if (config.append)
            std.fs.cwd().openFile(config.filepath, .{ .mode = .read_write }) catch
                try std.fs.cwd().createFile(config.filepath, .{})
        else
            try std.fs.cwd().createFile(config.filepath, .{});

        // Seek to end if appending
        if (config.append) {
            try file.seekFromEnd(0);
        }

        return Self{
            .file = file,
            .mutex = std.Thread.Mutex{},
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn log(self: *Self, level: LogLevel, comptime fmt: []const u8, args: anytype) !void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) return;

        // Lock for thread safety
        self.mutex.lock();
        defer self.mutex.unlock();

        // Check file size and rotate if needed
        const file_size = try self.file.getEndPos();
        if (file_size > self.config.max_size) {
            try self.rotate();
        }

        try self.file.writer().print("[{s}]: ", .{
            level.asString(),
        });
        try self.file.writer().print(fmt ++ "\n", args);
    }

    fn rotate(self: *Self) !void {
        // Close current file
        self.file.close();

        // Rename current file to backup
        const backup_path = try std.fmt.allocPrint(self.allocator, "{s}.{d}", .{
            self.config.filepath,
            std.time.timestamp(),
        });
        defer self.allocator.free(backup_path);

        try std.fs.cwd().rename(self.config.filepath, backup_path);

        // Open new file
        self.file = try std.fs.cwd().createFile(self.config.filepath, .{});
    }
};

test "basic logging" {
    const config = LogConfig{
        .filepath = "test.log",
        .max_size = 1024,
        .append = false,
        .timestamps = false,
    };

    var logger = try Logger.init(std.testing.allocator, config);
    defer logger.deinit();

    try logger.log(.info, "Test message {d}", .{42});
    try logger.log(.err, "Something went wrong", .{});

    // Verify log contents
    const contents = try std.fs.cwd().readFileAlloc(std.testing.allocator, config.filepath, 1024);
    defer std.testing.allocator.free(contents);

    try std.testing.expect(std.mem.indexOf(u8, contents, "[INFO]") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "Test message 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "[ERROR]") != null);

    // Cleanup
    try std.fs.cwd().deleteFile(config.filepath);
}
