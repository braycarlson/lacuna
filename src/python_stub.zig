const std = @import("std");

const c = @import("c.zig");

const assert = std.debug.assert;

fn stub() callconv(.c) noreturn {
    @trap();
}

comptime {
    assert(c.exports.len > 0);
    assert(!c.free_threaded);

    for (c.exports) |name| @export(&stub, .{ .name = name });
}
