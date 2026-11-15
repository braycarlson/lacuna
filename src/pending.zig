const std = @import("std");

const c = @import("c.zig");
const convert = @import("convert.zig");
const exception = @import("exception.zig");
const python = @import("python.zig");
const thread = @import("thread.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

const BuiltinError = exception.BuiltinError;
const BuiltinWarning = exception.BuiltinWarning;
const Object = value.Object;
const Reference = value.Reference;

pub const Error = error{PythonError};

pub fn occurred() bool {
    return c.PyErr_Occurred() != null;
}

pub fn matches(class: Object) bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
    assert(@intFromPtr(class.pointer) % c.object_alignment == 0);

    return c.PyErr_ExceptionMatches(class.pointer) != 0;
}

pub fn matches_builtin(kind: BuiltinError) bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
    assert(exception.builtin_names[@backingInt(exception.builtin_of_error(kind))].len > 0);

    var pending_kind: ?*c.PyObject = null;
    var pending_value: ?*c.PyObject = null;
    var pending_traceback: ?*c.PyObject = null;

    c.PyErr_Fetch(&pending_kind, &pending_value, &pending_traceback);

    const class = builtin_owned(kind) orelse {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

        c.Py_DecRef(pending_kind);
        c.Py_DecRef(pending_value);
        c.Py_DecRef(pending_traceback);

        return false;
    };

    defer c.Py_DecRef(class);

    c.PyErr_Restore(pending_kind, pending_value, pending_traceback);

    return c.PyErr_ExceptionMatches(class) != 0;
}

pub fn signals_check() Error!void {
    assert(thread.Interpreter.attached());

    if (c.graalpy) {
        if (c.PyErr_Occurred() != null) return error.PythonError;
    }

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (c.PyErr_CheckSignals() != 0) {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

        return error.PythonError;
    }

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
}

pub fn unraisable(context: ?Object) void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
    if (context) |present| assert(python.class_is(python.type_borrowed(present.pointer)));

    if (context) |present| {
        c.PyErr_WriteUnraisable(present.pointer);
    } else {
        const none = c.Py_BuildValue("") orelse unreachable;
        defer c.Py_DecRef(none);

        c.PyErr_WriteUnraisable(none);
    }

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
}

pub fn print() void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

    c.PyErr_Print();

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
}

pub fn clear() void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

    c.PyErr_Clear();

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
}

pub fn take() Reference {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

    const raised = exception.pending_take().?;

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(python.has_flag(raised, c.Py_TPFLAGS_BASE_EXC_SUBCLASS));

    return .{ .pointer = raised };
}

pub fn restore(raised: *Reference) Error {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(raised.pointer != null);

    const pointer = raised.pointer.?;

    raised.pointer = null;
    exception.pending_restore(pointer);

    return error.PythonError;
}

pub fn raise(class: Object, message: []const u8) Error {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(std.unicode.utf8ValidateSlice(message));
    assert(python.class_is(class.pointer));
    assert(c.PyType_GetFlags(class.pointer) & c.Py_TPFLAGS_BASE_EXC_SUBCLASS != 0);

    raise_message(class.pointer, message);

    return error.PythonError;
}

pub fn raise_builtin(kind: BuiltinError, message: []const u8) Error {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(std.unicode.utf8ValidateSlice(message));
    assert(exception.builtin_names[@backingInt(exception.builtin_of_error(kind))].len > 0);

    const class = builtin_owned(kind) orelse return error.PythonError;
    defer c.Py_DecRef(class);

    raise_message(class, message);

    return error.PythonError;
}

pub fn warn(category: anytype, message: []const u8, stack_level: u32) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(std.unicode.utf8ValidateSlice(message));
    assert(stack_level <= std.math.maxInt(c_int));
    comptime assert(@typeInfo(@TypeOf(category)) != .pointer);

    const Category = @TypeOf(category);

    if (Category == BuiltinWarning) return warn_builtin(category, message, stack_level);
    if (Category == @EnumLiteral()) return warn_builtin(category, message, stack_level);

    const name = comptime exception.warning_name_of(Category);
    const Binding = convert.BindingWarning(name);
    const target = comptime exception.target_of(name, Binding.errors);
    const state = try convert.state_of(Binding);

    return warn_class(state.error_class(target.module), message, stack_level);
}

fn warn_builtin(kind: BuiltinWarning, message: []const u8, stack_level: u32) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@backingInt(kind) < exception.builtin_count);
    assert(std.unicode.utf8ValidateSlice(message));
    assert(stack_level <= std.math.maxInt(c_int));

    const name = exception.builtin_names[@backingInt(exception.builtin_of_warning(kind))];
    const class = python.builtin_new(name) orelse return error.PythonError;
    defer c.Py_DecRef(class);

    return warn_class(class, message, stack_level);
}

pub fn note(text: []const u8) Error {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
    assert(std.unicode.utf8ValidateSlice(text));
    assert(text.len <= std.math.maxInt(c.Py_ssize_t));

    const raised = exception.pending_take().?;

    assert(python.has_flag(raised, c.Py_TPFLAGS_BASE_EXC_SUBCLASS));

    const added = note_add(raised, text);

    if (added) {
        exception.pending_restore(raised);

        return error.PythonError;
    }

    const failure = exception.pending_take().?;

    c.PyException_SetContext(failure, raised);
    exception.pending_restore(failure);

    return error.PythonError;
}

fn note_add(raised: *c.PyObject, text: []const u8) bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(text.len <= std.math.maxInt(c.Py_ssize_t));

    const method = python.attribute_get(raised, "add_note") orelse return false;
    defer c.Py_DecRef(method);

    const argument = c.PyUnicode_FromStringAndSize(text.ptr, @intCast(text.len)) orelse {
        return false;
    };

    defer c.Py_DecRef(argument);

    const result = c.PyObject_CallFunction(method, "O", argument) orelse return false;

    c.Py_DecRef(result);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return true;
}

pub fn warn_class(class: *c.PyObject, message: []const u8, stack_level: u32) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(python.class_is(class));
    assert(message.len <= std.math.maxInt(c.Py_ssize_t));
    assert(stack_level <= std.math.maxInt(c_int));

    const length: c.Py_ssize_t = @intCast(message.len);
    const text = c.PyUnicode_FromStringAndSize(message.ptr, length) orelse return error.PythonError;
    defer c.Py_DecRef(text);

    var size: c.Py_ssize_t = 0;

    const terminated = c.PyUnicode_AsUTF8AndSize(text, &size) orelse return error.PythonError;

    assert(size == length);

    if (c.PyErr_WarnEx(class, terminated, @intCast(stack_level)) != 0) {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

        return error.PythonError;
    }

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
}

fn raise_message(class: *c.PyObject, message: []const u8) void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(message.len <= std.math.maxInt(c.Py_ssize_t));

    const text = c.PyUnicode_FromStringAndSize(message.ptr, @intCast(message.len)) orelse return;
    defer c.Py_DecRef(text);

    c.PyErr_SetObject(class, text);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

fn builtin_owned(kind: BuiltinError) ?*c.PyObject {
    assert(exception.builtin_names[@backingInt(exception.builtin_of_error(kind))].len > 0);

    const builtin = exception.builtin_of_error(kind);
    const name = exception.builtin_names[@backingInt(builtin)];

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(name.len > 0);

    return python.builtin_new(name);
}
