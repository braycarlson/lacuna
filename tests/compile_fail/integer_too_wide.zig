const lacuna = @import("lacuna");

const Functions = struct {
    pub fn echo(arguments: struct { value: u1025 }) u1025 {
        return arguments.value;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
