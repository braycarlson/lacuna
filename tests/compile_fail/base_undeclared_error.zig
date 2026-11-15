const lacuna = @import("lacuna");

const Bases = struct {
    pub const Child = error.Missing;
};

const Functions = struct {
    pub fn fail() error{Child}!void {
        return error.Child;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .bases = Bases, .functions = Functions });
}
