const std = @import("std");
const Item = @import("item.zig").Item;

// BlockStore represents a document-level block store
pub const BlockStore = struct {
    var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var default_allocator = default_gpa.allocator();
    // clientBlocks is a map of clientID to their respective blocks-list
    var clientBlocks = std.AutoHashMap(u64, ClientBlocksList).init(default_allocator);

    pub fn new() BlockStore {
        return BlockStore{};
    }

    pub fn insert() !void {}
    pub fn apply_updates() !void {}
};

// BlockCell represents either an integration-block or a GC-block
const BlockCell = enum(Item) {
    // Block is a type of Cell that needs to be integrated in the Document
    Block = Item,
};

// ClientBlocksList is a list of BlockCells. This list is maintained per client that
// a running instance of y-zig knows about.
const ClientBlocksList = struct {
    list: std.ArrayList(BlockCell),
};
