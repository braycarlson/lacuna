const std = @import("std");

const assert = std.debug.assert;

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,
};

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,
};

pub const DateTime = struct {
    date: Date,
    time: Time,
    offset_seconds: ?i32 = null,
    zone_name: ?ZoneName = null,

    pub const ZoneName = @import("text.zig").TextType(64);
};

pub const Duration = struct {
    microseconds: i64,
};

pub const microseconds_per_second: i64 = 1_000_000;
pub const seconds_per_day: i64 = 86_400;

comptime {
    assert(microseconds_per_second * seconds_per_day < std.math.maxInt(i64));
    assert(@sizeOf(Duration) == @sizeOf(i64));
}

pub const Parts = struct {
    days: i64,
    seconds: i64,
    microseconds: i64,

    pub fn normalized(parts: *const Parts) bool {
        assert(@intFromPtr(parts) % @alignOf(Parts) == 0);

        if (parts.seconds < 0) return false;
        if (parts.seconds >= seconds_per_day) return false;
        if (parts.microseconds < 0) return false;
        return parts.microseconds < microseconds_per_second;
    }
};

pub fn duration_of(parts: Parts) ?Duration {
    assert(parts.normalized());

    const per_day: i128 = seconds_per_day * microseconds_per_second;

    const total = @as(i128, parts.days) * per_day +
        @as(i128, parts.seconds) * microseconds_per_second + parts.microseconds;

    const result: Duration = .{ .microseconds = std.math.cast(i64, total) orelse return null };
    const restored = parts_of(&result);

    assert(restored.days == parts.days);
    assert(restored.microseconds == parts.microseconds);

    return result;
}

pub fn parts_of(duration: *const Duration) Parts {
    assert(@intFromPtr(duration) % @alignOf(Duration) == 0);

    const per_day = seconds_per_day * microseconds_per_second;
    const rest = @mod(duration.microseconds, per_day);

    const result: Parts = .{
        .days = @divFloor(duration.microseconds, per_day),
        .seconds = @divFloor(rest, microseconds_per_second),
        .microseconds = @mod(rest, microseconds_per_second),
    };

    assert(result.normalized());

    return result;
}

test duration_of {
    const cases = [_]i64{
        0,
        1,
        -1,
        microseconds_per_second * seconds_per_day,
        -microseconds_per_second * seconds_per_day - 7,
        std.math.maxInt(i64),
        std.math.minInt(i64),
    };

    for (cases) |microseconds| {
        const duration: Duration = .{ .microseconds = microseconds };
        const restored = duration_of(parts_of(&duration)).?;

        try std.testing.expectEqual(microseconds, restored.microseconds);
    }

    const huge: Parts = .{ .days = std.math.maxInt(i64), .seconds = 0, .microseconds = 0 };

    try std.testing.expectEqual(@as(?Duration, null), duration_of(huge));
}
