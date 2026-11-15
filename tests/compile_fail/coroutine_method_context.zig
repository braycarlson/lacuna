const lacuna = @import("lacuna");

const Counter = struct {
    count: u64,

    pub const coroutines = .{.describe};
    pub const frozen = true;

    pub fn init(counter: *Counter) void {
        counter.* = .{ .count = 0 };
    }

    pub fn describe(counter: *const Counter, class: lacuna.TypeObject) bool {
        return counter.count == 0 and class.object.none();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Counter} });
}
