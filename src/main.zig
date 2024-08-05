const std = @import("std");

const CLIENT_ID: u8 = 1;

const YZigError = error{
    LocalInsertError,
};

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
    allocator: ?std.mem.Allocator = null,

    pub const InitConfig = struct {
        allocator: ?std.mem.Allocator = null,

        var default_gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var default_allocator = default_gpa.allocator();
    };

    pub fn init(config: InitConfig) YArray {
        const arr = std.ArrayList(YataCharacter).init(config.allocator orelse InitConfig.default_allocator);
        return YArray{
            .list = arr,
        };
    }

    pub fn local_insert(self: *YArray, newCharacter: YataCharacter) !void {
        for (self.list.allocatedSlice(), 0..) |yc, currentIdx| {
            if (newCharacter.id > yc.id) {
                try self.list.insert(currentIdx, newCharacter);
            }
        }
    }
};

const YDoc = struct {
    clientId: u8 = CLIENT_ID,
    array: YArray,

    pub fn init() YDoc {
        return YDoc{
            .array = YArray.init(YArray.InitConfig{}),
        };
    }
};

pub fn main() !void {
    var new_doc: YDoc = YDoc.init();
    try new_doc.array.local_insert(YataCharacter.new(1, "", "", "*", "*"));
    try new_doc.array.local_insert(YataCharacter.new(2, "*", "*", "", "*"));
}

fn shenanigan1() void {
    const local: []const u8 = "amogh";
    std.debug.print("source {s}\n", .{local});
    var new_local: [local.len + 1]u8 = undefined;
    @memcpy(new_local[1..], local);
    @memcpy(new_local[0..1], "y");
    std.debug.print("after {s}\n", .{new_local});
}

// test "slices" {
//     const local: [4]u8 = [_]u8{ 11, 23, 45, 56 };
//     std.debug.print("source {any}\n", .{@TypeOf(local)});
//     const other = local[0..2];
//     std.debug.print("type {any}\n", .{@TypeOf(other)});
// }
//
// test "array" {
//     var arr = std.ArrayList(u8).init(std.testing.allocator);
//     defer arr.deinit();
//     try arr.insert(0, 12);
//     std.debug.print("{any}", .{arr.allocatedSlice()[0]});
// }
