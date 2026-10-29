const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "hello",
    .doc = "Greets from Zig.",
    .functions = Functions,
    .thread_safe = true,
};

const Functions = struct {
    pub const docs = .{ .add = "Add two integers." };

    pub fn add(arguments: struct { left: i64, right: i64 = 1 }) error{Overflow}!i64 {
        const result = try std.math.add(i64, arguments.left, arguments.right);

        assert(result - arguments.right == arguments.left);
        assert((result > arguments.left) == (arguments.right > 0));

        return result;
    }
};
