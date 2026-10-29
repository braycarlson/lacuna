const lacuna = @import("lacuna");

const References = lacuna.ListType(lacuna.Reference, 4);

const Functions = struct {
    pub fn make() References {
        return .empty;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions });
}
