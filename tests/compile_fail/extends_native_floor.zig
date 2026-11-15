const lacuna = @import("lacuna");

const Failure = struct {
    line: u32,

    pub const extends = lacuna.Native.exception;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Failure} });
}
