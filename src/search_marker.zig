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
            if (self.markers.items.len == 0) return MarkerError.NoMarkers;

            var marker: Marker = self.markers.items[0];
            for (self.markers.items) |mrk| {
                if (pos == mrk.pos) {
                    marker = mrk;
                    return marker;
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
        monotonic_clock: *Clock,

        const Self = @This();

        pub fn init(allocator: Allocator, marker_system: *markers, clock: *Clock) Self {
            return Self{
                .allocator = allocator,
                .marker_system = marker_system,
                .monotonic_clock = clock,
            };
        }

        // this function should only be called in certain scenarios when a block actually requires
        // splitting, the caller needs to have all checks in place before calling this function
        // we dont want to split weirdly
        fn split_and_add_block(self: *Self, m: Marker, new_block: *Block, index: usize) anyerror!void {
            // split a block into multiple which have the same client id
            // with left and right neighbors adjusted
            std.debug.print("{d}.{d}.{d}\n", .{ m.pos, m.item.content.len, index });
            const split_point = m.pos + m.item.content.len - index;

            var bufal = std.ArrayList(u8).init(self.allocator);
            errdefer bufal.deinit();

            try bufal.appendSlice(m.item.content[0..split_point]);
            const textl = try bufal.toOwnedSlice();
            const left = Block.block(new_block.id, textl);

            try bufal.appendSlice(m.item.content[split_point..]);
            const text = try bufal.toOwnedSlice();
            const right = Block.block(ID.id(self.monotonic_clock.getClock(), 1), text);

            const left_ptr = try self.allocator.create(Block);
            left_ptr.* = left;

            const right_ptr = try self.allocator.create(Block);
            right_ptr.* = right;

            left_ptr.*.right = new_block;
            new_block.*.left = left_ptr;
            new_block.*.right = right_ptr;
            right_ptr.*.left = new_block;
        }

        // TODO: clocks should be assigned by block store
        pub fn insert_text(self: *Self, index: usize, text: []const u8) anyerror!void {
            const new_block = try self.allocator.create(Block);
            new_block.* = Block.block(ID.id(self.monotonic_clock.getClock(), 1), text);

            // TODO: find_block should give you the closest approximation block
            // in other words the exact block which can either be the neighbor of new_block
            // or will be split into new blocks (if required) for them to be neighbors
            // of new_block, revisit the and test find_block
            const m = self.marker_system.find_block(index) catch |err| switch (err) {
                MarkerError.NoMarkers => return try self.marker_system.new(index, new_block),
                else => unreachable,
            };
            // adjusting the new blocks left and right neighbors
            if (index != m.pos) try self.split_and_add_block(m, new_block, index);

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
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    try array.insert_text(0, "A");

    try array.insert_text(1, "B");

    try array.insert_text(2, "C");

    try array.insert_text(3, "D");

    try array.insert_text(4, "E");

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
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    try array.insert_text(0, "A");

    try array.insert_text(1, "B");

    try array.insert_text(2, "C");

    try array.insert_text(3, "D");

    try array.insert_text(4, "E");

    const marker = try marker_system.find_block(3);
    std.debug.print("got marker: {s}", .{marker.item.content});
}
