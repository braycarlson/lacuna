const std = @import("std");

const c = @import("c.zig");
const calendar = @import("calendar.zig");
const instance = @import("instance.zig");
const kind_module = @import("kind.zig");
const python = @import("python.zig");
const value_module = @import("value.zig");
const variant_module = @import("variant.zig");

const assert = std.debug.assert;

const kind_of = kind_module.kind_of;

pub const Error = error{Raised};

pub fn to_python(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) Error!*c.PyObject {
    comptime assert(T != type);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const result: ?*c.PyObject = switch (comptime kind_of(T, Binding.declared)) {
        .array => array_to(Binding, T, state, value),
        .boolean => c.PyBool_FromLong(@intFromBool(value.*)),
        .buffer, .buffer_mutable => slice_to(Binding, T, state, value.*),
        .buffer_strided => @compileError(
            "lacuna: a strided buffer is returned only from __buffer__",
        ),
        .bytes => c.PyBytes_FromStringAndSize(value.bytes.ptr, @intCast(value.bytes.len)),
        .bytes_owned => c.PyBytes_FromStringAndSize(&value.bytes, @intCast(value.length)),
        .class_pointer, .class_pointer_mutable => @compileError(
            "lacuna: a class pointer is returned only as the receiver of its own method",
        ),
        .class_extended => class_extended_to(Binding, T.extended_class, state, value),
        .class_value => class_value_to(Binding, T, state, value),
        .complex => c.PyComplex_FromDoubles(value.re, value.im),
        .container => python.reference_new(value.reference.pointer.?),
        .date => date_to(Binding, state, value),
        .datetime => datetime_to(Binding, state, value),
        .decimal => decimal_to(Binding, state, value),
        .duration => duration_to(Binding, state, value),
        .enumeration => enumeration_to(Binding, T, state, value.*),
        .float => c.PyFloat_FromDouble(@floatCast(value.*)),
        .fraction => fraction_to(Binding, state, value),
        .ip_address => address_to(Binding, state, value),
        .integer => if (@typeInfo(T).int.bits <= 64) integer_to(T, value) else integer_wide_to(
            T,
            value,
        ),
        .list => slice_to(Binding, []const T.Item, state, value.slice()),
        .map => map_to(Binding, T, state, value),
        .none => python.reference_new(state.builtins.get(.none)),
        .object => python.reference_new(value.pointer),
        .optional => optional_to(Binding, T, state, value),
        .path => path_to(Binding, state, value),
        .record => record_to(Binding, T, state, value),
        .reference => python.reference_new(value.pointer orelse state.builtins.get(.none)),
        .set => set_to(Binding, T, state, value),
        .slice => slice_object_to(value),
        .text, .text_terminated => text_to(value.*),
        .text_owned => text_to(value.slice()),
        .time => time_to(Binding, state, value),
        .tuple => tuple_to(Binding, T, state, value),
        .union_class => union_class_to(Binding, T, state, value),
        .uuid => uuid_to(Binding, state, value),
        .variant => variant_to(Binding, T, state, value),
    };

    return result orelse error.Raised;
}

fn slice_object_to(slice: *const value_module.Slice) ?*c.PyObject {
    assert(slice.step != 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const start = c.PyLong_FromLongLong(slice.start) orelse return null;
    defer c.Py_DecRef(start);

    const stop = c.PyLong_FromLongLong(slice.stop) orelse return null;
    defer c.Py_DecRef(stop);

    const step = c.PyLong_FromLongLong(slice.step) orelse return null;
    defer c.Py_DecRef(step);

    return c.PySlice_New(start, stop, step);
}

fn integer_to(comptime T: type, number: *const T) ?*c.PyObject {
    comptime assert(@sizeOf(T) <= 8);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(number) % @alignOf(T) == 0);

    return switch (@typeInfo(T).int.signedness) {
        .signed => c.PyLong_FromLongLong(number.*),
        .unsigned => c.PyLong_FromUnsignedLongLong(number.*),
    };
}

fn text_to(text: []const u8) ?*c.PyObject {
    assert(text.len <= std.math.maxInt(c.Py_ssize_t));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return c.PyUnicode_FromStringAndSize(text.ptr, @intCast(text.len));
}

fn optional_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const Child = @typeInfo(T).optional.child;

    comptime assert(@typeInfo(Child) != .optional);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (value.*) |*present| return to_python(Binding, Child, state, present) catch null;
    return python.reference_new(state.builtins.get(.none));
}

fn decimal_to(
    comptime Binding: type,
    state: *const Binding.State,
    value: *const value_module.Decimal,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(value.exponent >= std.math.minInt(i32));

    const class = state.library_get(.decimal) catch return null;

    var buffer: [64]u8 = undefined;

    const text = std.mem.print(&buffer, "{d}E{d}", .{ value.coefficient, value.exponent }) catch {
        unreachable;
    };

    const spelled = c.PyUnicode_FromStringAndSize(text.ptr, @intCast(text.len)) orelse return null;
    defer c.Py_DecRef(spelled);

    return c.PyObject_CallFunction(class, "O", spelled);
}

fn uuid_to(
    comptime Binding: type,
    state: *const Binding.State,
    value: *const value_module.UUID,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(value.bytes.len == 16);

    const class = state.library_get(.uuid) catch return null;
    const arguments = c.PyTuple_New(0) orelse return null;
    defer c.Py_DecRef(arguments);

    const size: c.Py_ssize_t = value.bytes.len;
    const bytes = c.PyBytes_FromStringAndSize(&value.bytes, size) orelse return null;
    defer c.Py_DecRef(bytes);

    const keywords = c.Py_BuildValue("{s:O}", "bytes", bytes) orelse return null;

    defer c.Py_DecRef(keywords);

    return c.PyObject_Call(class, arguments, keywords);
}

fn enumeration_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: T,
) ?*c.PyObject {
    assert(std.enums.tagName(T, value) != null);

    const index = comptime kind_module.enum_index(T, Binding.enums);
    const number: c_longlong = @backingInt(value);

    comptime assert(index < Binding.enums.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return c.PyObject_CallFunction(state.enum_get(index), "L", number);
}

fn class_value_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const index = comptime kind_module.class_index(T, Binding.classes).?;
    const Instance = instance.InstanceType(T);

    if (Instance.referencing) {
        @compileError("lacuna: the class '" ++ @typeName(T) ++
            "' owns Python references, so it is never returned by value");
    }

    if (Instance.base) |Base| {
        @compileError("lacuna: the class '" ++ @typeName(T) ++ "' extends '" ++
            @typeName(Base) ++ "', so it is returned as lacuna.ExtendedType(" ++
            @typeName(T) ++ ") with its base");
    }

    comptime assert(index < Binding.classes.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const allocation = Instance.allocate(state.class_get(index)) catch return null;

    allocation.storage.value = value.*;
    allocation.storage.initialized = true;

    assert(Instance.data_of(allocation.object) == &allocation.storage.value);

    return allocation.object;
}

fn class_extended_to(
    comptime Binding: type,
    comptime Class: type,
    state: *const Binding.State,
    value: *const instance.InstanceType(Class).Extended,
) ?*c.PyObject {
    const index = comptime kind_module.class_index(Class, Binding.classes).?;
    const Instance = instance.InstanceType(Class);

    if (Instance.referencing) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++
            "' owns Python references, so it is never returned by value");
    }

    comptime assert(Instance.base != null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const allocation = Instance.allocate(state.class_get(index)) catch return null;

    Instance.store(allocation, value);

    assert(Instance.data_of(allocation.object) == &allocation.storage.value);

    return allocation.object;
}

fn slice_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    items: T,
) ?*c.PyObject {
    const Item = @typeInfo(T).pointer.child;

    assert(items.len <= std.math.maxInt(c.Py_ssize_t));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const list = c.PyList_New(@intCast(items.len)) orelse return null;

    for (items, 0..) |*item, index| {
        const element = to_python(Binding, Item, state, item) catch {
            c.Py_DecRef(list);

            return null;
        };

        const status = c.PyList_SetItem(list, @intCast(index), element);

        assert(status == 0);
    }

    return list;
}

fn array_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const array = @typeInfo(T).array;

    comptime assert(array.len <= std.math.maxInt(u32));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const tuple = c.PyTuple_New(array.len) orelse return null;

    for (value, 0..) |*item, index| {
        const element = to_python(Binding, array.child, state, item) catch {
            c.Py_DecRef(tuple);

            return null;
        };

        const status = c.PyTuple_SetItem(tuple, @intCast(index), element);

        assert(status == 0);
    }

    return tuple;
}

fn tuple_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const structure = @typeInfo(T).@"struct";

    comptime assert(structure.is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const tuple = c.PyTuple_New(structure.field_names.len) orelse return null;

    inline for (structure.field_names, structure.field_types, 0..) |name, Field, index| {
        const element = to_python(Binding, Field, state, &@field(value, name)) catch {
            c.Py_DecRef(tuple);

            return null;
        };

        const status = c.PyTuple_SetItem(tuple, index, element);

        assert(status == 0);
    }

    return tuple;
}

pub fn record_fields(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) Error!*c.PyObject {
    comptime assert(@typeInfo(T) == .@"struct");
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return record_to(Binding, T, state, value) orelse error.Raised;
}

fn record_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const structure = @typeInfo(T).@"struct";

    comptime assert(!structure.is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const dictionary = c.PyDict_New() orelse return null;

    inline for (structure.field_names, structure.field_types) |name, Field| {
        const element = to_python(Binding, Field, state, &@field(value, name)) catch {
            c.Py_DecRef(dictionary);

            return null;
        };

        defer c.Py_DecRef(element);

        if (c.PyDict_SetItemString(dictionary, name, element) != 0) {
            c.Py_DecRef(dictionary);

            return null;
        }
    }

    return dictionary;
}

pub fn integer_wide_to(comptime T: type, number: *const T) ?*c.PyObject {
    const integer = @typeInfo(T).int;
    const chunk_count = comptime @divFloor(integer.bits + 63, 64);
    const Wide = @Int(integer.signedness, chunk_count * 64);
    const Unsigned = @Int(.unsigned, chunk_count * 64);

    comptime assert(integer.bits > 64);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const wide: Wide = number.*;
    const bits: Unsigned = @bitCast(wide);
    const top_shift = 64 * (chunk_count - 1);
    const shift = c.PyLong_FromLongLong(64) orelse return null;
    defer c.Py_DecRef(shift);

    var result = switch (integer.signedness) {
        .signed => c.PyLong_FromLongLong(@truncate(wide >> top_shift)),
        .unsigned => c.PyLong_FromUnsignedLongLong(@truncate(bits >> top_shift)),
    } orelse return null;

    for (0..chunk_count - 1) |step| {
        const chunk = chunk_count - 2 - step;
        const part: u64 = @truncate(bits >> @intCast(64 * chunk));
        const shifted = c.PyNumber_Lshift(result, shift);

        c.Py_DecRef(result);

        const moved = shifted orelse return null;

        const low = c.PyLong_FromUnsignedLongLong(part) orelse {
            c.Py_DecRef(moved);

            return null;
        };

        const joined = c.PyNumber_Or(moved, low);

        c.Py_DecRef(moved);
        c.Py_DecRef(low);
        result = joined orelse return null;
    }

    return result;
}

fn call_with(class: *c.PyObject, items: anytype) ?*c.PyObject {
    comptime assert(@typeInfo(@TypeOf(items)).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Items = @TypeOf(items);
    const count = @typeInfo(Items).@"struct".field_names.len;
    const tuple = c.PyTuple_New(count) orelse return null;
    defer c.Py_DecRef(tuple);

    inline for (@typeInfo(Items).@"struct".field_names, 0..) |name, index| {
        const Item = @FieldType(Items, name);

        const element: ?*c.PyObject = if (Item == *c.PyObject)
            python.reference_new(@field(items, name))
        else
            c.PyLong_FromLongLong(@field(items, name));

        const status = c.PyTuple_SetItem(tuple, index, element orelse return null);

        assert(status == 0);
    }

    return c.PyObject_CallObject(class, tuple);
}

fn date_to(
    comptime Binding: type,
    state: *const Binding.State,
    date: *const calendar.Date,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(date) % @alignOf(calendar.Date) == 0);

    const class = state.library_get(.date) catch return null;
    return call_with(class, .{ date.year, date.month, date.day });
}

fn time_to(
    comptime Binding: type,
    state: *const Binding.State,
    time: *const calendar.Time,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(time) % @alignOf(calendar.Time) == 0);

    const class = state.library_get(.time) catch return null;
    return call_with(class, .{ time.hour, time.minute, time.second, time.microsecond });
}

fn datetime_to(
    comptime Binding: type,
    state: *const Binding.State,
    moment: *const calendar.DateTime,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(moment) % @alignOf(calendar.DateTime) == 0);

    const class = state.library_get(.datetime) catch return null;
    const date = moment.date;
    const time = moment.time;

    if (moment.zone_name) |*zone_name| return datetime_zoned_to(Binding, state, moment, zone_name);

    const offset_seconds = moment.offset_seconds orelse return call_with(class, .{
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
        time.second,
        time.microsecond,
    });

    const delta_class = state.library_get(.timedelta) catch return null;
    const zone_class = state.library_get(.timezone) catch return null;
    const delta = call_with(delta_class, .{ 0, offset_seconds }) orelse return null;
    defer c.Py_DecRef(delta);

    const zone = call_with(zone_class, .{delta}) orelse return null;
    defer c.Py_DecRef(zone);

    return call_with(class, .{
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
        time.second,
        time.microsecond,
        zone,
    });
}

fn fraction_to(
    comptime Binding: type,
    state: *const Binding.State,
    fraction: *const value_module.Fraction,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(fraction.denominator != 0);

    const class = state.library_get(.fraction) catch return null;
    const numerator = integer_wide_to(i256, &fraction.numerator) orelse return null;
    defer c.Py_DecRef(numerator);

    const denominator = integer_wide_to(i256, &fraction.denominator) orelse return null;
    defer c.Py_DecRef(denominator);

    return c.PyObject_CallFunction(class, "OO", numerator, denominator);
}

fn address_to(
    comptime Binding: type,
    state: *const Binding.State,
    address: *const value_module.IPAddress,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(address) % @alignOf(value_module.IPAddress) == 0);

    const item: @import("state.zig").Library.Item = switch (address.*) {
        .v4 => .address_v4,
        .v6 => .address_v6,
    };

    const class = state.library_get(item) catch return null;

    const packed_bytes: []const u8 = switch (address.*) {
        .v4 => |*bytes| bytes,
        .v6 => |*bytes| bytes,
    };

    const bytes = c.PyBytes_FromStringAndSize(packed_bytes.ptr, @intCast(packed_bytes.len)) orelse {
        return null;
    };

    defer c.Py_DecRef(bytes);

    return c.PyObject_CallFunction(class, "O", bytes);
}

fn datetime_zoned_to(
    comptime Binding: type,
    state: *const Binding.State,
    moment: *const calendar.DateTime,
    zone_name: *const calendar.DateTime.ZoneName,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(zone_name.length > 0);

    const class = state.library_get(.datetime) catch return null;
    const zone_class = state.library_get(.zone) catch return null;
    const key = c.PyUnicode_FromStringAndSize(&zone_name.bytes, @intCast(zone_name.length)) orelse {
        return null;
    };

    defer c.Py_DecRef(key);

    const zone = c.PyObject_CallFunction(zone_class, "O", key) orelse return null;
    defer c.Py_DecRef(zone);

    const date = moment.date;
    const time = moment.time;

    return call_with(class, .{
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
        time.second,
        time.microsecond,
        zone,
    });
}

fn duration_to(
    comptime Binding: type,
    state: *const Binding.State,
    duration: *const calendar.Duration,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(duration) % @alignOf(calendar.Duration) == 0);

    const class = state.library_get(.timedelta) catch return null;
    const parts = calendar.parts_of(duration);

    return call_with(class, .{ parts.days, parts.seconds, parts.microseconds });
}

fn path_to(
    comptime Binding: type,
    state: *const Binding.State,
    path: *const value_module.Path,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(path.bytes.len <= std.math.maxInt(c.Py_ssize_t));

    const class = state.library_get(.path) catch return null;
    const size: c.Py_ssize_t = @intCast(path.bytes.len);
    const text = c.PyUnicode_DecodeFSDefaultAndSize(path.bytes.ptr, size) orelse return null;
    defer c.Py_DecRef(text);

    return call_with(class, .{text});
}

fn set_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    set: *const T,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(set.slice().len <= T.capacity_max);

    const result = c.PySet_New(null) orelse return null;

    for (set.slice()) |*item| {
        const element = to_python(Binding, T.Item, state, item) catch {
            c.Py_DecRef(result);

            return null;
        };

        defer c.Py_DecRef(element);

        if (c.PySet_Add(result, element) != 0) {
            c.Py_DecRef(result);

            return null;
        }
    }

    if (!T.frozen) return result;

    defer c.Py_DecRef(result);

    return c.PyFrozenSet_New(result);
}

fn map_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    map: *const T,
) ?*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(map.slice().len <= T.capacity_max);

    const result = c.PyDict_New() orelse return null;

    for (map.slice()) |*entry| {
        const status = entry_set(Binding, T, state, result, entry);

        if (status != 0) {
            c.Py_DecRef(result);

            return null;
        }
    }

    return result;
}

fn entry_set(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    dictionary: *c.PyObject,
    entry: *const T.Entry,
) c_int {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(dictionary) % @alignOf(*c.PyObject) == 0);

    const key = to_python(Binding, T.Key, state, &entry.key) catch return -1;
    defer c.Py_DecRef(key);

    const item = to_python(Binding, T.Value, state, &entry.value) catch return -1;
    defer c.Py_DecRef(item);

    return c.PyDict_SetItem(dictionary, key, item);
}

fn union_class_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    value: *const T,
) ?*c.PyObject {
    const index = comptime kind_module.class_index(T, Binding.unions).?;
    const first = comptime variant_module.slot_first(Binding.unions, index);
    const Variant = variant_module.VariantType(Binding, T);

    comptime assert(index < Binding.unions.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    inline for (@typeInfo(T).@"union".field_names, 0..) |tag, tag_index| {
        if (std.meta.activeTag(value.*) == @field(std.meta.Tag(T), tag)) {
            return Variant.allocate(state.variant_get(first + 1 + tag_index), value);
        }
    }

    unreachable;
}

fn variant_to(
    comptime Binding: type,
    comptime T: type,
    state: *const Binding.State,
    variant: *const T,
) ?*c.PyObject {
    comptime assert(@typeInfo(T).@"union".tag_type != null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    switch (variant.*) {
        inline else => |*payload| {
            const Payload = @TypeOf(payload.*);
            if (Payload == void) return python.reference_new(state.builtins.get(.none));
            return to_python(Binding, Payload, state, payload) catch null;
        },
    }
}
