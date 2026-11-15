const lacuna = @import("lacuna");

const Bases = struct {
    pub const Missing: lacuna.BuiltinError = .value_error;
};

const Functions = struct {
    pub fn fail() error{Present}!void {
        return error.Present;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .bases = Bases, .functions = Functions });
}
