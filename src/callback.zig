const std = @import("std");

const c = @import("c.zig");
const python = @import("python.zig");
const text_module = @import("text.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

pub const Error = error{PythonError};
pub const argument_count_max: u32 = 16;

pub fn call(callable: *c.PyObject, arguments: anytype) Error!value.Reference {
    comptime assert(@typeInfo(@TypeOf(arguments)) == .@"struct");
    comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const tuple = try tuple_of(arguments);
    defer c.Py_DecRef(tuple);

    const result = c.PyObject_CallObject(callable, tuple) orelse return error.PythonError;

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return .{ .pointer = result };
}

pub fn call_keywords(callable: *c.PyObject, invocation: anytype) Error!value.Reference {
    comptime assert(@typeInfo(@TypeOf(invocation.arguments)).@"struct".is_tuple);
    comptime assert(!@typeInfo(@TypeOf(invocation.keywords)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const tuple = try tuple_of(invocation.arguments);
    defer c.Py_DecRef(tuple);

    const dictionary = try dictionary_of(invocation.keywords);
    defer c.Py_DecRef(dictionary);

    const result = c.PyObject_Call(callable, tuple, dictionary) orelse return error.PythonError;

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return .{ .pointer = result };
}

fn tuple_of(arguments: anytype) Error!*c.PyObject {
    comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Arguments = @TypeOf(arguments);
    const count = @typeInfo(Arguments).@"struct".field_names.len;

    comptime assert(count <= argument_count_max);

    const tuple = c.PyTuple_New(count) orelse return error.PythonError;
    errdefer c.Py_DecRef(tuple);

    inline for (@typeInfo(Arguments).@"struct".field_names, 0..) |name, index| {
        const Field = @FieldType(Arguments, name);
        const item = try plain_to(Field, @field(arguments, name));
        const status = c.PyTuple_SetItem(tuple, index, item);

        assert(status == 0);
    }

    return tuple;
}

fn dictionary_of(keywords: anytype) Error!*c.PyObject {
    comptime assert(!@typeInfo(@TypeOf(keywords)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Keywords = @TypeOf(keywords);

    comptime assert(@typeInfo(Keywords).@"struct".field_names.len <= argument_count_max);

    const dictionary = c.PyDict_New() orelse return error.PythonError;
    errdefer c.Py_DecRef(dictionary);

    inline for (@typeInfo(Keywords).@"struct".field_names) |name| {
        const Field = @FieldType(Keywords, name);
        const item = try plain_to(Field, @field(keywords, name));
        defer c.Py_DecRef(item);

        if (c.PyDict_SetItemString(dictionary, name, item) != 0) return error.PythonError;
    }

    return dictionary;
}

pub fn attribute_set(object: *c.PyObject, name: [:0]const u8, item: anytype) Error!void {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(plain_valid(@TypeOf(item), &item));

    const converted = try plain_to(@TypeOf(item), item);
    defer c.Py_DecRef(converted);

    if (c.PyObject_SetAttrString(object, name, converted) != 0) return error.PythonError;
}

pub fn attribute_delete(object: *c.PyObject, name: [:0]const u8) Error!void {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (c.PyObject_SetAttrString(object, name, null) != 0) return error.PythonError;
}

pub fn item_get(object: *c.PyObject, key: anytype) Error!value.Reference {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
    assert(plain_valid(@TypeOf(key), &key));

    const converted = try plain_to(@TypeOf(key), key);
    defer c.Py_DecRef(converted);

    const result = c.PyObject_GetItem(object, converted) orelse return error.PythonError;
    return .{ .pointer = result };
}

pub fn item_set(object: *c.PyObject, entry: anytype) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
    assert(plain_valid(@TypeOf(entry.key), &entry.key));
    assert(plain_valid(@TypeOf(entry.value), &entry.value));

    const key_converted = try plain_to(@TypeOf(entry.key), entry.key);
    defer c.Py_DecRef(key_converted);

    const item_converted = try plain_to(@TypeOf(entry.value), entry.value);
    defer c.Py_DecRef(item_converted);

    if (c.PyObject_SetItem(object, key_converted, item_converted) != 0) {
        return error.PythonError;
    }
}

pub fn item_delete(object: *c.PyObject, key: anytype) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
    assert(plain_valid(@TypeOf(key), &key));

    const converted = try plain_to(@TypeOf(key), key);
    defer c.Py_DecRef(converted);

    if (c.PyObject_DelItem(object, converted) != 0) return error.PythonError;
}

pub fn status_of(status: c_int) Error!bool {
    assert(status >= -1);
    assert(status <= 1);

    if (status < 0) return error.PythonError;
    return status == 1;
}

pub fn attribute(object: *c.PyObject, name: [:0]const u8) Error!value.Reference {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const result = c.PyObject_GetAttrString(object, name) orelse return error.PythonError;
    return .{ .pointer = result };
}

pub fn plain_to(comptime T: type, item: T) Error!*c.PyObject {
    assert(plain_valid(T, &item));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const result: ?*c.PyObject = switch (@typeInfo(T)) {
        .bool => c.PyBool_FromLong(@intFromBool(item)),
        .comptime_int => c.PyLong_FromLongLong(item),
        .comptime_float, .float => c.PyFloat_FromDouble(item),
        .@"enum" => @compileError("lacuna: an enum reaches a callback only through its " ++
            "module's class; pass @tagName of '" ++ @typeName(T) ++ "' instead"),
        .int => |int| if (int.bits > 64)
            @import("to_python.zig").integer_wide_to(T, &item)
        else if (int.signedness == .signed)
            c.PyLong_FromLongLong(item)
        else
            c.PyLong_FromUnsignedLongLong(item),
        .null => none_new(),
        .optional => |optional| if (item) |present|
            try plain_to(optional.child, present)
        else
            none_new(),
        .pointer => text_new(item),
        .@"struct" => struct_to(T, &item),
        .void => none_new(),
        else => @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a callback argument"),
    };

    return result orelse error.PythonError;
}

pub fn plain_valid(comptime T: type, item: *const T) bool {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    return switch (@typeInfo(T)) {
        .optional => |optional| if (item.*) |*present|
            plain_valid(optional.child, present)
        else
            true,
        .pointer => std.unicode.utf8ValidateSlice(item.*),
        else => true,
    };
}

pub fn plain_from(comptime T: type, object: *c.PyObject) Error!T {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    comptime assert(T != type);

    return switch (@typeInfo(T)) {
        .bool => boolean_from(object),
        .float => float_from(T, object),
        .int => integer_from(T, object),
        .optional => |optional| if (python.is_none(object)) null else try plain_from(
            optional.child,
            object,
        ),
        .pointer => text_from(T, object),
        .@"struct" => if (T == value.Object)
            .{ .pointer = object }
        else if (T == value.Bytes)
            octets_from(object)
        else
            @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a callback result"),
        else => @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a callback result"),
    };
}

fn struct_to(comptime T: type, item: *const T) ?*c.PyObject {
    comptime assert(@typeInfo(T) == .@"struct");
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (T == value.Object) return python.reference_new(item.pointer);
    if (comptime value.container_is(T)) return python.reference_new(item.reference.pointer.?);

    if (comptime text_module.is_text(T)) {
        return c.PyUnicode_FromStringAndSize(&item.bytes, @intCast(item.length));
    }

    if (comptime text_module.is_blob(T)) {
        return c.PyBytes_FromStringAndSize(&item.bytes, @intCast(item.length));
    }

    if (T == std.math.Complex(f64)) return c.PyComplex_FromDoubles(item.re, item.im);
    if (T == std.math.Complex(f32)) return c.PyComplex_FromDoubles(item.re, item.im);

    if (T == value.Bytes) {
        return c.PyBytes_FromStringAndSize(item.bytes.ptr, @intCast(item.bytes.len));
    }

    if (T == value.Reference) {
        const object = item.pointer orelse return none_new();
        return python.reference_new(object);
    }

    @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a callback argument");
}

fn text_new(text: []const u8) ?*c.PyObject {
    assert(text.len <= std.math.maxInt(c.Py_ssize_t));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return c.PyUnicode_FromStringAndSize(text.ptr, @intCast(text.len));
}

fn none_new() ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const result = c.Py_BuildValue("");

    assert(result == null or python.is_none(result.?));

    return result;
}

fn boolean_from(object: *c.PyObject) Error!bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const truth = c.PyBool_FromLong(1) orelse return error.PythonError;
    defer c.Py_DecRef(truth);

    const falsity = c.PyBool_FromLong(0) orelse return error.PythonError;
    defer c.Py_DecRef(falsity);

    if (object == truth) return true;
    if (object == falsity) return false;
    return mismatch(object, "bool");
}

fn integer_from(comptime T: type, object: *c.PyObject) Error!T {
    comptime assert(@typeInfo(T).int.bits <= 64);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const index = c.PyNumber_Index(object) orelse return error.PythonError;
    defer c.Py_DecRef(index);

    if (@typeInfo(T).int.signedness == .signed) {
        const wide = c.PyLong_AsLongLong(index);

        if (c.PyErr_Occurred() != null) return error.PythonError;
        return std.math.cast(T, wide) orelse overflow(T);
    }

    const wide = c.PyLong_AsUnsignedLongLong(index);

    if (c.PyErr_Occurred() != null) return error.PythonError;
    return std.math.cast(T, wide) orelse overflow(T);
}

fn float_from(comptime T: type, object: *c.PyObject) Error!T {
    comptime assert(@typeInfo(T) == .float);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const wide = c.PyFloat_AsDouble(object);

    if (wide == -1.0) {
        if (c.PyErr_Occurred() != null) return error.PythonError;
    }

    return @floatCast(wide);
}

fn text_from(comptime T: type, object: *c.PyObject) Error!T {
    comptime assert(T == []const u8);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (!python.has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS)) return mismatch(object, "str");

    const text = python.text_of(object) orelse return error.PythonError;
    return text;
}

fn octets_from(object: *c.PyObject) Error!value.Bytes {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (!python.has_flag(object, c.Py_TPFLAGS_BYTES_SUBCLASS)) return mismatch(object, "bytes");
    return .{ .bytes = python.octets_of(object) orelse return error.PythonError };
}

fn mismatch(object: *c.PyObject, comptime expected: [:0]const u8) Error {
    comptime assert(expected.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = python.class_of(object);
    defer c.Py_DecRef(class);

    const kind = python.builtin_new("TypeError") orelse return error.PythonError;
    defer c.Py_DecRef(kind);

    _ = c.PyErr_Format(kind, "a callback result must be " ++ expected ++ ", not %R", class);

    return error.PythonError;
}

fn overflow(comptime T: type) Error {
    comptime assert(@typeInfo(T) == .int);

    const message = std.fmt.comptimePrint("a callback result must be in the range [{d}, {d}]", .{
        std.math.minInt(T),
        std.math.maxInt(T),
    });

    python.exception_raise(.{ .class_name = "OverflowError", .message = message });

    return error.PythonError;
}
