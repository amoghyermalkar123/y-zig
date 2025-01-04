const DotCloud = @import("doc.zig").DotCloud;

// Updates is decoded from a remote peer data we get from the network
pub const Updates = struct {
    updates: DotCloud,
};

// TODO: should returning pending stack
// and the caller should handle this
// (typically the caller should be the doc store)
pub fn apply_update(update: Updates) anyerror!void {
    // STEP 1: integrate dot cloud
    // STEP 2: set the target client block list from the dot cloud
    // STEP 3: set the stack head (first element from the client block list)
    // STEP 4: figure out neighbor assignment is possible or not based off of left/right origins
    // STEP 5: integrate (optional, based on result of step 4)
}

pub fn integrate_structs() !void {}
