const std = @import("std");

pub const ID = struct {
    clock: u64,
    client: u64,

    pub fn id(clk: u64, client: u64) ID {
        return ID{
            .clock = clk,
            .client = client,
        };
    }
};
pub const YDoc = struct {};
