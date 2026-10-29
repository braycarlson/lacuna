const std = @import("std");

const c = @import("c.zig");
const buffer_module = @import("buffer.zig");
const calendar = @import("calendar.zig");
const instance = @import("instance.zig");
const kind_module = @import("kind.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const state_module = @import("state.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

const Builtins = state_module.Builtins;
const Scope = scope_module.Scope;
const kind_of = kind_module.kind_of;

pub const Error = error{Raised};

pub fn from_python(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return switch (comptime kind_of(T, Binding.declared)) {
        .array => array_from(Binding, T, label, state, object, scope),
        .boolean => boolean_from(label, &state.builtins, object),
        .buffer, .buffer_mutable => buffer_from(T, label, &state.builtins, object, scope),
        .buffer_strided => strided_from(T, label, &state.builtins, object, scope),
        .bytes => octets_from(object, scope),
        .bytes_owned => octets_owned_from(T, label, &state.builtins, object, scope),
        .class_pointer, .class_pointer_mutable => class_pointer_from(
            Binding,
            T,
            label,
            state,
            object,
            scope,
        ),
        .class_extended => @compileError("lacuna: lacuna.Extended is a result, not an argument"),
        .class_value => if (comptime instance.InstanceType(T).referencing)
            @compileError("lacuna: the class '" ++ class_name(T) ++
                "' owns Python references, so it is passed by pointer, not copied")
        else
            (try class_pointer_from(Binding, *const T, label, state, object, scope)).*,
        .complex => complex_from(T, label, &state.builtins, object),
        .container => container_from(T, label, &state.builtins, object),
        .date => date_from(Binding, label, state, object),
        .datetime => datetime_from(Binding, label, state, object),
        .decimal => decimal_from(Binding, label, state, object),
        .duration => duration_from(Binding, label, state, object),
        .enumeration => enumeration_from(Binding, T, label, state, object),
        .float => float_from(T, object),
        .fraction => fraction_from(Binding, label, state, object),
        .ip_address => address_from(Binding, label, state, object),
        .integer => if (@typeInfo(T).int.bits <= 64)
            integer_from(T, label, &state.builtins, object)
        else
            integer_wide_from(T, label, &state.builtins, object),
        .list => list_from(Binding, T, label, state, object, scope),
        .map => map_from(Binding, T, label, state, object, scope),
        .none => @compileError("lacuna: void is not an argument type"),
        .object => .{ .pointer = object },
        .optional => optional_from(Binding, T, label, state, object, scope),
        .path => path_from(label, &state.builtins, object, scope),
        .record => record_from(Binding, T, label, state, object, scope),
        .reference => @compileError("lacuna: take an lacuna.Object argument and acquire " ++
            "an lacuna.Reference from it, so the function decides what it keeps"),
        .set => set_from(Binding, T, label, state, object, scope),
        .slice => slice_from(label, &state.builtins, object),
        .text => text_from(label, &state.builtins, object),
        .text_owned => text_owned_from(T, label, &state.builtins, object),
        .text_terminated => text_terminated_from(label, &state.builtins, object),
        .time => time_from(Binding, label, state, object),
        .tuple => tuple_from(Binding, T, label, state, object, scope),
        .union_class => union_class_from(Binding, T, label, state, object),
        .uuid => uuid_from(Binding, label, state, object),
        .variant => variant_from(Binding, T, label, state, object, scope),
    };
}

pub fn mismatch(
    builtins: *const Builtins,
    comptime message: [:0]const u8,
    object: *c.PyObject,
) Error {
    comptime assert(std.mem.find(u8, message, " must be ") != null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = python.class_of(object);
    defer c.Py_DecRef(class);

    const format = message ++ ", not %R";

    _ = c.PyErr_Format(builtins.get(.type_error), format, class);

    return error.Raised;
}

fn container_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(value.container_is(T));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (python.type_borrowed(object) != builtins.get(T.builtin_exact)) {
        const name = @import("exception.zig").builtin_names[@backingInt(T.builtin_exact)];

        return mismatch(builtins, label ++ " must be " ++ name, object);
    }

    return .{ .reference = .{ .pointer = object }, .owned = false };
}

fn slice_from(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!value.Slice {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (python.type_borrowed(object) != builtins.get(.slice)) {
        return mismatch(builtins, label ++ " must be slice", object);
    }

    var start: c.Py_ssize_t = 0;
    var stop: c.Py_ssize_t = 0;
    var step: c.Py_ssize_t = 0;

    if (c.PySlice_Unpack(object, &start, &stop, &step) != 0) return error.Raised;

    assert(step != 0);

    return .{ .start = start, .stop = stop, .step = step };
}

fn fraction_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!value.Fraction {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const fraction_class = try state.library_get(.fraction);
    const fraction = c.PyObject_IsInstance(object, fraction_class);
    if (fraction < 0) return error.Raised;

    if (fraction == 0) {
        const integer = python.has_flag(object, c.Py_TPFLAGS_LONG_SUBCLASS);
        const true_class = python.type_borrowed(state.builtins.get(.true));
        const boolean = python.type_borrowed(object) == true_class;
        const expected = label ++ " must be fractions.Fraction";

        if (!integer) return mismatch(&state.builtins, expected, object);
        if (boolean) return mismatch(&state.builtins, expected, object);
    }

    const numerator_object = c.PyObject_GetAttrString(object, "numerator") orelse {
        return error.Raised;
    };

    defer c.Py_DecRef(numerator_object);

    const denominator_object = c.PyObject_GetAttrString(object, "denominator") orelse {
        return error.Raised;
    };

    defer c.Py_DecRef(denominator_object);

    const numerator = try integer_wide_from(i256, label, &state.builtins, numerator_object);
    const denominator = try integer_wide_from(i256, label, &state.builtins, denominator_object);

    assert(denominator > 0);

    return .{ .numerator = numerator, .denominator = denominator };
}

fn address_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!value.IPAddress {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const version_four = c.PyObject_IsInstance(object, try state.library_get(.address_v4));
    if (version_four < 0) return error.Raised;

    const version_six = c.PyObject_IsInstance(object, try state.library_get(.address_v6));
    if (version_six < 0) return error.Raised;

    if (version_four == 0) {
        if (version_six == 0) {
            const expected = label ++ " must be ipaddress.IPv4Address or ipaddress.IPv6Address";

            return mismatch(&state.builtins, expected, object);
        }
    }

    const packed_object = c.PyObject_GetAttrString(object, "packed") orelse return error.Raised;
    defer c.Py_DecRef(packed_object);

    if (!python.has_flag(packed_object, c.Py_TPFLAGS_BYTES_SUBCLASS)) {
        return mismatch(&state.builtins, label ++ " packed form must be bytes", packed_object);
    }

    const bytes = python.octets_of(packed_object) orelse return error.Raised;

    if (version_four == 1) {
        if (bytes.len != 4) return mismatch(&state.builtins, label ++ " must be 4 bytes", object);

        return .{ .v4 = bytes[0..4].* };
    }

    if (bytes.len != 16) return mismatch(&state.builtins, label ++ " must be 16 bytes", object);

    return .{ .v6 = bytes[0..16].* };
}

fn boolean_from(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!bool {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (object == builtins.get(.true)) return true;
    if (object == builtins.get(.false)) return false;
    return mismatch(builtins, label ++ " must be bool", object);
}

fn integer_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const index = c.PyNumber_Index(object) orelse return error.Raised;
    defer c.Py_DecRef(index);

    const signed = switch (@typeInfo(T)) {
        .int => |int| int.signedness == .signed,
        else => @compileError("lacuna: '" ++ @typeName(T) ++ "' is not an argument type"),
    };

    if (signed) {
        const wide = c.PyLong_AsLongLong(index);

        if (wide == -1) {
            if (c.PyErr_Occurred() != null) return overflow(T, label, builtins);
        }

        return std.math.cast(T, wide) orelse overflow(T, label, builtins);
    } else {
        const wide = c.PyLong_AsUnsignedLongLong(index);

        if (c.PyErr_Occurred() != null) return overflow(T, label, builtins);
        return std.math.cast(T, wide) orelse overflow(T, label, builtins);
    }
}

fn overflow(comptime T: type, comptime label: [:0]const u8, builtins: *const Builtins) Error {
    comptime assert(label.len > 0);
    comptime assert(@typeInfo(T) == .int);

    const minimum = std.math.minInt(T);
    const maximum = std.math.maxInt(T);

    const message = std.fmt.comptimePrint("{s} must be in the range [{d}, {d}]", .{
        label,
        minimum,
        maximum,
    });

    c.PyErr_Clear();
    c.PyErr_SetString(builtins.get(.overflow_error), message);

    return error.Raised;
}

fn float_from(comptime T: type, object: *c.PyObject) Error!T {
    comptime assert(@typeInfo(T) == .float);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const wide = c.PyFloat_AsDouble(object);

    if (wide == -1.0) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    const result: T = @floatCast(wide);
    return result;
}

fn text_from(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error![]const u8 {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (!python.has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
        return mismatch(builtins, label ++ " must be str", object);
    }

    const text = python.text_of(object) orelse return error.Raised;
    return text;
}

fn text_terminated_from(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error![:0]const u8 {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (!python.has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
        return mismatch(builtins, label ++ " must be str", object);
    }

    const text = python.text_of(object) orelse return error.Raised;

    if (std.mem.findScalar(u8, text, 0) != null) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " holds an embedded null character");

        return error.Raised;
    }

    return text;
}

fn complex_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(@hasField(T, "re"));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Part = @FieldType(T, "re");
    const complex_class = builtins.get(.complex);
    const exact = c.PyObject_IsInstance(object, complex_class);

    if (exact < 0) return error.Raised;

    if (exact == 1) return complex_parts(T, object);

    if (python.has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
        return mismatch(builtins, label ++ " must be complex", object);
    }

    const converted = c.PyObject_GetAttrString(object, "__complex__") orelse {
        c.PyErr_Clear();

        const real = c.PyFloat_AsDouble(object);

        if (real == -1.0) {
            if (c.PyErr_Occurred() != null) {
                if (c.PyErr_ExceptionMatches(builtins.get(.type_error)) == 0) return error.Raised;

                c.PyErr_Clear();

                return mismatch(builtins, label ++ " must be complex", object);
            }
        }

        return .{ .re = @floatCast(real), .im = @as(Part, 0) };
    };

    c.Py_DecRef(converted);

    const promoted = c.PyObject_CallFunction(complex_class, "O", object) orelse return error.Raised;
    defer c.Py_DecRef(promoted);

    return complex_parts(T, promoted);
}

fn complex_parts(comptime T: type, object: *c.PyObject) Error!T {
    comptime assert(@hasField(T, "im"));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const real = c.PyComplex_RealAsDouble(object);

    if (real == -1.0) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    const imaginary = c.PyComplex_ImagAsDouble(object);

    if (imaginary == -1.0) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    return .{ .re = @floatCast(real), .im = @floatCast(imaginary) };
}

fn decimal_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!value.Decimal {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = try state.library_get(.decimal);
    const decimal = c.PyObject_IsInstance(object, class);

    if (decimal < 0) return error.Raised;

    if (decimal == 0) {
        if (!python.has_flag(object, c.Py_TPFLAGS_LONG_SUBCLASS)) {
            return mismatch(&state.builtins, label ++ " must be decimal.Decimal or int", object);
        }

        if (object == state.builtins.get(.true)) {
            return mismatch(&state.builtins, label ++ " must be decimal.Decimal or int", object);
        }

        if (object == state.builtins.get(.false)) {
            return mismatch(&state.builtins, label ++ " must be decimal.Decimal or int", object);
        }

        const whole = try integer_wide_from(i128, label, &state.builtins, object);
        return .{ .coefficient = whole, .exponent = 0 };
    }

    const parts = c.PyObject_CallMethod(object, "as_tuple", null) orelse return error.Raised;
    defer c.Py_DecRef(parts);

    return decimal_parts(label, &state.builtins, parts);
}

fn decimal_parts(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    parts: *c.PyObject,
) Error!value.Decimal {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const shape = label ++ ".as_tuple() must be (sign, digits, exponent)";

    const tuple = python.has_flag(parts, c.Py_TPFLAGS_TUPLE_SUBCLASS);

    if (!tuple) return mismatch(builtins, shape, parts);
    if (c.PyTuple_Size(parts) != 3) return mismatch(builtins, shape, parts);

    const digits = c.PyTuple_GetItem(parts, 1).?;
    const exponent_object = c.PyTuple_GetItem(parts, 2).?;

    const digits_tuple = python.has_flag(digits, c.Py_TPFLAGS_TUPLE_SUBCLASS);

    if (!digits_tuple) return mismatch(builtins, shape, parts);

    if (!python.has_flag(exponent_object, c.Py_TPFLAGS_LONG_SUBCLASS)) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " must be finite");

        return error.Raised;
    }

    const negative = try decimal_sign(label, builtins, c.PyTuple_GetItem(parts, 0).?);
    const exponent_wide = c.PyLong_AsLongLong(exponent_object);

    if (exponent_wide == -1) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    const exponent = std.math.cast(i32, exponent_wide) orelse {
        return decimal_overflow(label, builtins);
    };

    const count = c.PyTuple_Size(digits);

    if (count > decimal_digit_count_max) return decimal_overflow(label, builtins);

    var coefficient: i128 = 0;

    for (0..@intCast(count)) |index| {
        const digit = c.PyLong_AsLongLong(c.PyTuple_GetItem(digits, @intCast(index)).?);

        if (c.PyErr_Occurred() != null) return error.Raised;
        const digit_message = label ++ " digits must be 0-9";

        if (digit < 0) return mismatch(builtins, digit_message, digits);
        if (digit > 9) return mismatch(builtins, digit_message, digits);

        const shifted = std.math.mul(i128, coefficient, 10) catch {
            return decimal_overflow(label, builtins);
        };

        coefficient = std.math.add(i128, shifted, digit) catch {
            return decimal_overflow(label, builtins);
        };
    }

    assert(coefficient >= 0);

    return .{ .coefficient = if (negative) -coefficient else coefficient, .exponent = exponent };
}

fn decimal_sign(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    sign: *c.PyObject,
) Error!bool {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const number = c.PyLong_AsLongLong(sign);

    if (c.PyErr_Occurred() != null) return error.Raised;
    if (number == 0) return false;
    if (number == 1) return true;
    return mismatch(builtins, label ++ " sign must be 0 or 1", sign);
}

const decimal_digit_count_max: u32 = 39;

fn decimal_overflow(comptime label: [:0]const u8, builtins: *const Builtins) Error {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const message = label ++ " does not fit a 128-bit coefficient and a 32-bit exponent";

    c.PyErr_SetString(builtins.get(.overflow_error), message);

    return error.Raised;
}

fn uuid_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!value.UUID {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = try state.library_get(.uuid);
    const identifier = c.PyObject_IsInstance(object, class);

    if (identifier < 0) return error.Raised;
    if (identifier == 0) return mismatch(&state.builtins, label ++ " must be uuid.UUID", object);

    const bytes = c.PyObject_GetAttrString(object, "bytes") orelse return error.Raised;
    defer c.Py_DecRef(bytes);

    if (!python.has_flag(bytes, c.Py_TPFLAGS_BYTES_SUBCLASS)) {
        return mismatch(&state.builtins, label ++ " bytes must be bytes", bytes);
    }

    const octets = python.octets_of(bytes) orelse return error.Raised;

    if (octets.len != 16) {
        c.PyErr_SetString(state.builtins.get(.value_error), label ++ " must hold 16 bytes");

        return error.Raised;
    }

    var result: value.UUID = undefined;

    @memcpy(&result.bytes, octets);

    return result;
}

fn enumeration_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(@typeInfo(T) == .@"enum");
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const index = comptime kind_module.enum_index(T, Binding.enums);
    const class = state.enum_get(index);
    const member = c.PyObject_IsInstance(object, class);

    if (member < 0) return error.Raised;
    if (member == 0) {
        return mismatch(&state.builtins, label ++ " must be " ++ class_name(T), object);
    }

    const number_object = c.PyObject_GetAttrString(object, "value") orelse return error.Raised;
    defer c.Py_DecRef(number_object);

    const number = c.PyLong_AsLongLong(number_object);

    if (number == -1) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    inline for (@typeInfo(T).@"enum".field_names) |name| {
        if (number == @backingInt(@field(T, name))) return @field(T, name);
    }

    c.PyErr_SetString(state.builtins.get(.value_error), label ++ " holds an unknown member");

    return error.Raised;
}

pub fn choices(comptime T: type) [:0]const u8 {
    comptime assert(@typeInfo(T) == .@"enum");
    comptime assert(@typeInfo(T).@"enum".field_names.len > 0);

    return comptime result: {
        var text: [:0]const u8 = "";

        for (@typeInfo(T).@"enum".field_names, 0..) |name, index| {
            const separator = if (index == 0) "" else ", ";

            text = text ++ separator ++ "'" ++ name ++ "'";
        }

        break :result text;
    };
}

fn octets_from(object: *c.PyObject, scope: *Scope) Error!value.Bytes {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(scope.view_count < scope.views.len);

    const view = scope.view_next();
    if (c.PyObject_GetBuffer(object, view, c.PyBUF_SIMPLE) != 0) return error.Raised;

    scope.view_commit();

    assert(view.len >= 0);

    return .{ .bytes = python.view_bytes(view) };
}

fn octets_owned_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(T.blob_capacity_max > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const borrowed = try octets_from(object, scope);

    if (borrowed.bytes.len > T.blob_capacity_max) {
        const message = std.fmt.comptimePrint("{s} must hold at most {d} bytes", .{
            label,
            T.blob_capacity_max,
        });

        c.PyErr_SetString(builtins.get(.value_error), message);

        return error.Raised;
    }

    var result: T = .empty;

    @memcpy(result.bytes[0..borrowed.bytes.len], borrowed.bytes);
    result.length = @intCast(borrowed.bytes.len);

    assert(std.mem.eql(u8, result.slice(), borrowed.bytes));

    return result;
}

fn buffer_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const pointer = @typeInfo(T).pointer;
    const Element = pointer.child;
    const writable = !pointer.attrs.@"const";
    const flags = c.PyBUF_FORMAT | c.PyBUF_C_CONTIGUOUS | if (writable) c.PyBUF_WRITABLE else 0;

    comptime assert(kind_module.buffer_element(Element));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const view = scope.view_next();
    if (c.PyObject_GetBuffer(object, view, flags) != 0) return error.Raised;

    scope.view_commit();

    if (view.ndim != 1) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " must be one-dimensional");

        return error.Raised;
    }

    const expected = label ++ " must be a buffer of " ++ @typeName(Element) ++ " items";
    if (view.itemsize != @sizeOf(Element)) return mismatch(builtins, expected, object);

    const format = python.format_of(view);
    if (!format_matches(Element, format)) return mismatch(builtins, expected, object);

    if (@mod(view.len, view.itemsize) != 0) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " has a partial item");

        return error.Raised;
    }

    return python.items_of(Element, view) orelse {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " is not aligned for its items");

        return error.Raised;
    };
}

fn strided_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(kind_module.buffer_element(T.Element));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Element = T.Element;
    const flags = c.PyBUF_FORMAT | c.PyBUF_STRIDES | if (T.writable) c.PyBUF_WRITABLE else 0;
    const view = scope.view_next();
    if (c.PyObject_GetBuffer(object, view, flags) != 0) return error.Raised;

    scope.view_commit();

    if (view.ndim > buffer_module.dimensions_max) {
        const message = label ++ " has more dimensions than lacuna.limits.buffer_dimensions_max";

        c.PyErr_SetString(builtins.get(.buffer_error), message);

        return error.Raised;
    }

    const expected = label ++ " must be a buffer of " ++ @typeName(Element) ++ " items";
    if (view.itemsize != @sizeOf(Element)) return mismatch(builtins, expected, object);
    const format = python.format_of(view);
    if (!format_matches(Element, format)) return mismatch(builtins, expected, object);

    const address = @intFromPtr(view.buf);

    if (view.len == 0) return strided_of(T, view);

    if (address % @alignOf(Element) != 0) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " is not aligned for its items");

        return error.Raised;
    }

    return strided_of(T, view);
}

fn strided_of(comptime T: type, view: *const c.Py_buffer) T {
    assert(view.ndim >= 0);
    assert(view.ndim <= buffer_module.dimensions_max);

    const Element = T.Element;
    const Empty = struct {
        var items: [1]Element = .{0};
    };

    const count: u8 = @intCast(view.ndim);

    var result: T = .{
        .data = if (view.len == 0) &Empty.items else @ptrCast(@alignCast(view.buf.?)),
        .dimension_count = count,
        .shape = @splat(0),
        .strides = @splat(0),
        .read_only = view.readonly != 0,
    };

    var stride: i64 = @sizeOf(Element);
    var position: u8 = count;

    for (0..count) |_| {
        position -= 1;

        result.shape[position] = @intCast(view.shape.?[position]);
        result.strides[position] = if (view.strides) |strides| strides[position] else stride;
        stride *= @intCast(result.shape[position]);
    }

    assert(position == 0);

    return result;
}

pub fn format_matches(comptime Element: type, text: []const u8) bool {
    comptime assert(kind_module.buffer_element(Element));
    comptime assert(@sizeOf(Element) <= 8);
    assert(text.len <= 1 << 16);
    var code = text;

    if (code.len == 2) {
        if (prefix_native(code[0])) code = code[1..];
    }

    if (code.len != 1) return false;

    const codes = switch (@typeInfo(Element)) {
        .float => "efd",
        .int => |int| if (int.signedness == .signed) "bhilqn" else "BHILQNc",
        else => unreachable,
    };

    return std.mem.findScalar(u8, codes, code[0]) != null;
}

fn prefix_native(prefix: u8) bool {
    assert(prefix <= std.math.maxInt(u8));

    const native: u8 = if (@import("builtin").target.cpu.arch.endian() == .little) '<' else '>';

    assert(native != '@');

    return switch (prefix) {
        '@', '=' => true,
        else => prefix == native,
    };
}

fn class_pointer_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const Class = @typeInfo(T).pointer.child;
    const index = comptime kind_module.class_index(Class, Binding.classes).?;

    comptime assert(index < Binding.classes.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const Instance = instance.InstanceType(Class);
    const class = python.type_borrowed(object);

    if (Instance.defining_of(class) != state.class_get(index)) {
        return mismatch(&state.builtins, label ++ " must be " ++ class_name(Class), object);
    }

    const data = Instance.data_required(object) orelse return error.Raised;

    scope.lock(object);

    return data;
}

pub fn class_name(comptime Class: type) [:0]const u8 {
    comptime assert(@typeName(Class).len > 0);

    if (@hasDecl(Class, "python_name")) return Class.python_name;

    return comptime result: {
        const full = @typeName(Class);
        const start = if (std.mem.findScalarLast(u8, full, '.')) |dot| dot + 1 else 0;

        assert(start < full.len);

        break :result full[start..];
    };
}

fn optional_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const Child = @typeInfo(T).optional.child;

    comptime assert(@typeInfo(Child) != .optional);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (object == state.builtins.get(.none)) return null;

    const result: T = try from_python(Binding, Child, label, state, object, scope);
    return result;
}

const Bound = struct {
    count: u32,
    relation: []const u8,
};

fn sequence_of(
    comptime label: [:0]const u8,
    comptime bound: Bound,
    builtins: *const Builtins,
    object: *c.PyObject,
    scope: *Scope,
) Error!*c.PyObject {
    comptime assert(label.len > 0);
    comptime assert(bound.count <= std.math.maxInt(u32) - 1);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const concrete = python.has_flag(object, c.Py_TPFLAGS_LIST_SUBCLASS) or
        python.has_flag(object, c.Py_TPFLAGS_TUPLE_SUBCLASS);

    if (!concrete) {
        if (python.has_flag(object, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
            return mismatch(builtins, label ++ " must be a sequence", object);
        }

        if (c.PySequence_Check(object) == 0) {
            return mismatch(builtins, label ++ " must be a sequence", object);
        }
    }

    const size = c.PyObject_Size(object);

    if (size < 0) {
        if (c.PyErr_ExceptionMatches(builtins.get(.type_error)) == 0) return error.Raised;

        c.PyErr_Clear();
    } else if (size > bound.count) {
        return count_mismatch(label, bound.relation, bound.count, builtins);
    } else {
        const snapshot = c.PySequence_Tuple(object) orelse return error.Raised;

        scope.hold(snapshot);

        return snapshot;
    }

    const collected = try items_bounded(label, bound, builtins, object);

    scope.hold(collected);

    const snapshot = c.PySequence_Tuple(collected) orelse return error.Raised;

    scope.hold(snapshot);

    return snapshot;
}

fn items_bounded(
    comptime label: [:0]const u8,
    comptime bound: Bound,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!*c.PyObject {
    comptime assert(label.len > 0);
    comptime assert(bound.relation.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const iterator = c.PyObject_GetIter(object) orelse return error.Raised;
    defer c.Py_DecRef(iterator);

    const result = c.PyList_New(0) orelse return error.Raised;
    errdefer c.Py_DecRef(result);

    for (0..bound.count + 1) |_| {
        const element = c.PyIter_Next(iterator) orelse {
            if (c.PyErr_Occurred() != null) return error.Raised;
            return result;
        };

        defer c.Py_DecRef(element);

        if (c.PyList_Append(result, element) != 0) return error.Raised;
    }

    return count_mismatch(label, bound.relation, bound.count, builtins);
}

fn count_mismatch(
    comptime label: [:0]const u8,
    comptime relation: []const u8,
    comptime count: u32,
    builtins: *const Builtins,
) Error {
    comptime assert(label.len > 0);
    comptime assert(relation.len > 0);
    comptime assert(count > 0);

    const message = std.fmt.comptimePrint(
        "{s} must hold {s} {d} items",
        .{ label, relation, count },
    );

    c.PyErr_SetString(builtins.get(.value_error), message);

    return error.Raised;
}

fn array_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const array = @typeInfo(T).array;

    comptime assert(array.len <= std.math.maxInt(u32));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const bound: Bound = .{ .count = array.len, .relation = "exactly" };
    const tuple = try sequence_of(label, bound, &state.builtins, object, scope);

    if (c.PyTuple_Size(tuple) != array.len) {
        return count_mismatch(label, "exactly", array.len, &state.builtins);
    }

    var result: T = undefined;

    for (&result, 0..) |*item, index| {
        const element = c.PyTuple_GetItem(tuple, @intCast(index)).?;

        item.* = try from_python(Binding, array.child, label ++ " item", state, element, scope);
    }

    return result;
}

fn list_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(T.capacity_max > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const bound: Bound = .{ .count = T.capacity_max, .relation = "at most" };
    const tuple = try sequence_of(label, bound, &state.builtins, object, scope);
    const size = c.PyTuple_Size(tuple);

    if (size > T.capacity_max) {
        return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
    }

    var result: T = .empty;

    for (0..@intCast(size)) |index| {
        const element = c.PyTuple_GetItem(tuple, @intCast(index)).?;
        const item_label = label ++ " item";

        result.items[index] = try from_python(Binding, T.Item, item_label, state, element, scope);
        result.count += 1;
    }

    assert(result.count == size);

    return result;
}

fn tuple_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const structure = @typeInfo(T).@"struct";

    comptime assert(structure.is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const fields = structure.field_names.len;
    const bound: Bound = .{ .count = fields, .relation = "exactly" };
    const tuple = try sequence_of(label, bound, &state.builtins, object, scope);

    if (c.PyTuple_Size(tuple) != structure.field_names.len) {
        return count_mismatch(label, "exactly", structure.field_names.len, &state.builtins);
    }

    var result: T = undefined;

    inline for (structure.field_names, structure.field_types, 0..) |name, Field, index| {
        const element = c.PyTuple_GetItem(tuple, index).?;

        @field(
            result,
            name,
        ) = try from_python(Binding, Field, label ++ " item", state, element, scope);
    }

    return result;
}

pub fn record_restore(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(@typeInfo(T) == .@"struct");

    return record_from(Binding, T, label, state, object, scope);
}

fn record_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    const structure = @typeInfo(T).@"struct";

    comptime assert(!structure.is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (!python.has_flag(object, c.Py_TPFLAGS_DICT_SUBCLASS)) {
        return mismatch(&state.builtins, label ++ " must be dict", object);
    }

    if (c.PyDict_Size(object) > structure.field_names.len) {
        try record_unknown(T, label, &state.builtins, object);
    }

    var result: T = undefined;

    inline for (structure.field_names, structure.field_attrs) |name, attributes| {
        const Field = @FieldType(T, name);
        const key_label = label ++ " key '" ++ name ++ "'";

        switch (try record_item(name, object, scope)) {
            .present => |element| {
                const field = try from_python(Binding, Field, key_label, state, element, scope);

                @field(result, name) = field;
            },
            .absent => {
                const default = attributes.defaultValue(Field) orelse {
                    c.PyErr_SetString(state.builtins.get(.key_error), key_label ++ " is missing");

                    return error.Raised;
                };

                @field(result, name) = default;
            },
        }
    }

    try record_unknown(T, label, &state.builtins, object);

    return result;
}

const Lookup = union(enum) {
    absent,
    present: *c.PyObject,
};

fn record_item(comptime name: [:0]const u8, object: *c.PyObject, scope: *Scope) Error!Lookup {
    comptime assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(scope.object_count < scope.objects.len);

    const key = c.PyUnicode_FromStringAndSize(name.ptr, name.len) orelse return error.Raised;
    defer c.Py_DecRef(key);

    const item = c.PyDict_GetItemWithError(object, key) orelse {
        if (c.PyErr_Occurred() != null) return error.Raised;
        return .absent;
    };

    scope.hold(python.reference_new(item));

    return .{ .present = item };
}

fn record_unknown(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!void {
    comptime assert(label.len > 0);
    const names = @typeInfo(T).@"struct".field_names;

    comptime assert(names.len <= std.math.maxInt(u32));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    var position: c.Py_ssize_t = 0;
    var key: ?*c.PyObject = null;
    var item: ?*c.PyObject = null;
    var step: u32 = 0;

    while (c.PyDict_Next(object, &position, &key, &item) != 0) : (step += 1) {
        if (step == names.len) {
            const message = label ++ " repeats a key under different str objects";

            c.PyErr_SetString(builtins.get(.value_error), message);

            return error.Raised;
        }

        if (!python.has_flag(key.?, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
            return mismatch(builtins, label ++ " key must be str", key.?);
        }

        const text = python.text_of(key.?) orelse return error.Raised;

        const known = inline for (names) |name| {
            if (std.mem.eql(u8, text, name)) break true;
        } else false;

        if (!known) {
            _ = c.PyErr_Format(builtins.get(.key_error), label ++ " has no key %R", key.?);

            return error.Raised;
        }
    }
}

fn integer_wide_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    const integer = @typeInfo(T).int;
    const chunk_count = comptime @divFloor(integer.bits + 63, 64);
    const Unsigned = @Int(.unsigned, chunk_count * 64);
    const Signed = @Int(.signed, chunk_count * 64);

    comptime assert(integer.bits > 64);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const mask = c.PyLong_FromUnsignedLongLong(std.math.maxInt(u64)) orelse return error.Raised;
    defer c.Py_DecRef(mask);

    const shift = c.PyLong_FromLongLong(64) orelse return error.Raised;
    defer c.Py_DecRef(shift);

    var rest = c.PyNumber_Index(object) orelse return error.Raised;
    defer c.Py_DecRef(rest);

    var bits: Unsigned = 0;

    for (0..chunk_count) |chunk| {
        const low = c.PyNumber_And(rest, mask) orelse return error.Raised;
        const part = c.PyLong_AsUnsignedLongLong(low);

        c.Py_DecRef(low);

        if (c.PyErr_Occurred() != null) return error.Raised;

        bits |= @as(Unsigned, part) << @intCast(64 * chunk);

        const next = c.PyNumber_Rshift(rest, shift) orelse return error.Raised;

        c.Py_DecRef(rest);
        rest = next;
    }

    const sign = c.PyLong_AsLongLong(rest);

    if (c.PyErr_Occurred() != null) return overflow(T, label, builtins);

    if (integer.signedness == .signed) {
        const top_set = bits >> @intCast(chunk_count * 64 - 1) == 1;

        if (sign == 0) {
            if (top_set) return overflow(T, label, builtins);
        } else if (sign == -1) {
            if (!top_set) return overflow(T, label, builtins);
        } else {
            return overflow(T, label, builtins);
        }

        const wide: Signed = @bitCast(bits);
        return std.math.cast(T, wide) orelse overflow(T, label, builtins);
    }

    if (sign != 0) return overflow(T, label, builtins);
    return std.math.cast(T, bits) orelse overflow(T, label, builtins);
}

fn text_owned_from(
    comptime T: type,
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(T.capacity_max > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const text = try text_from(label, builtins, object);

    if (text.len > T.capacity_max) {
        const message = std.fmt.comptimePrint("{s} must hold at most {d} bytes of UTF-8", .{
            label,
            T.capacity_max,
        });

        c.PyErr_SetString(builtins.get(.value_error), message);

        return error.Raised;
    }

    var result: T = .empty;

    @memcpy(result.bytes[0..text.len], text);
    result.length = @intCast(text.len);

    assert(std.mem.eql(u8, result.slice(), text));

    return result;
}

fn path_from(
    comptime label: [:0]const u8,
    builtins: *const Builtins,
    object: *c.PyObject,
    scope: *Scope,
) Error!value.Path {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const spelled = c.PyOS_FSPath(object) orelse return error.Raised;

    scope.hold(spelled);

    const bytes = try path_bytes(spelled, scope);

    if (std.mem.findScalar(u8, bytes, 0) != null) {
        c.PyErr_SetString(builtins.get(.value_error), label ++ " holds an embedded null byte");

        return error.Raised;
    }

    return .{ .bytes = bytes };
}

fn path_bytes(spelled: *c.PyObject, scope: *Scope) Error![]const u8 {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(scope.object_count > 0);

    if (python.has_flag(spelled, c.Py_TPFLAGS_BYTES_SUBCLASS)) {
        return python.octets_of(spelled) orelse error.Raised;
    }

    if (@import("builtin").target.os.tag == .windows) {
        return python.text_of(spelled) orelse error.Raised;
    }

    const encoded = c.PyUnicode_EncodeFSDefault(spelled) orelse return error.Raised;

    scope.hold(encoded);

    return python.octets_of(encoded) orelse error.Raised;
}

const Attributed = struct {
    builtins: *const Builtins,
    object: *c.PyObject,
};

fn attribute_integer(field: Attributed, comptime T: type, comptime name: [:0]const u8) Error!T {
    assert(field.builtins.objects[0] != null);
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(T) == .int);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const item = c.PyObject_GetAttrString(field.object, name) orelse return error.Raised;
    defer c.Py_DecRef(item);

    const wide = c.PyLong_AsLongLong(item);

    if (wide == -1) {
        if (c.PyErr_Occurred() != null) return error.Raised;
    }

    return std.math.cast(T, wide) orelse {
        _ = c.PyErr_Format(
            field.builtins.get(.value_error),
            "the attribute '" ++ name ++ "' of %R is out of range",
            field.object,
        );

        return error.Raised;
    };
}

const Check = struct {
    expected: [:0]const u8,
    item: @import("state.zig").Library.Item,
    label: [:0]const u8,
};

fn instance_check(
    comptime Binding: type,
    comptime check: Check,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!void {
    comptime assert(check.label.len > 0);
    comptime assert(check.expected.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const class = try state.library_get(check.item);
    const status = c.PyObject_IsInstance(object, class);
    const message = check.label ++ " must be " ++ check.expected;

    if (status < 0) return error.Raised;
    if (status == 0) return mismatch(&state.builtins, message, object);
}

fn date_parts(field: Attributed) Error!calendar.Date {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(field.object) % @alignOf(*c.PyObject) == 0);

    return .{
        .year = try attribute_integer(field, u16, "year"),
        .month = try attribute_integer(field, u8, "month"),
        .day = try attribute_integer(field, u8, "day"),
    };
}

fn time_parts(field: Attributed) Error!calendar.Time {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(field.object) % @alignOf(*c.PyObject) == 0);

    return .{
        .hour = try attribute_integer(field, u8, "hour"),
        .minute = try attribute_integer(field, u8, "minute"),
        .second = try attribute_integer(field, u8, "second"),
        .microsecond = try attribute_integer(field, u32, "microsecond"),
    };
}

fn date_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!calendar.Date {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const check = comptime Check{
        .expected = "datetime.date",
        .item = .date,
        .label = label,
    };

    try instance_check(Binding, check, state, object);

    return date_parts(.{ .builtins = &state.builtins, .object = object });
}

fn time_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!calendar.Time {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const check = comptime Check{
        .expected = "datetime.time",
        .item = .time,
        .label = label,
    };

    try instance_check(Binding, check, state, object);

    const zone = c.PyObject_GetAttrString(object, "tzinfo") orelse return error.Raised;
    defer c.Py_DecRef(zone);

    if (zone != state.builtins.get(.none)) {
        c.PyErr_SetString(state.builtins.get(.value_error), label ++ " must be a naive time");

        return error.Raised;
    }

    return time_parts(.{ .builtins = &state.builtins, .object = object });
}

fn datetime_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!calendar.DateTime {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const check = comptime Check{
        .expected = "datetime.datetime",
        .item = .datetime,
        .label = label,
    };

    try instance_check(Binding, check, state, object);

    const method = c.PyObject_GetAttrString(object, "utcoffset") orelse return error.Raised;
    defer c.Py_DecRef(method);

    const offset = c.PyObject_CallObject(method, null) orelse return error.Raised;
    defer c.Py_DecRef(offset);

    const own: Attributed = .{ .builtins = &state.builtins, .object = object };

    const zone_name = try zone_name_of(Binding, label, state, object);

    var result: calendar.DateTime = .{
        .date = try date_parts(own),
        .time = try time_parts(own),
        .offset_seconds = null,
        .zone_name = if (zone_name.length > 0) zone_name else null,
    };

    if (offset == state.builtins.get(.none)) return result;

    const delta: Attributed = .{ .builtins = &state.builtins, .object = offset };
    const days = try attribute_integer(delta, i64, "days");
    const seconds = try attribute_integer(delta, i64, "seconds");
    const microseconds = try attribute_integer(delta, i64, "microseconds");

    if (microseconds != 0) {
        c.PyErr_SetString(
            state.builtins.get(.value_error),
            label ++ " must have a UTC offset of whole seconds",
        );

        return error.Raised;
    }

    const builtins = &state.builtins;

    const day_seconds = std.math.mul(i64, days, calendar.seconds_per_day) catch {
        return offset_invalid(label, builtins);
    };

    const total = std.math.add(i64, day_seconds, seconds) catch {
        return offset_invalid(label, builtins);
    };

    if (@abs(total) >= calendar.seconds_per_day) return offset_invalid(label, builtins);

    result.offset_seconds = @intCast(total);

    return result;
}

fn zone_name_of(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!calendar.DateTime.ZoneName {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    var result: calendar.DateTime.ZoneName = .empty;

    const zone = c.PyObject_GetAttrString(object, "tzinfo") orelse return error.Raised;
    defer c.Py_DecRef(zone);

    if (zone == state.builtins.get(.none)) return result;

    const zone_class = try state.library_get(.zone);
    const status = c.PyObject_IsInstance(zone, zone_class);

    if (status < 0) return error.Raised;
    if (status == 0) return result;

    const key = c.PyObject_GetAttrString(zone, "key") orelse return error.Raised;
    defer c.Py_DecRef(key);

    if (key == state.builtins.get(.none)) return result;
    if (!python.has_flag(key, c.Py_TPFLAGS_UNICODE_SUBCLASS)) return result;

    const text = python.text_of(key) orelse return error.Raised;
    const message = label ++ " has a zone key over 64 bytes";

    result.extend(text) catch {
        c.PyErr_SetString(state.builtins.get(.value_error), message);

        return error.Raised;
    };

    return result;
}

fn offset_invalid(comptime label: [:0]const u8, builtins: *const Builtins) Error {
    assert(builtins.objects[0] != null);
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    c.PyErr_SetString(
        builtins.get(.value_error),
        label ++ " must have a UTC offset under one day",
    );

    return error.Raised;
}

fn duration_from(
    comptime Binding: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!calendar.Duration {
    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const check = comptime Check{
        .expected = "datetime.timedelta",
        .item = .timedelta,
        .label = label,
    };

    try instance_check(Binding, check, state, object);

    const field: Attributed = .{ .builtins = &state.builtins, .object = object };
    const days = try attribute_integer(field, i64, "days");
    const seconds = try attribute_integer(field, i64, "seconds");
    const microseconds = try attribute_integer(field, i64, "microseconds");

    const parts: calendar.Parts = .{
        .days = days,
        .seconds = seconds,
        .microseconds = microseconds,
    };

    if (!parts.normalized()) {
        c.PyErr_SetString(state.builtins.get(.value_error), label ++ " is not normalized");

        return error.Raised;
    }

    return calendar.duration_of(parts) orelse {
        c.PyErr_SetString(
            state.builtins.get(.overflow_error),
            label ++ " must fit in 64 bits of microseconds",
        );

        return error.Raised;
    };
}

fn set_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(T.capacity_max > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const abstract = try state.library_get(.set);
    const member = c.PyObject_IsInstance(object, abstract);

    if (member < 0) return error.Raised;
    if (member == 0) return mismatch(&state.builtins, label ++ " must be a set", object);

    const size = c.PyObject_Size(object);
    if (size < 0) return error.Raised;

    if (size > T.capacity_max) {
        return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
    }

    const iterator = c.PyObject_GetIter(object) orelse return error.Raised;

    scope.hold(iterator);

    var result: T = .empty;

    for (0..T.capacity_max + 1) |position| {
        const element = c.PyIter_Next(iterator) orelse {
            if (c.PyErr_Occurred() != null) return error.Raised;

            break;
        };

        if (position == T.capacity_max) {
            c.Py_DecRef(element);

            return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
        }

        scope.hold(element);

        const item = try from_python(Binding, T.Item, label ++ " item", state, element, scope);

        result.include(item) catch {
            return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
        };
    }

    assert(result.slice().len <= T.capacity_max);

    return result;
}

fn map_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(T.capacity_max > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const dictionary = python.has_flag(object, c.Py_TPFLAGS_DICT_SUBCLASS);

    if (!dictionary) {
        const abstract = try state.library_get(.mapping);
        const mapping = c.PyObject_IsInstance(object, abstract);

        if (mapping < 0) return error.Raised;
        if (mapping == 0) return mismatch(&state.builtins, label ++ " must be a mapping", object);
    }

    const declared = c.PyObject_Size(object);

    if (declared < 0) return error.Raised;

    if (declared > T.capacity_max) {
        return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
    }

    const items = (if (dictionary) c.PyDict_Items(object) else c.PyMapping_Items(object)) orelse {
        return error.Raised;
    };

    scope.hold(items);

    const size = c.PyList_Size(items);

    if (size > T.capacity_max) {
        return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
    }

    var result: T = .empty;

    for (0..@intCast(size)) |index| {
        const pair = c.PyList_GetItem(items, @intCast(index)).?;

        if (!python.has_flag(pair, c.Py_TPFLAGS_TUPLE_SUBCLASS)) {
            return mismatch(&state.builtins, label ++ " items must be pairs", pair);
        }

        if (c.PyTuple_Size(pair) != 2) {
            return mismatch(&state.builtins, label ++ " items must be pairs", pair);
        }

        const key_object = c.PyTuple_GetItem(pair, 0).?;
        const value_object = c.PyTuple_GetItem(pair, 1).?;
        const key = try from_python(Binding, T.Key, label ++ " key", state, key_object, scope);
        const item_label = label ++ " value";
        const item = try from_python(Binding, T.Value, item_label, state, value_object, scope);

        result.assign(.{ .key = key, .value = item }) catch {
            return count_mismatch(label, "at most", T.capacity_max, &state.builtins);
        };
    }

    assert(result.slice().len <= @as(usize, @intCast(size)));

    return result;
}

fn union_class_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
) Error!T {
    const index = comptime kind_module.class_index(T, Binding.unions).?;
    const first = comptime @import("variant.zig").slot_first(Binding.unions, index);
    const Variant = @import("variant.zig").VariantType(Binding, T);
    const class = python.type_borrowed(object);

    comptime assert(label.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    inline for (0..Variant.count) |tag_index| {
        if (class == state.variant_get(first + 1 + tag_index)) {
            return Variant.storage_of(object).value;
        }
    }

    return mismatch(&state.builtins, label ++ " must be " ++ class_name(T), object);
}

fn variant_from(
    comptime Binding: type,
    comptime T: type,
    comptime label: [:0]const u8,
    state: *const Binding.State,
    object: *c.PyObject,
    scope: *Scope,
) Error!T {
    comptime assert(label.len > 0);
    comptime assert(@typeInfo(T).@"union".tag_type != null);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    inline for (@typeInfo(T).@"union".field_names) |name| {
        const Payload = @FieldType(T, name);

        if (Payload == void) {
            if (object == state.builtins.get(.none)) return @unionInit(T, name, {});
        } else {
            if (from_python(Binding, Payload, label, state, object, scope)) |payload| {
                return @unionInit(T, name, payload);
            } else |_| {
                if (!variant_rejected(&state.builtins)) return error.Raised;
            }
        }
    }

    const names = comptime variant_names(T, Binding.declared);
    return mismatch(&state.builtins, label ++ " must be " ++ names, object);
}

fn variant_rejected(builtins: *const Builtins) bool {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);
    assert(builtins.objects.len > 0);

    const rejections = [_]@import("exception.zig").Builtin{
        .type_error,
        .value_error,
        .overflow_error,
    };

    for (rejections) |rejection| {
        if (c.PyErr_ExceptionMatches(builtins.get(rejection)) != 0) {
            c.PyErr_Clear();

            return true;
        }
    }

    return false;
}

pub fn variant_names(comptime T: type, comptime classes: []const type) [:0]const u8 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(@typeInfo(T).@"union".field_names.len > 0);

    return comptime result: {
        var text: [:0]const u8 = "";

        for (@typeInfo(T).@"union".field_types, 0..) |Payload, index| {
            const separator = if (index == 0) "" else " or ";

            text = text ++ separator ++ python_name(Payload, classes);
        }

        break :result text;
    };
}

fn python_name(comptime T: type, comptime classes: []const type) [:0]const u8 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"fn");

    return switch (kind_of(T, classes)) {
        .array, .list, .tuple => "a sequence",
        .complex => "complex",
        .container => @import("exception.zig").builtin_names[@backingInt(T.builtin_exact)],
        .decimal => "decimal.Decimal",
        .uuid => "uuid.UUID",
        .boolean => "bool",
        .buffer, .buffer_mutable, .buffer_strided => "a buffer",
        .bytes, .bytes_owned => "a bytes-like object",
        .class_pointer, .class_pointer_mutable => class_name(@typeInfo(T).pointer.child),
        .class_extended => class_name(T.extended_class),
        .class_value => class_name(T),
        .date => "datetime.date",
        .datetime => "datetime.datetime",
        .duration => "datetime.timedelta",
        .enumeration => class_name(T),
        .text, .text_owned, .text_terminated => "str",
        .float => "float",
        .fraction => "fractions.Fraction",
        .integer => "int",
        .ip_address => "ipaddress.IPv4Address or ipaddress.IPv6Address",
        .map, .record => "dict",
        .none => "None",
        .object, .reference => "object",
        .optional => python_name(@typeInfo(T).optional.child, classes) ++ " or None",
        .path => "a path",
        .set => "a set",
        .slice => "slice",
        .time => "datetime.time",
        .union_class => class_name(T),
        .variant => variant_names(T, classes),
    };
}

test format_matches {
    try std.testing.expect(format_matches(f64, "d"));
    try std.testing.expect(format_matches(f64, "<d"));
    try std.testing.expect(format_matches(f64, "@d"));
    try std.testing.expect(!format_matches(f64, ">d"));
    try std.testing.expect(!format_matches(f64, "2d"));
    try std.testing.expect(format_matches(i64, "q"));
    try std.testing.expect(format_matches(i64, "l"));
    try std.testing.expect(!format_matches(i64, "Q"));
    try std.testing.expect(format_matches(u8, "B"));
    try std.testing.expect(format_matches(u8, "B"));
    try std.testing.expect(!format_matches(i8, "B"));
    try std.testing.expect(format_matches(f32, "f"));
}

test choices {
    const Color = enum { red, green, blue };

    try std.testing.expectEqualStrings("'red', 'green', 'blue'", choices(Color));
}

test class_name {
    const Point = struct { horizontal: f64 };

    try std.testing.expectEqualStrings("Point", class_name(Point));
}

const FormatCase = struct {
    codes: []const u8,
    text: []const u8,
};

fn format_accepted(case: FormatCase) bool {
    assert(case.codes.len > 0);
    assert(case.text.len <= 2);

    for (case.codes) |code| {
        const forms = [_][2]u8{ .{ '@', code }, .{ '=', code }, .{ '<', code } };

        if (std.mem.eql(u8, case.text, &.{code})) return true;

        for (forms) |form| {
            if (std.mem.eql(u8, case.text, &form)) return true;
        }
    }

    return false;
}

test "format_matches agrees with the enumerated forms on every string of up to two bytes" {
    const cases = .{
        .{ f16, "efd" },
        .{ f32, "efd" },
        .{ f64, "efd" },
        .{ i8, "bhilqn" },
        .{ i16, "bhilqn" },
        .{ i32, "bhilqn" },
        .{ i64, "bhilqn" },
        .{ u8, "BHILQNc" },
        .{ u16, "BHILQNc" },
        .{ u64, "BHILQNc" },
    };

    comptime assert(@import("builtin").target.cpu.arch.endian() == .little);

    inline for (cases) |case| {
        var text: [3:0]u8 = @splat(0);
        var checked: u32 = 0;

        for (0..3) |length| {
            const total: u32 = std.math.pow(u32, 255, @intCast(length));

            for (0..total) |ordinal| {
                var rest: u32 = @intCast(ordinal);

                for (0..length) |position| {
                    text[position] = @intCast(rest % 255 + 1);
                    rest /= 255;
                }

                text[length] = 0;

                const expected = format_accepted(.{ .codes = case[1], .text = text[0..length] });

                try std.testing.expectEqual(expected, format_matches(case[0], text[0..length]));

                checked += 1;
            }
        }

        try std.testing.expectEqual(@as(u32, 1 + 255 + 255 * 255), checked);
    }
}
