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

    var counter: u64 = 1;
    while (counter < 10000000) {
        var b3 = Block.block(
            ID.id(m_clk.getClock(), local_client),
            "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Curabitur pretium tincidunt lacus. Nulla gravida orci a odio. Nullam varius, turpis et commodo pharetra est, et congue eros lacus eu lectus. Sed sed nunc. Morbi arcu libero, rutrum ac, lobortis nec, dictum eu, sapien. Mauris venenatis consequat lorem. Phasellus ut lectus quis ligula vehicula scelerisque. Integer porta, lectus at sagittis pulvinar, augue turpis rhoncus nunc, eget aliquam justo nisi in odio. Nam euismod tellus id erat.Phasellus non purus gravida, cursus turpis quis, varius quam. Proin aliquet sapien sed tortor commodo, at pharetra quam gravida. Mauris ac tincidunt felis. Etiam egestas mauris id ultricies fringilla. Aliquam erat volutpat. Nam pellentesque eget eros at auctor. Proin vel tincidunt ligula. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas.",
        );
        try aa.add(counter, &b3);
        counter += 1;
    }

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
    std.debug.print("\n", .{});
}
