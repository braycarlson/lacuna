const lacuna = @import("lacuna");

const Marker = union(enum) { wide: [0]u128, none: void };

const Tally = struct {
    count: u32,
    marker: Marker,

    pub fn init(tally: *Tally) void {
        tally.* = .{ .count = 0, .marker = .none };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Tally} });
}
