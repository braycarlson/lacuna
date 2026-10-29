const lacuna = @import("lacuna");

const Functions = struct {
    pub const docs = .{ .missing = "Nothing is declared under this name." };

    pub fn present() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
