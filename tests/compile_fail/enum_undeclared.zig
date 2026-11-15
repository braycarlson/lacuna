const lacuna = @import("lacuna");

const Level = enum { low, high };

const Functions = struct {
    pub fn echo(arguments: struct { level: Level }) Level {
        return arguments.level;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
