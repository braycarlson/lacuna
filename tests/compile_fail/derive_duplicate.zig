const lacuna = @import("lacuna");

const Pair = struct {
    left: i64,

    pub const derive = .{ .eq, .hash };

    pub fn __hash__(pair: *const Pair) i64 {
        return pair.left;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Pair} });
}
