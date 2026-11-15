const lacuna = @import("lacuna");

const Functions = struct {
    pub const coroutines = .{.inspect};

    pub fn inspect(arguments: struct { item: lacuna.Object }) bool {
        return arguments.item.none();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
