const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "example",
    .functions = Functions,
    .thread_safe = true,
};

const Functions = struct {
    pub fn double(arguments: struct { value: i32 }) i64 {
        const result = @as(i64, arguments.value) * 2;

        assert(@divExact(result, 2) == arguments.value);

        return result;
    }
};
