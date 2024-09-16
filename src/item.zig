pub const Item = struct {
    id: ID,
    left: *Item,
    right: *Item,
    origin_left: *Item,
    content: []const u8,
    is_deleted: bool,

    pub fn new(id: ID, content: []const u8) Item {
        return Item{
            .id = id,
            .content = content,
        };
    }
};

pub const ID = struct {
    clientId: u64,
    clock: u64,
};
