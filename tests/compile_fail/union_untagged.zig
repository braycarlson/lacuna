const lacuna = @import("lacuna");

const Number = union { integer: i64, float: f64 };

const Functions = struct {
    pub fn echo(arguments: struct { number: Number }) Number {
        return arguments.number;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
