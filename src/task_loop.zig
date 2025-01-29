const std = @import("std");
const Clock = @import("global_clock.zig").MonotonicClock;
const BlockStore = @import("block_store.zig");
const Thread = std.Thread;

pub const TaskLoop = struct {
    // read only pointer to the block store
    block_store: *const BlockStore.BlockStoreType(),
    tasks: *std.ArrayList(*const fn (*const BlockStore.BlockStoreType()) void),

    const Self = @This();

    pub fn init(store: *const BlockStore.BlockStoreType(), tasks: *std.ArrayList(*const fn (*const BlockStore.BlockStoreType()) void)) Self {
        return .{
            .block_store = store,
            .tasks = tasks,
        };
    }

    pub fn register_callback(self: Self, callback: *const fn (*const BlockStore.BlockStoreType()) void) void {
        self.tasks.append(callback) catch unreachable;
        return;
    }
};

// caller should spawn in seperate thread
// call blocks
pub fn loop(self: TaskLoop) void {
    while (true) {
        //wait
        std.time.sleep(100000000);
        //start
        if (self.tasks.items.len == 0) continue;
        std.debug.print("YES {d}\n", .{self.tasks.items.len});
        defer self.tasks.deinit();
        for (self.tasks.items, 0..) |task, i| {
            std.debug.print("index: {d}\n", .{i});
            task(self.block_store);
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

    var task_list = std.ArrayList(*const fn (*const BlockStore.BlockStoreType()) void).init(allocator);
    const tl = TaskLoop.init(&store, &task_list);
    tl.register_callback(clb);

    const thread = try Thread.spawn(.{}, loop, .{tl});
    thread.join();
}

fn clb(store: *const BlockStore.BlockStoreType()) void {
    std.debug.print("TEST: {s}\n", .{store.start.?.content});
}
