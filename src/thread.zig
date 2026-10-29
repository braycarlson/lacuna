const std = @import("std");

const c = @import("c.zig");
const python = @import("python.zig");
const version_module = @import("version.zig");

const assert = std.debug.assert;

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

        assert(!Detached.active);

        Detached.active = attached.active_outer;
    }
};

pub const Detached = struct {
    active_outer: bool,
    thread: *c.PyThreadState,

    threadlocal var active: bool = false;

    pub fn reattach(detached: *const Detached) void {
        assert(@intFromPtr(detached.thread) % @alignOf(*c.PyThreadState) == 0);
        assert(Detached.active);

        c.PyEval_RestoreThread(detached.thread);

        Detached.active = detached.active_outer;

        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    }
};

pub const Ensured = struct {
    active_outer: bool,
    state: c.PyGILState_STATE,

    pub fn release(ensured: *const Ensured) void {
        assert(ensured.state == .locked or ensured.state == .unlocked);
        assert(!Detached.active);

        c.PyGILState_Release(ensured.state);

        Detached.active = ensured.active_outer;
    }
};

pub const Interpreter = struct {
    state: ?*c.PyInterpreterState,

    pub fn attached() bool {
        if (c.pypy) return c.PyGILState_Check() != 0;
        if (thread_state_global()) return attached_global();

        const dictionary = c.PyThreadState_GetDict();

        assert(@intFromPtr(dictionary) % @alignOf(c.PyObject_Header) == 0);

        if (dictionary) |present| assert(python.has_flag(present, c.Py_TPFLAGS_DICT_SUBCLASS));

        return dictionary != null;
    }

    fn attached_global() bool {
        if (Detached.active) return false;

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

    pub fn version() version_module.Version {
        const Cache = struct {
            var rank: std.atomic.Value(u16) = .init(0);
        };

        const cached = Cache.rank.load(.acquire);

        if (cached != 0) {
            const known: version_module.Version = .{
                .major = @intCast(cached >> 8),
                .minor = @truncate(cached),
            };

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
            .active_outer = Detached.active,
            .mode = interpreter.acquire(),
        };

        Detached.active = false;

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

pub fn detach() Detached {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const thread = c.PyEval_SaveThread();

    assert(thread != null);

    const detached: Detached = .{
        .active_outer = Detached.active,
        .thread = thread.?,
    };

    Detached.active = true;

    return detached;
}

pub fn ensure() Ensured {
    const ensured: Ensured = .{
        .active_outer = Detached.active,
        .state = c.PyGILState_Ensure(),
    };

    assert(ensured.state == .locked or ensured.state == .unlocked);

    Detached.active = false;

    return ensured;
}
