const std = @import("std");
const Item = @import("item.zig").Item;
const ID = @import("item.zig").ID;

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

    pub fn apply_updates() !void {}
};

// BlockCell represents either an integration-block or a GC-block
const BlockCell = union {
    // Block is a type of Cell that needs to be integrated in the Document
    Block: Item,
    GC: Item,
};

// ClientBlocksList is a list of BlockCells. This list is maintained per client that
// a running instance of y-zig knows about.
const ClientBlocksList = struct {
    list: std.ArrayList(BlockCell),
    var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var default_allocator = default_gpa.allocator();

    fn new() ClientBlocksList {
        return ClientBlocksList{
            .list = std.ArrayList(BlockCell).init(default_allocator),
        };
    }
};
