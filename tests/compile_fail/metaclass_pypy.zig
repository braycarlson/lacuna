const lacuna = @import("lacuna");

pub const lacuna_abi: lacuna.c.ABI = .{ .pypy = .{ .major = 3, .minor = 12 } };

const Catalog = struct {
    pub const extends = lacuna.Native.type;
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Catalog} });
}
