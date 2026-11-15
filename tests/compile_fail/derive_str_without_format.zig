const lacuna = @import("lacuna");

const Ruler = struct {
    length: u32,

    pub const derive = .{ .init, .str };
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Ruler} });
}
