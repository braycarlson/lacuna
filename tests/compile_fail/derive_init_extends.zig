const lacuna = @import("lacuna");

const Base = struct {
    width: u32,

    pub const subclassable = true;

    pub fn init(base: *Base, arguments: struct { width: u32 }) void {
        base.* = .{ .width = arguments.width };
    }
};

const Child = struct {
    height: u32,

    pub const derive = .{.init};
    pub const extends = Base;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Base, Child } });
}
