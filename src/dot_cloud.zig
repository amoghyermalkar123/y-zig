const std = @import("std");
const ID = @import("doc.zig").ID;
const Block = @import("block.zig").Block;
const BlockStore = @import("block.zig").BlockStoreType();
const SearchMarkers = @import("search_marker.zig").SearchMarkerType();
const Allocator = std.mem.Allocator;
const LOCAL_CLIENT = 1;

const DotCloudError = error{
    ClientDoesNotExist,
};

const DotCloud = struct {
    client_blocks: std.ArrayHashMap(u64, std.ArrayList(*Block)),
    block_store: BlockStore,
    search_markers: SearchMarkers,

    const Self = @This();

    pub fn init(al: Allocator) anyerror!DotCloud {
        const dc = &DotCloud{
            .client_blocks = std.ArrayHashMap(u64, std.ArrayList(*Block)).init(al),
        };
        dc.client_blocks.putNoClobber(LOCAL_CLIENT, std.ArrayList(*Block).init(al));
        return Self;
    }

    // it's important for the caller of this api to provide blocks whose content is a
    // single character. This is the raw block store and will only be responsible for the
    // core YATA CRDT algorithm, higher levels should work towards the qol content mgmt
    pub fn insert_text(self: *Self, b: *Block, pos: usize) anyerror!void {
        // get local clients block list
        const client_blocks = self.client_blocks.get(LOCAL_CLIENT) orelse return DotCloudError.ClientDoesNotExist;
        // allocate this block
        const block_ptr = try self.block_store.add_block(b.*, pos, true);
        // attach the neighbors
        const right = self.search_markers.get_curr_pos_block(pos);
        block_ptr.right = right;
        block_ptr.left = right.left;
        // add the final block into the local client list
        try client_blocks.append(block_ptr);
    }
};
