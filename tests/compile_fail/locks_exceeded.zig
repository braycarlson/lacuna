const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

const Point = struct {
    horizontal: f64,

    pub fn blend(
        point: *Point,
        arguments: struct { left: *const Point, right: *const Point },
    ) void {
        assert(@intFromPtr(point) % @alignOf(Point) == 0);
        assert(@intFromPtr(arguments.left) % @alignOf(Point) == 0);
        assert(@intFromPtr(arguments.right) % @alignOf(Point) == 0);

        point.horizontal = arguments.left.horizontal + arguments.right.horizontal;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Point} });
}
