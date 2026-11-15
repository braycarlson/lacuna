const lacuna = @import("lacuna");

const Functions = struct {
    pub const deprecated = .{ .old = .{ .message = "use new instead" } };

    pub fn new() void {}

    pub fn old() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
