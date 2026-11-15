const lacuna = @import("lacuna");

const Functions = struct {
    pub fn careful() lacuna.PythonError!void {
        try lacuna.exception.warn(error.Missing, "careful", 1);
    }
};

pub const lacuna_module: lacuna.Module = .{ .name = "fixture", .functions = Functions };

comptime {
    lacuna.module_export(lacuna_module);
}
