const std = @import("std");

const assert = std.debug.assert;

const Feature = std.Target.x86.Feature;
const Set = std.Target.Cpu.Feature.Set;

pub const Level = enum {
    baseline,
    x86_64_v3,
};

pub const Probe = struct {
    feature: Feature,
    index: u5,
    saved: bool,
    word: Word,
};

pub const Word = enum {
    basic,
    extended,
    structured,
};

pub const probes = [_]Probe{
    .{ .feature = .avx, .index = 28, .saved = true, .word = .basic },
    .{ .feature = .avx2, .index = 5, .saved = true, .word = .structured },
    .{ .feature = .bmi, .index = 3, .saved = false, .word = .structured },
    .{ .feature = .bmi2, .index = 8, .saved = false, .word = .structured },
    .{ .feature = .cx16, .index = 13, .saved = false, .word = .basic },
    .{ .feature = .f16c, .index = 29, .saved = true, .word = .basic },
    .{ .feature = .fma, .index = 12, .saved = true, .word = .basic },
    .{ .feature = .lzcnt, .index = 5, .saved = false, .word = .extended },
    .{ .feature = .movbe, .index = 22, .saved = false, .word = .basic },
    .{ .feature = .popcnt, .index = 23, .saved = false, .word = .basic },
    .{ .feature = .sahf, .index = 0, .saved = false, .word = .extended },
    .{ .feature = .sse3, .index = 0, .saved = false, .word = .basic },
    .{ .feature = .sse4_1, .index = 19, .saved = false, .word = .basic },
    .{ .feature = .sse4_2, .index = 20, .saved = false, .word = .basic },
    .{ .feature = .ssse3, .index = 9, .saved = false, .word = .basic },
    .{ .feature = .xsave, .index = 26, .saved = true, .word = .basic },
};

pub const variant_names = [_][]const u8{
    "lacuna_variant_baseline",
    "lacuna_variant_x86_64_v3",
};

comptime {
    assert(variant_names.len == @typeInfo(Level).@"enum".field_names.len);
    assert(std.mem.endsWith(u8, variant_names[@backingInt(Level.x86_64_v3)], "x86_64_v3"));
    assert(probes.len == 16);
    assert(probes[0].feature == .avx);
}

pub fn level_of(features: Set) Level {
    comptime assert(probes.len == 16);

    assert(!features.isEnabled(@backingInt(Feature.@"16bit_mode")));
    assert(!features.isEnabled(@backingInt(Feature.@"32bit_mode")));

    for (probes) |probe| {
        if (!features.isEnabled(@backingInt(probe.feature))) return .baseline;
    }

    assert(features.count() >= probes.len);

    return .x86_64_v3;
}

fn model_features(model: *const std.Target.Cpu.Model) Set {
    assert(model.name.len > 0);
    assert(std.Target.x86.all_features.len > 0);

    var result = model.features;

    result.populateDependencies(&std.Target.x86.all_features);

    return result;
}

test level_of {
    const x86 = std.Target.x86.cpu;

    try std.testing.expectEqual(Level.baseline, level_of(model_features(&x86.x86_64)));
    try std.testing.expectEqual(Level.baseline, level_of(model_features(&x86.x86_64_v2)));
    try std.testing.expectEqual(Level.x86_64_v3, level_of(model_features(&x86.x86_64_v3)));
    try std.testing.expectEqual(Level.x86_64_v3, level_of(model_features(&x86.x86_64_v4)));
    try std.testing.expectEqual(Level.baseline, level_of(model_features(&x86.sandybridge)));
    try std.testing.expectEqual(Level.x86_64_v3, level_of(model_features(&x86.haswell)));
    try std.testing.expectEqual(Level.baseline, level_of(Set.empty));

    var without_movbe = model_features(&x86.x86_64_v3);

    without_movbe.removeFeature(@backingInt(Feature.movbe));

    try std.testing.expectEqual(Level.baseline, level_of(without_movbe));
}
