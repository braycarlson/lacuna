const lacuna = @import("lacuna");

const inner: lacuna.Module = .{ .name = "elsewhere.inner" };

comptime {
    lacuna.module_export(.{ .name = "fixture", .submodules = &.{inner} });
}
