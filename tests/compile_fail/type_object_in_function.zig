const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

const Functions = struct {
    pub fn kind(class: lacuna.TypeObject) bool {
        assert(!class.object.none());

        return class.object.none();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
