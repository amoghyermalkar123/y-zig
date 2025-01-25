const std = @import("std");

const EntityTag = enum {
    state_vector,
    block,
    clock,
};

// Entity represents a component of the algorithm
// that needs to be visualized in the replay system
pub const Entity = struct {
    tag: EntityTag,
};

pub const Event = struct {
    entity: Entity,
    timestamp: u64,
    msg: []const u8,
};

const Allocator = std.mem.Allocator;

// writes a series of events as json to a file
pub const EventWriter = struct {
    allocator: *std.ArrayList(Event),
    file: *std.fs.File,

    const Self = @This();

    pub fn init(al: Allocator, jsonFile: []const u8) !Self {
        const f = try std.fs.openFileAbsolute(jsonFile, .{ .mode = .read_write });
        return .{
            .allocator = al,
            .file = f,
        };
    }

    pub fn add(self: *Self, ev: Event) !void {
        try self.allocator.append(ev);
    }

    pub fn flush(self: *Self) !void {
        for (self.allocator.items) |event| {
            var al = std.ArrayList(u8).init(self.allocator);
            defer al.deinit();
            try std.json.stringify(event, .{}, al.writer());
        }
    }
};
