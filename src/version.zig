const std = @import("std");

const assert = std.debug.assert;

pub const Version = struct {
    major: u8,
    minor: u8,

    pub fn rank(version: Version) u16 {
        assert(version.major > 0);

        const result = @as(u16, version.major) << 8 | version.minor;

        assert(result >> 8 == version.major);

        return result;
    }
};

pub const floor: Version = .{ .major = 3, .minor = 11 };
pub const per_interpreter_gil: Version = .{ .major = 3, .minor = 12 };
pub const text_bytes_max: u32 = 256;
const digits = "0123456789";

comptime {
    assert(per_interpreter_gil.rank() > floor.rank());
    assert(floor.major == per_interpreter_gil.major);
}

pub fn parse(text: []const u8) ?Version {
    assert(text.len <= text_bytes_max);

    const major_end = std.mem.findNone(u8, text, digits) orelse return null;
    if (major_end == 0) return null;
    if (text[major_end] != '.') return null;

    const rest = text[major_end + 1 ..];
    const minor_end = std.mem.findNone(u8, rest, digits) orelse rest.len;
    if (minor_end == 0) return null;

    const major = std.fmt.parseInt(u8, text[0..major_end], 10) catch return null;
    const minor = std.fmt.parseInt(u8, rest[0..minor_end], 10) catch return null;

    if (major == 0) return null;

    assert(std.ascii.isDigit(text[major_end - 1]));
    assert(minor_end == rest.len or !std.ascii.isDigit(rest[minor_end]));
    assert(major_end + 1 + minor_end <= text.len);

    return .{ .major = major, .minor = minor };
}

pub fn free_threaded_is(text: []const u8) bool {
    assert(text.len <= text_bytes_max);

    const marker = "free-threading build";
    const position = std.mem.find(u8, text, marker);

    if (position) |index| assert(index + marker.len <= text.len);
    if (text.len < marker.len) assert(position == null);

    return position != null;
}

test free_threaded_is {
    const Case = struct {
        expected: bool,
        text: []const u8,
    };

    const cases = [_]Case{
        .{ .expected = true, .text = "3.14.8 free-threading build (main, Oct 14 2026) [Clang]" },
        .{ .expected = true, .text = "3.13.16 experimental free-threading build (main) [Clang]" },
        .{ .expected = false, .text = "3.14.6 (main, Jul 23 2026, 14:45:24) [Clang 22.1.3 ]" },
        .{ .expected = false, .text = "3.12.0rc1" },
        .{ .expected = false, .text = "" },
    };

    for (cases) |case| {
        try std.testing.expectEqual(case.expected, free_threaded_is(case.text));
    }
}

test parse {
    const Case = struct {
        text: []const u8,
        expected: ?Version,
    };

    const cases = [_]Case{
        .{ .text = "3.11.14 (main, Oct 14 2026, 21:10:02) [Clang 20.1.4 ]", .expected = .{
            .major = 3,
            .minor = 11,
        } },
        .{ .text = "3.12.0rc1", .expected = .{ .major = 3, .minor = 12 } },
        .{ .text = "3.15.0a1+ (heads/main)", .expected = .{ .major = 3, .minor = 15 } },
        .{ .text = "4.0", .expected = .{ .major = 4, .minor = 0 } },
        .{ .text = "3", .expected = null },
        .{ .text = "3.", .expected = null },
        .{ .text = ".11", .expected = null },
        .{ .text = "+3.11", .expected = null },
        .{ .text = "3_1.11", .expected = null },
        .{ .text = "0.11", .expected = null },
        .{ .text = "3.256", .expected = null },
        .{ .text = "", .expected = null },
    };

    for (cases) |case| {
        try std.testing.expectEqual(case.expected, parse(case.text));
    }
}

test "rank orders versions like tuples" {
    const versions = [_]Version{
        .{ .major = 3, .minor = 10 },
        .{ .major = 3, .minor = 11 },
        .{ .major = 3, .minor = 12 },
        .{ .major = 3, .minor = 255 },
        .{ .major = 4, .minor = 0 },
    };

    for (versions, 0..) |left, left_index| {
        for (versions, 0..) |right, right_index| {
            try std.testing.expectEqual(left_index >= right_index, left.rank() >= right.rank());
        }
    }
}
