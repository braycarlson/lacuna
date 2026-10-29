const std = @import("std");

const registry = @import("registry.zig");

const assert = std.debug.assert;

const Module = registry.Module;
const TypeObject = @import("value.zig").TypeObject;

const Counter = struct {
    count: u32,
    window: Window,

    pub const doc = "Counts up.";
    pub const fields = .{ .count = .read_write };

    pub fn init(counter: *Counter, arguments: struct { start: u32 = 0 }) void {
        assert(arguments.start < std.math.maxInt(u32));

        counter.* = .{
            .count = arguments.start,
            .window = .{ .start = arguments.start, .stop = arguments.start },
        };

        assert(counter.window.start == counter.count);
    }

    pub fn step(counter: *Counter) *Counter {
        assert(counter.count < std.math.maxInt(u32));

        counter.count += 1;
        counter.window.stop = @max(counter.window.stop, counter.count);

        assert(counter.window.stop >= counter.count);

        return counter;
    }

    pub fn __contains__(counter: *const Counter, arguments: struct { value: u32 }) bool {
        return arguments.value < counter.count;
    }
};

const Point = struct {
    horizontal: f64,
    vertical: f64,
};

const Window = struct {
    start: u32,
    stop: u32,
};

const Functions = struct {
    pub const docs = .{ .distance = "The distance between two points." };

    pub fn distance(arguments: struct { left: Point, right: Point }) f64 {
        const horizontal = arguments.left.horizontal - arguments.right.horizontal;
        const vertical = arguments.left.vertical - arguments.right.vertical;
        const result = std.math.hypot(horizontal, vertical);

        assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn origin() Point {
        return .{ .horizontal = 0, .vertical = 0 };
    }

    pub fn scale(
        arguments: struct { factor: f64 = 2.0, label: ?[]const u8 = null },
    ) error{Negative}!void {
        if (arguments.label) |label| assert(std.unicode.utf8ValidateSlice(label));

        if (arguments.factor < 0) return error.Negative;
    }
};

const Legacy = struct {
    pub const deprecated = .{ .reset = "use clear instead" };

    pub fn reset() void {}
};

const Gauge = struct {
    level: u32,

    pub const deprecated = .{ .zero = "use empty instead" };

    pub fn zero(gauge: *Gauge) void {
        assert(gauge.level <= std.math.maxInt(u32));

        gauge.level = 0;

        assert(gauge.level == 0);
    }
};

const Catalog = struct {
    pub const extends = @import("native.zig").Native.type;
    pub const subclassable = true;

    pub fn describe(class: TypeObject) bool {
        return class.object.none();
    }

    pub fn __contains__(class: TypeObject, arguments: struct { value: u32 }) bool {
        assert(!class.object.none());

        return arguments.value == 0;
    }
};

const Palette = struct {
    shade: u8,

    pub const metaclass = Catalog;
};

const Plugin = struct {
    level: u8,

    pub const metaclass = "registry.meta.Registered";
};

const Coroutines = struct {
    pub const coroutines = .{.fetch};

    pub fn fetch(arguments: struct { count: u32 }) u32 {
        return arguments.count;
    }
};

const Constants = struct {
    pub const count_max = 64;
    pub const version = "1.0";
};

pub const module: Module = .{
    .name = "sample",
    .classes = &.{Counter},
    .constants = Constants,
    .functions = Functions,
};

pub const module_without_constants: Module = .{
    .name = "sample",
    .classes = &.{Counter},
    .functions = Functions,
};

pub const module_deprecated: Module = .{
    .name = "legacy",
    .classes = &.{Gauge},
    .functions = Legacy,
};

pub const module_metaclass: Module = .{
    .name = "catalog",
    .classes = &.{ Catalog, Palette, Plugin },
    .functions = Coroutines,
};
