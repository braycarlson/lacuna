const std = @import("std");
const builtin = @import("builtin");

const detect = @import("detect.zig");
const dispatch = @import("dispatch.zig");
const options = @import("options");

const assert = std.debug.assert;

const Feature = std.Target.x86.Feature;

extern fn lacuna_variant_baseline() callconv(.c) ?*anyopaque;
extern fn lacuna_variant_x86_64_v3() callconv(.c) ?*anyopaque;

comptime {
    assert(builtin.target.cpu.arch == .x86_64);
    assert(options.leaf.len > 0);

    @export(&initialize, .{ .name = "PyInit_" ++ options.leaf });
}

fn initialize() callconv(.c) ?*anyopaque {
    const features = detect.features_detect();
    const level = dispatch.level_of(features);

    if (level == .x86_64_v3) assert(features.isEnabled(@backingInt(Feature.avx2)));
    if (level == .x86_64_v3) assert(features.isEnabled(@backingInt(Feature.fma)));

    return switch (level) {
        .baseline => lacuna_variant_baseline(),
        .x86_64_v3 => lacuna_variant_x86_64_v3(),
    };
}
