const std = @import("std");
const ID = @import("item.zig").ID;

pub const StateVector = struct {
    state_vector: std.ArrayHashMap(u64, ID),

    // returns the max observed clock value for a given clientID
    // if the client is not found, returns void
    pub fn getObservedClock(self: *StateVector, clientID: u64) ?ID {
        return self.state_vector.get(clientID);
    }
};
