const std = @import("std");

const lacuna = @import("lacuna");

const Big = std.math.big.int.Const;

const Widest = struct {
    a: Big,
    b: Big,
    c: Big,
    d: Big,
    e: Big,
    f: Big,
    g: Big,
    h: Big,
    i: Big,
};

const Functions = struct {
    pub fn widest(arguments: Widest) u64 {
        return arguments.a.bitCountAbs() + arguments.i.bitCountAbs();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
