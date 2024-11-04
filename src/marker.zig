const std = @import("std");
const Block = @import("doc.zig").Block;
const ID = @import("doc.zig").ID;
const GlobalClock = @import("global_clock.zig").MonotonicClock;

// ---
pub const AssociativeArray = struct {
    assoc_array: *std.ArrayList(Block),

    var array = std.ArrayList(Block).init(std.heap.page_allocator);
    const Self = @This();

    pub fn init() Self {
        var b = Block{
            .id = ID{ .clock = 69, .client = 1 },
            .content = "*",
            // rest null
            .left = null,
            .right = null,
            .left_origin = null,
            .right_origin = null,
        };
        var b1 = Block{
            .id = ID{ .clock = 0, .client = 1 },
            .content = "*",
            // rest null
            .left = null,
            .right = null,
            .left_origin = null,
            .right_origin = null,
        };
        b.right = &b1;
        b.right_origin = b1.id;

        b1.left = &b;
        b1.left_origin = b.id;

        array.insert(0, b) catch {
            unreachable;
        };
        array.insert(1, b1) catch {
            unreachable;
        };
        return Self{
            .assoc_array = &array,
        };
    }

    // TODO: change this to search marker system later
    pub fn add(self: *Self, pos: usize, b: *Block) anyerror!void {
        try self.assoc_array.insert(pos, b.*);
        self.assoc_array.items[pos - 1].right = b;
        self.assoc_array.items[pos + 1].left = b;
        self.assoc_array.items[pos].left = &self.assoc_array.items[pos - 1];
        self.assoc_array.items[pos].right = &self.assoc_array.items[pos + 1];
    }
};

test "neighbors" {
    const MonC = @import("global_clock.zig").MonotonicClock;
    var m = MonC.init();
    var mc = &m;
    var aa = AssociativeArray.init();

    var b = Block{
        .id = ID{ .clock = mc.getClock(), .client = 1 },
        .content = "A",
        // rest null
        .left = null,
        .right = null,
        .left_origin = null,
        .right_origin = null,
    };
    try aa.add(1, &b);

    var b2 = Block{
        .id = ID{ .clock = mc.getClock(), .client = 1 },
        .content = "B",
        // rest null
        .left = null,
        .right = null,
        .left_origin = null,
        .right_origin = null,
    };
    try aa.add(2, &b2);

    var b3 = Block{
        .id = ID{ .clock = mc.getClock(), .client = 1 },
        .content = "C",
        // rest null
        .left = null,
        .right = null,
        .left_origin = null,
        .right_origin = null,
    };
    try aa.add(3, &b3);

    try std.testing.expectEqual(5, aa.assoc_array.items.len);

    for (aa.assoc_array.items) |v| {
        const r = v.right orelse {
            std.debug.print("--{s} with no right", .{v.content});
            break;
        };
        std.debug.print("--{s} and it's right {any} where {s}\n", .{ v.content, &r, r.content });
    }
}
