const lacuna = @import("lacuna");

const Functions = struct {
    pub fn relay(loop: lacuna.Loop, arguments: struct { count: u32 }) u32 {
        if (loop.requested()) return 0;

        return arguments.count;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
