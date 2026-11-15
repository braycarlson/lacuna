const std = @import("std");

const assert = std.debug.assert;

var count: std.atomic.Value(u32) = .init(0);

export fn mixed_counter_next() u32 {
    const previous = count.fetchAdd(1, .monotonic);

    assert(previous < std.math.maxInt(u32));
    assert(count.load(.monotonic) > previous);

    return previous + 1;
}
