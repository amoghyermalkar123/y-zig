const DotCloud = @import("doc.zig").DotCloud;

pub const Updates = struct {
    updates: DotCloud,
};

// TODO: should returning pending stack
// and the caller should handle this
// (typically the caller should be the doc store)
pub fn apply_update(update: Updates) anyerror!void {
    const iter = update.updates.client_blocks.iterator();
    const next = iter.next();
    var stack = next orelse unreachable;
    const client_id = stack.key_ptr;
    const client_block_list = stack.value_ptr.* orelse unreachable;
    var stack_head = client_block_list.start orelse unreachable;
}
