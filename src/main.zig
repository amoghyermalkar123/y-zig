const std = @import("std");

const CLIENT_ID: u64 = 1;

pub const Update = struct {
    character: []const u8,
    position: usize,
};

pub const YataCharacter = struct {
    id: u64,
    originLeft: ?*YataCharacter,
    left: ?*YataCharacter,
    right: ?*YataCharacter,
    isDeleted: bool,
    content: []const u8,

    pub fn new(id: u64, originLeft: ?*YataCharacter, left: ?*YataCharacter, right: ?*YataCharacter, content: []const u8) YataCharacter {
        return YataCharacter{
            .id = id,
            .originLeft = originLeft,
            .left = left,
            .right = right,
            .content = content,
            .isDeleted = false,
        };
    }
};

pub const YArray = struct {
    list: std.ArrayList(YataCharacter),
    current_capacity: u64,
    allocator: ?std.mem.Allocator = null,

    pub const InitConfig = struct {
        allocator: ?std.mem.Allocator = null,

        var default_gpa = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        var default_allocator = default_gpa.allocator();
    };

    pub fn init(config: InitConfig) anyerror!YArray {
        const decided_allocator = config.allocator orelse InitConfig.default_allocator;
        var arr = std.ArrayList(YataCharacter).init(decided_allocator);
        try arr.insert(0, YataCharacter.new(1, null, null, null, "*"));
        try arr.insert(1, YataCharacter.new(2, null, null, null, "*"));
        return YArray{
            .list = arr,
            .current_capacity = 0,
            .allocator = decided_allocator,
        };
    }

    pub fn deinit(self: *YArray) void {
        self.list.deinit();
    }

    pub fn local_insert(self: *YArray, newCharacter: *YataCharacter, pos: usize) anyerror!void {
        newCharacter.*.left = &self.list.items[pos - 2];
        newCharacter.*.originLeft = &self.list.items[pos - 2];
        newCharacter.*.right = &self.list.items[pos - 1];
        self.list.items[pos - 2].right = newCharacter;
        self.list.items[pos - 1].left = newCharacter;
        try self.list.insert(pos - 1, newCharacter.*);
        self.current_capacity += newCharacter.content.len;
        return;
        // TODO: the below implementation was an older one and it didn't work,
        // figure out why
        // pub fn get_adj_neighbors(self: *YArray, pos: usize) [2]YataCharacter {
        //     return [2]YataCharacter{ self.list.items[pos - 2], self.list.items[pos - 1] };
        // }

        // var neighs = self.get_adj_neighbors(pos);
        // newCharacter.*.left = &neighs[0];
        // newCharacter.*.right = &neighs[1];
        // neighs[0].right = newCharacter;
        // neighs[1].left = newCharacter;
    }

    pub fn integrate_insert(self: *YArray, updates: []Update, remote_client_id: u64) anyerror!void {
        // iterate over updates
        for (updates) |i| {
            // create a slice of conflicting ops
            const conflictingOps = self.list.items[i.position - 1 .. i.position];
            std.debug.print("conlen {d}\n", .{conflictingOps.len});
            // if len 0/ 1 -> locl insert
            if (conflictingOps.len == 0 or conflictingOps.len == 1) {
                var is = YataCharacter.new(10, null, null, null, i.character);
                try self.local_insert(&is, i.position - 1);
            } else {
                // else range over conflicting ops
                var listPos = i.position - 1;
                for (conflictingOps) |o| {
                    if (listPos > i.position) {
                        std.debug.print("break\n", .{});
                        break;
                    }
                    var ol = self.list.items[listPos - 1];
                    var is = YataCharacter.new(10, &ol, null, null, i.character);
                    if ((o.id < is.originLeft.?.id or is.originLeft.?.id <= o.originLeft.?.id) and (o.originLeft.?.id != is.originLeft.?.id or remote_client_id < CLIENT_ID)) {
                        // i is a successor of o
                        try self.local_insert(&is, listPos + 1);
                    }
                    listPos += 1;
                }
            }
        }
        return;
    }

    // caller owns memory
    pub fn content(self: *YArray, al: std.mem.Allocator) anyerror![]const u8 {
        const yataAllocation = self.list.allocatedSlice();
        const stringBuf = try al.alloc(u8, self.current_capacity);
        var p: usize = 0;

        for (yataAllocation, 0..) |value, i| {
            if (i >= self.list.items.len) break;
            if (std.mem.eql(u8, value.content, "*")) continue;
            const n = p + value.content.len;
            @memcpy(stringBuf[p..n], value.content);
            p += value.content.len;
        }
        return stringBuf;
    }
};

pub const YDoc = struct {
    clientId: u8 = CLIENT_ID,
    array: YArray,

    pub fn init() anyerror!YDoc {
        return YDoc{
            .array = try YArray.init(YArray.InitConfig{}),
        };
    }

    pub fn deinit(self: *YDoc) void {
        self.array.deinit();
    }

    pub fn content(self: *YDoc, al: std.mem.Allocator) anyerror![]const u8 {
        return self.array.content(al);
    }
};

pub fn main() anyerror!void {
    var new_doc: YDoc = try YDoc.init();
    defer new_doc.deinit();
}
