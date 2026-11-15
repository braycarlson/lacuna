const lacuna = @import("lacuna");

const Gauge = struct {
    level: u32,

    pub const deleters = .{ .reading = .reading_clear };
    pub const properties = .{.reading};

    pub fn init(gauge: *Gauge, arguments: struct { level: u32 }) void {
        gauge.* = .{ .level = arguments.level };
    }

    pub fn reading(gauge: *const Gauge) u32 {
        return gauge.level;
    }

    pub fn reading_clear(gauge: *Gauge, arguments: struct { level: u32 }) void {
        gauge.level = arguments.level;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Gauge} });
}
