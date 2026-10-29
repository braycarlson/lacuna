const lacuna = @import("lacuna");

const Base = struct {
    sides: u32,

    pub const subclassable = true;

    pub fn init(base: *Base) void {
        base.* = .{ .sides = 0 };
    }
};

const Child = struct {
    radius: f64,

    pub const extends = Base;

    pub fn init(child: *Child, base: *Base) void {
        child.* = .{ .radius = 0 };
        base.* = .{ .sides = 0 };
    }
};

const Functions = struct {
    pub fn build(arguments: struct { kind: lacuna.Object }) lacuna.PythonError!lacuna.Reference {
        const class: lacuna.TypeObject = .{ .object = arguments.kind };

        return class.instance_new(Child{ .radius = 1 });
    }
};

comptime {
    lacuna.module_export(.{
        .name = "fixture",
        .classes = &.{ Base, Child },
        .functions = Functions,
    });
}
