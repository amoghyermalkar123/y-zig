const std = @import("std");
const Clock = @import("global_clock.zig").MonotonicClock;
const BlockStore = @import("block_store.zig");
const Thread = std.Thread;

const TICKER = 1000000000;

pub const Tag = enum {
    block,
    sv,
};

pub const Entity = union(Tag) {
    block: *const BlockStore.BlockStoreType(),
    sv: *const std.AutoHashMap(u64, u64),
};

pub const Callback = struct {
    function: *const fn (Entity) void,
    args: Entity,
};

pub const TaskLoop = struct {
    // read only pointer to the block store
    block_store: *const BlockStore.BlockStoreType(),
    callbacks: *std.ArrayList(Callback),

    const Self = @This();

    pub fn init(store: *const BlockStore.BlockStoreType(), cb: *std.ArrayList(Callback)) Self {
        return .{
            .block_store = store,
            .callbacks = cb,
        };
    }

    pub fn register_callback(self: Self, callback: Callback) void {
        self.callbacks.append(callback) catch unreachable;
        return;
    }
};

// caller should spawn in seperate thread
// call blocks
pub fn EventLoop(self: TaskLoop) void {
    errdefer self.callbacks.clearAndFree();
    while (true) {
        std.time.sleep(TICKER);
        if (self.callbacks.items.len == 0) continue;
        defer self.callbacks.clearAndFree();
        for (self.callbacks.items) |callback| {
            callback.function(callback.args);
        }
    }
}

test "callbacks" {
    var clk = Clock.init();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var marker_list = std.ArrayList(BlockStore.Marker).init(allocator);
    var marker_system = BlockStore.SearchMarkerType().init(&marker_list);

    // we declare this as var but it coerces to const pointer when passed to TaskLoop.init(&store) below !!
    // you can check this because firstly it compiles, secondly if you try to mutate any field in block_store,
    // you get a compile error!
    var store = BlockStore.BlockStoreType().init(allocator, &marker_system, &clk);

    try store.insert_text(0, "A");

    var cb = std.ArrayList(Callback).init(allocator);

    const tl = TaskLoop.init(&store, &cb);
    tl.register_callback(
        .{
            .function = DefaultCallback,
            .args = .{
                .block = &store,
            },
        },
    );

    const thread = try Thread.spawn(.{}, EventLoop, .{tl});
    thread.join();
}

pub fn DefaultCallback(entity: Entity) void {
    switch (entity) {
        .block => |b| {
            std.debug.print("block: {s}\n", .{b.start.?.content});
        },
        .sv => |vec| {
            std.debug.print("sv: {any}\n", .{vec});
        },
    }
}
