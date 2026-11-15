const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Catalog = struct {
    count: u32,

    pub const extends = lacuna.Native.type;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Catalog} });
}
