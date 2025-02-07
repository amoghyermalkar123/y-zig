const std = @import("std");

pub const ID = struct {
    clock: u64,
    client: u64,

    pub fn id(clock: u64, client: u64) ID {
        return ID{
            .clock = clock,
            .client = client,
        };
    }
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

pub const EventType = enum {
    // TODO: probably won't use these 2
    create,
    delete,
    // block
    marker,
    neighbor_reconnection,
    // state vector events
    state_vector_update,
    // integration
    ibo_update,
    ci_update,
    // integration
    integration_start,
    conflict_detected,
    conflict_resolved,
    integration_end,
    // generic
    generic,
};

pub fn BlockLogEventType(comptime T: type) type {
    return struct {
        event_type: EventType,
        block_id: T,
        content: []const u8,
        left_origin: ?T,
        right_origin: ?T,
        left: ?T,
        right: ?T,
        timestamp: i64,
        msg: []const u8,
    };
}

pub fn IBOLogEventType(comptime T: type) type {
    return struct {
        event_type: EventType = .ibo_update,
        block_id: T,
        timestamp: i64,
    };
}

pub fn CILogEventType(comptime T: type) type {
    return struct {
        event_type: EventType = .ci_update,
        block_id: T,
        timestamp: i64,
    };
}

pub fn IntegrationLogEventType(comptime T: type) type {
    return struct {
        phase: EventType, // "start", "conflict_detected", "resolution_step", "complete"
        block_id: T,
        details: []const u8,
        timestamp: i64,
    };
}

pub const StateVectorLogEvent = struct {
    client: u64,
    clock: u64,
    timestamp: i64,
};

pub const GenericEvent = struct {
    event_type: EventType = .generic,
    msg: []const u8,
    timestamp: i64,
};

pub const LogEventType = enum {
    blocklog,
    ibolog,
    cilog,
    svlog,
    genericlog,
    integlog,
};

pub fn InternalEventType(comptime T: type) type {
    return union(LogEventType) {
        blocklog: BlockLogEventType(T),
        ibolog: IBOLogEventType(T),
        cilog: CILogEventType(T),
        svlog: StateVectorLogEvent,
        genericlog: GenericEvent,
        integlog: IntegrationLogEventType(T),
    };
}

pub const StructuredLogger = struct {
    file: std.fs.File,
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, filepath: []const u8) !Self {
        const file = try std.fs.cwd().createFile(filepath, .{});

        return Self{
            .file = file,
            .mutex = std.Thread.Mutex{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) !void {
        // Write closing JSON array
        self.file.close();
    }

    pub fn log(self: *Self, event: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const json = try std.json.stringifyAlloc(self.allocator, event, .{});
        defer self.allocator.free(json);

        try self.file.writeAll(json);
        try self.file.writeAll("\n");
    }
};

pub const Replay = struct {
    internal_events: *std.ArrayList(InternalEventType(ID)),

    const Self = @This();

    // try accepting an allocator and create the ArrayList in the init function
    // it wont work, FOW
    pub fn init(allocator: *std.ArrayList(InternalEventType(ID))) Self {
        return .{
            .internal_events = allocator,
        };
    }

    pub fn parse_log(self: *Self, allocator: std.mem.Allocator, path: []const u8) !void {
        const file = try std.fs.cwd().openFile(path, .{});
        var buf_reader = std.io.bufferedReader(file.reader());
        var in_stream = buf_reader.reader();

        // Reset file cursor to beginning
        try file.seekTo(0);

        while (true) {
            // Read a line, getting an owned slice
            const line = in_stream.readUntilDelimiterAlloc(allocator, '\n', 1024) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            defer allocator.free(line);

            const parsed = try readConfig(allocator, line);
            try self.internal_events.append(parsed.value);
            // std.debug.print("V: {any}", .{parsed.value});
        }
    }

    fn readConfig(allocator: std.mem.Allocator, data: []const u8) !std.json.Parsed(InternalEventType(ID)) {
        return std.json.parseFromSlice(InternalEventType(ID), allocator, data, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    }
};

pub fn main() !void {
    var alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc.deinit();

    var ls = std.ArrayList(InternalEventType(ID)).init(alloc.allocator());
    var r = Replay.init(&ls);

    try r.parse_log(alloc.allocator(), "/home/amogh/projects/y-zig/test.log");
}
