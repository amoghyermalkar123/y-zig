const std = @import("std");
const Clock = @import("global_clock.zig").MonotonicClock;
const Set = @import("ziglangSet");

const Allocator = std.mem.Allocator;

pub const ID = struct {
    clock: u64,
    client: u64,

    pub fn id(clock: u64, client: u64) ID {
        return ID{
            .clock = clock,
            .client = client,
        };
    }
};

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

// TODO: Marker positions should ALWAYS point to the start of a block
// which holds a bigger content i.e. if a content in a block is 8 length
// and it's the second block at position 2, the marker should point to 2
// and this should follow along during block splitting as well.
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

        pub fn new(self: *Self, pos: usize, block: *Block) anyerror!Marker {
            try self.markers.append(.{
                .pos = pos,
                .item = block,
                .timestamp = std.time.milliTimestamp(),
            });
            self.curr_idx += 1;
            return self.markers.items[0];
        }

        // TODO: this should eventuall update all existing markers with every update that
        // happens in the document, right now it de-allocates all markers and keeps only one
        // for simplicity
        pub fn overwrite(self: *Self, pos: usize, block: *Block) anyerror!void {
            self.markers.deinit();
            self.curr_idx = 0;
            try self.new(pos, block);
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
        length: usize = 0,
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

        pub fn get_block_by_id(self: Self, id: ID) ?Block {
            var next = self.start;
            while (next) {
                if (next.?.id.clock == id.clock and next.?.id.client == id.client) return next;
                next = next.?.right;
            }
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

            self.allocator.destroy(m.item);

            try self.marker_system.overwrite(split_point, left_ptr);

            left_ptr.*.right = new_block;
            new_block.*.left = left_ptr;
            new_block.*.right = right_ptr;
            right_ptr.*.left = new_block;
        }

        // TODO: support multi-character inputs
        pub fn insert_text(self: *Self, index: usize, text: []const u8) anyerror!void {
            // allocate memory for new block
            const new_block = try self.allocator.create(Block);
            new_block.* = Block.block(ID.id(self.monotonic_clock.getClock(), 1), text);

            // find the neighbor via the marker system
            const m = self.marker_system.find_block(index) catch |err| switch (err) {
                MarkerError.NoMarkers => try self.marker_system.new(index, new_block),
                else => unreachable,
            };

            // attach left and right neighbors
            if (index < self.length) {
                // add items in the middle of the list
                // the marker system will find us exactly where this block needs to be added
                new_block.left = m.item.left;
                new_block.right = m.item;
                new_block.left.?.right = new_block;
                m.item.left = new_block;
            } else if (self.start == null) {
                // add first item
                self.start = new_block;
            } else {
                // add items that are appended
                m.item.right = new_block;
                new_block.left = m.item;
            }

            self.length += text.len;
        }

        pub fn content(self: *Self, allocator: *std.ArrayList(u8)) anyerror!void {
            var next = self.start;
            while (next != null) {
                try allocator.appendSlice(next.?.content);
                next = next.?.right orelse break;
            }
        }

        // caller should take care of adding the block to the respective dot cloud
        // TODO: assert origins exist for the block before executing anything in this function
        pub fn integrate(self: *Self, block: *Block) anyerror!void {
            std.debug.assert(block.left_origin != null and block.right_origin != null);

            var isConflict = false;
            if (!block.left and !block.right) {
                isConflict = true;
            } else if (!block.left and block.right) {
                const r = block.right.?;
                if (r.left != null) {
                    isConflict = true;
                }
            } else if (block.left) {
                if (block.left.?.right != block.right) {
                    isConflict = true;
                }
            } else unreachable;

            if (isConflict) {
                // set the left pointer, this is used across the conflict resolution loop to figure out the new neighbors
                // for ' block'
                var left = block.left;
                // set first conflicting item as start element of the document by default
                var o: ?*Block = null;
                // if we have a left neighbor, set that as the first conflicting item
                if (left) {
                    o = left.?.right;
                } else {
                    o = self.start orelse unreachable;
                }

                // now the first conflicting item has been set
                // let's move on to the conflict resolution loop

                // this array acts as a distinct set of items that are "potential" conflicts with the `block`
                // this is because we have not found the right neighbor for our block yet
                // at every point where we know that these set of items for sure won't conflict with the `block`
                // we clear this set out
                var conflicting_items = Set.Set(Block).init(self.allocator);
                defer conflicting_items.deinit();

                // this array acts as a distinct set of items which we consider as falling before `block`
                // this set is used in conjunction with the conflicting items set to figure out WHEN to clear
                // the conflicting set! this is used to avoid origin crossing since we only increment our left
                // pointer when we find that left origin is not the same for `block` and `o` but the left origin
                // of `o` falls in this set but is not present in the conflicting items set, this is because we know
                // for sure such items will not conflict with the `block`
                var items_before_origin = Set.Set(Block).init(self.allocator);
                defer items_before_origin.deinit();

                // conflict resolution loop starts
                while (o != null and o.? != block.right) {
                    items_before_origin.add(o.?.*);
                    conflicting_items.add(o.?.*);

                    // check for same left derivation points
                    if (o.left_origin == block.left_origin or (o != null and block != null and o.?.id.client == block.id.client and o.?.id.clock == block.id.clock)) {
                        // if left origin is same, order by client ids - we go with the ascending order of client ids from left ro right
                        if (o.?.id.client < block.id.client) {
                            left = o.?;
                            conflicting_items.clearAndFree();
                        } else if (o.?.right_origin == block.right_origin or (o != null and block != null and o.?.id.client == block.id.client and o.?.id.clock == block.id.clock)) {
                            // this loop breaks because we know that `block` and `o` had the same left,right derivation points.
                            break;
                        }
                        // check if the left origin of the conflicting item is in the ibo set but not in the conflicting items set
                        // if that is the case, we can clear the conflicting items set and increment our left pointer to point to the
                        // `o` block
                    } else if (o.?.left_origin != null and items_before_origin.contains(self.get_block_by_id(o.?.left_origin.?))) {
                        if (!conflicting_items.contains(self.get_block_by_id(o.?.left_origin.?))) {
                            left = o.?;
                            conflicting_items.clearAndFree();
                        }
                    } else {
                        // we might have found our left
                        break;
                    }
                    o = o.?.right;
                }
                // set the new neighbor
                block.left = left;
            }

            std.debug.print("conflict resolved left neighbor: id:{any} content: {s} \n", .{ block.left.?.id, block.left.?.content });

            // reconnect left neighbor
            if (block.left != null) {
                const right = block.left.?.right;
                block.right = right;
                block.left.?.right = block;
            } else {
                std.debug.print("block.left is null \n left neighbor reconnection failed :( \n", .{});
            }

            // reconnect right neighbor
            if (block.right != null) {
                block.right.left = block;
            } else {
                std.debug.print("block.left is null \n right neighbor reconnection failed :( \n", .{});
            }
        }
    };
}

const t = std.testing;

test "integrate - append should work" {}
test "integrate - adding in the middle should work" {}
test "integrate - adding at the start should work" {}

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
    try array.insert_text(5, "F");

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();

    try t.expectEqualSlices(u8, "ABCDEF", content);
}

test "localInsert between" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    try array.insert_text(0, "A");

    try array.insert_text(1, "B");

    try array.insert_text(1, "C");

    var buf = std.ArrayList(u8).init(std.heap.page_allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();

    try t.expectEqualSlices(u8, "ACB", content);
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

    var marker = try marker_system.find_block(0);
    try t.expectEqualStrings("A", marker.item.content);

    marker = try marker_system.find_block(3);
    try t.expectEqualStrings("D", marker.item.content);

    marker = try marker_system.find_block(59);
    try t.expectEqualStrings("E", marker.item.content);
}
