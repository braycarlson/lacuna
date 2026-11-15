const lacuna = @import("lacuna");

const Parent = struct {
    value: i64,

    pub const subclassable = true;

    pub fn init(parent: *Parent) void {
        parent.* = .{ .value = 0 };
    }
};

const Child = struct {
    extra: i64,

    pub const extends = Parent;
    pub const frozen = true;

    pub fn init(child: *Child, parent: *Parent) void {
        child.* = .{ .extra = 0 };
        parent.* = .{ .value = 0 };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Parent, Child } });
}
