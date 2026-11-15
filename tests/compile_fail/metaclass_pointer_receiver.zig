const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Catalog = struct {
    pub const extends = lacuna.Native.type;

    pub fn describe(catalog: *const Catalog) bool {
        _ = catalog;

        return true;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Catalog} });
}
