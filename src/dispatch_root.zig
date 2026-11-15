const std = @import("std");
const builtin = @import("builtin");

const debug_io = @import("debug_io.zig");
const detect = @import("detect.zig");
const dispatch = @import("dispatch.zig");
const options = @import("options");

const assert = std.debug.assert;

const Feature = std.Target.x86.Feature;

pub const std_options_debug_io: std.Io = debug_io.io;

extern fn lacuna_variant_baseline() callconv(.c) ?*anyopaque;
extern fn lacuna_variant_x86_64_v3() callconv(.c) ?*anyopaque;

comptime {
    assert(builtin.target.cpu.arch == .x86_64);
    assert(options.leaf.len > 0);

    const prefix = if (options.abi3t) "PyModExport_" else "PyInit_";

    @export(&initialize, .{ .name = prefix ++ options.leaf });
}

fn initialize() callconv(.c) ?*anyopaque {
    const features = detect.features();
    const level = dispatch.level_of(features);

    if (level == .x86_64_v3) assert(features.isEnabled(@backingInt(Feature.avx2)));
    if (level == .x86_64_v3) assert(features.isEnabled(@backingInt(Feature.fma)));

    return switch (level) {
        .baseline => lacuna_variant_baseline(),
        .x86_64_v3 => lacuna_variant_x86_64_v3(),
    };
}
