const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Catalog = struct {
    pub const extends = lacuna.Native.type;
};

const Palette = struct {
    shade: u8,

    pub const metaclass = Catalog;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Palette, Catalog } });
}
