const std = @import("std");

const c = @import("c.zig");
const python = @import("python.zig");
const signature_module = @import("signature.zig");

const assert = std.debug.assert;

pub const Builtin = enum(u8) {
    none,
    not_implemented,
    false,
    true,
    frozenset,
    set,
    complex,
    bytearray,
    dictionary,
    list,
    tuple,
    slice,
    ellipsis,
    exception,
    arithmetic_error,
    assertion_error,
    attribute_error,
    blocking_io_error,
    broken_pipe_error,
    buffer_error,
    child_process_error,
    connection_aborted_error,
    connection_error,
    connection_refused_error,
    connection_reset_error,
    eof_error,
    file_exists_error,
    file_not_found_error,
    floating_point_error,
    import_error,
    index_error,
    interrupted_error,
    is_a_directory_error,
    key_error,
    lookup_error,
    memory_error,
    module_not_found_error,
    not_a_directory_error,
    not_implemented_error,
    os_error,
    overflow_error,
    permission_error,
    process_lookup_error,
    recursion_error,
    reference_error,
    runtime_error,
    stop_async_iteration,
    stop_iteration,
    system_error,
    timeout_error,
    type_error,
    unicode_error,
    value_error,
    zero_division_error,
    warning,
    deprecation_warning,
    pending_deprecation_warning,
    runtime_warning,
    user_warning,
    syntax_warning,
    future_warning,
    import_warning,
    unicode_warning,
    bytes_warning,
    resource_warning,
    encoding_warning,
};

pub const BuiltinError = builtin_error: {
    const first = @backingInt(builtin_exception_first);
    const last = @backingInt(builtin_warning_first);
    const names = @typeInfo(Builtin).@"enum".field_names[first..last];

    break :builtin_error @Enum(u8, .exhaustive, names, &std.simd.iota(u8, names.len));
};

pub const BuiltinWarning = builtin_warning: {
    const first = @backingInt(builtin_warning_first);
    const names = @typeInfo(Builtin).@"enum".field_names[first..];

    break :builtin_warning @Enum(u8, .exhaustive, names, &std.simd.iota(u8, names.len));
};

pub const Saved = if (c.api_3_12_linked) struct {
    raised: ?*c.PyObject,
} else struct {
    kind: ?*c.PyObject,
    instance: ?*c.PyObject,
    traceback: ?*c.PyObject,
};

pub const Target = union(enum) {
    builtin: Builtin,
    module: u32,
};

pub const builtin_count: u32 = builtin_names.len;
pub const builtin_exception_first: Builtin = .arithmetic_error;
pub const builtin_warning_first: Builtin = .warning;

pub const builtin_names = [_][:0]const u8{
    "None",
    "NotImplemented",
    "False",
    "True",
    "frozenset",
    "set",
    "complex",
    "bytearray",
    "dict",
    "list",
    "tuple",
    "slice",
    "Ellipsis",
    "Exception",
    "ArithmeticError",
    "AssertionError",
    "AttributeError",
    "BlockingIOError",
    "BrokenPipeError",
    "BufferError",
    "ChildProcessError",
    "ConnectionAbortedError",
    "ConnectionError",
    "ConnectionRefusedError",
    "ConnectionResetError",
    "EOFError",
    "FileExistsError",
    "FileNotFoundError",
    "FloatingPointError",
    "ImportError",
    "IndexError",
    "InterruptedError",
    "IsADirectoryError",
    "KeyError",
    "LookupError",
    "MemoryError",
    "ModuleNotFoundError",
    "NotADirectoryError",
    "NotImplementedError",
    "OSError",
    "OverflowError",
    "PermissionError",
    "ProcessLookupError",
    "RecursionError",
    "ReferenceError",
    "RuntimeError",
    "StopAsyncIteration",
    "StopIteration",
    "SystemError",
    "TimeoutError",
    "TypeError",
    "UnicodeError",
    "ValueError",
    "ZeroDivisionError",
    "Warning",
    "DeprecationWarning",
    "PendingDeprecationWarning",
    "RuntimeWarning",
    "UserWarning",
    "SyntaxWarning",
    "FutureWarning",
    "ImportWarning",
    "UnicodeWarning",
    "BytesWarning",
    "ResourceWarning",
    "EncodingWarning",
};

comptime {
    const error_count = @typeInfo(BuiltinError).@"enum".field_names.len;
    const warning_count = @typeInfo(BuiltinWarning).@"enum".field_names.len;

    assert(builtin_names.len == @typeInfo(Builtin).@"enum".field_names.len);
    assert(@backingInt(builtin_exception_first) == 14);
    assert(@backingInt(builtin_warning_first) == 54);
    assert(error_count + 14 + warning_count == builtin_names.len);
    assert(warning_count == 12);
}

pub fn builtin_of_error(kind: BuiltinError) Builtin {
    assert(@backingInt(kind) < @backingInt(builtin_warning_first) -
        @backingInt(builtin_exception_first));

    const index = @as(u8, @backingInt(kind)) + @backingInt(builtin_exception_first);

    assert(index < @backingInt(builtin_warning_first));
    assert(index >= @backingInt(builtin_exception_first));

    return @fromBackingInt(index);
}

pub fn builtin_of_warning(kind: BuiltinWarning) Builtin {
    assert(@backingInt(kind) < builtin_count - @backingInt(builtin_warning_first));

    const index = @as(u8, @backingInt(kind)) + @backingInt(builtin_warning_first);

    assert(index < builtin_count);
    assert(index >= @backingInt(builtin_warning_first));

    return @fromBackingInt(index);
}

pub fn pending_save() Saved {
    if (c.api_3_12_linked) {
        const raised = c.PyErr_GetRaisedException();

        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        if (raised) |present| assert(python.has_flag(present, c.Py_TPFLAGS_BASE_EXC_SUBCLASS));

        return .{ .raised = raised };
    }

    var saved: Saved = .{ .kind = null, .instance = null, .traceback = null };

    c.PyErr_Fetch(&saved.kind, &saved.instance, &saved.traceback);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(saved.kind != null or saved.instance == null);

    return saved;
}

pub fn pending_resume(saved: *const Saved) void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (c.api_3_12_linked) {
        c.PyErr_SetRaisedException(saved.raised);

        assert((c.PyErr_Occurred() != null) == (saved.raised != null));

        return;
    }

    c.PyErr_Restore(saved.kind, saved.instance, saved.traceback);

    assert((c.PyErr_Occurred() != null) == (saved.kind != null));
}

pub fn pending_take() ?*c.PyObject {
    if (c.PyErr_Occurred() == null) return null;

    var kind: ?*c.PyObject = null;
    var instance: ?*c.PyObject = null;
    var traceback: ?*c.PyObject = null;

    c.PyErr_Fetch(&kind, &instance, &traceback);
    c.PyErr_NormalizeException(&kind, &instance, &traceback);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(instance != null);

    if (traceback) |present| {
        const status = c.PyException_SetTraceback(instance.?, present);

        assert(status == 0);
    }

    c.Py_DecRef(traceback);
    c.Py_DecRef(kind);

    return instance;
}

pub fn pending_restore(instance: *c.PyObject) void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(python.has_flag(instance, c.Py_TPFLAGS_BASE_EXC_SUBCLASS));

    const class = python.class_of(instance);
    const traceback = c.PyException_GetTraceback(instance);

    c.PyErr_Restore(class, instance, traceback);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

pub fn cause_attach(cause: ?*c.PyObject) void {
    if (cause) |candidate| assert(python.has_flag(candidate, c.Py_TPFLAGS_BASE_EXC_SUBCLASS));

    const present = cause orelse return;

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

    const raised = pending_take().?;

    c.Py_IncRef(present);
    c.PyException_SetContext(raised, present);
    c.PyException_SetCause(raised, present);

    pending_restore(raised);
}

pub fn builtin_of(comptime name: []const u8) ?Builtin {
    comptime assert(name.len > 0);
    comptime assert(builtin_names.len == builtin_count);

    @setEvalBranchQuota((builtin_names.len + 1) * (name.len + 8) + 1000);

    if (std.mem.eql(u8, name, "OutOfMemory")) return .memory_error;

    const first = @backingInt(builtin_exception_first);
    const last = @backingInt(builtin_warning_first);

    inline for (builtin_names[first..last], first..) |builtin_name, index| {
        if (std.mem.eql(u8, name, builtin_name)) return @fromBackingInt(index);
    }

    return null;
}

pub fn target_of(comptime name: []const u8, comptime errors: []const [:0]const u8) Target {
    comptime assert(name.len > 0);
    comptime assert(errors.len <= std.math.maxInt(u32));

    @setEvalBranchQuota((errors.len + builtin_names.len + 1) * (name.len + 8) + 1000);

    if (builtin_of(name)) |builtin| return .{ .builtin = builtin };

    inline for (errors, 0..) |error_name, index| {
        if (std.mem.eql(u8, name, error_name)) return .{ .module = index };
    }

    @compileError("lacuna: the error '" ++ name ++ "' was not collected from any signature");
}

pub fn message_of(comptime messages: ?type, comptime name: []const u8) ?[:0]const u8 {
    comptime assert(name.len > 0);
    comptime assert(messages == null or @typeInfo(messages.?) == .@"struct");

    const namespace = messages orelse return null;

    if (!@hasDecl(namespace, "message")) {
        @compileError("lacuna: the messages namespace has no 'message' function");
    }

    const Function = @TypeOf(namespace.message);
    const parameters = @typeInfo(Function).@"fn".param_types;

    comptime assert(parameters.len == 1);

    const ErrorSet = parameters[0].?;

    const names = @typeInfo(ErrorSet).error_set.error_names orelse {
        @compileError("lacuna: the 'message' function must take a named error set");
    };

    @setEvalBranchQuota((names.len + 1) * (name.len + 8) + 1000);

    inline for (names) |error_name| {
        if (std.mem.eql(u8, error_name, name)) {
            const text = comptime namespace.message(@field(ErrorSet, error_name));
            return signature_module.terminated(text);
        }
    }

    return null;
}

pub fn raise(
    comptime Binding: type,
    state: *const Binding.State,
    comptime ErrorSet: type,
    err: ErrorSet,
    diagnostic: anytype,
) void {
    comptime assert(diagnostic_valid(@TypeOf(diagnostic)));
    comptime assert(@typeInfo(ErrorSet) == .error_set);
    assert(@errorName(err).len > 0);

    const raised_count = @typeInfo(ErrorSet).error_set.error_names.?.len;
    const known_count = Binding.errors.len + builtin_names.len + 1;

    @setEvalBranchQuota(raised_count * known_count * 256 + 10_000);

    switch (err) {
        inline else => |known| {
            const name = @errorName(known);

            if (comptime std.mem.eql(u8, name, python_error_name)) {
                if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

                return;
            }

            const cause = pending_take();

            if (cause) |present| {
                if (c.PyErr_GivenExceptionMatches(present, state.builtins.get(.exception)) == 0) {
                    pending_restore(present);

                    return;
                }
            }

            defer cause_attach(cause);

            const target = comptime target_of(name, Binding.errors);

            const class = switch (target) {
                .builtin => |builtin| state.builtins.get(builtin),
                .module => |index| state.error_class(index),
            };

            const text = message_dynamic(diagnostic) orelse comptime message_of(
                Binding.messages,
                name,
            );

            if (comptime target == .module) {
                if (@TypeOf(diagnostic) != @TypeOf(null)) {
                    if (diagnostic.details) |details| {
                        raise_detailed(Binding, state, class, text, details);

                        return;
                    }
                }
            }

            raise_message(class, text);
        },
    }

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

const python_error_name = "PythonError";

fn message_dynamic(diagnostic: anytype) ?[]const u8 {
    comptime assert(diagnostic_valid(@TypeOf(diagnostic)));

    if (@TypeOf(diagnostic) == @TypeOf(null)) return null;
    return diagnostic.message();
}

fn diagnostic_valid(comptime Diagnostic: type) bool {
    if (Diagnostic == @TypeOf(null)) return true;
    return @typeInfo(Diagnostic) == .pointer;
}

fn text_valid(text: *const ?[]const u8) bool {
    assert(@intFromPtr(text) % @alignOf(?[]const u8) == 0);

    const present = text.* orelse return true;
    return std.unicode.utf8ValidateSlice(present);
}

fn raise_message(class: *c.PyObject, text: ?[]const u8) void {
    assert(text_valid(&text));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(class) % @alignOf(*c.PyObject) == 0);

    const present = text orelse {
        c.PyErr_SetNone(class);

        return;
    };

    const message = c.PyUnicode_FromStringAndSize(present.ptr, @intCast(present.len)) orelse {
        return;
    };

    defer c.Py_DecRef(message);

    c.PyErr_SetObject(class, message);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

fn raise_detailed(
    comptime Binding: type,
    state: *const Binding.State,
    class: *c.PyObject,
    text: ?[]const u8,
    details: anytype,
) void {
    comptime assert(@typeInfo(@TypeOf(details)) == .@"struct");
    assert(text_valid(&text));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Details = @TypeOf(details);
    const arguments = c.PyTuple_New(@intFromBool(text != null)) orelse return;
    defer c.Py_DecRef(arguments);

    if (text) |present| {
        const message = c.PyUnicode_FromStringAndSize(present.ptr, @intCast(present.len)) orelse {
            return;
        };

        const status = c.PyTuple_SetItem(arguments, 0, message);

        assert(status == 0);
    }

    const instance = c.PyObject_CallObject(class, arguments) orelse return;
    defer c.Py_DecRef(instance);

    inline for (@typeInfo(Details).@"struct".field_names) |field| {
        const Field = @FieldType(Details, field);

        const item = @import("to_python.zig").to_python(
            Binding,
            Field,
            state,
            &@field(details, field),
        ) catch return;

        defer c.Py_DecRef(item);

        if (c.PyObject_SetAttrString(instance, field, item) != 0) return;
    }

    c.PyErr_SetObject(class, instance);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

test builtin_of {
    comptime {
        assert(builtin_of("IndexError").? == .index_error);
        assert(builtin_of("OutOfMemory").? == .memory_error);
        assert(builtin_of("ZeroDivisionError").? == .zero_division_error);
        assert(builtin_of("None") == null);
        assert(builtin_of("True") == null);
        assert(builtin_of("TextExhausted") == null);
        assert(builtin_of("UserWarning") == null);
        assert(builtin_of_warning(.encoding_warning) == .encoding_warning);
        assert(builtin_of_error(.zero_division_error) == .zero_division_error);
    }
}

test target_of {
    const errors = [_][:0]const u8{ "Busy", "Closed" };

    comptime {
        assert(target_of("Closed", &errors).module == 1);
        assert(target_of("KeyError", &errors).builtin == .key_error);
    }
}

test message_of {
    comptime {
        const messages = struct {
            pub fn message(err: error{ Busy, Closed }) []const u8 {
                assert(@errorName(err).len > 0);

                return switch (err) {
                    error.Busy => "the device is busy",
                    error.Closed => "the device is closed",
                };
            }
        };

        assert(std.mem.eql(u8, message_of(messages, "Busy").?, "the device is busy"));
        assert(message_of(messages, "Missing") == null);
        assert(message_of(null, "Busy") == null);
    }
}
