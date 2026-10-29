const lacuna = @import("lacuna");

const Functions = struct {
    pub const deprecated = .{ .missing = "use present instead" };

    pub fn present() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
