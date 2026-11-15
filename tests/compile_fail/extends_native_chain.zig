const lacuna = @import("lacuna");

const Base = struct {
    line: u32,

    pub const extends = lacuna.Native.exception;
    pub const subclassable = true;
};

const Derived = struct {
    column: u32,

    pub const extends = Base;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Base, Derived } });
}
