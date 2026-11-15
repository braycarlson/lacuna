const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

const Functions = struct {
    pub const parallel = .{.touch};

    pub fn touch(arguments: struct { item: ?lacuna.Object }) bool {
        if (arguments.item) |present| assert(!present.none());

        return arguments.item != null;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
