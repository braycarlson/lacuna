const lacuna = @import("lacuna");

const Functions = struct {
    pub fn fail() anyerror!void {
        return error.Failed;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
