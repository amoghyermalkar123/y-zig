const std = @import("std");
const UpdateStore = @import("update.zig");

// we only support text type document
pub const YDoc = struct {
    update_store: *UpdateStore,
    // TODO: transaction

    const Self = @This();

    pub fn init() Self {}
};
