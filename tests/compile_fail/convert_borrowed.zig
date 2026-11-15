const lacuna = @import("lacuna");

pub const lacuna_module: lacuna.Module = .{ .name = "fixture", .functions = Functions };

const Functions = struct {
    pub fn words(arguments: struct { item: lacuna.Object }) lacuna.PythonError!usize {
        const list = try arguments.item.convert(lacuna.ListType([]const u8, 4));

        return list.count;
    }
};

comptime {
    lacuna.module_export(lacuna_module);
}
