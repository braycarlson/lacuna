const lacuna = @import("lacuna");

const Functions = struct {
    pub const parallel = .{.touch};

    pub fn touch(arguments: struct { item: lacuna.Object }) void {
        _ = arguments;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
