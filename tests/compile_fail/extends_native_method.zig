const lacuna = @import("lacuna");

const Registry = struct {
    label: u32,

    pub const extends = lacuna.Native.dictionary;

    pub fn merge(registry: *Registry, base: lacuna.Object) void {
        _ = registry;
        _ = base;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Registry} });
}
