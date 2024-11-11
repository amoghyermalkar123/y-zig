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
        markers: *std.ArrayList(Marker),
        curr_idx: u8,
        max_cap: u8 = 10,

        const Self = @This();

        pub fn init() Self {
            var list = std.ArrayList(Marker).init(std.heap.page_allocator);
            return Self{
                .markers = &list,
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

        pub fn find_marker(self: *Self, pos: usize) anyerror!Marker {
            var marker: Marker = self.markers.items[0];
            for (self.markers.items) |mrk| {
                if (pos > mrk.pos) {
                    marker = mrk;
                }
            }
            return marker;
        }
    };
}

const t = std.testing;
test "markers" {
    const Clock = @import("global_clock.zig").MonotonicClock;
    var clk = Clock.init();
    var sm = SearchMarkerType().init();
    var b1 = Block.block(ID.id(clk.getClock(), 1), "*");
    var b2 = Block.block(ID.id(clk.getClock(), 1), "*");
    try sm.new(0, &b1);
    try sm.new(1, &b2);
    const m = try sm.find_marker(2);
    try t.expectEqual("*", m.item.content);
}
