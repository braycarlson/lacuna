const lacuna = @import("lacuna");

const Pair = struct {
    left: f64,

    pub const derive = .{ .eq, .hash };
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Pair} });
}
