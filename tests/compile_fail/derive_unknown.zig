const lacuna = @import("lacuna");

const Pair = struct {
    left: i64,

    pub const derive = .{.order};
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Pair} });
}
