pub const MonotonicClock = struct {
    clock: u64,
    const Self = @This();

    pub fn init() Self {
        return Self{
            .clock = 2,
        };
    }
    pub fn getClock(self: *MonotonicClock) u64 {
        self.clock += 1;
        return self.clock;
    }
};
