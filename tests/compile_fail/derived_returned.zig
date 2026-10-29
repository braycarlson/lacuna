const lacuna = @import("lacuna");

const Base = struct {
    value: i64,

    pub const subclassable = true;
};

const Derived = struct {
    extra: i64,

    pub const extends = Base;
    pub const static_methods = .{.make};

    pub fn make() Derived {
        return .{ .extra = 1 };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Base, Derived } });
}
