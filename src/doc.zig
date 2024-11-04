const std = @import("std");
const Updates = @import("update.zig").Updates;
const MarkerSystem = @import("marker.zig").AssociativeArray;
const MonotonicClock = @import("global_clock.zig").MonotonicClock;

const LOCAL_CLIENT = 1;

// all blocks owned by the doc
pub const YDoc = struct {
    block_store: *BlockStore,
    marker_system: MarkerSystem,
    mono_clock: MonotonicClock,

    const Self = @This();

    pub fn init() Self {
        const sp1 = &Block{ .id = ID{ .clock = 0, .client = LOCAL_CLIENT }, .left = null, .right = null, .left_origin = null, .right_origin = null, .content = "*" };
        return Self{
            .block_store = &BlockStore{
                .start = &sp1,
                .dot_cloud = DotCloud.init(),
            },
            .marker_system = MarkerSystem.init(),
            .mono_clock = MonotonicClock.init(),
        };
    }

    pub fn insert(self: *Self, pos: usize, text: []const u8) anyerror!void {
        const b = Block{
            .id = ID{ .clock = self.mono_clock.getClock(), .client = LOCAL_CLIENT },
            .content = text,
            .left = null,
            .right = null,
            .left_origin = null,
            .right_origin = null,
        };
        try self.marker_system.add(pos, b);
    }
};

const BlockStore = struct {
    start: *Block,
    dot_cloud: *DotCloud,
};

const DotCloudError = error{
    ClientDoesNotExist,
};

const DotCloud = struct {
    // this is an append-only list and does co-relate the actual user input sequence
    // that is maintained by the marker system, the job of the dot cloud is preserve
    // causal insertions by doing append-only ops on a per client basis
    // it acts as a state vector used to calculate the commutative delta and check how behind we're
    // from other nodes in the network.
    client_blocks: std.ArrayHashMap(u64, std.ArrayList(Block)),
    const Self = @This();

    pub fn init() *DotCloud!anyerror {
        const al = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const dc = &DotCloud{
            .client_blocks = std.ArrayHashMap(u64, std.ArrayList(Block)).init(al),
        };
        dc.client_blocks.putNoClobber(LOCAL_CLIENT, std.ArrayList(Block).init(al));
    }

    pub fn local_add(self: *Self, b: *Block) !anyerror {
        const client_blocks = self.client_blocks.get(LOCAL_CLIENT) orelse return DotCloudError.ClientDoesNotExist;
        try client_blocks.append(b);
    }
};

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
pub const Block = struct { id: ID, left_origin: ?ID, right_origin: ?ID, left: ?*Block, right: ?*Block, content: []const u8 };
