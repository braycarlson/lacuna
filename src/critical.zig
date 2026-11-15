const std = @import("std");

const c = @import("c.zig");

const assert = std.debug.assert;

const Object = @import("value.zig").Object;

pub const Section = if (c.unlocked_possible) c.PyCriticalSection else struct {};
pub const empty: Section = if (c.unlocked_possible) .{ ._cs_prev = 0, ._cs_mutex = null } else .{};
pub const Pair = if (c.unlocked_possible) c.PyCriticalSection2 else struct {};

pub const pair_empty: Pair = if (c.unlocked_possible)
    .{ ._cs_base = empty, ._cs_mutex2 = null }
else
    .{};

pub const CriticalSection = struct {
    pair: Pair,
    active: bool,

    pub const empty: CriticalSection = .{ .pair = pair_empty, .active = false };

    pub const Locked = struct {
        first: Object,
        second: ?Object = null,
    };

    pub fn begin(section: *CriticalSection, locked: Locked) void {
        assert(!section.active);
        assert(@intFromPtr(locked.first.pointer) % c.object_alignment == 0);

        const second = locked.second orelse locked.first;

        pair_begin(&section.pair, .{ locked.first.pointer, second.pointer });
        section.active = true;
    }

    pub fn end(section: *CriticalSection) void {
        assert(section.active);
        assert(@intFromPtr(section) % @alignOf(CriticalSection) == 0);

        pair_end(&section.pair);

        section.pair = pair_empty;
        section.active = false;
    }
};

pub fn begin(section: *Section, object: *c.PyObject) void {
    assert(@intFromPtr(object) % c.object_alignment == 0);
    assert(@intFromPtr(section) % @alignOf(Section) == 0);

    if (c.unlocked_possible) {
        assert(section._cs_mutex == null);

        c.PyCriticalSection_Begin(section, object);
    }

    if (c.free_threaded) {
        const mutex = @intFromPtr(object) + @offsetOf(c.PyObject_Header, "ob_mutex");
        if (section._cs_mutex) |held| assert(@intFromPtr(held) == mutex);
    }
}

pub fn end(section: *Section) void {
    assert(@intFromPtr(section) % @alignOf(Section) == 0);

    if (c.unlocked_possible) {
        if (section._cs_mutex == null) assert(section._cs_prev == 0);

        c.PyCriticalSection_End(section);
    }
}

pub fn pair_begin(pair: *Pair, objects: [2]*c.PyObject) void {
    assert(@intFromPtr(objects[0]) % c.object_alignment == 0);
    assert(@intFromPtr(objects[1]) % c.object_alignment == 0);
    assert(@intFromPtr(pair) % @alignOf(Pair) == 0);

    if (c.unlocked_possible) {
        assert(pair._cs_base._cs_mutex == null);
        assert(pair._cs_mutex2 == null);

        c.PyCriticalSection2_Begin(pair, objects[0], objects[1]);
    }

    if (c.free_threaded) {
        const offset = @offsetOf(c.PyObject_Header, "ob_mutex");
        const lower = @min(@intFromPtr(objects[0]), @intFromPtr(objects[1])) + offset;
        const upper = @max(@intFromPtr(objects[0]), @intFromPtr(objects[1])) + offset;
        const locked_lower = pair._cs_base._cs_mutex != null;
        const locked_upper = pair._cs_mutex2 != null;

        if (pair._cs_base._cs_mutex) |held| assert(@intFromPtr(held) == lower);
        if (pair._cs_mutex2) |held| assert(@intFromPtr(held) == upper);
        if (objects[0] == objects[1]) assert(!locked_upper);
        if (objects[0] != objects[1]) assert(locked_lower == locked_upper);
    }
}

pub fn pair_end(pair: *Pair) void {
    assert(@intFromPtr(pair) % @alignOf(Pair) == 0);

    if (c.unlocked_possible) {
        if (pair._cs_base._cs_mutex == null) assert(pair._cs_mutex2 == null);
        if (pair._cs_base._cs_mutex == null) assert(pair._cs_base._cs_prev == 0);

        c.PyCriticalSection2_End(pair);
    }
}

test Section {
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Section));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Pair));
    try std.testing.expect(!c.free_threaded);
}
