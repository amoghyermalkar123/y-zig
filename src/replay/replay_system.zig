const std = @import("std");
const Block = @import("../block_store.zig").Block;
const ID = @import("../block_store.zig").ID;

const EntityTag = enum {
    state_vector,
    block,
};

// Entity represents a component of the algorithm
// that needs to be visualized in the replay system
pub const Entity = union(EntityTag) {
    state_vector: []const u8,
    block: BlockEvent,
};

pub const Event = struct {
    entity: Entity,
    timestamp: u64,
    msg: []const u8,
};

const Allocator = std.mem.Allocator;

const BlockEvent = struct {
    content: []const u8,
    left: ?[]const u8,
    right: ?[]const u8,
    leftOrigin: ID,
    rightOrigin: ID,
};

// writes a series of events as json to a file
pub const EventWriter = struct {
    file: std.fs.File,

    const Self = @This();

    pub fn init(jsonFile: []const u8) !Self {
        const f = try std.fs.openFileAbsolute(jsonFile, .{ .mode = .read_write });
        return .{
            .file = f,
        };
    }

    pub fn addBlockEvent(self: *Self, ev: Block) !void {
        const be: BlockEvent = .{
            .content = ev.content,
            .left = if (ev.left != null) ev.left.?.content else "",
            .right = if (ev.right != null) ev.right.?.content else "",
            .leftOrigin = ev.left_origin.?,
            .rightOrigin = ev.right_origin.?,
        };
        const event = Event{
            .msg = "block",
            .entity = .{ .block = be },
            .timestamp = 1,
        };
        try std.json.stringify(event, .{}, self.file.writer());
    }

    pub fn deinit(self: *Self) void {
        defer self.file.close();
    }
};
