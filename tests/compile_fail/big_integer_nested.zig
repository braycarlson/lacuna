const std = @import("std");

const lacuna = @import("lacuna");

const Functions = struct {
    pub fn first(arguments: struct { values: [2]std.math.big.int.Const }) u64 {
        return arguments.values[0].bitCountAbs();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
