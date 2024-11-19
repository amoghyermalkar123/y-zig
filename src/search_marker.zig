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
        pub fn find_block(self: *Self, pos: usize) anyerror!Marker {
            if (self.markers.items.len == 0) return null;

            var marker: Marker = self.markers.items[0];
            for (self.markers.items) |mrk| {
                if (pos == mrk.pos) {
                    marker = mrk;
                }
            }

            var b: ?*Block = marker.item;
            // this will always point at the start of some block
            // because we traverse block by block and increment this
            // offset by the traversed block's content length
            var p = marker.pos;

            while (b != null and p < pos) {
                b = b.?.right orelse break;
                p += b.?.content.len;
            }

            while (b != null and p > pos) {
                b = b.?.left orelse break;
                p -= b.?.content.len;
            }

            // TODO: from yjs - making sure the left can't be merged with
            // TODO: update existing marker upon reaching limit
            const final = Marker{ .pos = p, .item = b.?, .timestamp = std.time.milliTimestamp() };
            try self.markers.append(final);
            return final;
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

        fn split_and_add_block(self: *Self, m: Marker, block: Block, index: usize) anyerror!void {
            // split a block into multiple which have the same client id
            // with left and right neighbors adjusted
            const split_point = m.pos + m.item.content.len - index;

            var bufal = std.ArrayList(u8).init(self.allocator);
            defer bufal.deinit();

            try bufal.append(m.item.content[0..split_point]);
            const text = try bufal.toOwnedSlice();
            var t = Block.block(block.id, text);

            try bufal.append(m.item.content[split_point..]);
            const text = try bufal.toOwnedSlice();
            // TODO: new id for the right side of the split block
            var b = Block.block(ID.id(), text);

            const split_one = try self.allocator.create(Block);
            split_one.* = t;

            const new_block = try self.allocator.create(Block);
            new_block.* = block;

            const split_two = try self.allocator.create(Block);
            split_two.* = b;

            split_one.*.right = new_block;
            new_block.*.left = split_one;
            new_block.*.right = split_two;
            split_two.*.left = new_block;
        }

        // TODO: clocks should be assigned by block store
        pub fn add_block(self: *Self, block: Block, index: usize) anyerror!void {
            const new_block = try self.allocator.create(Block);
            new_block.* = block;
            const m = try self.marker_system.find_block(index, block.content.len);
            if (index != m.pos) try self.split_and_add_block(m, block, index);
            // adjusting the new blocks left and right neighbors
            // TODO: use split blocks as neighbors for new_block
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

const t = std.testing;

test "localInsert" {
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

    try t.expectEqualSlices(u8, content, "Lorem Ipsum Lorem Ipsum 1 Lorem Ipsum 2 Lorem Ipsum 3 Lorem Ipsum 4");
}

test "searchMarkers" {
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

    try array.add_block(Block.block(ID.id(clk.getClock(), 1), "Lorem Ipsum 4"), 4, false);

    const marker = try marker_system.find_block(3, 6);
    std.debug.print("got marker: {s}", .{marker.?.item.content});
}
