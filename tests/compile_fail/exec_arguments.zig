const lacuna = @import("lacuna");

const Functions = struct {
    pub fn exec(arguments: struct { count: u32 }) void {
        _ = arguments;
    }

    pub fn ping() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
