const std = @import("std");
const Item = @import("item.zig").Item;
const ID = @import("item.zig").ID;
const Update = @import("update/updates.zig").Update;

// Store wraps the BlockStore type
// It handles integration and operations related to updates, merges, etc
pub const Store = struct {
    blocks: BlockStore,

    pub fn new() anyerror!Store {
        const blk = try BlockStore.new();
        return Store{ .blocks = blk };
    }
};

// test "basic" {
//     const store = Store.new();
//     store.insert();
//
//     const updates = [1]u64{1};
//     const pending = store.apply_updates(updates);
//
//     store.apply_updates(pending);
// }

// BlockStore represents a document-level block store
pub const BlockStore = struct {
    clientId: u64,
    currentClock: u64,
    // clientBlocks is a map of clientID to their respective blocks-list
    clientBlocks: std.AutoHashMap(u64, ClientBlocksList),

    var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var default_allocator = default_gpa.allocator();

    pub fn new() anyerror!BlockStore {
        var b = BlockStore{
            .clientId = 1,
            .currentClock = 0,
            .clientBlocks = std.AutoHashMap(u64, ClientBlocksList).init(default_allocator),
        };
        try b.clientBlocks.put(1, ClientBlocksList.new());
        return b;
    }

    pub fn local_insert(self: *BlockStore, pos: usize, content: []const u8) anyerror!void {
        const clientBlocklist = self.clientBlocks.get(self.clientId) orelse unreachable;
        // build item
        const new_clock = self.current_clock + 1;
        const item = Item.new(ID{
            .clientId = self.clientId,
            .clock = new_clock,
        }, content);
        // add item
        item.left = clientBlocklist.list.items[pos - 1].Block;
        item.right = clientBlocklist.list.items[pos].Block;
        try clientBlocklist.list.append(item);
        self.currentClock = new_clock;
    }

    // function will return void if integration was successfull
    // otherwise returns an Update struct consisting of blocks that couldnt be integrated
    pub fn integrate_update() Update!void {
        // first check if the update block received can be inserted next in the clock sequence
        // for the given client, if not add it to pending stack and find the missing client info
        // and start integrating blocks for that client
        //
        // if it can be inserted next in the clock sequence, check if it's conflicting with existing elements
        // if yes, resolve conflicts and then insert, if conflict cannot be resolved, add to pending stack and return

    }
};

// BlockCell represents either an integration-block or a GC-block
const BlockCell = union {
    // Block is a type of Cell that needs to be integrated in the Document
    Block: Item,
    GC: Item,
};

// ClientBlocksList is a list of BlockCells. This list is maintained per client that
// a running instance of y-zig knows about.
pub const ClientBlocksList = struct {
    list: std.ArrayList(BlockCell),
    var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var default_allocator = default_gpa.allocator();

    fn new() ClientBlocksList {
        return ClientBlocksList{
            .list = std.ArrayList(BlockCell).init(default_allocator),
        };
    }
};
