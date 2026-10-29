const lacuna = @import("lacuna");

const Functions = struct {
    pub fn kind(class: lacuna.TypeObject) bool {
        return class.object.none();
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
