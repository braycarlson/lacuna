const lacuna = @import("lacuna");

const Celsius = struct {
    degrees: f64,

    pub const python = struct {
        pub const annotation = "float";

        pub fn from(object: lacuna.Object) Celsius {
            _ = object;

            return .{ .degrees = 0 };
        }
    };
};

const Functions = struct {
    pub fn warm(arguments: struct { value: Celsius }) f64 {
        return arguments.value.degrees + 1;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
