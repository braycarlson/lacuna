const std = @import("std");
const builtin = @import("builtin");

const dispatch = @import("dispatch.zig");

const assert = std.debug.assert;

const Set = std.Target.Cpu.Feature.Set;

const Leaf = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

const Words = std.enums.EnumArray(dispatch.Word, u32);

const leaf_basic: u32 = 1;
const leaf_extended: u32 = 0x8000_0001;
const leaf_extended_maximum: u32 = 0x8000_0000;
const leaf_maximum: u32 = 0;
const leaf_structured: u32 = 7;
const osxsave_index: u5 = 27;
const xcr0_saved_mask: u32 = 0b110;

comptime {
    assert(builtin.target.cpu.arch == .x86_64);
    assert(leaf_structured > leaf_basic);
    assert(leaf_extended > leaf_extended_maximum);
    assert(osxsave_index != dispatch.probes[0].index);
}

pub fn features_detect() Set {
    comptime assert(dispatch.probes.len == 16);

    const words = words_read();
    const saved = avx_saved(words.get(.basic));

    var result: Set = .empty;

    for (dispatch.probes) |probe| {
        if (probe.saved) {
            if (!saved) continue;
        }

        const word = words.get(probe.word);

        if ((word >> probe.index) & 1 == 1) result.addFeature(@backingInt(probe.feature));
    }

    assert(result.count() <= dispatch.probes.len);

    return result;
}

fn words_read() Words {
    const maximum = cpuid(leaf_maximum).eax;
    const extended_maximum = cpuid(leaf_extended_maximum).eax;

    assert(maximum >= leaf_basic);
    assert(extended_maximum >= leaf_extended_maximum);

    const basic = cpuid(leaf_basic).ecx;
    const structured = if (maximum >= leaf_structured) cpuid(leaf_structured).ebx else 0;
    const extended = if (extended_maximum >= leaf_extended) cpuid(leaf_extended).ecx else 0;

    return .init(.{ .basic = basic, .extended = extended, .structured = structured });
}

fn avx_saved(basic: u32) bool {
    const avx_index = dispatch.probes[0].index;

    comptime assert(dispatch.probes[0].feature == .avx);
    comptime assert(avx_index != osxsave_index);

    if ((basic >> osxsave_index) & 1 == 0) return false;
    if ((basic >> avx_index) & 1 == 0) return false;
    return xcr0_read() & xcr0_saved_mask == xcr0_saved_mask;
}

fn cpuid(leaf: u32) Leaf {
    comptime assert(@sizeOf(Leaf) == 16);

    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("cpuid"
        : [_] "={eax}" (eax),
          [_] "={ebx}" (ebx),
          [_] "={ecx}" (ecx),
          [_] "={edx}" (edx),
        : [_] "{eax}" (leaf),
          [_] "{ecx}" (@as(u32, 0)),
    );

    if (leaf == leaf_maximum) assert(eax >= leaf_basic);

    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

fn xcr0_read() u32 {
    comptime assert(xcr0_saved_mask & 1 == 0);

    const result = asm volatile (
        \\ xor %%ecx, %%ecx
        \\ xgetbv
        : [_] "={eax}" (-> u32),
        :
        : .{ .edx = true, .ecx = true });

    assert(result & 1 == 1);

    return result;
}

test features_detect {
    const query: std.Target.Query = .{ .cpu_model = .native };
    const native = try std.zig.system.resolveTargetQuery(std.testing.io, query);
    const detected = features_detect();

    for (dispatch.probes) |probe| {
        const index = @backingInt(probe.feature);
        const expected = native.cpu.features.isEnabled(index);

        try std.testing.expectEqual(expected, detected.isEnabled(index));
    }

    const level = dispatch.level_of(detected);

    try std.testing.expectEqual(dispatch.level_of(native.cpu.features), level);
}
