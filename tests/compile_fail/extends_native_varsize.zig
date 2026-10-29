const lacuna = @import("lacuna");

const Counted = struct {
    step: u32,

    pub const extends = lacuna.Native.integer;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Counted} });
}
