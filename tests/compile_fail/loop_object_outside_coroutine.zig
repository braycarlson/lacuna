const lacuna = @import("lacuna");

const Functions = struct {
    pub fn hold(arguments: struct { item: lacuna.LoopObject }) bool {
        return @intFromPtr(arguments.item.pointer) != 0;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
