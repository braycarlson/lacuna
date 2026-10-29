const lacuna = @import("lacuna");

const Functions = struct {
    pub const names = .{ .present = "not valid" };

    pub fn present() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
