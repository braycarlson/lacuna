const lacuna = @import("lacuna");

const Functions = struct {
    pub fn watch(cancellation: lacuna.Cancellation) bool {
        return cancellation.requested();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
