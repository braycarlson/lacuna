const lacuna = @import("lacuna");

const Point = struct {
    x: i64,

    pub const frozen = true;

    pub fn init(point: *Point) void {
        point.x = 0;
    }

    pub fn shift(point: *Point) void {
        point.x += 1;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Point} });
}
