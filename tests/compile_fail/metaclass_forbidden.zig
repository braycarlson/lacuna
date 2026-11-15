const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Catalog = struct {
    pub const extends = lacuna.Native.type;
    pub const pickle = true;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Catalog} });
}
