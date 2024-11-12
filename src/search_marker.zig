const std = @import("std");
const ID = @import("doc.zig").ID;
const Clock = @import("global_clock.zig").MonotonicClock;

const Allocator = std.mem.Allocator;

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

pub const Marker = struct {
    item: *Block,
    pos: usize,
    timestamp: i128,
};

pub const MarkerError = error{
    NoMarkers,
};

pub fn SearchMarkerType() type {
    return struct {
        markers: *std.ArrayList(Marker),
        curr_idx: u8,
        max_cap: u8 = 10,

        const Self = @This();

        pub fn init(allocator: *std.ArrayList(Marker)) Self {
            return Self{
                .markers = allocator,
                .curr_idx = 0,
            };
        }

        pub fn new(self: *Self, pos: usize, block: *Block) anyerror!void {
            try self.markers.append(.{
                .pos = pos,
                .item = block,
                .timestamp = std.time.milliTimestamp(),
            });
            self.curr_idx += 1;
        }

        // find_marker returns the best possible marker for a given position in the document
        pub fn find_marker(self: *Self, pos: usize) ?*Block {
            if (self.markers.items.len == 0) return null;

            // set the initial element
            var marker: Marker = self.markers.items[0];
            for (self.markers.items) |mrk| {
                if (pos == mrk.pos) {
                    marker = mrk;
                }
            }

            std.debug.print("alo", .{});
            var b: ?*Block = marker.item;
            const p = marker.pos;
            // iterate to right if possible
            while (b != null and p < pos) {
                std.debug.print("going right {s}\n", .{b.?.content});
                b = b.?.right orelse break;
            }
            // iterate to left if possible
            while (b != null and p > pos) {
                std.debug.print("going left {s}\n", .{b.?.content});
                b = b.?.left orelse break;
            }

            // TODO: from yjs - making sure the left can't be merged with
            //

            return b;
        }
    };
}

pub fn BlockStoreType() type {
    const markers = SearchMarkerType();
    return struct {
        start: ?*Block = null,
        curr: ?*Block = null,
        allocator: Allocator,
        marker_system: *markers,

        const Self = @This();

        pub fn init(allocator: Allocator, marker_system: *markers) Self {
            return Self{
                .allocator = allocator,
                .marker_system = marker_system,
            };
        }

        pub fn add_block(self: *Self, block: Block, pos: usize, marker: bool) anyerror!void {
            const new_block = try self.allocator.create(Block);
            new_block.* = block;

            if (marker) try self.marker_system.new(pos, new_block);

            if (self.start == null) {
                self.start = new_block;
            } else {
                if (self.curr == null) {
                    new_block.left = self.start.?;
                    self.start.?.right = new_block;
                    self.curr = new_block;
                } else {
                    self.curr.?.right = new_block;
                    new_block.left = self.curr.?;
                    self.curr.? = new_block;
                }
            }
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
    defer arena.deinit();

    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system);

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum "), 0, false);

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum 1 "), 1, false);

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum 2 "), 2, true);

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum 3 "), 3, false);

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum 4"), 3, false);

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();
    std.debug.print("{s}\n", .{content});
}
