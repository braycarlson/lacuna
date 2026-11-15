const lacuna = @import("lacuna");

const Plugin = struct {
    label: u32,

    pub fn init(plugin: *Plugin) void {
        plugin.* = .{ .label = 0 };
    }

    pub fn __init_subclass__(class: lacuna.TypeObject) void {
        _ = class;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Plugin} });
}
