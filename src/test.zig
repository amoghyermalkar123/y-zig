const yzig = @import("main.zig");
const std = @import("std");

const YDoc = yzig.YDoc;
const YArray = yzig.YArray;
const YataCharacter = yzig.YataCharacter;
const Update = yzig.Update;

const testify = std.testing;

test "integrate: basic test" {
    var new_doc: YDoc = try yzig.YDoc.init();
    defer new_doc.deinit();

    var one = YataCharacter.new(3, null, null, null, "a");
    try new_doc.array.local_insert(&one, 2);

    var two = YataCharacter.new(4, null, null, null, "b");
    try new_doc.array.local_insert(&two, 3);

    var thr = YataCharacter.new(5, null, null, null, "c");
    try new_doc.array.local_insert(&thr, 4);

    var fr = YataCharacter.new(6, null, null, null, "d");
    try new_doc.array.local_insert(&fr, 5);

    var updates = [2]Update{
        Update{
            .character = "y",
            .position = 4,
        },
        Update{
            .character = "z",
            .position = 4,
        },
    };

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

    var fr = YataCharacter.new(6, null, null, null, "d");
    try new_doc.array.local_insert(&fr, 5);

    try testify.expectEqualSlices(u8, two.left.?.content, one.content);
}

fn debufprint(new_doc: *YArray) void {
    for (new_doc.list.items) |vl| {
        std.debug.print("-debug- char:{s} ", .{vl.content});
        if (vl.left != null) {
            std.debug.print("left :{s} ", .{vl.left.?.content});
        }
        if (vl.right != null) {
            std.debug.print("right :{s} ", .{vl.right.?.content});
        }
        std.debug.print("\n", .{});
    }
    return;
}
