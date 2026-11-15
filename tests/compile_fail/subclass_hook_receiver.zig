const lacuna = @import("lacuna");

const Plugin = struct {
    label: u32,

    pub const subclassable = true;

    pub fn init(plugin: *Plugin) void {
        plugin.* = .{ .label = 0 };
    }

    pub fn __init_subclass__(plugin: *const Plugin) void {
        _ = plugin;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Plugin} });
}
