const std = @import("std");

const CLIENT_ID: u64 = 1;

const Update = struct {
    character: []const u8,
    position: usize,
    leftContent: []const u8,
    rightContent: []const u8,
};

const YataCharacter = struct {
    id: u64,
    originLeft: ?*YataCharacter,
    left: ?*YataCharacter,
    right: ?*YataCharacter,
    isDeleted: bool,
    content: []const u8,

    pub fn new(id: u64, originLeft: ?*YataCharacter, left: ?*YataCharacter, right: ?*YataCharacter, content: []const u8) YataCharacter {
        return YataCharacter{
            .id = id,
            .originLeft = originLeft,
            .left = left,
            .right = right,
            .content = content,
            .isDeleted = false,
        };
    }

    fn assign_neighbors(self: *YataCharacter, left: ?*YataCharacter, right: ?*YataCharacter) void {
        self.left = left orelse self.left;
        self.right = right orelse self.right;
        return;
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

    pub fn get_adj_neighbors(self: *YArray, pos: usize) [2]YataCharacter {
        // std.debug.print("pos {d} ", .{pos});
        // std.debug.print("posPrev {d}, posNext {d}, len {d}\n", .{ pos - 2, pos - 1, self.list.items.len });
        return [2]YataCharacter{ self.list.items[pos - 1], self.list.items[pos - 2] };
    }

    pub fn init(config: InitConfig) anyerror!YArray {
        const decided_allocator = config.allocator orelse InitConfig.default_allocator;
        var arr = std.ArrayList(YataCharacter).init(decided_allocator);
        try arr.insert(0, YataCharacter.new(1, null, null, null, "*"));
        try arr.insert(1, YataCharacter.new(2, null, null, null, "*"));
        return YArray{
            .list = arr,
            .current_capacity = 0,
            .allocator = decided_allocator,
        };
    }

    pub fn deinit(self: *YArray) void {
        self.list.deinit();
    }

    pub fn local_insert(self: *YArray, newCharacter: *YataCharacter, pos: usize) anyerror!void {
        var neighs = self.get_adj_neighbors(pos);
        _ = newCharacter.assign_neighbors(&neighs[0], &neighs[1]);
        _ = &neighs[0].assign_neighbors(null, newCharacter);
        _ = &neighs[1].assign_neighbors(newCharacter, null);
        std.debug.print("adding: {s} left: {s} right: {s}\n", .{ newCharacter.content, newCharacter.left.?.content, newCharacter.right.?.content });
        try self.list.insert(pos, newCharacter.*);
        self.current_capacity += newCharacter.content.len;
        return;
    }

    pub fn integrate_insert(self: *YArray, updates: []Update, remote_client_id: u64) anyerror!void {
        for (updates) |i| {
            const conflictingOps = self.list.items[i.position - 1 .. i.position];
            if (conflictingOps.len > 0) {
                var listPos = i.position - 1;
                for (conflictingOps) |o| {
                    if (listPos > i.position) {
                        break;
                    }
                    var neighs = self.get_adj_neighbors(listPos);
                    var is = YataCharacter.new(10, &neighs[0], &neighs[0], &neighs[1], i.character);
                    if ((o.id < is.originLeft.?.id or is.originLeft.?.id <= o.originLeft.?.id) and (o.originLeft.?.id != is.originLeft.?.id or remote_client_id < CLIENT_ID)) {
                        // i is a successor of o
                        try self.local_insert(&is, listPos + 1);
                    }
                    listPos += 1;
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
}

const testify = std.testing;

test "integrate: basic test" {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();

    var neigh = new_doc.array.get_adj_neighbors(2);
    var one = YataCharacter.new(3, &neigh[0], &neigh[0], &neigh[1], "a");
    try new_doc.array.local_insert(&one, 2);

    neigh = new_doc.array.get_adj_neighbors(3);
    var two = YataCharacter.new(4, &neigh[0], &neigh[0], &neigh[1], "b");
    try new_doc.array.local_insert(&two, 3);

    neigh = new_doc.array.get_adj_neighbors(4);
    var thr = YataCharacter.new(5, &neigh[0], &neigh[0], &neigh[1], "c");
    try new_doc.array.local_insert(&thr, 4);

    var updates = [1]Update{Update{ .character = "y", .position = 3, .leftContent = "a", .rightContent = "b" }};

    // simulating remote doc integration
    try new_doc.array.integrate_insert(&updates, 2);

    var areAl = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const al = areAl.allocator();
    const dc = try new_doc.content(al);
    defer al.free(dc);
    const d = "aybc";
    try testify.expectEqualSlices(u8, d, dc);
}

test "neighbors" {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();

    var one = YataCharacter.new(3, null, null, null, "a");
    try new_doc.array.local_insert(&one, 2);

    var two = YataCharacter.new(4, null, null, null, "b");
    try new_doc.array.local_insert(&two, 3);

    var thr = YataCharacter.new(5, null, null, null, "c");
    try new_doc.array.local_insert(&thr, 4);

    std.debug.print("{s}{s}\n", .{ two.left.?.content, one.content });
    try testify.expectEqual(two.left.?.content, one.content);
}
