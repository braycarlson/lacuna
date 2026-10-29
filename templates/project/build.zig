const std = @import("std");

const lacuna = @import("lacuna");

pub fn build(builder: *std.Build) void {
    const module = builder.createModule(.{ .root_source_file = builder.path("src/root.zig") });

    const extension = lacuna.add_extension(builder, .{
        .dispatch = false,
        .free_threaded = &lacuna.free_threaded_default,
        .module = module,
        .name = "example",
        .optimize = builder.standardOptimizeOption(.{ .preferred_optimize_mode = null }),
        .package = .{
            .authors = &.{},
            .classifiers = &.{},
            .data = &.{},
            .dependencies = &.{},
            .description = null,
            .dynamic = &.{},
            .entry_points = &.{},
            .extras = &.{},
            .gui_scripts = &.{},
            .keywords = &.{},
            .license = null,
            .links = &.{},
            .maintainers = &.{},
            .name = "example",
            .obsoletes = &.{},
            .provides = &.{},
            .requires_python = null,
            .scripts = &.{},
            .summary = "An extension module written in Zig with lacuna.",
            .version = "0.1.0",
        },
        .platforms = &lacuna.platforms,
        .python_exclude_extensions = &lacuna.python_exclude_default,
        .python_include_extensions = null,
        .python_source = null,
        .pypy = &.{},
        .python_version_min = lacuna.python_version_floor,
        .release_optimize = .safe,
        .strip = false,
        .target = builder.standardTargetOptions(.{ .whitelist = null, .default_target = .{} }),
        .versioned = &.{},
    });

    _ = extension;
}
