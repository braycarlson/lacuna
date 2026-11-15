const lacuna = @import("lacuna");

const Functions = struct {
    pub fn keep(arguments: struct { item: lacuna.Reference }) void {
        _ = arguments;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
