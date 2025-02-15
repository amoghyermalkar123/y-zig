const std = @import("std");
const SearchMarkerType = @import("./search_marker.zig").SearchMarkerType;
const Marker = @import("./search_marker.zig").Marker;
const MarkerError = @import("./search_marker.zig").MarkerError;
const Clock = @import("global_clock.zig").MonotonicClock;
const assert = std.debug.assert;
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

// TODO: auto generate and persist this
const LOCAL_CLIENT = 1;

// Special Blocks indicating first and last elements
pub const SPECIAL_CLOCK_LEFT = 0;
pub const SPECIAL_CLOCK_RIGHT = 1;

// Block is a unit of an event totally ordered over a set such events
pub const Block = struct {
    id: ID,
    left_origin: ?ID,
    right_origin: ?ID,
    left: ?*Block,
    right: ?*Block,
    content: []const u8,

    const Self = @This();

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

    // attaches left and right to self
    fn attach_neighbor(self: *Self, left: *Block, right: *Block) void {
        left.right = self;
        self.left = left;
        self.right = right;
        right.left = self;
    }
};

// BlockStore is a primary way of doing ops on the sequenced list of blocks
pub fn BlockStoreType() type {
    const markers = SearchMarkerType();

    return struct {
        start: ?*Block = null,
        length: usize = 0,
        allocator: Allocator,
        marker_system: *markers,
        monotonic_clock: *Clock,
        state_vector: std.AutoHashMap(u64, u64),

        const Self = @This();

        pub fn init(allocator: Allocator, marker_system: *markers, clock: *Clock) Self {
            var state_vector = std.AutoHashMap(u64, u64).init(allocator);
            state_vector.put(LOCAL_CLIENT, 1) catch unreachable;

            return Self{
                .allocator = allocator,
                .marker_system = marker_system,
                .monotonic_clock = clock,
                .state_vector = state_vector,
            };
        }

        pub fn deinit(self: *Self) void {
            var next = self.start;
            while (next != null) {
                self.allocator.destroy(self.start.?);
                next = next.?.right;
            }
        }

        // TODO: optimize search
        // when items being added at end from remote update, this will never match for the right origin
        // because we are checking clock and client for right sentinel which will not match
        pub fn get_block_by_id(self: Self, id: ID) ?*Block {
            var next = self.start;
            while (next != null) {
                if (next.?.id.clock == id.clock and next.?.id.client == id.client) return next;
                next = next.?.right;
            }
            return next;
        }

        pub fn getState(self: *Self, client: u64) u64 {
            return self.state_vector.get(client) orelse 0;
        }

        // TODO: ponder: if someone gives a clock of 10 and highest value watched is 5
        // that would case this sv to misrepresent dot cloud space.
        pub fn updateState(self: *Self, block: *Block) !void {
            const current = self.getState(block.id.client);
            if (block.id.clock > current) {
                try self.state_vector.put(block.id.client, block.id.clock);
            }
        }

        // will allocate some space in memory and return the pointer to it.
        pub fn allocate_block(self: *Self, block: Block) !*Block {
            const new_block = try self.allocator.create(Block);
            new_block.* = block;
            return new_block;
        }

        // Returns the client ID if we're missing updates, null if we have everything
        pub fn getMissing(self: *Self, block: *Block) !?u64 {
            // Skip checking origin reference if it's a sentinel
            if (block.left_origin) |origin| {
                // If origin is from another client and we have a gap between the referenced origins clock vs
                // what we have locally for the same client. this is indicating that we are getting a remote
                // block whose left origin has a much higher clock for a client than what we see locally
                // for the same client
                if (origin.client != block.id.client and
                    // TODO: yjs uses >= for some reason, i have not figured out yet so i will go with > only since it makes
                    // sense to me
                    origin.clock > self.getState(origin.client))
                {
                    return origin.client;
                }
            }

            // same logic as above but for right origin
            if (block.right_origin) |r_origin| {
                // If right origin is from another client and we don't have its clock yet
                if (r_origin.client != block.id.client and
                    r_origin.clock > self.getState(r_origin.client))
                {
                    return r_origin.client;
                }
            }

            // We have all dependencies, try to find actual blocks, if not found, simply return the client id
            //
            // no gaps, safe to assign the left origin as the left neighbor
            if (block.left_origin) |origin| {
                // assign left neighbor, if we dont find the left origin block in our blockstore
                // return the origins client as missing client
                block.left = self.get_block_by_id(origin);
            }

            // no gaps, safe to assign the right origin as the right neighbor
            if (block.right_origin) |r_origin| {
                // assign right neighbor, if we dont find the right origin block in our blockstore
                // return the origins client as missing client
                block.right = self.get_block_by_id(r_origin);
            }

            return null;
        }

        // this function should only be called in certain scenarios when a block actually requires
        // splitting, the caller needs to have all checks in place before calling this function
        // we dont want to split weirdly
        fn split_and_add_block(self: *Self, m: Marker, new_block: *Block, index: usize) anyerror!void {
            const split_point = m.item.content.len - index - 1;

            // use split point to create two blocks
            const blk_left = try self.allocate_block(
                Block.block(
                    ID.id(self.monotonic_clock.getClock(), LOCAL_CLIENT),
                    try self.allocator.dupe(u8, m.item.content[0..split_point]),
                ),
            );

            const blk_right = try self.allocate_block(
                Block.block(
                    ID.id(self.monotonic_clock.getClock(), LOCAL_CLIENT),
                    try self.allocator.dupe(u8, m.item.content[split_point..]),
                ),
            );
            // insert left split block at index
            // insert new_block at the right of left split
            // insert right split block at the right of new_block
            self.replace_repair(m.item, blk_left, blk_right);
            // attaches the new left and right blocks to the new_block
            // we just created
            new_block.attach_neighbor(blk_left, blk_right);
        }

        // replaces `old` block by provided new_left and new_right
        // and de-allocates `old`
        fn replace_repair(self: *Self, old: *Block, new_left: *Block, new_right: *Block) void {
            if (old.left != null) {
                old.left.?.right = new_left;
                new_left.left = old.left;
            } else {
                self.start = new_left;
            }

            if (old.right != null) {
                new_right.right = old.right;
                old.right.?.left = new_right;
            }
        }

        // attaches new_block and neighbor block 'm' as each other's neighbor
        fn attach_neighbor(new_block: *Block, m: *Block) void {
            assert(m.left != null);
            // attach neighbors
            new_block.left = m.left;
            new_block.left_origin = m.left.?.id;

            new_block.right = m;
            new_block.right_origin = m.id;

            new_block.left.?.right = new_block;
            m.left = new_block;
        }

        // attaches new_block to the end of the block store
        // which is the `m` marker we get from the marker_system
        fn attach_last(new_block: *Block, m: *Block) void {
            m.right = new_block;
            new_block.right_origin = ID.id(SPECIAL_CLOCK_RIGHT, 1);
            new_block.left = m;
            new_block.left_origin = m.id;
        }

        // attaches new_block to the beginning of the block store
        fn attach_first(self: *Self, new_block: *Block) void {
            new_block.left_origin = ID.id(SPECIAL_CLOCK_LEFT, 1);
            new_block.right_origin = ID.id(SPECIAL_CLOCK_RIGHT, 1);
            self.start = new_block;
        }

        pub fn insert_text(self: *Self, index: usize, text: []const u8) !void {
            const new_block = try self.allocator.create(Block);
            new_block.* = Block.block(ID.id(self.monotonic_clock.getClock(), LOCAL_CLIENT), text);

            try self.insert(index, new_block);

            self.length += text.len;
            try self.updateState(new_block);
        }

        // inserts a text content in the block store
        // TODO: support the case where a new item is added at 0th index when one already exists
        pub fn insert(self: *Self, index: usize, new_block: *Block) !void {
            // find the neighbor via the marker system
            const m = self.marker_system.find_block(index) catch |err| switch (err) {
                MarkerError.NoMarkers => try self.marker_system.new(index, new_block),
                else => unreachable,
            };

            if (self.start == null) {
                self.attach_first(new_block);
                return;
            }

            if (index >= self.length) {
                attach_last(new_block, m.item);
                return;
            }

            if (index > m.pos and index < m.item.content.len) {
                try self.split_and_add_block(m, new_block, index);
                // TODO: bring marker updates out of this function
                self.marker_system.deleteMarkerAtPos(m.pos);
                try self.marker_system.update_markers(index, new_block, .add);
                _ = try self.marker_system.new(index, new_block);
            } else {
                attach_neighbor(new_block, m.item);
                try self.marker_system.update_markers(index, new_block, .add);
            }
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
        pub fn integrate(self: *Self, block: *Block) !void {
            assert(block.left_origin != null and block.right_origin != null);

            var isConflict = false;
            // this case check can be a false positive, if your blocks do no go through neighbor checking
            // before integrating this can act as a conflict (since remote blocks always come with empty left/right neighbors)
            // caller's responsibility to check if neighbor asg is possible or not based on the origins
            // if not only then call the integration process.
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

                // conflict resolution loop starts
                while (o != null and o != block.right) {
                    try items_before_origin.put(o.?.id, {});
                    try conflicting_items.put(o.?.id, {});

                    // check for same left derivation points
                    if (o != null and BlockStoreType().compareIDs(o.?.left_origin, block.left_origin)) {
                        // if left origin is same, order by client ids - we go with the ascending order of client ids from left ro right
                        if (o.?.id.client < block.id.client) {
                            left = o.?;
                            conflicting_items.clearAndFree();
                        } else if (o != null and BlockStoreType().compareIDs(o.?.right_origin, block.right_origin)) {
                            // this loop breaks because we know that `block` and `o` had the same left,right derivation points.
                            break;
                        }
                        // check if the left origin of the conflicting item is in the ibo set but not in the conflicting items set
                        // if that is the case, we can clear the conflicting items set and increment our left pointer to point to the
                        // `o` block
                    } else if (o.?.left_origin != null) {
                        const blk = self.get_block_by_id(o.?.left_origin.?);

                        if (blk != null and items_before_origin.contains(blk.?.id) and !conflicting_items.contains(blk.?.id)) {
                            left = o.?;
                            conflicting_items.clearAndFree();
                        } else {}
                    } else {
                        // we might have found our left
                        break;
                    }

                    o = o.?.right;
                }
                // set the new neighbor
                block.left = left;
            }

            // reconnect left neighbor
            if (block.left != null) {
                block.right = block.left.?.right;
                block.left.?.right = block;
            } else {
                block.right = self.start;
                self.start.?.left = block;
                self.start = block;
            }

            // reconnect right neighbor
            if (block.right != null) {
                block.right.?.left = block;
            }
        }
    };
}

const t = std.testing;
const mem = std.mem;

test "localInsert" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

    // Create initial blocks: "A" -> "B"
    try array.insert_text(0, "A");
    try array.insert_text(1, "B");

    // Get references to A and B blocks
    const block_a = array.start.?;
    const block_b = block_a.right.?;

    // Create two concurrent blocks "C" and "D" from different clients
    // Both trying to insert between A and B
    const block_c = try allocator.create(Block);
    block_c.* = Block.block(ID.id(2, 1), "C"); // Client 1

    const block_d = try allocator.create(Block);
    block_d.* = Block.block(ID.id(2, 2), "D"); // Client 2

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Setup marker system
    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var array = BlockStoreType().init(allocator, &marker_system, &clk);
    defer array.deinit();

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
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);
    defer store.deinit();

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

test "origin crossing prevention - basic" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);
    defer store.deinit();

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

test "blockSplit - basic" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);
    var store = BlockStoreType().init(allocator, &marker_system, &clk);
    defer store.deinit();

    try store.insert_text(0, "ABC");
    try store.insert_text(1, "DEF");

    var current = store.start;
    var content = std.ArrayList(u8).init(allocator);
    while (current != null) : (current = current.?.right) {
        try content.appendSlice(current.?.content);
    }

    const result = content.items;
    try t.expectEqualStrings("ADEFBC", result);
}

test "blockSplit - twice the split" {
    var clk = Clock.init();

    var arena = std.heap.ArenaAllocator.init(t.allocator);

    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);

    var store = BlockStoreType().init(allocator, &marker_system, &clk);
    defer store.deinit();

    try store.insert_text(0, "ABC");
    try store.insert_text(1, "DEF");
    try store.insert_text(1, "XY");

    var current1 = store.start;
    var content1 = std.ArrayList(u8).init(allocator);
    while (current1 != null) : (current1 = current1.?.right) {
        try content1.appendSlice(current1.?.content);
    }
    const result = content1.items;

    try t.expectEqualStrings("AXYDEFBC", result);
}

test "blockSplit - thrice the split" {
    var clk = Clock.init();

    var arena = std.heap.ArenaAllocator.init(t.allocator);

    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.AutoHashMap(usize, Marker).init(allocator);
    var marker_system = SearchMarkerType().init(&marker_list);

    var store = BlockStoreType().init(allocator, &marker_system, &clk);
    defer store.deinit();

    try store.insert_text(0, "ABC");
    try store.insert_text(1, "DEF");
    try store.insert_text(1, "LMN");
    try store.insert_text(1, "PQR");

    var current1 = store.start;
    var content1 = std.ArrayList(u8).init(allocator);
    while (current1 != null) : (current1 = current1.?.right) {
        try content1.appendSlice(current1.?.content);
    }
    const result = content1.items;

    try t.expectEqualStrings("APQRLMNDEFBC", result);
}
