const std = @import("std");
const ID = @import("doc.zig").ID;
const Block = @import("block.zig").Block;
const LOCAL_CLIENT = 1;

pub const Marker = struct {
    item: *Block,
    pos: usize,
    timestamp: i128,
};

// TODO: update markers at every change in the doc
pub fn SearchMarkerType() type {
    return struct {
        markers: [10]Marker,
        curr_idx: u8,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .markers = undefined,
            };
        }

        pub fn new(self: *Self, pos: usize, block: *Block) void {
            if (self.markers.len == self.curr_idx) {
                var oldest: i128 = 0;
                var oldest_pos: usize = 0;
                for (self.markers) |marker| {
                    if (marker.timestamp < oldest) {
                        oldest = marker.timestamp;
                        oldest_pos = marker.pos;
                    }
                }
            } else {
                self.markers[self.curr_idx] = .{
                    .pos = pos,
                    .item = block,
                    .timestamp = std.time.milliTimestamp(),
                };
                self.curr_idx += 1;
            }
        }

        fn find_closest_marker(self: *Self, pos: usize) *Marker {
            var marker = &Marker{};
            for (self.markers) |v| {
                if (v.pos > pos) {
                    marker = v;
                    break;
                }
            }
            return marker;
        }

        fn get_pos_block(marker: *Marker, index: usize) *Block {
            var b = marker.item;
            // iterate to right if possible
            while (b != null and marker.pos < index) {
                b = b.right;
            }
            // iterate to left if possible
            while (b != null and marker.pos > index) {
                b = b.left;
            }
            return b;
        }

        pub fn get_curr_pos_block(self: *Self, pos: usize) *Block {
            const marker = self.find_closest_marker(pos);
            const current_block = get_pos_block(marker, pos);
            return current_block;
        }
    };
}
