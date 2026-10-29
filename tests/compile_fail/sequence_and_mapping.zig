const lacuna = @import("lacuna");

const Both = struct {
    count: u32,

    pub const mapping = true;
    pub const sequence = true;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Both} });
}
