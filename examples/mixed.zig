const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "mixed._native",
    .doc = "The native half of a package that also ships Python modules.",
    .classes = if (lacuna.metaclasses) &.{Plugin} else &.{},
    .constants = Constants,
    .functions = Functions,
    .thread_safe = true,
};

const Constants = struct {
    pub const metaclasses = lacuna.metaclasses;
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

const Functions = struct {
    pub const docs = .{ .greet = "Greet someone by name." };

    pub fn greet(arguments: struct { name: []const u8 }) lacuna.TextError!Greeting {
        assert(std.unicode.utf8ValidateSlice(arguments.name));

        var result: Greeting = .empty;

        try result.print("Hello, {s}!", .{arguments.name});

        assert(std.mem.endsWith(u8, result.slice(), "!"));

        return result;
    }
};
