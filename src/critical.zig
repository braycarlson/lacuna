const std = @import("std");

const c = @import("c.zig");

const assert = std.debug.assert;

pub const Section = if (c.free_threaded) c.PyCriticalSection else struct {};
pub const empty: Section = if (c.free_threaded) .{ ._cs_prev = 0, ._cs_mutex = null } else .{};

pub fn begin(section: *Section, object: *c.PyObject) void {
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
    assert(@intFromPtr(section) % @alignOf(Section) == 0);

    if (c.free_threaded) c.PyCriticalSection_Begin(section, object);
}

pub fn end(section: *Section) void {
    assert(@intFromPtr(section) % @alignOf(Section) == 0);

    if (c.free_threaded) {
        assert(section._cs_mutex != null);

        c.PyCriticalSection_End(section);
    }
}

test Section {
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Section));
    try std.testing.expect(!c.free_threaded);
}
