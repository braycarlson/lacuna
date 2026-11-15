const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const callback = @import("callback.zig");
const critical = @import("critical.zig");
const exception = @import("exception.zig");
const python = @import("python.zig");
const thread = @import("thread.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

pub const Error = error{PythonError};
pub const Flag = std.atomic.Value(bool);

pub const Token = struct {
    flag: Flag,
    loop: *c.PyObject,
    pending: ?*c.PyObject,
    submit: *c.PyObject,
};

pub const token_name: [:0]const u8 = "lacuna.cancellation";

pub const Cancellation = struct {
    flag: *const Flag,

    pub fn requested(cancellation: Cancellation) bool {
        assert(@intFromPtr(cancellation.flag) % @alignOf(Flag) == 0);

        return cancellation.flag.load(.acquire);
    }
};

pub const LoopObject = struct {
    pointer: *c.PyObject,

    pub const annotation = "object";
};

const Submission = struct {
    arguments: *c.PyObject,
    target: *c.PyObject,
};

pub const Loop = struct {
    capsule: *c.PyObject,
    token: *Token,

    pub fn requested(loop: Loop) bool {
        assert(@intFromPtr(loop.token) % @alignOf(Token) == 0);
        assert(@intFromPtr(loop.capsule) % c.object_alignment == 0);

        return loop.token.flag.load(.acquire);
    }

    pub fn call(
        loop: Loop,
        comptime T: type,
        function: LoopObject,
        arguments: anytype,
    ) Error!T {
        comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
        assert(@intFromPtr(function.pointer) % c.object_alignment == 0);
        assert(@intFromPtr(loop.token) % @alignOf(Token) == 0);

        const visit = thread.visit();
        defer visit.leave();

        if (c.graalpy) {
            if (c.PyErr_Occurred() != null) return error.PythonError;
        }

        const tuple = try callback.tuple_of(arguments);
        defer c.Py_DecRef(tuple);

        return loop.run(T, .{ .arguments = tuple, .target = function.pointer });
    }

    pub fn wait(loop: Loop, comptime T: type, awaitable: LoopObject) Error!T {
        assert(@intFromPtr(awaitable.pointer) % c.object_alignment == 0);
        assert(@intFromPtr(loop.token) % @alignOf(Token) == 0);

        const visit = thread.visit();
        defer visit.leave();

        if (c.graalpy) {
            if (c.PyErr_Occurred() != null) return error.PythonError;
        }

        const none = c.Py_BuildValue("") orelse return error.PythonError;
        defer c.Py_DecRef(none);

        return loop.run(T, .{ .arguments = none, .target = awaitable.pointer });
    }

    fn run(loop: Loop, comptime T: type, submission: Submission) Error!T {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@intFromPtr(loop.token) % @alignOf(Token) == 0);
        assert(@intFromPtr(submission.target) % c.object_alignment == 0);
        assert(thread.Interpreter.attached());

        if (builtin.single_threaded) return loop_refused();

        const token = loop.token;

        const submitted = c.PyObject_CallFunction(
            token.submit,
            "OOO",
            token.loop,
            submission.target,
            submission.arguments,
        );

        const future = submitted orelse return error.PythonError;

        const result = if (loop.pending_set(future)) future_result(future) else null;
        const saved = exception.pending_save();

        loop.pending_clear();
        c.Py_DecRef(future);
        exception.pending_resume(&saved);

        const present = result orelse return error.PythonError;

        var reference: value.Reference = .{ .pointer = present };
        defer reference.release();

        return reference.convert(T);
    }

    fn pending_set(loop: Loop, future: *c.PyObject) bool {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@intFromPtr(future) % c.object_alignment == 0);
        assert(@intFromPtr(loop.token) % @alignOf(Token) == 0);

        var section = critical.empty;

        critical.begin(&section, loop.capsule);
        defer critical.end(&section);

        assert(loop.token.pending == null);

        loop.token.pending = python.reference_new(future);

        if (!loop.token.flag.load(.acquire)) return true;
        return future_cancel(future);
    }

    fn pending_clear(loop: Loop) void {
        assert(@intFromPtr(loop.capsule) % c.object_alignment == 0);
        assert(loop.token.pending != null);

        var section = critical.empty;

        critical.begin(&section, loop.capsule);

        const pending = loop.token.pending;

        loop.token.pending = null;
        critical.end(&section);
        c.Py_DecRef(pending);
    }
};

pub const token_new_definition: c.PyMethodDef = .{
    .ml_name = "_lacuna_token_new",
    .ml_meth = @ptrCast(&token_new),
    .ml_flags = c.METH_FASTCALL,
    .ml_doc = "_lacuna_token_new($module, loop, submit, /)\n--\n\nMake a cancellation token.",
};

pub const cancel_definition: c.PyMethodDef = .{
    .ml_name = "_lacuna_cancel",
    .ml_meth = &cancel,
    .ml_flags = c.METH_O,
    .ml_doc = "_lacuna_cancel($module, token, /)\n--\n\nAsk a running coroutine to stop.",
};

pub fn token_of(capsule: *c.PyObject) ?*Token {
    assert(@intFromPtr(capsule) % c.object_alignment == 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const pointer = c.PyCapsule_GetPointer(capsule, token_name) orelse return null;

    assert(@intFromPtr(pointer) % @alignOf(Token) == 0);

    return @ptrCast(@alignCast(pointer));
}

pub fn flag_of(capsule: *c.PyObject) ?*Flag {
    assert(@intFromPtr(capsule) % c.object_alignment == 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const token = token_of(capsule) orelse return null;

    return &token.flag;
}

fn loop_refused() Error {
    assert(builtin.single_threaded);
    assert(thread.Interpreter.attached());

    python.exception_raise(.{
        .class_name = "RuntimeError",
        .message = "this build runs no threads, so a coroutine cannot wait on its event loop",
    });

    return error.PythonError;
}

fn future_result(future: *c.PyObject) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(future) % c.object_alignment == 0);

    const method = python.attribute_get(future, "result") orelse return null;
    defer c.Py_DecRef(method);

    return c.PyObject_CallObject(method, null);
}

fn future_cancel(future: *c.PyObject) bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(future) % c.object_alignment == 0);

    const method = python.attribute_get(future, "cancel") orelse return false;
    defer c.Py_DecRef(method);

    const cancelled = c.PyObject_CallObject(method, null) orelse return false;

    c.Py_DecRef(cancelled);

    return true;
}

fn token_new(
    module: *c.PyObject,
    arguments: [*]const *c.PyObject,
    count: c.Py_ssize_t,
) callconv(.c) ?*c.PyObject {
    assert(@intFromPtr(module) % c.object_alignment == 0);
    assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
    assert(count >= 0);

    if (count != 2) {
        python.exception_raise(.{
            .class_name = "TypeError",
            .message = "_lacuna_token_new() takes the running loop and its submit helper",
        });

        return null;
    }

    const memory = c.PyMem_Malloc(@sizeOf(Token)) orelse return python.memory_raise();
    const token: *Token = @ptrCast(@alignCast(memory));

    token.* = .{
        .flag = .init(false),
        .loop = python.reference_new(arguments[0]),
        .pending = null,
        .submit = python.reference_new(arguments[1]),
    };

    return c.PyCapsule_New(token, token_name, &token_free) orelse {
        token_release(token);

        return null;
    };
}

fn token_free(capsule: *c.PyObject) callconv(.c) void {
    assert(@intFromPtr(capsule) % c.object_alignment == 0);

    const saved = exception.pending_save();
    defer exception.pending_resume(&saved);

    const token = token_of(capsule) orelse {
        c.PyErr_Clear();

        return;
    };

    token_release(token);
}

fn token_release(token: *Token) void {
    assert(@intFromPtr(token) % @alignOf(Token) == 0);
    assert(token.pending == null);

    c.Py_DecRef(token.loop);
    c.Py_DecRef(token.submit);
    c.PyMem_Free(token);
}

fn cancel(module: *c.PyObject, capsule: ?*c.PyObject) callconv(.c) ?*c.PyObject {
    assert(@intFromPtr(module) % c.object_alignment == 0);
    assert(capsule != null);

    const token = token_of(capsule.?) orelse return null;

    token.flag.store(true, .release);

    var section = critical.empty;

    critical.begin(&section, capsule.?);

    const pending = if (token.pending) |future| python.reference_new(future) else null;

    critical.end(&section);

    assert(token.flag.load(.acquire));

    if (pending) |future| {
        defer c.Py_DecRef(future);

        if (!future_cancel(future)) return null;
    }

    return c.Py_BuildValue("");
}
