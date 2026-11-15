const lacuna = @import("lacuna");

const Plugin = struct {
    level: u8,

    pub const metaclass = "plugins.meta.Registered";
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Plugin} });
}
