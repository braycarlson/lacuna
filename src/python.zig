const std = @import("std");

const c = @import("c.zig");

const assert = std.debug.assert;

pub fn class_of(object: *c.PyObject) *c.PyObject {
    const class = c.PyObject_Type(object);

    assert(class != null);
    assert(class_is(class.?));

    return class.?;
}

pub fn class_is(object: *c.PyObject) bool {
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

    const header: *const c.PyObject_Header = @ptrCast(@alignCast(object));
    const meta = header.ob_type.?;

    return c.PyType_GetFlags(meta) & c.Py_TPFLAGS_TYPE_SUBCLASS != 0;
}

pub fn type_borrowed(object: *c.PyObject) *c.PyObject {
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

    const header: *const c.PyObject_Header = @ptrCast(@alignCast(object));
    const result = header.ob_type.?;

    assert(class_is(result));

    return result;
}

pub fn flags_of(object: *c.PyObject) c_ulong {
    const class = class_of(object);
    defer c.Py_DecRef(class);

    const flags = c.PyType_GetFlags(class);

    assert(flags != 0);
    assert(class_is(class));

    return flags;
}

pub fn has_flag(object: *c.PyObject, comptime flag: c_ulong) bool {
    comptime assert(flag != 0);
    comptime assert(std.math.isPowerOfTwo(flag));

    return flags_of(object) & flag != 0;
}

pub fn flagged_or_null(object: ?*c.PyObject, comptime flag: c_ulong) bool {
    comptime assert(std.math.isPowerOfTwo(flag));
    assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

    const live = object orelse return true;
    return has_flag(live, flag);
}

pub fn storage_at(comptime Storage: type, object: *c.PyObject, offset: u32) *Storage {
    assert(offset >= @sizeOf(c.PyObject_Header));
    assert(@intFromPtr(object) % @alignOf(Storage) == 0);

    const bytes: [*]u8 = @ptrCast(object);
    const result: *Storage = @ptrCast(@alignCast(bytes + offset));

    assert(@intFromPtr(result) - @intFromPtr(object) == offset);

    return result;
}

pub fn text_bounded(text: [*:0]const u8, comptime bytes_max: u32) []const u8 {
    assert(@intFromPtr(text) != 0);
    comptime assert(bytes_max > 0);

    var length: u32 = 0;

    for (0..bytes_max) |_| {
        if (text[length] == 0) break;

        length += 1;
    }

    assert(length <= bytes_max);

    return text[0..length];
}

pub fn builtin_new(name: [:0]const u8) ?*c.PyObject {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const modules = c.PyImport_GetModuleDict() orelse return null;
    const key = c.PyUnicode_FromStringAndSize("builtins", "builtins".len) orelse return null;
    defer c.Py_DecRef(key);

    const builtins = c.PyObject_GetItem(modules, key) orelse return null;
    defer c.Py_DecRef(builtins);

    return c.PyObject_GetAttrString(builtins, name);
}

pub const Raise = struct {
    class_name: [:0]const u8,
    message: [:0]const u8,
};

pub fn exception_raise(raise: Raise) void {
    assert(raise.class_name.len > 0);
    assert(raise.message.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = builtin_new(raise.class_name) orelse return;
    defer c.Py_DecRef(class);

    c.PyErr_SetString(class, raise.message);

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
}

pub fn is_none(object: *c.PyObject) bool {
    assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

    const none = c.Py_BuildValue("") orelse unreachable;
    defer c.Py_DecRef(none);

    return object == none;
}

pub fn reference_new(object: *c.PyObject) *c.PyObject {
    assert(@intFromPtr(object) % @alignOf(usize) == 0);

    c.Py_IncRef(object);

    assert(@intFromPtr(object) != 0);

    return object;
}

pub fn octets_of(object: *c.PyObject) ?[]const u8 {
    assert(has_flag(object, c.Py_TPFLAGS_BYTES_SUBCLASS));

    const size = c.PyBytes_Size(object);
    const pointer = c.PyBytes_AsString(object) orelse return null;

    assert(size >= 0);

    return pointer[0..@intCast(size)];
}

pub fn text_of(object: *c.PyObject) ?[:0]const u8 {
    assert(has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS));

    var size: c.Py_ssize_t = 0;

    const pointer = c.PyUnicode_AsUTF8AndSize(object, &size) orelse return null;

    assert(size >= 0);

    return pointer[0..@intCast(size) :0];
}

pub fn vector_of(
    arguments: ?[*]const *c.PyObject,
    count: c.Py_ssize_t,
    names: ?*c.PyObject,
) []const *c.PyObject {
    assert(count >= 0);
    assert(count == 0 or arguments != null);
    assert(@intFromPtr(names) % @alignOf(*c.PyObject) == 0);

    const keyword_size = if (names) |keyword_names| c.PyTuple_Size(keyword_names) else 0;
    const total: usize = @intCast(count + keyword_size);

    assert(total == 0 or arguments != null);

    const pointer = arguments orelse return &.{};
    return pointer[0..total];
}

pub fn view_bytes(view: *const c.Py_buffer) []const u8 {
    assert(view.len >= 0);
    assert(view.obj != null);

    if (view.len == 0) return &.{};

    const pointer: [*]const u8 = @ptrCast(view.buf.?);
    return pointer[0..@intCast(view.len)];
}

pub fn items_of(comptime Element: type, view: *const c.Py_buffer) ?[]Element {
    comptime assert(@sizeOf(Element) > 0);
    assert(view.itemsize == @sizeOf(Element));
    assert(@mod(view.len, view.itemsize) == 0);

    const Empty = struct {
        var items: [0]Element = .{};
    };

    if (view.len == 0) return &Empty.items;
    if (@intFromPtr(view.buf.?) % @alignOf(Element) != 0) return null;

    const count: usize = @intCast(@divExact(view.len, view.itemsize));
    const items: [*]Element = @ptrCast(@alignCast(view.buf.?));

    return items[0..count];
}

pub fn format_of(view: *const c.Py_buffer) []const u8 {
    assert(view.obj != null);
    assert(view.itemsize > 0);

    const format = view.format orelse return "B";
    return std.mem.span(format);
}

pub const Visit = struct {
    argument: ?*anyopaque,
    visitor: c.visitproc,
};

pub fn visit_all(objects: []const ?*c.PyObject, visit: Visit) c_int {
    assert(visit.visitor != null);
    assert(objects.len <= std.math.maxInt(u16));

    for (objects) |object| {
        if (object) |live| {
            const result = visit.visitor.?(live, visit.argument);
            if (result != 0) return result;
        }
    }

    return 0;
}

test text_bounded {
    const short: [:0]const u8 = "3.11.14";
    const long: [300:0]u8 = @splat('9');

    try std.testing.expectEqualStrings("3.11.14", text_bounded(short.ptr, 256));
    try std.testing.expectEqual(@as(usize, 256), text_bounded(&long, 256).len);
    try std.testing.expectEqual(@as(usize, 0), text_bounded("", 256).len);
}
