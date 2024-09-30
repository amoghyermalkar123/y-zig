const std = @import("std");
const ClientBlocksList = @import("../store.zig").ClientBlocksList;

pub const Update = struct {
    updateBlocks: UpdateBlocks,
    pub fn init() Update {}
};

pub const UpdateBlocks = struct {
    // clientBlocks is a map of clientID to their respective blocks-list
    clientUpdateBlocks: std.AutoHashMap(u64, ClientBlocksList),
    pub fn init() UpdateBlocks {}
};
