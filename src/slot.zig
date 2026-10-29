const std = @import("std");

const arguments_module = @import("arguments.zig");
const buffer_module = @import("buffer.zig");
const c = @import("c.zig");
const critical = @import("critical.zig");
const derive = @import("derive.zig");
const exception = @import("exception.zig");
const from_python_module = @import("from_python.zig");
const instance = @import("instance.zig");
const invoke_module = @import("invoke.zig");
const kind_module = @import("kind.zig");
const native_module = @import("native.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const to_python_module = @import("to_python.zig");
const value_module = @import("value.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const Scope = scope_module.Scope;

pub const Shape = enum {
    anext,
    assign,
    attribute_get,
    attribute_set,
    binary,
    buffer,
    call,
    compare,
    contains,
    descriptor_get,
    descriptor_set,
    hash,
    inplace,
    inplace_power,
    inquiry,
    length,
    next,
    power,
    subscript,
    unary,
};

pub const Entry = struct {
    name: []const u8,
    reflected: []const u8,
    shape: Shape,
    slot: c_int,
};

pub const entries = [_]Entry{
    .{ .name = "__abs__", .reflected = "", .shape = .unary, .slot = c.Py_nb_absolute },
    .{ .name = "__aiter__", .reflected = "", .shape = .unary, .slot = c.Py_am_aiter },
    .{ .name = "__anext__", .reflected = "", .shape = .anext, .slot = c.Py_am_anext },
    .{ .name = "__await__", .reflected = "", .shape = .unary, .slot = c.Py_am_await },
    .{ .name = "__buffer__", .reflected = "", .shape = .buffer, .slot = c.Py_bf_getbuffer },
    .{ .name = "__get__", .reflected = "", .shape = .descriptor_get, .slot = c.Py_tp_descr_get },
    .{ .name = "__getattr__", .reflected = "", .shape = .attribute_get, .slot = c.Py_tp_getattro },
    .{ .name = "__set__", .reflected = "", .shape = .descriptor_set, .slot = c.Py_tp_descr_set },
    .{ .name = "__setattr__", .reflected = "", .shape = .attribute_set, .slot = c.Py_tp_setattro },
    .{ .name = "__iadd__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_add },
    .{ .name = "__iand__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_and },
    .{
        .name = "__ifloordiv__",
        .reflected = "",
        .shape = .inplace,
        .slot = c.Py_nb_inplace_floor_divide,
    },
    .{ .name = "__ilshift__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_lshift },
    .{
        .name = "__imatmul__",
        .reflected = "",
        .shape = .inplace,
        .slot = c.Py_nb_inplace_matrix_multiply,
    },
    .{ .name = "__imod__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_remainder },
    .{ .name = "__imul__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_multiply },
    .{ .name = "__ior__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_or },
    .{
        .name = "__ipow__",
        .reflected = "",
        .shape = .inplace_power,
        .slot = c.Py_nb_inplace_power,
    },
    .{ .name = "__irshift__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_rshift },
    .{ .name = "__isub__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_subtract },
    .{
        .name = "__itruediv__",
        .reflected = "",
        .shape = .inplace,
        .slot = c.Py_nb_inplace_true_divide,
    },
    .{ .name = "__ixor__", .reflected = "", .shape = .inplace, .slot = c.Py_nb_inplace_xor },
    .{ .name = "__add__", .reflected = "__radd__", .shape = .binary, .slot = c.Py_nb_add },
    .{ .name = "__and__", .reflected = "__rand__", .shape = .binary, .slot = c.Py_nb_and },
    .{ .name = "__bool__", .reflected = "", .shape = .inquiry, .slot = c.Py_nb_bool },
    .{ .name = "__call__", .reflected = "", .shape = .call, .slot = c.Py_tp_call },
    .{ .name = "__contains__", .reflected = "", .shape = .contains, .slot = c.Py_sq_contains },
    .{ .name = "__divmod__", .reflected = "__rdivmod__", .shape = .binary, .slot = c.Py_nb_divmod },
    .{ .name = "__eq__", .reflected = "", .shape = .compare, .slot = c.Py_tp_richcompare },
    .{ .name = "__float__", .reflected = "", .shape = .unary, .slot = c.Py_nb_float },
    .{
        .name = "__floordiv__",
        .reflected = "__rfloordiv__",
        .shape = .binary,
        .slot = c.Py_nb_floor_divide,
    },
    .{ .name = "__getitem__", .reflected = "", .shape = .subscript, .slot = c.Py_mp_subscript },
    .{ .name = "__hash__", .reflected = "", .shape = .hash, .slot = c.Py_tp_hash },
    .{ .name = "__index__", .reflected = "", .shape = .unary, .slot = c.Py_nb_index },
    .{ .name = "__int__", .reflected = "", .shape = .unary, .slot = c.Py_nb_int },
    .{ .name = "__invert__", .reflected = "", .shape = .unary, .slot = c.Py_nb_invert },
    .{ .name = "__iter__", .reflected = "", .shape = .unary, .slot = c.Py_tp_iter },
    .{ .name = "__len__", .reflected = "", .shape = .length, .slot = c.Py_mp_length },
    .{ .name = "__lshift__", .reflected = "__rlshift__", .shape = .binary, .slot = c.Py_nb_lshift },
    .{
        .name = "__matmul__",
        .reflected = "__rmatmul__",
        .shape = .binary,
        .slot = c.Py_nb_matrix_multiply,
    },
    .{ .name = "__mod__", .reflected = "__rmod__", .shape = .binary, .slot = c.Py_nb_remainder },
    .{ .name = "__mul__", .reflected = "__rmul__", .shape = .binary, .slot = c.Py_nb_multiply },
    .{ .name = "__neg__", .reflected = "", .shape = .unary, .slot = c.Py_nb_negative },
    .{ .name = "__next__", .reflected = "", .shape = .next, .slot = c.Py_tp_iternext },
    .{ .name = "__or__", .reflected = "__ror__", .shape = .binary, .slot = c.Py_nb_or },
    .{ .name = "__pos__", .reflected = "", .shape = .unary, .slot = c.Py_nb_positive },
    .{ .name = "__pow__", .reflected = "__rpow__", .shape = .power, .slot = c.Py_nb_power },
    .{ .name = "__repr__", .reflected = "", .shape = .unary, .slot = c.Py_tp_repr },
    .{ .name = "__rshift__", .reflected = "__rrshift__", .shape = .binary, .slot = c.Py_nb_rshift },
    .{ .name = "__setitem__", .reflected = "", .shape = .assign, .slot = c.Py_mp_ass_subscript },
    .{ .name = "__str__", .reflected = "", .shape = .unary, .slot = c.Py_tp_str },
    .{ .name = "__sub__", .reflected = "__rsub__", .shape = .binary, .slot = c.Py_nb_subtract },
    .{
        .name = "__truediv__",
        .reflected = "__rtruediv__",
        .shape = .binary,
        .slot = c.Py_nb_true_divide,
    },
    .{ .name = "__xor__", .reflected = "__rxor__", .shape = .binary, .slot = c.Py_nb_xor },
};

pub const compare_names = [_][]const u8{
    "__lt__",
    "__le__",
    "__eq__",
    "__ne__",
    "__gt__",
    "__ge__",
};

comptime {
    assert(compare_names.len == 6);
    assert(c.Py_LT == 0);
    assert(c.Py_GE == 5);
}

pub const paired_names = [_][]const u8{ "__delattr__", "__delete__", "__delitem__" };

pub fn is_slot_name(comptime name: []const u8) bool {
    comptime assert(name.len > 0);
    comptime assert(entries.len > 0);

    @setEvalBranchQuota(100_000);

    inline for (paired_names) |paired| {
        if (std.mem.eql(u8, name, paired)) return true;
    }

    inline for (compare_names) |compare| {
        if (std.mem.eql(u8, name, compare)) return true;
    }

    inline for (entries) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return true;
        if (std.mem.eql(u8, name, entry.reflected)) return true;
    }

    return false;
}

pub fn entry_present(comptime Class: type, comptime entry: Entry) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(entry.name.len > 0);

    return switch (entry.shape) {
        .assign => @hasDecl(Class, "__setitem__") or @hasDecl(Class, "__delitem__"),
        .attribute_set => @hasDecl(Class, "__setattr__") or @hasDecl(Class, "__delattr__"),
        .compare => compare_present(Class) or derive.derived(Class, .equality) or
            derive.derived(Class, .ordering),
        .descriptor_set => @hasDecl(Class, "__set__") or @hasDecl(Class, "__delete__"),
        else => @hasDecl(Class, entry.name) or
            (entry.reflected.len > 0 and @hasDecl(Class, entry.reflected)) or
            derive.derived_dunder(Class, entry.name),
    };
}

fn compare_present(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(compare_names.len > 0);

    inline for (compare_names) |name| {
        if (@hasDecl(Class, name)) return true;
    }

    return false;
}

pub fn slot_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(entries.len > 0);

    var result: u32 = 0;

    inline for (entries) |entry| {
        if (entry_present(Class, entry)) result += 1;
    }

    if (sequence(Class)) {
        if (@hasDecl(Class, "__getitem__")) result += 1;
        if (@hasDecl(Class, "__len__")) result += 1;
        if (sequence_assigned(Class)) result += 1;
    }

    if (@hasDecl(Class, "__buffer__")) result += 1;

    return result;
}

pub fn sequence(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "sequence")) return false;

    comptime assert(@TypeOf(Class.sequence) == bool);

    return Class.sequence;
}

fn sequence_assigned(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(sequence(Class));

    if (@hasDecl(Class, "__setitem__")) return true;
    return @hasDecl(Class, "__delitem__");
}

pub fn SlotsType(comptime Binding: type, comptime Class: type) type {
    const Instance = instance.InstanceType(Class);
    const qualified_name = from_python_module.class_name(Class);
    const count = slot_count(Class);

    comptime assert(count <= entries.len);
    comptime assert(@typeInfo(Class) == .@"struct");

    return struct {
        const Pair = struct {
            left: *c.PyObject,
            right: *c.PyObject,
        };

        const Held = struct {
            data: *Class,
            object: *c.PyObject,
        };

        const Outcome = error{ Mismatch, Raised };

        const Keyed = struct {
            object: *c.PyObject,
            key: *c.PyObject,
        };

        const Tolerance = enum {
            member,
            operand,
            strict,
        };

        const BufferPayload = Dunder("__buffer__").Payload;
        const Layout = [2 * buffer_module.dimensions_max]c.Py_ssize_t;
        const layout_stride_first = buffer_module.dimensions_max;

        const buffer_read_only = if (buffer_module.is_buffer(BufferPayload))
            !BufferPayload.writable
        else
            @typeInfo(BufferPayload).pointer.attrs.@"const";

        const BufferElement = if (buffer_module.is_buffer(BufferPayload))
            BufferPayload.Element
        else
            @typeInfo(BufferPayload).pointer.child;

        const ReprText = @import("text.zig").TextType(derive.repr_bytes_max);
        const repr_tail = "...)";

        const Extent = struct {
            count: u8,
            shape: [buffer_module.dimensions_max]u64,
            strides: [buffer_module.dimensions_max]i64,
            read_only: bool,
            contiguous: bool,
        };

        pub const slots: [count]c.PyType_Slot = slots: {
            var result: [count]c.PyType_Slot = undefined;
            var index: u32 = 0;

            for (entries) |entry| {
                if (entry_present(Class, entry)) {
                    result[index] = slot_of(entry);
                    index += 1;
                }
            }

            if (sequence(Class)) {
                if (@hasDecl(Class, "__getitem__")) {
                    result[index] = .{ .slot = c.Py_sq_item, .pfunc = &sequence_item };
                    index += 1;
                }

                if (@hasDecl(Class, "__len__")) {
                    result[index] = .{ .slot = c.Py_sq_length, .pfunc = &length };
                    index += 1;
                }

                if (sequence_assigned(Class)) {
                    result[index] = .{ .slot = c.Py_sq_ass_item, .pfunc = &sequence_assign };
                    index += 1;
                }
            }

            if (@hasDecl(Class, "__buffer__")) {
                result[index] = .{ .slot = c.Py_bf_releasebuffer, .pfunc = &buffer_release };
                index += 1;
            }

            assert(index == count);

            break :slots result;
        };

        pub const inplace_power_method: c.PyMethodDef = .{
            .ml_name = "__ipow__",
            .ml_meth = &inplace_power_call,
            .ml_flags = c.METH_FASTCALL | c.METH_COEXIST,
            .ml_doc = "__ipow__($self, value, mod=None, /)\n--\n\nReturn self **= value.",
        };

        pub const generic_method: c.PyMethodDef = .{
            .ml_name = "__getattribute__",
            .ml_meth = &attribute_generic,
            .ml_flags = c.METH_O | c.METH_COEXIST,
            .ml_doc = "__getattribute__($self, name, /)\n--\n\nLook up an attribute normally.",
        };

        pub const attribute_method: c.PyMethodDef = .{
            .ml_name = "__getattr__",
            .ml_meth = &attribute_fallback,
            .ml_flags = c.METH_O,
            .ml_doc = "__getattr__($self, name, /)\n--\n\nLook up an attribute that is not found.",
        };

        fn slot_of(comptime entry: Entry) c.PyType_Slot {
            comptime assert(entry_present(Class, entry));
            comptime assert(entry.name.len > 0);

            return switch (entry.shape) {
                .anext => .{ .slot = entry.slot, .pfunc = &anext },
                .assign => .{ .slot = entry.slot, .pfunc = &assign },
                .attribute_get => .{ .slot = entry.slot, .pfunc = &attribute_get },
                .attribute_set => .{ .slot = entry.slot, .pfunc = &attribute_set },
                .buffer => .{ .slot = entry.slot, .pfunc = &buffer_get },
                .descriptor_get => .{ .slot = entry.slot, .pfunc = &descriptor_get },
                .descriptor_set => .{ .slot = entry.slot, .pfunc = &descriptor_set },
                .inplace => .{ .slot = entry.slot, .pfunc = &InplaceType(entry.name).call },
                .inplace_power => .{ .slot = entry.slot, .pfunc = &inplace_power },
                .binary => .{ .slot = entry.slot, .pfunc = &BinaryType(entry).call },
                .call => .{ .slot = entry.slot, .pfunc = &call },
                .compare => .{ .slot = entry.slot, .pfunc = &compare },
                .contains => .{ .slot = entry.slot, .pfunc = &contains },
                .hash => if (derive.derived(Class, .hash))
                    .{ .slot = entry.slot, .pfunc = &derived_hash }
                else
                    .{ .slot = entry.slot, .pfunc = &hash },
                .inquiry => .{ .slot = entry.slot, .pfunc = &inquiry },
                .length => .{ .slot = entry.slot, .pfunc = &length },
                .next => .{ .slot = entry.slot, .pfunc = &next },
                .power => .{ .slot = entry.slot, .pfunc = &power },
                .subscript => .{ .slot = entry.slot, .pfunc = &subscript },
                .unary => if (derive.derived_dunder(Class, entry.name))
                    .{ .slot = entry.slot, .pfunc = &derived_repr }
                else
                    .{ .slot = entry.slot, .pfunc = &UnaryType(entry.name).call },
            };
        }

        fn payload_of(
            comptime name: []const u8,
            comptime tolerance: Tolerance,
            state: *const Binding.State,
            held: Held,
            operands: anytype,
        ) Outcome!Dunder(name).Payload {
            comptime assert(arguments_count(Dunder(name).Arguments) == operands.len);
            assert(Instance.data_of(held.object) == held.data);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            var section = critical.empty;

            critical.begin(&section, held.object);
            defer critical.end(&section);

            const data = signature_module.receiver_argument(Class, held.data, held.object);
            const function = @field(Class, name);
            const Arguments = Dunder(name).Arguments;
            const Errors = Dunder(name).Errors;

            if (Arguments == void) {
                const outcome = @call(.auto, function, .{data});
                return if (Errors) |Set| outcome catch |err| raised(Set, state, err) else outcome;
            }

            const counts = comptime operand_counts(Arguments);

            var objects: [counts.holders]*c.PyObject = undefined;
            var sections: [counts.sections]critical.Section = undefined;
            var views: [counts.views]c.Py_buffer = undefined;

            var scope: Scope = .init(.{
                .objects = &objects,
                .sections = &sections,
                .views = &views,
            });

            defer scope.release();

            var arguments: Arguments = undefined;

            inline for (@typeInfo(Arguments).@"struct".field_names, 0..) |field, index| {
                const label = qualified_name ++ "." ++ name ++ "() argument '" ++ field ++ "'";

                @field(arguments, field) = from_python_module.from_python(
                    Binding,
                    @FieldType(Arguments, field),
                    label,
                    state,
                    operands[index],
                    &scope,
                ) catch return mismatch_of(tolerance, state);
            }

            const outcome = @call(.auto, function, .{ data, arguments });
            return if (Errors) |Set| outcome catch |err| raised(Set, state, err) else outcome;
        }

        fn raised(comptime Errors: type, state: *const Binding.State, err: Errors) Outcome {
            comptime assert(@typeInfo(Errors) == .error_set);
            assert(@errorName(err).len > 0);

            exception.raise(Binding, state, Errors, err, null);

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            return error.Raised;
        }

        fn arguments_count(comptime Arguments: type) u32 {
            comptime assert(Arguments == void or @typeInfo(Arguments) == .@"struct");
            comptime assert(Arguments != type);

            if (Arguments == void) return 0;
            return @typeInfo(Arguments).@"struct".field_names.len;
        }

        fn mismatch_of(comptime tolerance: Tolerance, state: *const Binding.State) Outcome {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            const tolerated: []const exception.Builtin = switch (tolerance) {
                .member => &.{ .overflow_error, .type_error, .value_error },
                .operand => &.{.type_error},
                .strict => &.{},
            };

            for (tolerated) |builtin| {
                if (c.PyErr_ExceptionMatches(state.builtins.get(builtin)) != 0) {
                    c.PyErr_Clear();

                    return error.Mismatch;
                }
            }

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            return error.Raised;
        }

        fn Dunder(comptime name: []const u8) type {
            comptime assert(name.len > 4);
            comptime assert(@hasDecl(Class, name));

            const Function = @TypeOf(@field(Class, name));
            const Return = @typeInfo(Function).@"fn".return_type.?;
            const First = @typeInfo(Function).@"fn".param_types[0].?;

            const receiver_valid = if (comptime native_module.metaclass_is(Class))
                First == value_module.TypeObject
            else
                First == *Class or First == *const Class;

            if (!receiver_valid) {
                @compileError("lacuna: '" ++ @typeName(Class) ++ "." ++ name ++
                    "' takes its receiver as the first parameter");
            }

            const parameters = @typeInfo(Function).@"fn".param_types;
            const Operands = if (parameters.len == 2) parameters[1].? else void;

            if (parameters.len > 2) {
                @compileError("lacuna: '" ++ @typeName(Class) ++ "." ++ name ++
                    "' takes its operands as one struct");
            }

            if (Operands != void) {
                if (@typeInfo(Operands) != .@"struct") {
                    @compileError("lacuna: the operands of '" ++ @typeName(Class) ++ "." ++ name ++
                        "' must be a struct");
                }
            }

            return switch (@typeInfo(Return)) {
                .error_union => |error_union| struct {
                    pub const Arguments = Operands;

                    pub const Errors: ?type = signature_module.errors_of(
                        error_union.error_set,
                        name,
                    );

                    pub const Payload = error_union.payload;
                    pub const Returned = Return;
                },
                else => struct {
                    pub const Arguments = Operands;
                    pub const Errors: ?type = null;
                    pub const Payload = Return;
                    pub const Returned = Return;
                },
            };
        }

        fn operand_counts(comptime Arguments: type) invoke_module.Counts {
            comptime assert(@typeInfo(Arguments) == .@"struct");
            comptime assert(Binding.classes.len <= std.math.maxInt(u32));

            var result: invoke_module.Counts = .{ .holders = 0, .sections = 0, .views = 0 };

            for (@typeInfo(Arguments).@"struct".field_types) |Operand| {
                result.holders += scope_module.holder_count(Operand, Binding.declared, 0);
                result.sections += scope_module.section_count(Operand, Binding.declared, 0);
                result.views += scope_module.view_count(Operand, Binding.declared, false);
            }

            return result;
        }

        fn state_of(object: *c.PyObject) *const Binding.State {
            const class = python.type_borrowed(object);
            const defining = Instance.defining_of(class).?;

            assert(Instance.owns(defining));
            assert(class != object);

            return Binding.State.of_class(defining);
        }

        fn result_of(
            comptime name: []const u8,
            state: *const Binding.State,
            object: *c.PyObject,
            data: *Class,
            payload: *const Dunder(name).Payload,
        ) ?*c.PyObject {
            comptime assert(name.len > 4);
            const receiver: invoke_module.Receiver(Class) = .{ .data = data, .object = object };

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(Instance.data_of(object) == data);

            return invoke_module.result_of(
                Binding,
                Class,
                Dunder(name).Payload,
                state,
                receiver,
                payload,
            );
        }

        fn not_implemented(state: *const Binding.State) *c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(state.builtins.objects.len == exception.builtin_count);

            return python.reference_new(state.builtins.get(.not_implemented));
        }

        fn UnaryType(comptime name: []const u8) type {
            comptime assert(name.len > 0);
            comptime assert(@hasDecl(Class, name));

            return struct {
                fn call(object: *c.PyObject) callconv(.c) ?*c.PyObject {
                    const state = state_of(object);
                    const data = Instance.data_required(object) orelse return null;

                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    assert(Instance.owned_by(object));

                    const held: Held = .{ .data = data, .object = object };
                    const payload = payload_of(name, .strict, state, held, .{}) catch return null;

                    return result_of(name, state, object, data, &payload);
                }
            };
        }

        fn BinaryType(comptime entry: Entry) type {
            comptime assert(entry.shape == .binary);
            comptime assert(entry.reflected.len > 0);

            return struct {
                fn call(left: *c.PyObject, right: *c.PyObject) callconv(.c) ?*c.PyObject {
                    comptime assert(entry.shape == .binary);
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    comptime assert(entry.reflected.len > 0);

                    return binary(entry, .{ .left = left, .right = right });
                }
            };
        }

        fn binary(comptime entry: Entry, operands: Pair) ?*c.PyObject {
            comptime assert(entry.reflected.len > 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(operands.left) % @alignOf(*c.PyObject) == 0);
            assert(@intFromPtr(operands.right) % @alignOf(*c.PyObject) == 0);

            const left = operands.left;
            const right = operands.right;

            if (@hasDecl(Class, entry.name)) {
                if (Instance.data_of(left)) |data| {
                    const state = state_of(left);

                    const payload = payload_of(
                        entry.name,
                        .operand,
                        state,
                        .{ .data = data, .object = left },
                        .{right},
                    ) catch |err| {
                        return if (err == error.Mismatch) not_implemented(state) else null;
                    };

                    return result_of(entry.name, state, left, data, &payload);
                }
            }

            if (@hasDecl(Class, entry.reflected)) {
                if (Instance.data_of(right)) |data| {
                    const state = state_of(right);

                    const payload = payload_of(
                        entry.reflected,
                        .operand,
                        state,
                        .{ .data = data, .object = right },
                        .{left},
                    ) catch |err| {
                        return if (err == error.Mismatch) not_implemented(state) else null;
                    };

                    return result_of(entry.reflected, state, right, data, &payload);
                }
            }

            const owner = if (Instance.owned_by(left)) left else right;
            return not_implemented(state_of(owner));
        }

        fn power(
            left: *c.PyObject,
            right: *c.PyObject,
            modulus: *c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            const entry = comptime entry_named("__pow__");

            const owner = if (Instance.owned_by(left))
                left
            else if (Instance.owned_by(right))
                right
            else
                modulus;

            const state = state_of(owner);

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(Instance.owned_by(owner));

            if (modulus != state.builtins.get(.none)) return not_implemented(state);
            return binary(entry, .{ .left = left, .right = right });
        }

        fn InplaceType(comptime name: []const u8) type {
            comptime assert(name.len > 4);
            comptime assert(@hasDecl(Class, name));

            return struct {
                fn call(object: *c.PyObject, other: *c.PyObject) callconv(.c) ?*c.PyObject {
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    assert(@intFromPtr(other) % @alignOf(*c.PyObject) == 0);

                    return inplace(name, .{ .left = object, .right = other });
                }
            };
        }

        fn inplace(comptime name: []const u8, operands: Pair) ?*c.PyObject {
            comptime assert(Dunder(name).Payload == void);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(operands.left) % @alignOf(*c.PyObject) == 0);
            assert(@intFromPtr(operands.right) % @alignOf(*c.PyObject) == 0);

            const object = operands.left;
            const data = Instance.data_required(object) orelse return null;
            const state = state_of(object);
            const held: Held = .{ .data = data, .object = object };

            payload_of(name, .operand, state, held, .{operands.right}) catch |err| {
                return if (err == error.Mismatch) not_implemented(state) else null;
            };

            return python.reference_new(object);
        }

        fn inplace_power(
            object: *c.PyObject,
            other: *c.PyObject,
            modulus: *c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(modulus) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);

            if (modulus != state.builtins.get(.none)) return not_implemented(state);
            return inplace("__ipow__", .{ .left = object, .right = other });
        }

        fn inplace_power_call(
            object: *c.PyObject,
            arguments: ?[*]const *c.PyObject,
            argument_count: c.Py_ssize_t,
        ) callconv(.c) ?*c.PyObject {
            assert(argument_count >= 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            if (argument_count > 0) assert(arguments != null);

            const state = state_of(object);

            const supported = switch (argument_count) {
                1, 2 => true,
                else => false,
            };

            if (!supported) {
                const message = "__ipow__ expected 1 or 2 arguments";

                c.PyErr_SetString(state.builtins.get(.type_error), message);

                return null;
            }

            const modulus = if (argument_count == 2) arguments.?[1] else state.builtins.get(.none);

            return inplace_power(object, arguments.?[0], modulus);
        }

        fn attribute_get(object: *c.PyObject, name: *c.PyObject) callconv(.c) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(name) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);

            if (!python.has_flag(name, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
                attribute_name_mismatch(state, name) catch return null;
            }

            if (c.PyObject_GenericGetAttr(object, name)) |found| return found;
            if (c.PyErr_ExceptionMatches(state.builtins.get(.attribute_error)) == 0) return null;

            c.PyErr_Clear();

            const data = Instance.data_required(object) orelse return null;
            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__getattr__", .strict, state, held, .{name}) catch {
                return null;
            };

            return result_of("__getattr__", state, object, data, &payload);
        }

        fn attribute_name_mismatch(state: *const Binding.State, name: *c.PyObject) Outcome!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(!python.has_flag(name, c.Py_TPFLAGS_UNICODE_SUBCLASS));

            const message = "an attribute name must be str";

            return from_python_module.mismatch(&state.builtins, message, name);
        }

        fn attribute_generic(object: *c.PyObject, name: *c.PyObject) callconv(.c) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(name) % @alignOf(*c.PyObject) == 0);

            if (!python.has_flag(name, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
                attribute_name_mismatch(state_of(object), name) catch return null;
            }

            return c.PyObject_GenericGetAttr(object, name);
        }

        fn attribute_fallback(object: *c.PyObject, name: *c.PyObject) callconv(.c) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(name) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;
            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__getattr__", .strict, state, held, .{name}) catch {
                return null;
            };

            return result_of("__getattr__", state, object, data, &payload);
        }

        fn attribute_set(
            object: *c.PyObject,
            name: *c.PyObject,
            item: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (item) |given| assert(@intFromPtr(given) % @alignOf(*c.PyObject) == 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(name) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);

            if (!python.has_flag(name, c.Py_TPFLAGS_UNICODE_SUBCLASS)) {
                attribute_name_mismatch(state, name) catch return -1;
            }

            const data = Instance.data_required(object) orelse return -1;
            const held: Held = .{ .data = data, .object = object };

            if (item) |present| {
                if (!@hasDecl(Class, "__setattr__")) {
                    return c.PyObject_GenericSetAttr(object, name, present);
                }

                const outcome = payload_of("__setattr__", .strict, state, held, .{ name, present });

                _ = outcome catch return -1;
            } else {
                if (!@hasDecl(Class, "__delattr__")) {
                    return c.PyObject_GenericSetAttr(object, name, null);
                }

                const outcome = payload_of("__delattr__", .strict, state, held, .{name});

                _ = outcome catch return -1;
            }

            return 0;
        }

        fn descriptor_get(
            object: *c.PyObject,
            owner_instance: ?*c.PyObject,
            owner_class: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(owner_class) % @alignOf(*c.PyObject) == 0);

            if (owner_instance) |owner| assert(@intFromPtr(owner) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);
            const none = state.builtins.get(.none);
            const data = Instance.data_required(object) orelse return null;
            const held: Held = .{ .data = data, .object = object };
            const operands = .{ owner_instance orelse none, owner_class orelse none };
            const payload = payload_of("__get__", .strict, state, held, operands) catch {
                return null;
            };

            return result_of("__get__", state, object, data, &payload);
        }

        fn descriptor_set(
            object: *c.PyObject,
            owner_instance: *c.PyObject,
            item: ?*c.PyObject,
        ) callconv(.c) c_int {
            if (item) |given| assert(@intFromPtr(given) % @alignOf(*c.PyObject) == 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(owner_instance) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;
            const held: Held = .{ .data = data, .object = object };

            if (item) |present| {
                if (!@hasDecl(Class, "__set__")) return unsupported(state, "assignment");

                const operands = .{ owner_instance, present };
                const outcome = payload_of("__set__", .strict, state, held, operands);

                _ = outcome catch return -1;
            } else {
                if (!@hasDecl(Class, "__delete__")) return unsupported(state, "deletion");

                const outcome = payload_of("__delete__", .strict, state, held, .{owner_instance});

                _ = outcome catch return -1;
            }

            return 0;
        }

        fn anext(object: *c.PyObject) callconv(.c) ?*c.PyObject {
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;
            const Payload = Dunder("__anext__").Payload;
            const Item = @typeInfo(Payload).optional.child;

            comptime assert(@typeInfo(Payload) == .optional);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__anext__", .strict, state, held, .{}) catch return null;

            const item = payload orelse {
                c.PyErr_SetNone(state.builtins.get(.stop_async_iteration));

                return null;
            };

            const receiver: invoke_module.Receiver(Class) = .{ .data = data, .object = object };

            return invoke_module.result_of(Binding, Class, Item, state, receiver, &item);
        }

        fn buffer_get(object: *c.PyObject, view: *c.Py_buffer, flags: c_int) callconv(.c) c_int {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(flags >= 0);

            const state = state_of(object);
            view.obj = null;

            const data = Instance.data_required(object) orelse return -1;
            const held: Held = .{ .data = data, .object = object };
            const writable = flags & c.PyBUF_WRITABLE != 0;

            if (writable) {
                if (buffer_read_only) return buffer_refuse(state, "the buffer is read-only");
            }

            const items = payload_of("__buffer__", .strict, state, held, .{}) catch return -1;
            const extent = buffer_extent(&items);

            if (writable) {
                if (extent.read_only) return buffer_refuse(state, "the buffer is read-only");
            }

            if (!extent.contiguous) {
                const refusal = "the buffer is not contiguous";

                const strided = c.PyBUF_STRIDES;

                if (flags & c.PyBUF_FORMAT == 0) return buffer_refuse(state, refusal);
                if (flags & strided != strided) return buffer_refuse(state, refusal);
            }

            const inline_layout: ?*Layout = if (c.pypy)
                view._shape[0 .. 2 * buffer_module.dimensions_max]
            else
                null;

            const layout = inline_layout orelse buffer_layout_acquire(state) orelse return -1;

            view.buf = if (comptime buffer_module.is_buffer(BufferPayload))
                @ptrCast(items.data)
            else
                @ptrCast(@constCast(items.ptr));

            buffer_fill(view, object, &extent, layout, flags);

            assert(view.len == buffer_byte_count(&extent));

            return 0;
        }

        fn buffer_refuse(state: *const Binding.State, comptime message: [:0]const u8) c_int {
            comptime assert(message.len > 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            c.PyErr_SetString(state.builtins.get(.buffer_error), message);

            return -1;
        }

        fn buffer_extent(items: *const BufferPayload) Extent {
            comptime assert(kind_module.buffer_element(BufferElement));
            assert(@intFromPtr(items) % @alignOf(BufferPayload) == 0);

            if (comptime buffer_module.is_buffer(BufferPayload)) {
                assert(items.dimension_count <= buffer_module.dimensions_max);

                return .{
                    .count = items.dimension_count,
                    .shape = items.shape,
                    .strides = items.strides,
                    .read_only = items.read_only,
                    .contiguous = items.contiguous(),
                };
            }

            var result: Extent = .{
                .count = 1,
                .shape = @splat(0),
                .strides = @splat(0),
                .read_only = buffer_read_only,
                .contiguous = true,
            };

            result.shape[0] = items.len;
            result.strides[0] = @sizeOf(BufferElement);

            return result;
        }

        fn buffer_byte_count(extent: *const Extent) c.Py_ssize_t {
            assert(extent.count <= buffer_module.dimensions_max);

            var bytes: u64 = @sizeOf(BufferElement);

            for (extent.shape[0..extent.count]) |size| bytes *= size;

            assert(bytes <= std.math.maxInt(c.Py_ssize_t));

            return @intCast(bytes);
        }

        fn buffer_fill(
            view: *c.Py_buffer,
            object: *c.PyObject,
            extent: *const Extent,
            layout: *Layout,
            flags: c_int,
        ) void {
            assert(flags >= 0);
            assert(extent.count <= buffer_module.dimensions_max);

            view.obj = python.reference_new(object);
            view.len = buffer_byte_count(extent);
            view.readonly = @intFromBool(extent.read_only);
            view.suboffsets = null;
            view.internal = layout;

            if (flags & c.PyBUF_FORMAT == 0) {
                view.itemsize = 1;
                view.ndim = 1;
                view.format = null;
                layout[0] = view.len;
                layout[layout_stride_first] = 1;
            } else {
                view.itemsize = @sizeOf(BufferElement);
                view.ndim = extent.count;
                view.format = @constCast(format_of(BufferElement).ptr);

                for (0..extent.count) |dimension| {
                    layout[dimension] = @intCast(extent.shape[dimension]);
                    layout[layout_stride_first + dimension] = @intCast(extent.strides[dimension]);
                }
            }

            if (flags & c.PyBUF_ND != c.PyBUF_ND) view.ndim = 1;

            view.shape = if (flags & c.PyBUF_ND == c.PyBUF_ND) layout else null;

            view.strides = if (flags & c.PyBUF_STRIDES == c.PyBUF_STRIDES)
                layout[layout_stride_first..]
            else
                null;
        }

        fn buffer_layout_acquire(state: *const Binding.State) ?*Layout {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(state.builtins.objects.len == exception.builtin_count);

            const bytes = c.PyMem_Malloc(@sizeOf(Layout)) orelse {
                c.PyErr_SetNone(state.builtins.get(.memory_error));

                return null;
            };

            return @ptrCast(@alignCast(bytes));
        }

        fn buffer_release(object: *c.PyObject, view: *c.Py_buffer) callconv(.c) void {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            if (c.pypy) {
                const inline_layout: *anyopaque = &view._shape;

                if (view.internal) |internal| assert(internal == inline_layout);

                return;
            }

            assert(view.obj == object);
            assert(view.internal != null);

            c.PyMem_Free(view.internal);
            view.internal = null;
        }

        fn entry_named(comptime name: []const u8) Entry {
            comptime assert(name.len > 0);
            comptime assert(entries.len > 0);

            inline for (entries) |entry| {
                if (std.mem.eql(u8, entry.name, name)) return entry;
            }

            unreachable;
        }

        fn compare(
            object: *c.PyObject,
            other: *c.PyObject,
            operation: c_int,
        ) callconv(.c) ?*c.PyObject {
            assert(operation >= c.Py_LT);
            assert(operation <= c.Py_GE);

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;

            inline for (compare_names, 0..) |name, index| {
                if (operation == index) {
                    if (comptime derive.derived_dunder(Class, name)) {
                        const pair: Keyed = .{ .object = object, .key = other };

                        return derived_compare(state, pair, operation);
                    }

                    if (!@hasDecl(Class, name)) return not_implemented(state);

                    const held: Held = .{ .data = data, .object = object };

                    const payload = payload_of(name, .operand, state, held, .{other}) catch |err| {
                        return if (err == error.Mismatch) not_implemented(state) else null;
                    };

                    return result_of(name, state, object, data, &payload);
                }
            }

            unreachable;
        }

        fn derived_compare(
            state: *const Binding.State,
            pair: Keyed,
            operation: c_int,
        ) ?*c.PyObject {
            assert(operation >= c.Py_LT);
            assert(operation <= c.Py_GE);
            assert(@intFromPtr(pair.key) % @alignOf(*c.PyObject) == 0);

            const left_data = Instance.data_required(pair.object) orelse return null;
            const right_data = Instance.data_of(pair.key) orelse return not_implemented(state);

            const left = derived_copy(pair.object, left_data);
            const right = derived_copy(pair.key, right_data);
            const operands: derive.OperandsType(Class) = .{ .left = &left, .right = &right };
            const result = derive.fields_compare(Class, operands, operation);

            return c.PyBool_FromLong(@intFromBool(result));
        }

        fn derived_copy(object: *c.PyObject, data: *const Class) Class {
            assert(@intFromPtr(data) % @alignOf(Class) == 0);
            assert(Instance.data_of(object) == data);

            var section = critical.empty;

            critical.begin(&section, object);
            defer critical.end(&section);

            return data.*;
        }

        fn derived_hash(object: *c.PyObject) callconv(.c) c.Py_hash_t {
            comptime assert(derive.derived(Class, .hash));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const data = Instance.data_required(object) orelse return -1;
            const copy = derived_copy(object, data);
            const wide: i64 = @bitCast(derive.fields_hash(Class, &copy));

            const folded: c.Py_hash_t = if (@bitSizeOf(c.Py_hash_t) >= 64)
                @intCast(wide)
            else
                @truncate(wide ^ (wide >> 32));

            return if (folded == -1) -2 else folded;
        }

        fn derived_repr(object: *c.PyObject) callconv(.c) ?*c.PyObject {
            comptime assert(derive.derived(Class, .representation));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const data = Instance.data_required(object) orelse return null;
            const copy = derived_copy(object, data);

            var text: ReprText = .empty;
            var complete = repr_append(&text, comptime from_python_module.class_name(Class) ++ "(");

            inline for (@typeInfo(Class).@"struct".field_names, 0..) |field, index| {
                if (complete) {
                    const label = (if (index == 0) "" else ", ") ++ field ++ "=";
                    const item = &@field(copy, field);

                    complete = derived_repr_field(object, &text, label, item) catch return null;
                }
            }

            const tail = if (complete) ")" else repr_tail;

            @memcpy(text.bytes[text.length..][0..tail.len], tail);
            text.length += @intCast(tail.len);

            return c.PyUnicode_FromStringAndSize(&text.bytes, @intCast(text.length));
        }

        fn repr_append(text: *ReprText, piece: []const u8) bool {
            assert(text.length + repr_tail.len <= ReprText.capacity_max);
            assert(std.unicode.utf8ValidateSlice(piece));

            if (text.length + piece.len + repr_tail.len > ReprText.capacity_max) return false;

            @memcpy(text.bytes[text.length..][0..piece.len], piece);
            text.length += @intCast(piece.len);

            return true;
        }

        fn derived_repr_field(
            object: *c.PyObject,
            text: *ReprText,
            comptime label: []const u8,
            field: anytype,
        ) error{Raised}!bool {
            comptime assert(label.len > 0);
            comptime assert(@typeInfo(@TypeOf(field)) == .pointer);
            assert(text.length <= ReprText.capacity_max);

            const Field = @typeInfo(@TypeOf(field)).pointer.child;
            const state = state_of(object);
            const converted = to_python_module.to_python(Binding, Field, state, field) catch {
                return error.Raised;
            };

            defer c.Py_DecRef(converted);

            const shown = c.PyObject_Repr(converted) orelse return error.Raised;
            defer c.Py_DecRef(shown);

            const bytes = python.text_of(shown) orelse return error.Raised;

            if (!repr_append(text, label)) return false;
            return repr_append(text, bytes);
        }

        fn subscript(object: *c.PyObject, key: *c.PyObject) callconv(.c) ?*c.PyObject {
            comptime assert(@hasDecl(Class, "__getitem__"));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (comptime sequence_indexed()) {
                if (c.PyIndex_Check(key) != 0) {
                    const keyed: Keyed = .{ .object = object, .key = key };
                    const index = index_normalized(keyed) catch return null;

                    return sequence_item(object, index);
                }
            }

            return subscript_key(.{ .object = object, .key = key });
        }

        fn subscript_key(keyed: Keyed) ?*c.PyObject {
            assert(@intFromPtr(keyed.key) % @alignOf(*c.PyObject) == 0);

            const object = keyed.object;
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;

            comptime assert(@hasDecl(Class, "__getitem__"));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__getitem__", .strict, state, held, .{keyed.key}) catch {
                return null;
            };

            return result_of("__getitem__", state, object, data, &payload);
        }

        fn sequence_indexed() bool {
            comptime assert(@typeInfo(Class) == .@"struct");
            comptime assert(entries.len > 0);

            if (!sequence(Class)) return false;
            return @hasDecl(Class, "__len__");
        }

        fn index_normalized(keyed: Keyed) error{Raised}!c.Py_ssize_t {
            comptime assert(sequence_indexed());
            assert(c.PyIndex_Check(keyed.key) != 0);

            const state = state_of(keyed.object);
            const index = c.PyNumber_AsSsize_t(keyed.key, state.builtins.get(.index_error));

            if (index == -1) {
                if (c.PyErr_Occurred() != null) return error.Raised;
            }

            if (index >= 0) return index;

            const size = length(keyed.object);
            if (size < 0) return error.Raised;

            if (index + size < 0) {
                c.PyErr_SetString(state.builtins.get(.index_error), "index out of range");

                return error.Raised;
            }

            return index + size;
        }

        fn sequence_item(object: *c.PyObject, index: c.Py_ssize_t) callconv(.c) ?*c.PyObject {
            assert(index > std.math.minInt(c.Py_ssize_t));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (index < 0) {
                const state = state_of(object);

                c.PyErr_SetString(state.builtins.get(.index_error), "index out of range");

                return null;
            }

            const key = c.PyLong_FromLongLong(index) orelse return null;
            defer c.Py_DecRef(key);

            return subscript_key(.{ .object = object, .key = key });
        }

        fn sequence_assign(
            object: *c.PyObject,
            index: c.Py_ssize_t,
            item: ?*c.PyObject,
        ) callconv(.c) c_int {
            assert(index > std.math.minInt(c.Py_ssize_t));
            assert(@intFromPtr(item) % @alignOf(*c.PyObject) == 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (index < 0) {
                const state = state_of(object);

                c.PyErr_SetString(state.builtins.get(.index_error), "index out of range");

                return -1;
            }

            const key = c.PyLong_FromLongLong(index) orelse return -1;
            defer c.Py_DecRef(key);

            return assign_key(.{ .object = object, .key = key }, item);
        }

        fn assign(object: *c.PyObject, key: *c.PyObject, item: ?*c.PyObject) callconv(.c) c_int {
            assert(@intFromPtr(item) % @alignOf(*c.PyObject) == 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (comptime sequence_indexed()) {
                if (c.PyIndex_Check(key) != 0) {
                    const keyed: Keyed = .{ .object = object, .key = key };
                    const index = index_normalized(keyed) catch return -1;

                    return sequence_assign(object, index, item);
                }
            }

            return assign_key(.{ .object = object, .key = key }, item);
        }

        fn assign_key(keyed: Keyed, item: ?*c.PyObject) c_int {
            assert(@intFromPtr(item) % @alignOf(*c.PyObject) == 0);
            assert(@intFromPtr(keyed.key) % @alignOf(*c.PyObject) == 0);

            const object = keyed.object;
            const key = keyed.key;

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(@hasDecl(Class, "__setitem__") or @hasDecl(Class, "__delitem__"));

            if (item) |present| {
                if (!@hasDecl(Class, "__setitem__")) return unsupported(state, "item assignment");

                const held: Held = .{ .data = data, .object = object };
                const payload = payload_of("__setitem__", .strict, state, held, .{ key, present });

                _ = payload catch return -1;
            } else {
                if (!@hasDecl(Class, "__delitem__")) return unsupported(state, "item deletion");

                const held: Held = .{ .data = data, .object = object };
                const payload = payload_of("__delitem__", .strict, state, held, .{key});

                _ = payload catch return -1;
            }

            return 0;
        }

        fn unsupported(state: *const Binding.State, comptime operation: []const u8) c_int {
            comptime assert(operation.len > 0);

            const message = comptime "'" ++ from_python_module.class_name(Class) ++
                "' object does not support " ++ operation;

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            c.PyErr_SetString(state.builtins.get(.type_error), message);

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            return -1;
        }

        fn contains(object: *c.PyObject, item: *c.PyObject) callconv(.c) c_int {
            assert(@intFromPtr(item) % @alignOf(*c.PyObject) == 0);

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;

            comptime assert(Dunder("__contains__").Payload == bool);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const held: Held = .{ .data = data, .object = object };

            const payload = payload_of("__contains__", .member, state, held, .{item}) catch |err| {
                return if (err == error.Mismatch) 0 else -1;
            };

            return @intFromBool(payload);
        }

        fn inquiry(object: *c.PyObject) callconv(.c) c_int {
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;

            comptime assert(Dunder("__bool__").Payload == bool);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__bool__", .strict, state, held, .{}) catch return -1;

            return @intFromBool(payload);
        }

        fn hash(object: *c.PyObject) callconv(.c) c.Py_hash_t {
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;
            const Payload = Dunder("__hash__").Payload;

            comptime assert(@typeInfo(Payload) == .int);
            comptime assert(@typeInfo(Payload).int.bits <= 64);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__hash__", .strict, state, held, .{}) catch return -1;

            const wide: i64 = switch (@typeInfo(Payload).int.signedness) {
                .signed => payload,
                .unsigned => @bitCast(@as(u64, payload)),
            };

            const folded: c.Py_hash_t = if (@bitSizeOf(c.Py_hash_t) >= 64)
                @intCast(wide)
            else
                @truncate(wide ^ (wide >> 32));

            return if (folded == -1) -2 else folded;
        }

        fn length(object: *c.PyObject) callconv(.c) c.Py_ssize_t {
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return -1;
            const Payload = Dunder("__len__").Payload;

            comptime assert(@typeInfo(Payload) == .int);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__len__", .strict, state, held, .{}) catch return -1;

            if (std.math.cast(c.Py_ssize_t, payload)) |size| {
                if (size >= 0) return size;
            }

            c.PyErr_SetString(state.builtins.get(.overflow_error), "__len__() is out of range");

            return -1;
        }

        fn next(object: *c.PyObject) callconv(.c) ?*c.PyObject {
            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;
            const Payload = Dunder("__next__").Payload;
            const Item = @typeInfo(Payload).optional.child;

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(@typeInfo(Payload) == .optional);

            const held: Held = .{ .data = data, .object = object };
            const payload = payload_of("__next__", .strict, state, held, .{}) catch return null;
            const item = payload orelse return null;
            const receiver: invoke_module.Receiver(Class) = .{ .data = data, .object = object };

            return invoke_module.result_of(Binding, Class, Item, state, receiver, &item);
        }

        fn call(
            object: *c.PyObject,
            arguments: *c.PyObject,
            keywords: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;
            const invocation: Call = .tuple(arguments, keywords);
            const receiver: invoke_module.Receiver(Class) = .{ .data = data, .object = object };

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(@hasDecl(Class, "__call__"));

            const Invoker = invoke_module.InvokerType(
                Binding,
                Class,
                Class.__call__,
                "__call__",
                .held,
            );

            const defining = Instance.defining_of(python.type_borrowed(object));

            return Invoker.invoke(state, receiver, .{ .defining = defining }, &invocation);
        }
    };
}

pub fn format_of(comptime Element: type) [:0]const u8 {
    comptime assert(kind_module.buffer_element(Element));
    comptime assert(@sizeOf(Element) <= 8);

    return switch (@typeInfo(Element)) {
        .float => |float| switch (float.bits) {
            16 => "e",
            32 => "f",
            64 => "d",
            else => unreachable,
        },
        .int => |int| switch (int.bits) {
            8 => if (int.signedness == .signed) "b" else "B",
            16 => if (int.signedness == .signed) "h" else "H",
            32 => if (int.signedness == .signed) "i" else "I",
            64 => if (int.signedness == .signed) "q" else "Q",
            else => unreachable,
        },
        else => unreachable,
    };
}

const Vector = struct {
    magnitude: f64,

    const Other = struct { other: *const Vector };

    pub fn __add__(vector: *const Vector, arguments: Other) Vector {
        assert(std.math.isFinite(vector.magnitude));
        assert(std.math.isFinite(arguments.other.magnitude));

        return .{ .magnitude = vector.magnitude + arguments.other.magnitude };
    }

    pub fn __contains__(vector: *const Vector, arguments: struct { value: f64 }) bool {
        assert(std.math.isFinite(vector.magnitude));
        assert(!std.math.isNan(arguments.value));

        return arguments.value <= vector.magnitude;
    }

    pub fn __hash__(vector: *const Vector) u64 {
        assert(std.math.isFinite(vector.magnitude));

        const result: u64 = @bitCast(vector.magnitude);

        assert(result != 0 or vector.magnitude == 0);

        return result;
    }

    pub fn __delitem__(vector: *Vector, arguments: struct { index: u32 }) void {
        assert(arguments.index < 1);
        assert(std.math.isFinite(vector.magnitude));
    }
};

test is_slot_name {
    comptime {
        assert(is_slot_name("__add__"));
        assert(is_slot_name("__radd__"));
        assert(is_slot_name("__delitem__"));
        assert(is_slot_name("__lt__"));
        assert(!is_slot_name("__enter__"));
        assert(!is_slot_name("generate"));
    }
}

test slot_count {
    comptime assert(slot_count(Vector) == 4);
}
