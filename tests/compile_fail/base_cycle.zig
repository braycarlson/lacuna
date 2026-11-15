const lacuna = @import("lacuna");

const Bases = struct {
    pub const First = error.Second;
    pub const Second = error.First;
};

const Functions = struct {
    pub fn fail() error{ First, Second }!void {
        return error.First;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .bases = Bases, .functions = Functions });
}
