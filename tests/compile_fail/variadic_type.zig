const lacuna = @import("lacuna");

const Functions = struct {
    pub fn gather(arguments: struct {
        rest: i64,

        pub const variadic = .rest;
    }) i64 {
        return arguments.rest;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
