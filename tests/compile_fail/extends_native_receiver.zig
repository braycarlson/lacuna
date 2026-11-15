const lacuna = @import("lacuna");

const Registry = struct {
    label: u32,

    pub const extends = lacuna.Native.dictionary;

    pub fn init(base: lacuna.Object) Registry {
        _ = base;

        return .{ .label = 0 };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Registry} });
}
