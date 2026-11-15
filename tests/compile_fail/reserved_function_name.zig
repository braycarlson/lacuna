const lacuna = @import("lacuna");

const Functions = struct {
    pub fn names(arguments: struct { count: u8 }) u8 {
        return arguments.count;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
