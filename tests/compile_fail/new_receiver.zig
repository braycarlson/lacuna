const lacuna = @import("lacuna");

const Token = struct {
    key: i64,

    pub fn __new__(token: *const Token) lacuna.PythonError!lacuna.Reference {
        _ = token;

        return error.PythonError;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Token} });
}
