const lacuna = @import("lacuna");

const Functions = struct {
    pub const coroutines = .{.total};
    pub const parallel = .{.total};

    pub fn total(arguments: struct { count: u64 }) void {
        _ = arguments;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
