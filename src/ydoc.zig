const Store = @import("docstore.zig").Store;

pub const YDoc = struct {
    store: Store,

    pub fn new() anyerror!YDoc {
        const d = try Store.new();
        return YDoc{ .store = d };
    }
};
