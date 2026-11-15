const lacuna = @import("lacuna");

const Stack = struct {
    depth: u32,

    pub const buffer_locked = .{.push};

    pub fn init(stack: *Stack) void {
        stack.depth = 0;
    }

    pub fn push(stack: *Stack) void {
        stack.depth += 1;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Stack} });
}
