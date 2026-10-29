const std = @import("std");

const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const from_python_module = @import("from_python.zig");
const kind_module = @import("kind.zig");
const python = @import("python.zig");
const registry = @import("registry.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const to_python_module = @import("to_python.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const Restoration = @import("class.zig").Restoration;
const Scope = scope_module.Scope;

pub const variant_count_max: u32 = 64;

pub fn slot_count(comptime unions: []const type) u32 {
    comptime assert(unions.len <= std.math.maxInt(u16));

    var result: u32 = 0;

    for (unions) |Union| result += 1 + @typeInfo(Union).@"union".field_names.len;

    return result;
}

pub fn slot_first(comptime unions: []const type, comptime index: u32) u32 {
    comptime assert(index < unions.len);

    return slot_count(unions[0..index]);
}

pub fn FieldsType(comptime Payload: type, comptime declared: []const type) type {
    comptime assert(Payload != type);
    comptime assert(declared.len <= std.math.maxInt(u32));

    if (Payload == void) return struct {};
    if (kind_module.kind_of(Payload, declared) == .record) return Payload;
    return struct { value: Payload };
}

pub fn member_name(comptime tag: []const u8) [:0]const u8 {
    comptime assert(tag.len > 0);
    comptime assert(std.mem.findScalar(u8, tag, 0) == null);

    return comptime result: {
        var text: [:0]const u8 = "";
        var upper = true;

        for (tag) |character| {
            if (character == '_') {
                upper = true;
            } else {
                const letter = if (upper) std.ascii.toUpper(character) else character;

                text = text ++ .{letter};
                upper = false;
            }
        }

        break :result text;
    };
}

pub fn fields_hashable(comptime Fields: type, comptime declared: []const type) bool {
    comptime assert(@typeInfo(Fields) == .@"struct");
    comptime assert(declared.len <= std.math.maxInt(u32));

    for (@typeInfo(Fields).@"struct".field_types) |Field| {
        if (kind_module.kind_of(Field, declared) == .class_value) return false;
    }

    return true;
}

pub fn unions_check(comptime module: registry.Module) void {
    comptime assert(module.name.len > 0);
    comptime assert(module.unions.len <= registry.union_count_max);

    const declared = module.classes ++ module.unions;

    for (module.unions) |Union| {
        if (@typeInfo(Union) != .@"union") {
            @compileError("lacuna: '" ++ @typeName(Union) ++ "' in .unions is not a union");
        }

        if (@typeInfo(Union).@"union".tag_type == null) {
            @compileError("lacuna: the union '" ++ @typeName(Union) ++ "' must be tagged");
        }

        const structure = @typeInfo(Union).@"union";

        if (structure.field_names.len > variant_count_max) {
            @compileError("lacuna: the union '" ++ @typeName(Union) ++ "' has too many variants");
        }

        for (structure.field_names, structure.field_types) |tag, Payload| {
            payload_check(Union, tag, Payload, declared);
        }
    }
}

fn payload_check(
    comptime Union: type,
    comptime tag: []const u8,
    comptime Payload: type,
    comptime declared: []const type,
) void {
    comptime assert(@typeInfo(Union) == .@"union");
    comptime assert(tag.len > 0);
    comptime assert(declared.len <= std.math.maxInt(u32));

    const label = @typeName(Union) ++ "." ++ tag;

    if (Payload == void) return;

    if (@typeInfo(Payload) == .@"union") {
        @compileError("lacuna: the variant '" ++ label ++ "' holds the union '" ++
            @typeName(Payload) ++ "', which a variant class cannot nest");
    }

    switch (kind_module.kind_of(Payload, declared)) {
        .record => {
            for (@typeInfo(Payload).@"struct".field_names) |field| {
                signature_module.identifier_check(field);
                scalar_check(label ++ "." ++ field, @FieldType(Payload, field), declared);
            }
        },
        .class_value => {
            if (@hasDecl(Payload, "extends")) {
                @compileError("lacuna: the variant '" ++ label ++ "' holds a class that " ++
                    "extends another, which a variant class cannot own");
            }
        },
        else => scalar_check(label, Payload, declared),
    }
}

fn scalar_check(
    comptime label: []const u8,
    comptime T: type,
    comptime declared: []const type,
) void {
    comptime assert(label.len > 0);
    comptime assert(T != type);
    comptime assert(declared.len <= std.math.maxInt(u32));

    switch (kind_module.kind_of(T, declared)) {
        .boolean, .complex, .date, .datetime, .decimal, .duration, .enumeration => {},
        .float, .integer, .text_owned, .bytes_owned, .time, .uuid => {},
        .optional => scalar_check(label, @typeInfo(T).optional.child, declared),
        else => @compileError("lacuna: the variant field '" ++ label ++ "' holds '" ++
            @typeName(T) ++ "', which a variant class cannot own"),
    }
}

pub fn VariantType(comptime Binding: type, comptime Union: type) type {
    const name = from_python_module.class_name(Union);
    const structure = @typeInfo(Union).@"union";

    comptime signature_module.identifier_check(name);
    comptime assert(structure.tag_type != null);

    return struct {
        pub const python_name: [:0]const u8 = name;
        pub const qualified_name: [:0]const u8 = Binding.name ++ "." ++ name;
        pub const count: u32 = structure.field_names.len;

        const Storage = struct {
            value: Union,
        };

        const Allocate = *const fn (*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject;
        const Free = *const fn (?*anyopaque) callconv(.c) void;

        const storage_offset: u32 = std.mem.alignForward(
            u32,
            @sizeOf(c.PyObject_Header),
            @alignOf(Storage),
        );

        const basic_size: u32 = storage_offset + @sizeOf(Storage);

        const base_doc: [:0]const u8 = if (@hasDecl(Union, "doc"))
            signature_module.terminated(Union.doc)
        else
            "";

        const base_slots = [_]c.PyType_Slot{
            .{ .slot = c.Py_tp_doc, .pfunc = base_doc.ptr },
            .{ .slot = 0, .pfunc = null },
        };

        pub const base_specification: c.PyType_Spec = .{
            .name = qualified_name,
            .basicsize = @sizeOf(c.PyObject_Header),
            .itemsize = 0,
            .flags = c.Py_TPFLAGS_DEFAULT | c.Py_TPFLAGS_BASETYPE |
                c.Py_TPFLAGS_DISALLOW_INSTANTIATION,
            .slots = &base_slots,
        };

        comptime {
            assert(basic_size <= std.math.maxInt(c_int));
            assert(storage_offset >= @sizeOf(c.PyObject_Header));
            assert(count > 0);
        }

        pub fn storage_of(object: *c.PyObject) *Storage {
            assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
            assert(python.type_borrowed(object) != object);

            return python.storage_at(Storage, object, storage_offset);
        }

        pub fn allocate(class: *c.PyObject, value: *const Union) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(python.class_is(class));

            const slot = c.PyType_GetSlot(class, c.Py_tp_alloc) orelse return null;
            const function: Allocate = @ptrCast(@alignCast(slot));
            const object = function(class, 0) orelse return null;

            storage_of(object).value = value.*;

            assert(python.type_borrowed(object) == class);

            return object;
        }

        pub fn MemberType(comptime tag_index: u32) type {
            comptime assert(tag_index < count);

            const tag = structure.field_names[tag_index];
            const Payload = structure.field_types[tag_index];
            const Fields = FieldsType(Payload, Binding.declared);
            const fields = @typeInfo(Fields).@"struct".field_names;
            const member = member_name(tag);
            const label: [:0]const u8 = name ++ "." ++ member;
            const Signature: ?type = if (fields.len == 0) null else Fields;
            const signature = signature_module.text_signature(member, .class, Signature);
            const hashable = comptime fields_hashable(Fields, Binding.declared);

            return struct {
                pub const python_name: [:0]const u8 = member;
                pub const qualified: [:0]const u8 = label;
                pub const field_names = fields;

                const doc: [:0]const u8 = signature_module.terminated(signature);

                const getsets: [fields.len + 1]c.PyGetSetDef = getsets: {
                    var result: [fields.len + 1]c.PyGetSetDef = undefined;

                    for (fields, 0..) |field, index| {
                        result[index] = FieldType(field).definition;
                    }

                    result[fields.len] = std.mem.zeroes(c.PyGetSetDef);

                    break :getsets result;
                };

                const methods = [_]c.PyMethodDef{
                    .{
                        .ml_name = "__reduce__",
                        .ml_meth = &reduce,
                        .ml_flags = c.METH_NOARGS,
                        .ml_doc = "__reduce__($self, /)\n--\n\nPickle the variant by its fields.",
                    },
                    std.mem.zeroes(c.PyMethodDef),
                };

                const hash_slots = if (hashable)
                    [_]c.PyType_Slot{.{ .slot = c.Py_tp_hash, .pfunc = &hash }}
                else
                    [_]c.PyType_Slot{};

                const slots = [_]c.PyType_Slot{
                    .{ .slot = c.Py_tp_dealloc, .pfunc = &dealloc },
                    .{ .slot = c.Py_tp_doc, .pfunc = doc.ptr },
                    .{ .slot = c.Py_tp_getset, .pfunc = &getsets },
                    .{ .slot = c.Py_tp_methods, .pfunc = &methods },
                    .{ .slot = c.Py_tp_new, .pfunc = &new },
                    .{ .slot = c.Py_tp_repr, .pfunc = &representation },
                    .{ .slot = c.Py_tp_richcompare, .pfunc = &compare },
                } ++ hash_slots ++ [_]c.PyType_Slot{.{ .slot = 0, .pfunc = null }};

                pub const specification: c.PyType_Spec = .{
                    .name = Binding.name ++ "." ++ member,
                    .basicsize = basic_size,
                    .itemsize = 0,
                    .flags = c.Py_TPFLAGS_DEFAULT,
                    .slots = &slots,
                };

                pub fn payload_of(fields_value: *const Fields) Union {
                    comptime assert(@sizeOf(Union) > 0);
                    assert(@intFromPtr(fields_value) % @alignOf(Fields) == 0);

                    if (Payload == void) return @unionInit(Union, tag, {});
                    if (Fields == Payload) return @unionInit(Union, tag, fields_value.*);
                    return @unionInit(Union, tag, fields_value.value);
                }

                pub fn fields_of(value: *const Union) Fields {
                    assert(std.mem.eql(u8, @tagName(value.*), tag));
                    comptime assert(@typeInfo(Fields) == .@"struct");

                    const payload = @field(value.*, tag);

                    if (Payload == void) return .{};
                    if (Fields == Payload) return payload;
                    return .{ .value = payload };
                }

                fn state_of(object: *c.PyObject) *const Binding.State {
                    const class = python.type_borrowed(object);

                    assert(python.class_is(class));
                    assert(class != object);

                    return Binding.State.of_class(class);
                }

                fn new(
                    class: *c.PyObject,
                    arguments: *c.PyObject,
                    keywords: ?*c.PyObject,
                ) callconv(.c) ?*c.PyObject {
                    assert(python.has_flag(arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
                    assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

                    const state = Binding.State.of_class(class);
                    const invocation: Call = .tuple(arguments, keywords);
                    const counts = comptime @import("invoke.zig").scope_counts(Binding, Fields);

                    var objects: [counts.holders]*c.PyObject = undefined;
                    var sections: [counts.sections]@import("critical.zig").Section = undefined;
                    var views: [counts.views]c.Py_buffer = undefined;

                    var scope: Scope = .init(.{
                        .objects = &objects,
                        .sections = &sections,
                        .views = &views,
                    });

                    defer scope.release();

                    const fields_value: Fields = if (fields.len == 0) empty: {
                        arguments_module.bind_none(label, &state.builtins, &invocation) catch {
                            return null;
                        };

                        break :empty .{};
                    } else arguments_module.bind(
                        Binding,
                        Fields,
                        label,
                        state,
                        &invocation,
                        &scope,
                    ) catch return null;

                    const value = payload_of(&fields_value);

                    return allocate(class, &value);
                }

                fn dealloc(object: *c.PyObject) callconv(.c) void {
                    const class = python.type_borrowed(object);
                    const slot = c.PyType_GetSlot(class, c.Py_tp_free);

                    assert(slot != null);
                    assert(python.class_is(class));

                    const free: Free = @ptrCast(@alignCast(slot.?));

                    free(object);
                    c.Py_DecRef(class);
                }

                fn tuple_of(object: *c.PyObject) ?*c.PyObject {
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    const state = state_of(object);
                    const fields_value = fields_of(&storage_of(object).value);
                    const result = c.PyTuple_New(fields.len) orelse return null;

                    inline for (fields, 0..) |field, index| {
                        const Field = @FieldType(Fields, field);

                        const item = to_python_module.to_python(
                            Binding,
                            Field,
                            state,
                            &@field(fields_value, field),
                        ) catch {
                            c.Py_DecRef(result);

                            return null;
                        };

                        const status = c.PyTuple_SetItem(result, index, item);

                        assert(status == 0);
                    }

                    return result;
                }

                fn representation(object: *c.PyObject) callconv(.c) ?*c.PyObject {
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    assert(python.class_is(python.type_borrowed(object)));

                    const items = tuple_of(object) orelse return null;
                    defer c.Py_DecRef(items);

                    const format = comptime representation_format();
                    const size: c.Py_ssize_t = @intCast(format.len);
                    const template = c.PyUnicode_FromStringAndSize(format.ptr, size) orelse {
                        return null;
                    };

                    defer c.Py_DecRef(template);

                    const method = c.PyObject_GetAttrString(template, "format") orelse return null;
                    defer c.Py_DecRef(method);

                    return c.PyObject_Call(method, items, null);
                }

                fn representation_format() []const u8 {
                    comptime assert(label.len > 0);
                    comptime assert(fields.len <= signature_module.argument_count_max);

                    var result: []const u8 = label ++ "(";

                    for (fields, 0..) |field, index| {
                        const separator = if (index == 0) "" else ", ";

                        result = result ++ separator ++ field ++ "={!r}";
                    }

                    return result ++ ")";
                }

                fn compare(
                    object: *c.PyObject,
                    other: *c.PyObject,
                    operation: c_int,
                ) callconv(.c) ?*c.PyObject {
                    assert(operation >= c.Py_LT);
                    assert(operation <= c.Py_GE);

                    const state = state_of(object);
                    const refused = python.reference_new(state.builtins.get(.not_implemented));

                    if (operation != c.Py_EQ) {
                        if (operation != c.Py_NE) return refused;
                    }

                    if (python.type_borrowed(other) != python.type_borrowed(object)) return refused;

                    c.Py_DecRef(refused);

                    const left = tuple_of(object) orelse return null;
                    defer c.Py_DecRef(left);

                    const right = tuple_of(other) orelse return null;
                    defer c.Py_DecRef(right);

                    const equal = c.PyObject_RichCompareBool(left, right, c.Py_EQ);
                    if (equal < 0) return null;

                    const result = (equal == 1) == (operation == c.Py_EQ);

                    return c.PyBool_FromLong(@intFromBool(result));
                }

                fn hash(object: *c.PyObject) callconv(.c) c.Py_hash_t {
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    const items = tuple_of(object) orelse return -1;
                    defer c.Py_DecRef(items);

                    const class = python.type_borrowed(object);
                    const keyed = c.PyTuple_New(2) orelse return -1;
                    defer c.Py_DecRef(keyed);

                    const first = c.PyTuple_SetItem(keyed, 0, python.reference_new(class));
                    const second = c.PyTuple_SetItem(keyed, 1, python.reference_new(items));

                    assert(first == 0);
                    assert(second == 0);

                    return c.PyObject_Hash(keyed);
                }

                fn reduce(object: *c.PyObject, ignored: ?*c.PyObject) callconv(.c) ?*c.PyObject {
                    assert(ignored == null);
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    const state = state_of(object);
                    const class = python.type_borrowed(object);
                    const module = c.PyType_GetModule(class) orelse return null;
                    const restorer = c.PyObject_GetAttrString(module, "_lacuna_restore") orelse {
                        return null;
                    };

                    defer c.Py_DecRef(restorer);

                    const fields_value = fields_of(&storage_of(object).value);
                    const dictionary = to_python_module.record_fields(
                        Binding,
                        Fields,
                        state,
                        &fields_value,
                    ) catch return null;

                    defer c.Py_DecRef(dictionary);

                    return c.Py_BuildValue("(O(OO))", restorer, class, dictionary);
                }

                pub fn restore(
                    state: *const Binding.State,
                    restoration: Restoration,
                ) ?*c.PyObject {
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    assert(python.class_is(restoration.class));

                    const class = restoration.class;
                    const dictionary = restoration.fields;

                    const holders = comptime scope_module.record_holder_count(
                        Fields,
                        Binding.declared,
                    );

                    var objects: [holders]*c.PyObject = undefined;

                    var scope: Scope = .init(.{
                        .objects = &objects,
                        .sections = &.{},
                        .views = &.{},
                    });

                    defer scope.release();

                    const fields_value = from_python_module.record_restore(
                        Binding,
                        Fields,
                        label ++ ".__reduce__() state",
                        state,
                        dictionary,
                        &scope,
                    ) catch return null;

                    const value = payload_of(&fields_value);

                    return allocate(class, &value);
                }

                fn FieldType(comptime field: [:0]const u8) type {
                    comptime assert(field.len > 0);
                    comptime assert(@hasField(Fields, field));

                    const Field = @FieldType(Fields, field);

                    return struct {
                        const definition: c.PyGetSetDef = .{
                            .name = field,
                            .get = &get,
                            .set = null,
                            .doc = null,
                            .closure = null,
                        };

                        fn get(
                            object: *c.PyObject,
                            closure: ?*anyopaque,
                        ) callconv(.c) ?*c.PyObject {
                            assert(closure == null);
                            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                            const state = state_of(object);
                            const fields_value = fields_of(&storage_of(object).value);

                            return to_python_module.to_python(
                                Binding,
                                Field,
                                state,
                                &@field(fields_value, field),
                            ) catch null;
                        }
                    };
                }
            };
        }
    };
}
