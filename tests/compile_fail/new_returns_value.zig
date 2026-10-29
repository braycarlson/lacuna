const lacuna = @import("lacuna");

const Token = struct {
    key: i64,

    pub fn __new__(arguments: struct { key: i64 }) Token {
        return .{ .key = arguments.key };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Token} });
}
