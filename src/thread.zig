const std = @import("std");

const c = @import("c.zig");
const python = @import("python.zig");
const version_module = @import("version.zig");

const assert = std.debug.assert;

const Version = version_module.Version;

pub const Attached = struct {
    active_outer: bool,
    mode: Mode,

    const Mode = union(enum) {
        created: *c.PyThreadState,
        ensured: c.PyGILState_STATE,
    };

    pub fn release(attached: *const Attached) void {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        switch (attached.mode) {
            .created => |thread| {
                c.PyThreadState_Clear(thread);

                const saved = c.PyEval_SaveThread();

                assert(saved == thread);

                c.PyThreadState_Delete(thread);
            },
            .ensured => |state| {
                assert(state == .locked or state == .unlocked);

                c.PyGILState_Release(state);
            },
        }

        assert(!active().*);

        active().* = attached.active_outer;
    }
};

pub const Detached = struct {
    active_outer: bool,
    saved_outer: ?*c.PyThreadState,
    thread: *c.PyThreadState,

    pub fn reattach(detached: *const Detached) void {
        assert(@intFromPtr(detached.thread) % @alignOf(*c.PyThreadState) == 0);
        assert(active().*);
        assert(thread_saved().thread == detached.thread);

        c.PyEval_RestoreThread(detached.thread);

        active().* = detached.active_outer;
        thread_saved().thread = detached.saved_outer;
    }
};

pub const Visit = struct {
    thread: *c.PyThreadState,

    pub fn leave(visit_held: *const Visit) void {
        assert(!active().*);
        assert(thread_saved().thread == visit_held.thread);

        const thread = c.PyEval_SaveThread();

        assert(thread == visit_held.thread);

        active().* = true;
    }
};

pub const Ensured = struct {
    active_outer: bool,
    state: c.PyGILState_STATE,

    pub fn release(ensured: *const Ensured) void {
        assert(ensured.state == .locked or ensured.state == .unlocked);
        assert(!active().*);

        c.PyGILState_Release(ensured.state);

        active().* = ensured.active_outer;
    }
};

pub const Interpreter = struct {
    state: ?*c.PyInterpreterState,

    pub fn attached() bool {
        if (c.pypy) return c.PyGILState_Check() != 0;
        if (c.graalpy) return c.PyGILState_Check() != 0;
        if (thread_state_global()) return attached_global();

        const dictionary = c.PyThreadState_GetDict();

        assert(@intFromPtr(dictionary) % c.object_alignment == 0);

        if (dictionary) |present| assert(python.has_flag(present, c.Py_TPFLAGS_DICT_SUBCLASS));

        return dictionary != null;
    }

    fn attached_global() bool {
        if (active().*) return false;

        const thread = c.PyGILState_GetThisThreadState();

        assert(@intFromPtr(thread) % @alignOf(*c.PyThreadState) == 0);

        return thread != null;
    }

    fn thread_state_global() bool {
        comptime assert(!c.pypy);

        const rank = Interpreter.version().rank();

        assert(rank >= version_module.floor.rank());

        return rank < version_module.per_interpreter_gil.rank();
    }

    pub fn version() Version {
        const Cache = struct {
            var rank: std.atomic.Value(u16) = .init(0);
        };

        const cached = Cache.rank.load(.acquire);

        if (cached != 0) {
            const known: Version = .{ .major = @intCast(cached >> 8), .minor = @truncate(cached) };

            assert(known.rank() == cached);

            return known;
        }

        const text = python.text_bounded(c.Py_GetVersion(), version_module.text_bytes_max);
        const parsed = version_module.parse(text).?;

        Cache.rank.store(parsed.rank(), .release);

        assert(parsed.major == 3);

        return parsed;
    }

    pub fn current() Interpreter {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (c.pypy) return .{ .state = null };

        const state = c.PyInterpreterState_Get();
        const identifier = c.PyInterpreterState_GetID(state);

        assert(identifier >= 0);

        return .{ .state = if (identifier == 0) null else state };
    }

    pub fn attach(interpreter: Interpreter) Attached {
        if (c.pypy) assert(interpreter.state == null);

        const holder: Attached = .{
            .active_outer = active().*,
            .mode = interpreter.acquire(),
        };

        active().* = false;

        return holder;
    }

    fn acquire(interpreter: Interpreter) Attached.Mode {
        if (c.pypy) assert(interpreter.state == null);

        const state = interpreter.state orelse {
            const ensured = c.PyGILState_Ensure();

            assert(ensured == .locked or ensured == .unlocked);

            return .{ .ensured = ensured };
        };

        const thread = c.PyThreadState_New(state).?;

        c.PyEval_RestoreThread(thread);

        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return .{ .created = thread };
    }
};

fn active() *bool {
    const State = struct {
        threadlocal var value: bool = false;
    };

    return &State.value;
}

const Saved = struct {
    thread: ?*c.PyThreadState,
};

fn thread_saved() *Saved {
    const State = struct {
        threadlocal var value: Saved = .{ .thread = null };
    };

    return &State.value;
}

pub fn detach() Detached {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const thread = c.PyEval_SaveThread();

    assert(thread != null);

    const detached: Detached = .{
        .active_outer = active().*,
        .saved_outer = thread_saved().thread,
        .thread = thread.?,
    };

    active().* = true;
    thread_saved().thread = thread.?;

    return detached;
}

pub fn visit() Visit {
    assert(active().*);
    assert(thread_saved().thread != null);

    const thread = thread_saved().thread.?;

    c.PyEval_RestoreThread(thread);
    active().* = false;

    if (!c.graalpy) {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    }

    return .{ .thread = thread };
}

pub fn ensure() Ensured {
    const ensured: Ensured = .{
        .active_outer = active().*,
        .state = c.PyGILState_Ensure(),
    };

    assert(ensured.state == .locked or ensured.state == .unlocked);

    active().* = false;

    assert(Interpreter.attached());

    return ensured;
}
