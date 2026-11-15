const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Plugin = struct {
    level: u8,

    pub const metaclass = "Registered";
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Plugin} });
}
