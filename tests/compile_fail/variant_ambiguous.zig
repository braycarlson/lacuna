const lacuna = @import("lacuna");

const Either = union(enum) {
    left: i64,
    right: i64,
};

const Functions = struct {
    pub fn echo(arguments: struct { value: Either }) Either {
        return arguments.value;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
