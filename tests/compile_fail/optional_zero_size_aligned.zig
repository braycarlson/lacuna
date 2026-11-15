const lacuna = @import("lacuna");

const Functions = struct {
    pub fn present(arguments: struct { value: ?[0]f128 }) bool {
        return arguments.value != null;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
