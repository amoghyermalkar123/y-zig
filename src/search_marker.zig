const std = @import("std");
const Block = @import("./block_store.zig").Block;

pub const Marker = struct {
    item: *Block,
    pos: usize,
    timestamp: i128,
};

pub const MarkerError = error{
    NoMarkers,
};

// SearchMarkers are indexes for the underlying block store.
// they help save time traversing a block store
pub fn SearchMarkerType() type {
    return struct {
        markers: *std.AutoHashMap(usize, Marker),
        curr_idx: u8,
        max_cap: u8 = 10,

        const Self = @This();

        pub fn init(allocator: *std.AutoHashMap(usize, Marker)) Self {
            return Self{
                .markers = allocator,
                .curr_idx = 0,
            };
        }

        pub fn new(self: *Self, pos: usize, block: *Block) anyerror!Marker {
            const m = .{
                .pos = pos,
                .item = block,
                .timestamp = std.time.milliTimestamp(),
            };
            try self.markers.put(@intFromPtr(block), m);
            self.curr_idx += 1;
            return m;
        }

        pub const OpType = enum {
            add,
            del,
        };

        // should be called when a new block is added or an existing block is deleted
        // updates positions for block pointers
        pub fn update_markers(self: *Self, pos: usize, updated_item: *Block, opType: OpType) !void {
            var iter = self.markers.iterator();
            var next = iter.next();
            while (next != null) : (next = iter.next()) {
                var value = next.?.value_ptr;
                switch (opType) {
                    .add => if (value.pos >= pos) {
                        value.pos += updated_item.content.len;
                        value.timestamp = std.time.timestamp();
                    },
                    .del => if (value.pos >= pos) {
                        value.pos -= updated_item.content.len;
                        value.timestamp = std.time.timestamp();
                    },
                }
            }
            return;
        }

        pub fn deleteMarkerAtPos(self: *Self, pos: usize) void {
            var iter = self.markers.iterator();
            var next = iter.next();
            while (next != null) : (next = iter.next()) {
                if (pos == next.?.value_ptr.*.pos) {
                    _ = self.markers.remove(next.?.key_ptr.*);
                }
            }
        }

        pub fn destroy_markers(self: *Self) void {
            self.markers.clearAndFree();
            self.curr_idx = 0;
        }

        // find_marker returns the best possible marker for a given position in the document
        pub fn find_block(self: *Self, pos: usize) !Marker {
            if (self.markers.count() == 0) return MarkerError.NoMarkers;

            var iter = self.markers.iterator();
            var next = iter.next();

            const marker = next.?.value_ptr;

            while (next != null) : (next = iter.next()) {
                if (pos == next.?.value_ptr.pos) {
                    return next.?.value_ptr.*;
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
            try self.markers.put(@intFromPtr(b.?), final);
            return final;
        }
    };
}
