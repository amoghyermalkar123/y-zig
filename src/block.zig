const std = @import("std");
const Clock = @import("global_clock.zig").MonotonicClock;
const Allocator = std.mem.Allocator;
const ID = @import("doc.zig").ID;
const SearchMarkerType = @import("search_marker.zig").SearchMarkerType;

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

pub fn BlockStoreType() type {
    return struct {
        start: ?*Block = null,
        allocator: Allocator,
        markers: *SearchMarkerType(),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return Self{
                .allocator = allocator,
            };
        }

        pub fn add_block(self: *Self, block: Block, pos: usize, marker: bool) anyerror!*Block {
            const new_block = try self.allocator.create(Block);
            new_block.* = block;
            if (self.start == null) self.start = new_block else self.start.?.right = new_block;
            if (marker) self.markers.new(pos, new_block);
            return new_block;
        }

        pub fn content(self: *Self, allocator: *std.ArrayList(u8)) anyerror!void {
            var next = self.start;
            while (next != null) {
                try allocator.appendSlice(next.?.content);
                next = next.?.right orelse break;
            }
        }
    };
}

test "basic" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    var array = BlockStoreType().init(allocator);
    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum"));
}

test "traverse" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    var array = BlockStoreType().init(allocator);
    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum"));

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    try array.content(&buf);

    const content = try buf.toOwnedSlice();
    std.debug.print("Content: {s}\n", .{content});
}
