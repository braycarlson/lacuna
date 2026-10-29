const std = @import("std");

const c = @import("c.zig");
const callback = @import("callback.zig");
const exception = @import("exception.zig");
const pending = @import("pending.zig");
const python = @import("python.zig");
const state_module = @import("state.zig");

const assert = std.debug.assert;

const Builtin = exception.Builtin;

pub const Bytes = struct {
    bytes: []const u8,
};

pub const Path = struct {
    bytes: []const u8,
};

pub const Decimal = struct {
    coefficient: i128,
    exponent: i32,
};

pub const Fraction = struct {
    numerator: i256,
    denominator: i256,
};

pub const IPAddress = union(enum) {
    v4: [4]u8,
    v6: [16]u8,
};

pub const Capsule = struct {
    pub fn capsule_new(pointer: anytype, name: [:0]const u8) callback.Error!Reference {
        comptime assert(@typeInfo(@TypeOf(pointer)).pointer.size == .one);
        comptime assert(!@typeInfo(@TypeOf(pointer)).pointer.attrs.@"const");
        assert(name.len > 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const capsule = c.PyCapsule_New(@ptrCast(pointer), name.ptr, null) orelse {
            return error.PythonError;
        };

        return .{ .pointer = capsule };
    }
};

pub const capsule_new = Capsule.capsule_new;

pub fn none() Object {
    return singleton_of(.none);
}

pub fn ellipsis() Object {
    return singleton_of(.ellipsis);
}

pub fn not_implemented() Object {
    return singleton_of(.not_implemented);
}

fn singleton_of(comptime which: state_module.Singleton) Object {
    comptime assert(@tagName(which).len > 0);

    const object = state_module.singleton_get(which);

    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

    return .{ .pointer = object };
}

pub const Slice = struct {
    start: i64,
    stop: i64,
    step: i64,

    pub fn adjust(slice: *Slice, length: u64) u64 {
        assert(slice.step != 0);
        assert(length <= std.math.maxInt(c.Py_ssize_t));

        var start: c.Py_ssize_t = @intCast(slice.start);
        var stop: c.Py_ssize_t = @intCast(slice.stop);

        const size: c.Py_ssize_t = @intCast(length);
        const count = c.PySlice_AdjustIndices(size, &start, &stop, @intCast(slice.step));

        slice.start = start;
        slice.stop = stop;

        assert(count >= 0);
        assert(count <= length);

        return @intCast(count);
    }
};

pub const UUID = struct {
    bytes: [16]u8,
};

pub const ModuleObject = struct {
    object: Object,
};

pub const TypeObject = struct {
    object: Object,

    pub fn instance_new(class: TypeObject, value: anytype) callback.Error!Reference {
        comptime assert(@typeInfo(@TypeOf(value)) == .@"struct");

        const Value = @TypeOf(value);
        const Class = if (@hasDecl(Value, "extended_class")) Value.extended_class else Value;
        const Instance = @import("instance.zig").InstanceType(Class);

        comptime assert(@typeInfo(Class) == .@"struct");
        comptime assert(@sizeOf(Value) >= @sizeOf(Class));
        assert(@intFromPtr(class.object.pointer) % @alignOf(c.PyObject_Header) == 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (Instance.native_base != null) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends a native " ++
                "base, so its instances come from init, not instance_new");
        }

        if (Instance.referencing) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' owns Python " ++
                "references, so instance_new cannot build it by value");
        }

        if (Instance.base) |Base| {
            if (Value == Class) {
                @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends '" ++
                    @typeName(Base) ++ "', so instance_new takes lacuna.ExtendedType(" ++
                    @typeName(Class) ++ ")");
            }
        }

        if (!python.class_is(class.object.pointer)) {
            return pending.raise_builtin(.type_error, "instance_new expects a type");
        }

        if (Instance.defining_of(class.object.pointer) == null) {
            return pending.raise_builtin(
                .type_error,
                "instance_new expects " ++ @typeName(Class) ++ " or a subclass of it",
            );
        }

        const allocation = Instance.allocate(class.object.pointer) catch return error.PythonError;

        Instance.store(allocation, &value);

        assert(Instance.data_of(allocation.object) == &allocation.storage.value);

        return .{ .pointer = allocation.object };
    }

    pub fn of(object: Object) callback.Error!TypeObject {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);

        if (python.class_is(object.pointer)) return .{ .object = object };
        return pending.raise_builtin(.type_error, "expected a type");
    }
};

pub const Comparison = enum(c_int) {
    less = c.Py_LT,
    less_equal = c.Py_LE,
    equal = c.Py_EQ,
    not_equal = c.Py_NE,
    greater = c.Py_GT,
    greater_equal = c.Py_GE,
};

pub const Iterator = struct {
    reference: Reference,

    pub fn next(iterator: *Iterator) callback.Error!?Reference {
        assert(iterator.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const item = c.PyIter_Next(iterator.reference.pointer.?) orelse {
            if (c.PyErr_Occurred() != null) return error.PythonError;
            return null;
        };

        return .{ .pointer = item };
    }

    pub fn release(iterator: *Iterator) void {
        assert(@intFromPtr(iterator) % @alignOf(Iterator) == 0);

        iterator.reference.release();

        assert(iterator.reference.pointer == null);
    }
};

pub fn eval(source: [:0]const u8, globals: Object, locals: ?Object) callback.Error!Reference {
    assert(globals.valid());
    assert(std.mem.findScalar(u8, source, 0) == null);
    if (locals) |present| assert(present.valid());
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const code = try compiled(source, .eval);
    defer c.Py_DecRef(code);

    const scope = if (locals) |present| present.pointer else null;
    const result = c.PyEval_EvalCode(code, globals.pointer, scope) orelse return error.PythonError;

    return .{ .pointer = result };
}

pub fn run(source: [:0]const u8, globals: Object, locals: ?Object) callback.Error!void {
    assert(globals.valid());
    assert(std.mem.findScalar(u8, source, 0) == null);
    if (locals) |present| assert(present.valid());
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const code = try compiled(source, .file);
    defer c.Py_DecRef(code);

    const scope = if (locals) |present| present.pointer else null;
    const result = c.PyEval_EvalCode(code, globals.pointer, scope) orelse return error.PythonError;

    c.Py_DecRef(result);
}

const Start = enum {
    eval,
    file,
};

const source_filename = "<lacuna>";

fn compiled(source: [:0]const u8, start: Start) callback.Error!*c.PyObject {
    assert(std.mem.findScalar(u8, source, 0) == null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (c.pypy) {
        if (c.abi.pypy.minor < 12) return compiled_builtin(source, start);
    }

    const mode: c_int = switch (start) {
        .eval => c.Py_eval_input,
        .file => c.Py_file_input,
    };

    return c.Py_CompileString(source, source_filename, mode) orelse error.PythonError;
}

fn compiled_builtin(source: [:0]const u8, start: Start) callback.Error!*c.PyObject {
    assert(c.pypy);
    assert(std.mem.findScalar(u8, source, 0) == null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const compile = python.builtin_new("compile") orelse return error.PythonError;
    defer c.Py_DecRef(compile);

    const mode: [:0]const u8 = switch (start) {
        .eval => "eval",
        .file => "exec",
    };

    const format = "sss";
    const result = c.PyObject_CallFunction(compile, format, source.ptr, source_filename, mode.ptr);

    return result orelse error.PythonError;
}

pub fn import_module(name: [:0]const u8) callback.Error!Reference {
    assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const module = c.PyImport_ImportModule(name) orelse return error.PythonError;
    return .{ .pointer = module };
}

pub const bytearray_bytes_max: u64 = 1 << 30;

pub const ListObject = struct {
    reference: Reference,
    owned: bool,

    pub const annotation = "list[Any]";
    pub const builtin_exact: Builtin = .list;

    pub fn init(capacity_hint: u64) callback.Error!ListObject {
        assert(capacity_hint <= std.math.maxInt(c.Py_ssize_t));
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const list = c.PyList_New(0) orelse return error.PythonError;

        return .{ .reference = .{ .pointer = list }, .owned = true };
    }

    pub fn append(list: *const ListObject, element: anytype) callback.Error!void {
        assert(callback.plain_valid(@TypeOf(element), &element));
        assert(list.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const converted = try callback.plain_to(@TypeOf(element), element);
        defer c.Py_DecRef(converted);

        if (c.PyList_Append(list.reference.pointer.?, converted) != 0) return error.PythonError;
    }

    pub fn set(list: *const ListObject, index: u64, element: anytype) callback.Error!void {
        assert(index <= std.math.maxInt(c.Py_ssize_t));
        assert(callback.plain_valid(@TypeOf(element), &element));
        assert(list.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (index >= list.length()) return index_error();

        const converted = try callback.plain_to(@TypeOf(element), element);
        const status = c.PyList_SetItem(list.reference.pointer.?, @intCast(index), converted);

        assert(status == 0);
    }

    pub fn length(list: *const ListObject) u64 {
        assert(list.reference.pointer != null);

        const size = c.PyList_Size(list.reference.pointer.?);

        assert(size >= 0);

        return @intCast(size);
    }

    pub fn item(list: *const ListObject, index: u64) callback.Error!Object {
        assert(index <= std.math.maxInt(c.Py_ssize_t));
        assert(list.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (index >= list.length()) return index_error();

        const element = c.PyList_GetItem(list.reference.pointer.?, @intCast(index)).?;

        return .{ .pointer = element };
    }

    pub fn release(list: *ListObject) void {
        assert(list.owned);
        assert(list.reference.pointer != null);

        list.reference.release();
    }
};

pub const TupleObject = struct {
    reference: Reference,
    owned: bool,

    pub const annotation = "tuple[Any, ...]";
    pub const builtin_exact: Builtin = .tuple;

    pub fn init(count: u64) callback.Error!TupleObject {
        assert(count <= std.math.maxInt(c.Py_ssize_t));
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const tuple = c.PyTuple_New(@intCast(count)) orelse return error.PythonError;
        const placeholder = c.Py_BuildValue("") orelse unreachable;
        defer c.Py_DecRef(placeholder);

        for (0..@as(usize, @intCast(count))) |index| {
            const filler = python.reference_new(placeholder);
            const status = c.PyTuple_SetItem(tuple, @intCast(index), filler);

            assert(status == 0);
        }

        return .{ .reference = .{ .pointer = tuple }, .owned = true };
    }

    pub fn set(tuple: *const TupleObject, index: u64, element: anytype) callback.Error!void {
        assert(index <= std.math.maxInt(c.Py_ssize_t));
        assert(callback.plain_valid(@TypeOf(element), &element));
        assert(tuple.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (index >= tuple.length()) return index_error();

        const converted = try callback.plain_to(@TypeOf(element), element);
        const status = c.PyTuple_SetItem(tuple.reference.pointer.?, @intCast(index), converted);

        if (status != 0) return error.PythonError;
    }

    pub fn length(tuple: *const TupleObject) u64 {
        assert(tuple.reference.pointer != null);

        const size = c.PyTuple_Size(tuple.reference.pointer.?);

        assert(size >= 0);

        return @intCast(size);
    }

    pub fn item(tuple: *const TupleObject, index: u64) callback.Error!Object {
        assert(index <= std.math.maxInt(c.Py_ssize_t));
        assert(tuple.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (index >= tuple.length()) return index_error();

        const element = c.PyTuple_GetItem(tuple.reference.pointer.?, @intCast(index)).?;

        return .{ .pointer = element };
    }

    pub fn release(tuple: *TupleObject) void {
        assert(tuple.owned);
        assert(tuple.reference.pointer != null);

        tuple.reference.release();
    }
};

pub const DictObject = struct {
    reference: Reference,
    owned: bool,

    pub const annotation = "dict[Any, Any]";
    pub const builtin_exact: Builtin = .dictionary;

    pub const Entry = struct {
        key: Object,
        value: Object,
    };

    pub const Entries = struct {
        dictionary: *c.PyObject,
        position: c.Py_ssize_t,

        pub fn next(cursor: *Entries) ?Entry {
            assert(cursor.position >= 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            var key: ?*c.PyObject = null;
            var element: ?*c.PyObject = null;

            if (c.PyDict_Next(cursor.dictionary, &cursor.position, &key, &element) == 0) {
                return null;
            }

            return .{ .key = .{ .pointer = key.? }, .value = .{ .pointer = element.? } };
        }
    };

    pub fn init() callback.Error!DictObject {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const dictionary = c.PyDict_New() orelse return error.PythonError;

        assert(c.PyDict_Size(dictionary) == 0);

        return .{ .reference = .{ .pointer = dictionary }, .owned = true };
    }

    pub fn set(dictionary: *const DictObject, entry: anytype) callback.Error!void {
        comptime assert(@hasField(@TypeOf(entry), "key"));

        const key: @TypeOf(entry.key) = entry.key;
        const element: @TypeOf(entry.value) = entry.value;

        assert(callback.plain_valid(@TypeOf(key), &key));
        assert(callback.plain_valid(@TypeOf(element), &element));
        assert(dictionary.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const converted_key = try callback.plain_to(@TypeOf(key), key);
        defer c.Py_DecRef(converted_key);

        const converted = try callback.plain_to(@TypeOf(element), element);
        defer c.Py_DecRef(converted);

        const status = c.PyDict_SetItem(dictionary.reference.pointer.?, converted_key, converted);
        if (status != 0) return error.PythonError;
    }

    pub fn get(dictionary: *const DictObject, key: anytype) callback.Error!?Object {
        assert(callback.plain_valid(@TypeOf(key), &key));
        assert(dictionary.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const converted_key = try callback.plain_to(@TypeOf(key), key);
        defer c.Py_DecRef(converted_key);

        const pointer = dictionary.reference.pointer.?;
        const found = c.PyDict_GetItemWithError(pointer, converted_key) orelse {
            if (c.PyErr_Occurred() != null) return error.PythonError;
            return null;
        };

        return .{ .pointer = found };
    }

    pub fn delete(dictionary: *const DictObject, key: anytype) callback.Error!void {
        assert(callback.plain_valid(@TypeOf(key), &key));
        assert(dictionary.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const converted_key = try callback.plain_to(@TypeOf(key), key);
        defer c.Py_DecRef(converted_key);

        const status = c.PyDict_DelItem(dictionary.reference.pointer.?, converted_key);
        if (status != 0) return error.PythonError;
    }

    pub fn length(dictionary: *const DictObject) u64 {
        assert(dictionary.reference.pointer != null);

        const size = c.PyDict_Size(dictionary.reference.pointer.?);

        assert(size >= 0);

        return @intCast(size);
    }

    pub fn entries(dictionary: *const DictObject) Entries {
        assert(dictionary.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return .{ .dictionary = dictionary.reference.pointer.?, .position = 0 };
    }

    pub fn release(dictionary: *DictObject) void {
        assert(dictionary.owned);
        assert(dictionary.reference.pointer != null);

        dictionary.reference.release();
    }
};

pub const SetObject = SetObjectType(false);
pub const FrozenSetObject = SetObjectType(true);

fn SetObjectType(comptime frozen: bool) type {
    return struct {
        reference: Reference,
        owned: bool,

        const Set = @This();

        pub const annotation = if (frozen) "frozenset[Any]" else "set[Any]";
        pub const builtin_exact: Builtin = if (frozen) .frozenset else .set;

        pub fn init() callback.Error!Set {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const created = if (frozen) c.PyFrozenSet_New(null) else c.PySet_New(null);
            const set = created orelse return error.PythonError;

            assert(c.PySet_Size(set) == 0);

            return .{ .reference = .{ .pointer = set }, .owned = true };
        }

        pub fn add(set: *const Set, element: anytype) callback.Error!void {
            assert(callback.plain_valid(@TypeOf(element), &element));
            assert(set.reference.pointer != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const converted = try callback.plain_to(@TypeOf(element), element);
            defer c.Py_DecRef(converted);

            if (c.PySet_Add(set.reference.pointer.?, converted) != 0) return error.PythonError;
        }

        pub fn contains(set: *const Set, element: anytype) callback.Error!bool {
            assert(callback.plain_valid(@TypeOf(element), &element));
            assert(set.reference.pointer != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const converted = try callback.plain_to(@TypeOf(element), element);
            defer c.Py_DecRef(converted);

            return callback.status_of(c.PySet_Contains(set.reference.pointer.?, converted));
        }

        pub fn length(set: *const Set) u64 {
            assert(set.reference.pointer != null);

            const size = c.PySet_Size(set.reference.pointer.?);

            assert(size >= 0);

            return @intCast(size);
        }

        pub fn release(set: *Set) void {
            assert(set.owned);
            assert(set.reference.pointer != null);

            set.reference.release();
        }
    };
}

pub const ByteArrayObject = struct {
    reference: Reference,
    owned: bool,

    pub const annotation = "bytearray";
    pub const builtin_exact: Builtin = .bytearray;

    pub const Writer = struct {
        array: *const ByteArrayObject,
        interface: std.Io.Writer,

        const vtable: std.Io.Writer.VTable = .{ .drain = drain };

        fn drain(
            interface: *std.Io.Writer,
            data: []const []const u8,
            splat: usize,
        ) std.Io.Writer.Error!usize {
            assert(data.len > 0);
            assert(data.len > 1 or splat > 0);
            assert(interface.end <= interface.buffer.len);

            const sink: *Writer = @alignCast(@fieldParentPtr("interface", interface));

            try sink.extend(interface.buffered());
            interface.end = 0;

            var written: u64 = 0;

            for (data[0 .. data.len - 1]) |bytes| {
                try sink.extend(bytes);
                written += bytes.len;
            }

            const last = data[data.len - 1];

            for (0..splat) |_| {
                try sink.extend(last);
                written += last.len;
            }

            assert(sink.array.length() >= written);
            assert(interface.end == 0);

            return @intCast(written);
        }

        fn extend(sink: *const Writer, bytes: []const u8) std.Io.Writer.Error!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(sink.array.reference.pointer != null);
            assert(bytes.len <= bytearray_bytes_max);

            if (bytes.len == 0) return;

            const held = sink.array.slice();
            const held_end = @intFromPtr(held.ptr) + held.len;

            if (bytes.len > 0) assert(@intFromPtr(bytes.ptr) >= held_end or
                @intFromPtr(bytes.ptr) + bytes.len <= @intFromPtr(held.ptr));

            const start: usize = @intCast(sink.array.length());
            const end = start + bytes.len;

            sink.array.resize(end) catch return error.WriteFailed;
            @memcpy(sink.array.slice()[start..end], bytes);

            assert(sink.array.length() == end);
        }
    };

    pub fn init(count: u64) callback.Error!ByteArrayObject {
        assert(count <= std.math.maxInt(c.Py_ssize_t));
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (count > bytearray_bytes_max) {
            return pending.raise_builtin(.value_error, "the bytearray exceeds bytearray_bytes_max");
        }

        const array = c.PyByteArray_FromStringAndSize(null, @intCast(count)) orelse {
            return error.PythonError;
        };

        @memset(slice_of(array), 0);

        return .{ .reference = .{ .pointer = array }, .owned = true };
    }

    pub fn resize(array: *const ByteArrayObject, count: u64) callback.Error!void {
        assert(count <= std.math.maxInt(c.Py_ssize_t));
        assert(array.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (count > bytearray_bytes_max) {
            return pending.raise_builtin(.value_error, "the bytearray exceeds bytearray_bytes_max");
        }

        const status = c.PyByteArray_Resize(array.reference.pointer.?, @intCast(count));
        if (status != 0) return error.PythonError;

        assert(array.length() == count);
    }

    pub fn slice(array: *const ByteArrayObject) []u8 {
        assert(array.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return slice_of(array.reference.pointer.?);
    }

    pub fn length(array: *const ByteArrayObject) u64 {
        assert(array.reference.pointer != null);

        const size = c.PyByteArray_Size(array.reference.pointer.?);

        assert(size >= 0);

        return @intCast(size);
    }

    pub fn writer(array: *const ByteArrayObject, buffer: []u8) Writer {
        assert(array.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(buffer.len <= bytearray_bytes_max);

        return .{ .array = array, .interface = .{ .vtable = &Writer.vtable, .buffer = buffer } };
    }

    pub fn to_bytes(array: *const ByteArrayObject) callback.Error!Reference {
        assert(array.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const bytes = array.slice();
        const result = c.PyBytes_FromStringAndSize(bytes.ptr, @intCast(bytes.len)) orelse {
            return error.PythonError;
        };

        return .{ .pointer = result };
    }

    pub fn to_text(array: *const ByteArrayObject) callback.Error!Reference {
        assert(array.reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const bytes = array.slice();
        const result = c.PyUnicode_FromStringAndSize(bytes.ptr, @intCast(bytes.len)) orelse {
            return error.PythonError;
        };

        return .{ .pointer = result };
    }

    pub fn release(array: *ByteArrayObject) void {
        assert(array.owned);
        assert(array.reference.pointer != null);

        array.reference.release();
    }

    fn slice_of(object: *c.PyObject) []u8 {
        const size = c.PyByteArray_Size(object);

        assert(size >= 0);

        if (size == 0) return &.{};

        const pointer = c.PyByteArray_AsString(object).?;

        return pointer[0..@intCast(size)];
    }
};

fn index_error() callback.Error {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const result = pending.raise_builtin(.index_error, "index out of range");

    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

    return result;
}

pub fn container_is(comptime T: type) bool {
    comptime assert(T != type);

    if (@typeInfo(T) != .@"struct") return false;

    inline for (containers) |Container| {
        if (T == Container) return true;
    }

    return false;
}

pub const containers = [_]type{
    ByteArrayObject,
    DictObject,
    FrozenSetObject,
    ListObject,
    SetObject,
    TupleObject,
};

pub const Object = struct {
    pointer: *c.PyObject,

    pub fn as_bytearray(object: Object) callback.Error!ByteArrayObject {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        try object.instance_require("bytearray");

        return .{ .reference = .{ .pointer = object.pointer }, .owned = false };
    }

    pub fn as_dict(object: Object) callback.Error!DictObject {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (!python.has_flag(object.pointer, c.Py_TPFLAGS_DICT_SUBCLASS)) {
            return pending.raise_builtin(.type_error, "expected a dict");
        }

        return .{ .reference = .{ .pointer = object.pointer }, .owned = false };
    }

    pub fn as_list(object: Object) callback.Error!ListObject {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (!python.has_flag(object.pointer, c.Py_TPFLAGS_LIST_SUBCLASS)) {
            return pending.raise_builtin(.type_error, "expected a list");
        }

        return .{ .reference = .{ .pointer = object.pointer }, .owned = false };
    }

    pub fn as_set(object: Object) callback.Error!SetObject {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        try object.instance_require("set");

        return .{ .reference = .{ .pointer = object.pointer }, .owned = false };
    }

    pub fn as_tuple(object: Object) callback.Error!TupleObject {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (!python.has_flag(object.pointer, c.Py_TPFLAGS_TUPLE_SUBCLASS)) {
            return pending.raise_builtin(.type_error, "expected a tuple");
        }

        return .{ .reference = .{ .pointer = object.pointer }, .owned = false };
    }

    fn instance_require(object: Object, comptime name: [:0]const u8) callback.Error!void {
        comptime assert(name.len > 0);
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const kind = python.builtin_new(name) orelse return error.PythonError;
        defer c.Py_DecRef(kind);

        if (try callback.status_of(c.PyObject_IsInstance(object.pointer, kind))) return;
        return pending.raise_builtin(.type_error, "expected a " ++ name);
    }

    fn valid(object: Object) bool {
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);

        return python.class_is(python.type_borrowed(object.pointer));
    }

    pub fn capsule_pointer(
        object: Object,
        comptime T: type,
        name: [:0]const u8,
    ) callback.Error!*T {
        comptime assert(@sizeOf(T) > 0);
        assert(object.valid());
        assert(name.len > 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const pointer = c.PyCapsule_GetPointer(object.pointer, name.ptr) orelse {
            return error.PythonError;
        };

        assert(@intFromPtr(pointer) % @alignOf(T) == 0);

        return @ptrCast(@alignCast(pointer));
    }

    pub fn weakref(object: Object) callback.Error!Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const reference = c.PyWeakref_NewRef(object.pointer, null) orelse return error.PythonError;

        return .{ .pointer = reference };
    }

    pub fn weakref_target(object: Object) callback.Error!?Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (c.api_3_13_linked) {
            var target: ?*c.PyObject = null;

            if (c.PyWeakref_GetRef(object.pointer, &target) < 0) return error.PythonError;

            const present = target orelse return null;
            return .{ .pointer = present };
        }

        try object.weakref_check();

        const borrowed = c.PyWeakref_GetObject(object.pointer) orelse return error.PythonError;
        if (python.is_none(borrowed)) return null;

        return .{ .pointer = python.reference_new(borrowed) };
    }

    fn weakref_check(object: Object) callback.Error!void {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const module = c.PyImport_ImportModule("weakref") orelse return error.PythonError;
        defer c.Py_DecRef(module);

        const names = [_][:0]const u8{ "ReferenceType", "ProxyTypes" };

        for (names) |name| {
            const expected = c.PyObject_GetAttrString(module, name) orelse return error.PythonError;
            defer c.Py_DecRef(expected);

            const status = c.PyObject_IsInstance(object.pointer, expected);

            if (status < 0) return error.PythonError;
            if (status == 1) return;
        }

        return pending.raise_builtin(.type_error, "expected a weakref");
    }

    pub fn attribute_delete(object: Object, name: [:0]const u8) callback.Error!void {
        assert(object.valid());
        assert(name.len > 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.attribute_delete(object.pointer, name);
    }

    pub fn attribute_set(object: Object, name: [:0]const u8, element: anytype) callback.Error!void {
        assert(object.valid());
        assert(name.len > 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(callback.plain_valid(@TypeOf(element), &element));

        return callback.attribute_set(object.pointer, name, element);
    }

    pub fn call_keywords(object: Object, invocation: anytype) callback.Error!Reference {
        assert(object.valid());
        comptime assert(@hasField(@TypeOf(invocation), "arguments"));
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.call_keywords(object.pointer, invocation);
    }

    pub fn call_method_keywords(
        object: Object,
        name: [:0]const u8,
        invocation: anytype,
    ) callback.Error!Reference {
        assert(object.valid());
        comptime assert(@hasField(@TypeOf(invocation), "keywords"));
        assert(name.len > 0);

        var method = try callback.attribute(object.pointer, name);
        defer method.release();

        return callback.call_keywords(method.pointer.?, invocation);
    }

    pub fn class(object: Object) Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const result = python.class_of(object.pointer);

        assert(python.class_is(result));

        return .{ .pointer = result };
    }

    pub fn compare(
        object: Object,
        comparing: struct { other: Object, comparison: Comparison },
    ) callback.Error!bool {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@intFromPtr(comparing.other.pointer) % @alignOf(c.PyObject_Header) == 0);

        const operation = @backingInt(comparing.comparison);
        const other = comparing.other.pointer;
        const status = c.PyObject_RichCompareBool(object.pointer, other, operation);
        return callback.status_of(status);
    }

    pub fn equal(object: Object, comparing: struct { other: Object }) callback.Error!bool {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@intFromPtr(comparing.other.pointer) % @alignOf(c.PyObject_Header) == 0);

        return object.compare(.{ .other = comparing.other, .comparison = .equal });
    }

    pub fn hash(object: Object) callback.Error!i64 {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const result = c.PyObject_Hash(object.pointer);

        if (result == -1) {
            if (c.PyErr_Occurred() != null) return error.PythonError;
        }

        return result;
    }

    pub fn identical(object: Object, comparing: struct { other: Object }) bool {
        assert(object.valid());
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);
        assert(@intFromPtr(comparing.other.pointer) % @alignOf(c.PyObject_Header) == 0);

        return object.pointer == comparing.other.pointer;
    }

    pub fn instance_of(object: Object, kind: TypeObject) callback.Error!bool {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(python.class_is(kind.object.pointer));

        return callback.status_of(c.PyObject_IsInstance(object.pointer, kind.object.pointer));
    }

    pub fn item(object: Object, key: anytype) callback.Error!Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(callback.plain_valid(@TypeOf(key), &key));

        return callback.item_get(object.pointer, key);
    }

    pub fn item_delete(object: Object, key: anytype) callback.Error!void {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(callback.plain_valid(@TypeOf(key), &key));

        return callback.item_delete(object.pointer, key);
    }

    pub fn item_set(object: Object, entry: anytype) callback.Error!void {
        assert(object.valid());
        comptime assert(@hasField(@TypeOf(entry), "key"));
        comptime assert(@hasField(@TypeOf(entry), "value"));
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.item_set(object.pointer, entry);
    }

    pub fn iterate(object: Object) callback.Error!Iterator {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const iterator = c.PyObject_GetIter(object.pointer) orelse return error.PythonError;
        return .{ .reference = .{ .pointer = iterator } };
    }

    pub fn length(object: Object) callback.Error!u64 {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const result = c.PyObject_Size(object.pointer);

        if (result < 0) return error.PythonError;

        const count: u64 = @intCast(result);

        assert(count <= std.math.maxInt(c.Py_ssize_t));

        return count;
    }

    pub fn none(object: Object) bool {
        assert(object.valid());
        return python.is_none(object.pointer);
    }

    pub fn representation(object: Object) callback.Error!Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const result = c.PyObject_Repr(object.pointer) orelse return error.PythonError;
        return .{ .pointer = result };
    }

    pub fn string(object: Object) callback.Error!Reference {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const result = c.PyObject_Str(object.pointer) orelse return error.PythonError;
        return .{ .pointer = result };
    }

    pub fn truthy(object: Object) callback.Error!bool {
        assert(object.valid());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.status_of(c.PyObject_IsTrue(object.pointer));
    }

    pub fn attribute(object: Object, name: [:0]const u8) callback.Error!Reference {
        assert(object.valid());
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);
        assert(name.len > 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.attribute(object.pointer, name);
    }

    pub fn call(object: Object, arguments: anytype) callback.Error!Reference {
        assert(object.valid());
        comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.call(object.pointer, arguments);
    }

    pub fn call_method(
        object: Object,
        name: [:0]const u8,
        arguments: anytype,
    ) callback.Error!Reference {
        assert(object.valid());
        comptime assert(@typeInfo(@TypeOf(arguments)).@"struct".is_tuple);
        assert(@intFromPtr(object.pointer) % @alignOf(c.PyObject_Header) == 0);
        assert(name.len > 0);

        var method = try callback.attribute(object.pointer, name);
        defer method.release();

        assert(method.pointer != null);

        return callback.call(method.pointer.?, arguments);
    }
};

pub const Reference = struct {
    pointer: ?*c.PyObject,

    pub const empty: Reference = .{ .pointer = null };

    pub fn acquire(held: Object) Reference {
        assert(@intFromPtr(held.pointer) % @alignOf(*c.PyObject) == 0);

        c.Py_IncRef(held.pointer);

        return .{ .pointer = held.pointer };
    }

    pub fn convert(reference: Reference, comptime T: type) callback.Error!T {
        assert(reference.pointer != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        return callback.plain_from(T, reference.pointer.?);
    }

    pub fn object(reference: Reference) ?Object {
        assert(@intFromPtr(reference.pointer) % @alignOf(*c.PyObject) == 0);

        const pointer = reference.pointer orelse return null;
        return .{ .pointer = pointer };
    }

    pub fn release(reference: *Reference) void {
        assert(@intFromPtr(reference.pointer) % @alignOf(*c.PyObject) == 0);

        const pointer = reference.pointer orelse return;

        reference.pointer = null;

        c.Py_DecRef(pointer);
    }

    pub fn assign(reference: *Reference, held: Object) void {
        assert(@intFromPtr(held.pointer) % @alignOf(c.PyObject_Header) == 0);
        assert(@intFromPtr(reference.pointer) % @alignOf(c.PyObject_Header) == 0);

        const previous = reference.pointer;

        reference.* = acquire(held);

        assert(reference.pointer == held.pointer);

        if (previous) |pointer| c.Py_DecRef(pointer);
    }
};

comptime {
    assert(@sizeOf(Object) == @sizeOf(*c.PyObject));
    assert(@sizeOf(Reference) == @sizeOf(*c.PyObject));
    assert(@sizeOf(Bytes) == @sizeOf([]const u8));
}

test Bytes {
    const kind_module = @import("kind.zig");
    const bytes: Bytes = .{ .bytes = "payload" };

    try std.testing.expect(comptime kind_module.kind_of(Bytes, &.{}) == .bytes);
    try std.testing.expectEqualStrings("payload", bytes.bytes);
}

test Object {
    const kind_module = @import("kind.zig");

    try std.testing.expect(comptime kind_module.kind_of(Object, &.{}) == .object);
    try std.testing.expect(comptime kind_module.kind_of(?Object, &.{}) == .optional);
    try std.testing.expect(comptime kind_module.kind_of(Reference, &.{}) == .reference);
}
