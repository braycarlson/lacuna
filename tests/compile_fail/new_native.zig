const lacuna = @import("lacuna");

const Registry = struct {
    label: u32,

    pub const extends = lacuna.Native.dictionary;

    pub fn __new__(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        _ = class;

        return error.PythonError;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Registry} });
}
