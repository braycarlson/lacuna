const lacuna = @import("lacuna");

const Functions = struct {
    pub fn scale(arguments: struct { factor: i64 = 2, value: i64 }) void {
        _ = arguments;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
