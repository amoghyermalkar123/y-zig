const std = @import("std");
const ID = @import("doc.zig").ID;
const GlobalClock = @import("global_clock.zig").MonotonicClock;

// ---

pub const Block = struct {
    id: ID,
    left_origin: ?ID,
    right_origin: ?ID,
    left: ?*Block,
    right: ?*Block,
    content: []const u8,

    pub fn block(id: ID, text: []const u8) Block {
        return Block{
            .id = id,
            .left = null,
            .left_origin = null,
            .right = null,
            .right_origin = null,
            .content = text,
        };
    }
};

pub const AssociativeArray = struct {
    list: *std.ArrayList(*Block),

    const Self = @This();

    var array = std.ArrayList(*Block).init(std.heap.page_allocator);

    pub fn init() Self {
        return Self{
            .list = &array,
        };
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit();
    }

    pub fn add(self: *Self, pos: usize, b: *Block) anyerror!void {
        try self.list.insert(pos, b);
        if (self.list.items.len > 2) {
            self.list.items[pos - 1].right = b;
            b.right = self.list.items[pos + 1];
        }
    }

    // caller owns memory
    pub fn content(self: *Self, al: *std.ArrayList(u8)) anyerror!void {
        for (self.list.items) |v| {
            try al.appendSlice(v.*.content);
        }
    }
};

test "basic-neighbors" {
    var m = GlobalClock.init();
    var m_clk = &m;
    const local_client = 1;

    var aa = AssociativeArray.init();
    defer aa.deinit();

    var b = Block.block(
        ID.id(m_clk.getClock(), local_client),
        "*",
    );
    try aa.add(0, &b);

    var b1 = Block.block(
        ID.id(m_clk.getClock(), local_client),
        "*",
    );
    try aa.add(1, &b1);

    var b2 = Block.block(
        ID.id(m_clk.getClock(), local_client),
        "A",
    );
    // a user will always start from 1-indexed document so naturally
    // the first position they will ever insert anything into is pos 1
    try aa.add(1, &b2);

    var b3 = Block.block(
        ID.id(m_clk.getClock(), local_client),
        "B",
    );
    try aa.add(2, &b3);

    var b4 = Block.block(
        ID.id(m_clk.getClock(), local_client),
        "C",
    );
    try aa.add(3, &b4);

    var p = aa.list.items[0];
    var o = aa.list.items[1];
    while (true) {
        if (p.right != null and o.right != null) {
            try std.testing.expectEqual(p.right.?.id, o.id);
            p = p.right.?;
            o = o.right.?;
        } else {
            break;
        }
    }
}
