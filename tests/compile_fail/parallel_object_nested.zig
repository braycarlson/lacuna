const lacuna = @import("lacuna");

const Functions = struct {
    pub const parallel = .{.touch};

    pub fn touch(arguments: struct { item: ?lacuna.Object }) bool {
        return arguments.item != null;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
