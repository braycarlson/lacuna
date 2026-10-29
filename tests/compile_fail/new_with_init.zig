const lacuna = @import("lacuna");

const Token = struct {
    key: i64,

    pub fn init(token: *Token, arguments: struct { key: i64 }) void {
        token.* = .{ .key = arguments.key };
    }

    pub fn __new__(
        class: lacuna.TypeObject,
        arguments: struct { key: i64 },
    ) lacuna.PythonError!lacuna.Reference {
        return class.instance_new(Token{ .key = arguments.key });
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Token} });
}
