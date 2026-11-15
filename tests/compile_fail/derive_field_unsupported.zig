const lacuna = @import("lacuna");

const Pair = struct {
    left: [2]i64,

    pub const derive = .{.eq};
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Pair} });
}
