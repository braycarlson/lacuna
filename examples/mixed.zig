const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "mixed._native",
    .doc = "The native half of a package that also ships Python modules.",
    .classes = if (lacuna.metaclasses) &.{ Badge, Plugin } else &.{Badge},
    .constants = Constants,
    .functions = Functions,
    .thread_safe = true,
};

const Constants = struct {
    pub const metaclasses = lacuna.metaclasses;
};

const Badge = struct {
    rank: u8,

    pub const doc = "A class that the package re-exports, so its module is the package.";
    pub const fields = .{ .rank = .read };
    pub const module_name = "mixed";

    pub fn init(badge: *Badge, arguments: struct { rank: u8 }) void {
        badge.* = .{ .rank = arguments.rank };
    }
};

const Plugin = struct {
    level: u8,

    pub const doc = "A class whose metaclass is the Python metaclass mixed.helpers.Registered.";
    pub const fields = .{ .level = .read };
    pub const metaclass = "mixed.helpers.Registered";
    pub const subclassable = true;

    pub fn init(plugin: *Plugin, arguments: struct { level: u8 = 0 }) void {
        plugin.* = .{ .level = arguments.level };

        assert(plugin.level == arguments.level);
    }
};

const Greeting = lacuna.TextType(128);

extern fn mixed_counter_next() u32;

const Functions = struct {
    pub const docs = .{
        .counter_next = "Count up through the shared library the wheel bundles.",
        .greet = "Greet someone by name.",
    };

    pub fn counter_next() u32 {
        return mixed_counter_next();
    }

    pub fn greet(arguments: struct { name: []const u8 }) lacuna.TextError!Greeting {
        assert(std.unicode.utf8ValidateSlice(arguments.name));

        var result: Greeting = .empty;

        try result.print("Hello, {s}!", .{arguments.name});

        assert(std.mem.endsWith(u8, result.slice(), "!"));

        return result;
    }
};
