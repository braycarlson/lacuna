const lacuna = @import("lacuna");

const Counter = struct {
    count: u64,

    pub const coroutines = .{.total};

    pub fn init(counter: *Counter) void {
        counter.* = .{ .count = 0 };
    }

    pub fn total(counter: *const Counter) u64 {
        return counter.count;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Counter} });
}
