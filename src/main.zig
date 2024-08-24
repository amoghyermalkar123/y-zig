const std = @import("std");

const CLIENT_ID: u64 = 1;

const YataCharacter = struct {
    id: u64,
    originLeft: u64,
    left: []const u8,
    right: []const u8,
    isDeleted: bool,
    content: []const u8,

    pub fn new(id: u64, originLeft: u64, left: []const u8, right: []const u8, content: []const u8) YataCharacter {
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
        try arr.insert(0, YataCharacter.new(1, 0, "", "*", "*"));
        try arr.insert(1, YataCharacter.new(2, 0, "*", "", "*"));
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
        self.current_capacity += newCharacter.content.len;
        return;
    }

    pub fn integrate_insert(self: *YArray, updates: []YataCharacter, remote_client_id: u64) anyerror!void {
        for (updates) |i| {
            for (self.list.items, 0..) |o, listPos| {
                std.debug.print("o.id: {d},{s}\t i.id: {d},{s}, i.originLeft: {d}\t o.originLeft: {d}\n", .{ o.id, o.content, i.id, i.content, i.originLeft, o.originLeft });
                if (o.id < i.originLeft or i.originLeft <= o.originLeft) {
                    if (o.originLeft != i.originLeft or remote_client_id < CLIENT_ID) {
                        // i is a successor of o
                        try self.list.insert(listPos + 1, i);
                        // TODO: update i left and right
                        self.current_capacity += i.content.len;
                    }
                }
            }
        }
        return;
    }

    // caller owns memory
    pub fn content(self: *YArray, al: std.mem.Allocator) anyerror![]const u8 {
        const yataAllocation = self.list.allocatedSlice();
        const stringBuf = try al.alloc(u8, self.current_capacity);
        var p: usize = 0;

        for (yataAllocation, 0..) |value, i| {
            if (i >= self.list.items.len) break;
            if (std.mem.eql(u8, value.content, "*")) continue;
            const n = p + value.content.len;
            @memcpy(stringBuf[p..n], value.content);
            p += value.content.len;
        }
        return stringBuf;
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

    pub fn content(self: *YDoc, al: std.mem.Allocator) anyerror![]const u8 {
        return self.array.content(al);
    }
};

pub fn main() anyerror!void {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();
    try new_doc.array.local_insert(YataCharacter.new(3, "*", "*", "*", "a"), 2);
    try new_doc.array.local_insert(YataCharacter.new(4, "*", "*", "*", "b"), 3);
    try new_doc.array.local_insert(YataCharacter.new(4, "*", "*", "*", "c"), 4);
    var areAl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = areAl.allocator();
    const dc = try new_doc.content(al);
    defer al.free(dc);
    std.debug.print("{s}", .{dc});
}

test "integrate: basic test" {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();
    try new_doc.array.local_insert(YataCharacter.new(3, 2, "*", "*", "Y"), 2);
    try new_doc.array.local_insert(YataCharacter.new(4, 3, "Y", "T", "A"), 3);
    try new_doc.array.local_insert(YataCharacter.new(5, 4, "A", "A", "T"), 4);
    try new_doc.array.local_insert(YataCharacter.new(6, 5, "T", "*", "A"), 5);

    var updates = [1]YataCharacter{
        YataCharacter.new(7, 4, "A", "T", "C"),
    };
    // simulating remote doc integration
    try new_doc.array.integrate_insert(&updates, 2);

    var areAl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = areAl.allocator();
    const dc = try new_doc.content(al);
    defer al.free(dc);
    std.debug.print("{s}\n", .{dc});
}
