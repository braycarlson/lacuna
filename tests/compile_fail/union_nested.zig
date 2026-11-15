const lacuna = @import("lacuna");

const Inner = union(enum) {
    left: i64,
    right: f64,
};

const Outer = union(enum) {
    inner: Inner,
    empty: void,
};

const Functions = struct {
    pub fn echo(arguments: struct { value: Outer }) Outer {
        return arguments.value;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions, .unions = &.{Outer} });
}
