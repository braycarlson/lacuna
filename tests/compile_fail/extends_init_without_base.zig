const lacuna = @import("lacuna");

const Base = struct {
    value: i64,

    pub const subclassable = true;

    pub fn init(base: *Base) void {
        base.* = .{ .value = 0 };
    }
};

const Derived = struct {
    extra: i64,

    pub const extends = Base;

    pub fn init(derived: *Derived) void {
        derived.* = .{ .extra = 0 };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Base, Derived } });
}
