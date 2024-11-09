const std = @import("std");
const ID = @import("doc.zig").ID;
const Block = @import("block.zig").Block;
const LOCAL_CLIENT = 1;

pub const Marker = struct {
    item: *Block,
    pos: u64,
    timestamp: i128,
};

// TODO: update markers at every change in the doc
pub fn SearchMarkerType() type {
    return struct {
        markers: *std.ArrayList(Marker),
        curr_idx: u8,

        const Self = @This();

        pub fn init(allocator: std.ArrayList(Marker)) Self {
            var list = allocator;
            return Self{
                .markers = &list,
                .curr_idx = 0,
            };
        }

        pub fn new(self: *Self, pos: u64, block: *Block) anyerror!void {
            if (self.markers.items.len == self.curr_idx) {
                var oldest: i128 = 0;
                var oldest_pos: u64 = 0;
                for (self.markers.items) |marker| {
                    if (marker.timestamp < oldest) {
                        oldest = marker.timestamp;
                        oldest_pos = marker.pos;
                    }
                }
            } else {
                try self.markers.insert(pos, .{
                    .pos = pos,
                    .item = block,
                    .timestamp = std.time.milliTimestamp(),
                });
                self.curr_idx += 1;
            }
            std.debug.print("added new markers : {any}\n", .{self.markers});
        }

        fn find_closest_marker(self: *Self, pos: u64) Marker {
            var marker: Marker = undefined;
            for (self.markers.items) |v| {
                if (v.pos > pos) {
                    marker = v;
                    break;
                }
            }
            return marker;
        }

        fn get_pos_block(marker: Marker, index: u64) *Block {
            var b: ?*Block = marker.item;
            // iterate to right if possible
            while (b != null and marker.pos < index) {
                b = b.?.right;
            }
            // iterate to left if possible
            while (b != null and marker.pos > index) {
                b = b.?.left;
            }
            return b.?;
        }

        pub fn get_curr_pos_block(self: *Self, pos: u64) *Block {
            const marker = self.find_closest_marker(pos);
            std.debug.print("got marker pos: {any} address :{*}\n", .{ marker.item, marker.item });
            return get_pos_block(marker, pos);
        }
    };
}
