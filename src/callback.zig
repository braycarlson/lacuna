const std = @import("std");

const c = @import("c.zig");
const convert = @import("convert.zig");
const python = @import("python.zig");
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

pub fn tuple_of(arguments: anytype) Error!*c.PyObject {
    comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Arguments = @TypeOf(arguments);
    const count = @typeInfo(Arguments).@"struct".field_names.len;

    comptime assert(count <= argument_count_max);

    const tuple = c.PyTuple_New(count) orelse return error.PythonError;
    errdefer c.Py_DecRef(tuple);

    inline for (@typeInfo(Arguments).@"struct".field_names, 0..) |name, index| {
        const Field = @FieldType(Arguments, name);
        const item = try convert.object_new(Field, @field(arguments, name));
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
        const item = try convert.object_new(Field, @field(keywords, name));
        defer c.Py_DecRef(item);

        if (c.PyDict_SetItemString(dictionary, name, item) != 0) return error.PythonError;
    }

    return dictionary;
}

pub fn attribute_set(object: *c.PyObject, name: [:0]const u8, item: anytype) Error!void {
    assert(name.len > 0);
    assert(convert.item_valid(@TypeOf(item), &item));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const converted = try convert.object_new(@TypeOf(item), item);
    defer c.Py_DecRef(converted);

    return attribute_store(object, name, converted);
}

pub fn attribute_delete(object: *c.PyObject, name: [:0]const u8) Error!void {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return attribute_store(object, name, null);
}

fn attribute_store(object: *c.PyObject, name: [:0]const u8, item: ?*c.PyObject) Error!void {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (python.attribute_set(object, name, item) != 0) return error.PythonError;
}

pub fn item_get(object: *c.PyObject, key: anytype) Error!value.Reference {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % c.object_alignment == 0);
    assert(convert.item_valid(@TypeOf(key), &key));

    const converted = try convert.object_new(@TypeOf(key), key);
    defer c.Py_DecRef(converted);

    const result = c.PyObject_GetItem(object, converted) orelse return error.PythonError;
    return .{ .pointer = result };
}

pub fn item_set(object: *c.PyObject, entry: anytype) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % c.object_alignment == 0);
    assert(convert.item_valid(@TypeOf(entry.key), &entry.key));
    assert(convert.item_valid(@TypeOf(entry.value), &entry.value));

    const key_converted = try convert.object_new(@TypeOf(entry.key), entry.key);
    defer c.Py_DecRef(key_converted);

    const item_converted = try convert.object_new(@TypeOf(entry.value), entry.value);
    defer c.Py_DecRef(item_converted);

    if (c.PyObject_SetItem(object, key_converted, item_converted) != 0) {
        return error.PythonError;
    }
}

pub fn item_delete(object: *c.PyObject, key: anytype) Error!void {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % c.object_alignment == 0);
    assert(convert.item_valid(@TypeOf(key), &key));

    const converted = try convert.object_new(@TypeOf(key), key);
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

    const result = python.attribute_get(object, name) orelse return error.PythonError;
    return .{ .pointer = result };
}
