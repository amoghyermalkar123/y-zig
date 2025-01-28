const std = @import("std");

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

pub const BlockLogEvent = struct {
    event_type: []const u8,
    block_id: struct {
        clock: u64,
        client: u64,
    },
    content: []const u8,
    left_origin: ?struct {
        clock: u64,
        client: u64,
    },
    right_origin: ?struct {
        clock: u64,
        client: u64,
    },
    left: ?struct {
        clock: u64,
        client: u64,
    },
    right: ?struct {
        clock: u64,
        client: u64,
    },
    timestamp: i64,
};

pub const StateVectorLogEvent = struct {
    client: u64,
    clock: u64,
    timestamp: i64,
};

pub const IntegrationLogEvent = struct {
    phase: []const u8, // "start", "conflict_detected", "resolution_step", "complete"
    block_id: struct {
        clock: u64,
        client: u64,
    },
    details: []const u8,
    timestamp: i64,
};

pub const StructuredLogger = struct {
    file: std.fs.File,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filepath: []const u8) !Self {
        const file = try std.fs.cwd().createFile(filepath, .{});

        // Write opening JSON array
        try file.writeAll("[\n");

        return Self{
            .file = file,
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) !void {
        // Write closing JSON array
        try self.file.writeAll("\n]");
        self.file.close();
    }

    pub fn logBlockEvent(self: *Self, event: BlockLogEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const json = try std.json.stringifyAlloc(self.allocator, .{
            .type = "block_event",
            .data = event,
        }, .{});
        defer self.allocator.free(json);

        try self.file.writeAll(json);
        try self.file.writeAll(",\n");
    }

    pub fn logStateVector(self: *Self, event: StateVectorLogEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const json = try std.json.stringifyAlloc(self.allocator, .{
            .type = "state_vector",
            .data = event,
        }, .{});
        defer self.allocator.free(json);

        try self.file.writeAll(json);
        try self.file.writeAll(",\n");
    }

    pub fn logIntegration(self: *Self, event: IntegrationLogEvent) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const json = try std.json.stringifyAlloc(self.allocator, .{
            .type = "integration",
            .data = event,
        }, .{});
        defer self.allocator.free(json);

        try self.file.writeAll(json);
        try self.file.writeAll(",\n");
    }
};

test "basic logging" {
    const allocator = std.testing.allocator;

    var logger = try StructuredLogger.init(allocator, "test.log");
    defer logger.deinit() catch unreachable;

    // Log a block event
    try logger.logBlockEvent(.{
        .event_type = "create",
        .block_id = .{ .clock = 1, .client = 1 },
        .content = "A",
        .left_origin = null,
        .right_origin = null,
        .left = null,
        .right = null,
        .timestamp = std.time.timestamp(),
    });

    // Log a state vector update
    try logger.logStateVector(.{
        .client = 1,
        .clock = 1,
        .timestamp = std.time.timestamp(),
    });

    // Log an integration event
    try logger.logIntegration(.{
        .phase = "start",
        .block_id = .{ .clock = 1, .client = 1 },
        .details = "Starting integration of block A",
        .timestamp = std.time.timestamp(),
    });

    // Verify log exists
    const stat = try std.fs.cwd().statFile("test.log");
    try std.testing.expect(stat.size > 0);

    // Cleanup
    try std.fs.cwd().deleteFile("test.log");
}
