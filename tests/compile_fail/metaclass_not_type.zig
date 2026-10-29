const lacuna = @import("lacuna");

pub const lacuna_stable_minor = 12;

const Ordinary = struct {
    level: u8,

    pub const subclassable = true;
};

const Plugin = struct {
    level: u8,

    pub const metaclass = Ordinary;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{ Ordinary, Plugin } });
}
