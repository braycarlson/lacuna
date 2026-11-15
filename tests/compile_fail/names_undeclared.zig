const lacuna = @import("lacuna");

const Functions = struct {
    pub const names = .{ .missing = "present" };

    pub fn present() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
