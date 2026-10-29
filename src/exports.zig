const std = @import("std");

const c = @import("c.zig");

const assert = std.debug.assert;

comptime {
    @setEvalBranchQuota(100_000);

    for (@typeInfo(c).@"struct".decl_names) |name| {
        if (function_is(@TypeOf(@field(c, name)))) {
            const all = c.exports ++ c.exports_free_threaded ++ c.exports_versioned ++
                c.exports_3_12 ++ c.exports_3_13 ++ c.exports_pypy;

            const listed = for (all) |exported| {
                if (std.mem.eql(u8, exported, name)) break true;
            } else false;

            if (!listed) {
                @compileError("lacuna: the extern '" ++ name ++ "' is missing from exports");
            }
        }
    }

    for (c.exports, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (!function_is(@TypeOf(@field(c, name)))) {
            @compileError("lacuna: the export '" ++ name ++ "' is not a function");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports[index - 1], name));
    }

    for (c.exports_free_threaded, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports_free_threaded[index - 1], name));
    }

    for (c.exports_3_12, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports_3_12[index - 1], name));
    }

    for (c.exports_3_13, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports_3_13[index - 1], name));
    }

    for (c.exports_versioned, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports_versioned[index - 1], name));
    }

    for (c.exports_pypy, 0..) |name, index| {
        if (!@hasDecl(c, name)) {
            @compileError("lacuna: the export '" ++ name ++ "' is not declared");
        }

        if (index > 0) assert(std.mem.lessThan(u8, c.exports_pypy[index - 1], name));
    }
}

fn function_is(comptime T: type) bool {
    comptime assert(T != noreturn);
    comptime assert(@typeInfo(T) != .@"opaque");

    return switch (@typeInfo(T)) {
        .@"fn" => true,
        .pointer => |pointer| @typeInfo(pointer.child) == .@"fn",
        else => false,
    };
}
