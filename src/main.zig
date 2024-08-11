const std = @import("std");

const CLIENT_ID: u8 = 1;

const YataCharacter = struct {
    id: u8,
    originLeft: []const u8,
    left: []const u8,
    right: []const u8,
    isDeleted: bool,
    content: []const u8,

    pub fn new(id: u8, originLeft: []const u8, left: []const u8, right: []const u8, content: []const u8) YataCharacter {
        return YataCharacter{
            .id = id,
            .originLeft = originLeft,
            .left = left,
            .right = right,
            .content = content,
            .isDeleted = false,
        };
    }
};

const YArray = struct {
    list: std.ArrayList(YataCharacter),
    current_capacity: u64,
    allocator: ?std.mem.Allocator = null,

    pub const InitConfig = struct {
        allocator: ?std.mem.Allocator = null,

        var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var default_allocator = default_gpa.allocator();
    };

    pub fn init(config: InitConfig) anyerror!YArray {
        const decided_allocator = config.allocator orelse InitConfig.default_allocator;
        var arr = std.ArrayList(YataCharacter).init(decided_allocator);
        try arr.insert(0, YataCharacter.new(1, "", "", "*", "*"));
        try arr.insert(1, YataCharacter.new(2, "*", "*", "", "*"));
        return YArray{
            .list = arr,
            .current_capacity = 0,
            .allocator = decided_allocator,
        };
    }

    pub fn deinit(self: *YArray) void {
        self.list.deinit();
    }

    pub fn local_insert(self: *YArray, newCharacter: YataCharacter, pos: usize) anyerror!void {
        try self.list.insert(pos, newCharacter);
    }

    pub fn content(self: *YArray) anyerror![]const u8 {
        const yataAllocation = self.list.allocatedSlice();
        for (yataAllocation, 0..) |value, i| {
            std.debug.print("{d}:{s}\n", .{ i, value.content });
        }
        return "";
    }
};

const YDoc = struct {
    clientId: u8 = CLIENT_ID,
    array: YArray,

    pub fn init() anyerror!YDoc {
        return YDoc{
            .array = try YArray.init(YArray.InitConfig{}),
        };
    }

    pub fn deinit(self: *YDoc) void {
        self.array.deinit();
    }

    pub fn content(self: *YDoc) anyerror![]const u8 {
        return self.array.content();
    }
};

pub fn main() anyerror!void {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();
    try new_doc.array.local_insert(YataCharacter.new(3, "*", "*", "*", "a"), 2);
    try new_doc.array.local_insert(YataCharacter.new(4, "*", "*", "*", "b"), 3);
    const dc = try new_doc.content();
    std.debug.print("{s}", .{dc});
}

test "local_insert" {
    var new_doc: YDoc = YDoc.init();
    defer new_doc.deinit();
    try new_doc.array.local_insert(YataCharacter.new(3, "*", "*", "*", "a"));
    const dc = try new_doc.content();
    std.debug.print("{any}", .{dc});
}
