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
            std.debug.print("checking id: {any}\n", .{id});
            var next = self.start;
            while (next != null) {
                if (next.?.id.clock == id.clock and next.?.id.client == id.client) return next.?.*;
                next = next.?.right;
            }
            return next.?.*;
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
        // TODO: the first and the last element should not have empty left/ right origins
        // add a special char or id to handle this
        // otherwise it's preventing to identify case 3 of conflict resolution
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
                new_block.left_origin = m.item.left.?.id;
                new_block.right = m.item;
                new_block.right_origin = m.item.id;
                new_block.left.?.right = new_block;
                m.item.left = new_block;
            } else if (self.start == null) {
                // add first item
                self.start = new_block;
            } else {
                // add items that are appended
                m.item.right = new_block;
                new_block.left = m.item;
                new_block.left_origin = m.item.id;
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

        fn compareIDs(this: ?ID, that: ?ID) bool {
            if (this == null or that == null) return false;
            if (this.?.clock == that.?.clock and this.?.client == that.?.client) return true;
            return false;
        }

        // caller should take care of adding the block to the respective dot cloud
        // TODO: assert origins exist for the block before executing anything in this function
        pub fn integrate(self: *Self, block: *Block) anyerror!void {
            std.debug.assert(block.left_origin != null and block.right_origin != null);

            std.debug.print("integrating : {s}\n", .{block.content});
            var isConflict = false;
            if (block.left == null and block.right == null) {
                isConflict = true;
            } else if (block.left == null and block.right != null) {
                const r = block.right.?;
                if (r.left != null) {
                    isConflict = true;
                }
            } else if (block.left != null) {
                if (block.left.?.right != block.right) {
                    isConflict = true;
                }
            } else unreachable;

            if (isConflict) {
                std.debug.print("==conflict detected==\n", .{});
                // set the left pointer, this is used across the conflict resolution loop to figure out the new neighbors
                // for ' block'
                var left = block.left;
                var o: ?*Block = null;
                // if we have a left neighbor, set the right of it as the first conflicting item
                // since we cannot conflict with our own left.
                if (left != null) {
                    o = left.?.right;
                } else {
                    // if the left neighbor of the new block is null, we can start
                    // at the start of the document
                    o = self.start orelse unreachable;
                }

                // now the first conflicting item has been set
                // let's move on to the conflict resolution loop

                // this array acts as a distinct set of items that are "potential" conflicts with the `block`
                // this is because we have not found the right neighbor for our block yet
                // at every point where we know that these set of items for sure won't conflict with the `block`
                // we clear this set out
                var conflicting_items = std.AutoHashMap(ID, void).init(self.allocator);
                defer conflicting_items.deinit();

                // this array acts as a distinct set of items which we consider as falling before `block`
                // this set is used in conjunction with the conflicting items set to figure out WHEN to clear
                // the conflicting set! this is used to avoid origin crossing since we only increment our left
                // pointer when we find that left origin is not the same for `block` and `o` but the left origin
                // of `o` falls in this set but is not present in the conflicting items set, this is because we know
                // for sure such items will not conflict with the `block`
                var items_before_origin = std.AutoHashMap(ID, void).init(self.allocator);
                defer items_before_origin.deinit();

                // std.debug.print("first conflict block set: {s}\n", .{o.?.content});
                // std.debug.print("first left pointer set: {s}\n", .{left.?.content});
                // conflict resolution loop starts
                while (o != null and o != block.right) {
                    std.debug.print("==conflict res logic starts==\n", .{});
                    try items_before_origin.put(o.?.id, {});
                    try conflicting_items.put(o.?.id, {});
                    std.debug.print("IBO \n", .{});
                    var it = items_before_origin.keyIterator();
                    var value = it.next();
                    while (value != null) {
                        std.debug.print("item : {any}\n", .{value.?.*});
                        value = it.next();
                    }
                    std.debug.print("IBO end\n", .{});
                    // check for same left derivation points
                    if (o != null and BlockStoreType().compareIDs(o.?.left_origin, block.left_origin)) {
                        // if left origin is same, order by client ids - we go with the ascending order of client ids from left ro right
                        if (o.?.id.client < block.id.client) {
                            std.debug.print("CASE 1\n", .{});
                            left = o.?;
                            conflicting_items.clearAndFree();
                        } else if (o != null and BlockStoreType().compareIDs(o.?.right_origin, block.right_origin)) {
                            // this loop breaks because we know that `block` and `o` had the same left,right derivation points.
                            std.debug.print("CASE 2\n", .{});
                            break;
                        }
                        // check if the left origin of the conflicting item is in the ibo set but not in the conflicting items set
                        // if that is the case, we can clear the conflicting items set and increment our left pointer to point to the
                        // `o` block
                    } else if (o.?.left_origin != null and items_before_origin.contains(self.get_block_by_id(o.?.left_origin.?).?.id)) {
                        if (!conflicting_items.contains(self.get_block_by_id(o.?.left_origin.?).?.id)) {
                            std.debug.print("CASE 3\n", .{});
                            left = o.?;
                            conflicting_items.clearAndFree();
                        }
                        std.debug.print("SKIP\n", .{});
                    } else {
                        // we might have found our left
                        std.debug.print("WEIRD\n", .{});
                        break;
                    }
                    o = o.?.right;
                }
                // set the new neighbor
                block.left = left;
            }

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
                block.right.?.left = block;
            } else {
                std.debug.print("block.right is null \n right neighbor reconnection failed :( \n", .{});
            }
        }
    };
}

const t = std.testing;
const mem = std.mem;

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

test "integrate - basic non-conflicting case" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial blocks: "A" -> "B"
    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    // Create a new block "C" to insert between A and B
    const block_c = try allocator.create(Block);
    block_c.* = Block.block(ID.id(3, 2), "C");

    // Get references to A and B blocks
    const block_a = array.start.?;
    const block_b = block_a.right.?;

    // Set up proper block relationships
    block_c.left = block_a;
    block_c.right = block_b;
    block_c.left_origin = block_a.id; // A's actual ID
    block_c.right_origin = block_b.id; // B's actual ID

    // Integrate block C
    try array.integrate(block_c);

    // Verify the final sequence is "A" -> "C" -> "B"
    var buf = std.ArrayList(u8).init(allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ACB", content);
}

test "integrate - concurrent edits at same position" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial blocks: "A" -> "B"
    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    // Get references to A and B blocks
    const block_a = array.start.?;
    const block_b = block_a.right.?;

    // Create two concurrent blocks "C" and "D" from different clients
    // Both trying to insert between A and B
    const block_c = try allocator.create(Block);
    block_c.* = Block.block(ID.id(3, 1), "C"); // Client 1

    const block_d = try allocator.create(Block);
    block_d.* = Block.block(ID.id(3, 2), "D"); // Client 2

    // Set up relationships for both blocks
    block_c.left = block_a;
    block_c.right = block_b;
    block_c.left_origin = block_a.id;
    block_c.right_origin = block_b.id;

    block_d.left = block_a;
    block_d.right = block_b;
    block_d.left_origin = block_a.id;
    block_d.right_origin = block_b.id;

    // Integrate both blocks
    try array.integrate(block_c);
    try array.integrate(block_d);

    // Verify final sequence - since client 1 < client 2,
    // we expect "C" to be before "D"
    var buf = std.ArrayList(u8).init(allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "ACDB", content);
}

test "integrate - same client different clocks" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial blocks: "A" -> "B"
    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    const block_a = array.start.?;
    const block_b = block_a.right.?;

    const block_c1 = try allocator.create(Block);
    block_c1.* = Block.block(ID.id(3, 1), "C1");
    block_c1.left = block_a;
    block_c1.right = block_b;
    block_c1.left_origin = block_a.id;
    block_c1.right_origin = block_b.id;

    const block_c2 = try allocator.create(Block);
    block_c2.* = Block.block(ID.id(4, 1), "C2"); // Same client (1), different clock (4)
    block_c2.left = block_a;
    block_c2.right = block_b;
    block_c2.left_origin = block_a.id;
    block_c2.right_origin = block_b.id;

    try array.integrate(block_c1);
    try array.integrate(block_c2);

    var buf = std.ArrayList(u8).init(allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();
    try t.expectEqualSlices(u8, "AC2C1B", content);
}

test "integrate - duplicate ID" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    const block_a = array.start.?;
    const block_b = block_a.right.?;

    const block_c = try allocator.create(Block);
    block_c.* = Block.block(ID.id(3, 1), "C");
    block_c.left = block_a;
    block_c.right = block_b;
    block_c.left_origin = block_a.id;
    block_c.right_origin = block_b.id;

    const block_duplicate = try allocator.create(Block);
    block_duplicate.* = Block.block(ID.id(3, 1), "D"); // Same ID as block_c
    block_duplicate.left = block_a;
    block_duplicate.right = block_b;
    block_duplicate.left_origin = block_a.id;
    block_duplicate.right_origin = block_b.id;

    try array.integrate(block_c);
    try array.integrate(block_duplicate);

    var buf = std.ArrayList(u8).init(allocator);
    try array.content(&buf);
    const content = try buf.toOwnedSlice();
    // Duplicate is treated as a concurrent edit at the same time but in this case
    // it's the same client, so it acts as a local insert
    try t.expectEqualSlices(u8, "ADCB", content);
}

test "integrate - null origins should fail" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);

    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    const block_a = array.start.?;
    const block_b = block_a.right.?;

    const block_null = try allocator.create(Block);
    block_null.* = Block.block(ID.id(5, 1), "C");
    block_null.left = block_a;
    block_null.right = block_b;
    block_null.left_origin = null;
    block_null.right_origin = null;

    // This should trigger an assertion failure in debug mode
    if (!std.debug.runtime_safety) {
        try array.integrate(block_null);
    }
}

test "same origin multiple items - basic ordering" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial block
    try store.insert_text(0, "A");
    const origin_block = store.start.?;

    // Create blocks with same origin but different timestamps
    try store.insert_text(1, "B");
    try store.insert_text(1, "C");

    // Get the actual blocks in order they appear in the list
    const first_insert = origin_block.right.?; // Points to C
    const second_insert = first_insert.right.?; // Points to B

    // Verify correct ordering by clock
    // The later insertion (C) should have a higher clock than earlier insertion (B)
    try t.expect(first_insert.id.clock > second_insert.id.clock);

    // Also verify the actual content to make our test more explicit
    try t.expectEqualStrings("C", first_insert.content);
    try t.expectEqualStrings("B", second_insert.content);
}

// TODO: last 3 tests should be for the update flow
// TODO: work on the update flow
//

test "same origin multiple items - concurrent inserts" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create base structure: "A"
    try store.insert_text(0, "A");
    const origin_block = store.start.?;

    // Simulate concurrent inserts from different clients after "A"
    const block_b = try allocator.create(Block);
    block_b.* = Block.block(ID.id(2, 0), "B");
    block_b.left_origin = origin_block.id;

    const block_c = try allocator.create(Block);
    block_c.* = Block.block(ID.id(1, 0), "C");
    block_c.left_origin = origin_block.id;

    // Integrate in different order than final expected order
    try store.integrate(block_b); // Higher client ID
    try store.integrate(block_c); // Lower client ID

    // Verify final order should be A -> C -> B based on client IDs
    var current = store.start.?;
    try t.expect(mem.eql(u8, current.content, "A"));
    current = current.right.?;
    try t.expect(mem.eql(u8, current.content, "C")); // Lower client ID first
    current = current.right.?;
    try t.expect(mem.eql(u8, current.content, "B")); // Higher client ID second
}

test "null origin handling" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Insert at start of empty document (null origin)
    try store.insert_text(0, "A");
    try t.expect(store.start.?.left_origin == null);

    // Create block explicitly with null origin
    const block = try allocator.create(Block);
    block.* = Block.block(ID.id(1, 0), "B");
    block.left_origin = null;
    block.right_origin = null;

    try store.integrate(block);

    // Verify integration at document start
    try t.expect(mem.eql(u8, store.start.?.content, "A"));
    try t.expect(mem.eql(u8, store.start.?.right.?.content, "B"));
}

test "origin crossing prevention - basic" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // Create initial structure: "ABC"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");
    try store.insert_text(2, "C");

    const a_block = store.start.?;
    const b_block = a_block.right.?;
    const c_block = b_block.right.?;

    // Try to create blocks that would cause origin crossing
    const block_x = try allocator.create(Block);
    block_x.* = Block.block(ID.id(2, 0), "X");
    block_x.left_origin = c_block.id;
    block_x.right_origin = a_block.id;

    // This integration should prevent origin crossing
    try store.integrate(block_x);

    // Verify final order maintains no crossing
    var current = store.start;
    var content = std.ArrayList(u8).init(allocator);
    while (current != null) : (current = current.?.right) {
        try content.appendSlice(current.?.content);
    }

    const result = content.items;
    // X should not be between A and C (which would indicate crossing)
    try t.expect(!containsSubsequence(result, "AXC"));
}

fn containsSubsequence(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..(haystack.len - needle.len + 1)) |i| {
        if (mem.eql(u8, haystack[i..(i + needle.len)], needle)) {
            return true;
        }
    }
    return false;
}

test "YATA origin ordering - concurrent operations" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);

    // First create a base sequence locally: "ABC"
    try store.insert_text(0, "A");
    try store.insert_text(1, "B");
    try store.insert_text(2, "C");

    // Get our base blocks for setting up concurrent operations
    const block_a = store.start.?;
    const block_b = block_a.right.?;
    const block_c = block_b.right.?;

    // Now simulate two concurrent remote operations:
    // Remote client 2 creates block X with:
    // - left origin points to B
    // - right origin points to C
    const block_x = try allocator.create(Block);
    block_x.* = Block.block(ID.id(0, 2), "X"); // Client 2, clock 0
    block_x.left_origin = block_b.id;
    block_x.right_origin = block_c.id;

    // Remote client 3 creates block Y with:
    // - left origin points to A
    // - right origin points to C
    const block_y = try allocator.create(Block);
    block_y.* = Block.block(ID.id(0, 3), "Y"); // Client 3, clock 0
    block_y.left_origin = block_a.id;
    block_y.right_origin = block_c.id;

    // Integrate both blocks
    try store.integrate(block_x);
    try store.integrate(block_y);

    // Get final content
    var buf = std.ArrayList(u8).init(allocator);
    try store.content(&buf);
    const content = try buf.toOwnedSlice();

    // Verify that:
    // 1. Content maintains origin ordering
    // 2. Y is integrated after its left origin (A)
    // 3. X is integrated after its left origin (B)
    // 4. Both X and Y come before their right origin (C)
    try t.expect(content.len == 5); // A,B,C + X,Y

    // Find positions of each character
    const pos_a = std.mem.indexOf(u8, content, "A").?;
    const pos_b = std.mem.indexOf(u8, content, "B").?;
    const pos_c = std.mem.indexOf(u8, content, "C").?;
    const pos_x = std.mem.indexOf(u8, content, "X").?;
    const pos_y = std.mem.indexOf(u8, content, "Y").?;

    // Verify the final ordering respects origin relationships
    try t.expect(pos_a < pos_y); // Y must come after its left origin A
    try t.expect(pos_b < pos_x); // X must come after its left origin B
    try t.expect(pos_x < pos_c); // X must come before its right origin C
    try t.expect(pos_y < pos_c); // Y must come before its right origin C

    // The expected final sequence should be "AYBXC"
    try t.expectEqualStrings("AYBXC", content);
}
