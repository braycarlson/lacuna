const std = @import("std");

const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const critical = @import("critical.zig");
const exception = @import("exception.zig");
const from_python_module = @import("from_python.zig");
const instance = @import("instance.zig");
const invoke_module = @import("invoke.zig");
const kind_module = @import("kind.zig");
const pending = @import("pending.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const slot = @import("slot.zig");
const to_python_module = @import("to_python.zig");
const value_module = @import("value.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const Scope = scope_module.Scope;

pub const Access = enum {
    read,
    read_write,
};

pub const Member = enum {
    constructor,
    creator,
    destructor,
    method,
    property,
    reserved,
    setter,
    skipped,
    slot,
    static,
};

pub const reserved_names = [_][]const u8{
    "constants",
    "deprecated",
    "derive",
    "dictionary",
    "doc",
    "docs",
    "extends",
    "fields",
    "generic",
    "mapping",
    "metaclass",
    "names",
    "pickle",
    "properties",
    "python_name",
    "sequence",
    "setters",
    "static_methods",
    "subclassable",
    "weakref",
};

pub fn member_of(comptime Class: type, comptime name: []const u8) Member {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    inline for (reserved_names) |reserved| {
        if (std.mem.eql(u8, name, reserved)) return .reserved;
    }

    const Declaration = @TypeOf(@field(Class, name));
    if (Declaration == type) return .skipped;

    if (@typeInfo(Declaration) != .@"fn") {
        @compileError("lacuna: the declaration '" ++ @typeName(Class) ++ "." ++ name ++
            "' is neither a function nor a type");
    }

    if (std.mem.eql(u8, name, "init")) return .constructor;
    if (std.mem.eql(u8, name, "__new__")) return .creator;
    if (std.mem.eql(u8, name, "deinit")) return .destructor;
    if (slot.is_slot_name(name)) return .slot;
    if (property_listed(Class, name)) return .property;
    if (setter_listed(Class, name)) return .setter;
    if (static_listed(Class, name)) return .static;
    return .method;
}

pub fn static_listed(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "static_methods")) return false;

    inline for (Class.static_methods) |listed| {
        if (std.mem.eql(u8, @tagName(listed), name)) return true;
    }

    return false;
}

pub const MetaclassSource = union(enum) {
    native: type,
    python: Path,

    pub const Path = struct {
        module: [:0]const u8,
        name: [:0]const u8,
    };
};

pub fn metaclass_of(comptime Class: type) ?MetaclassSource {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "metaclass")) return null;

    const Declared = @TypeOf(Class.metaclass);
    if (Declared == type) return .{ .native = Class.metaclass };

    const text: []const u8 = Class.metaclass;
    const problem = "lacuna: the metaclass of '" ++ @typeName(Class) ++ "' is '" ++ text ++
        "'; name a Python metaclass as 'module.Name'";

    const split = std.mem.findScalarLast(u8, text, '.') orelse @compileError(problem);

    const part_count = std.mem.countScalar(u8, text, '.') + 1;

    var parts = std.mem.splitScalar(u8, text, '.');

    for (0..part_count) |_| {
        const part = parts.next().?;
        if (part.len == 0) @compileError(problem);

        signature_module.identifier_check(part);
    }

    const rest = parts.next();

    assert(rest == null);
    assert(split > 0);
    assert(split + 1 < text.len);

    return .{ .python = .{
        .module = signature_module.terminated(text[0..split]),
        .name = signature_module.terminated(text[split + 1 ..]),
    } };
}

pub fn metaclass_check(comptime Class: type, comptime classes: []const type) void {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(classes.len <= @import("registry.zig").class_count_max);

    const source = metaclass_of(Class) orelse return;

    if (!@import("native.zig").available) {
        @compileError(std.fmt.comptimePrint("lacuna: the class '{s}' declares a metaclass, " ++
            "which needs Python 3.12; this build's floor is Python {d}.{d}", .{
            @typeName(Class),
            3,
            c.stable_minor,
        }));
    }

    const Meta = switch (source) {
        .native => |Known| Known,
        .python => return,
    };

    if (!@import("native.zig").metaclass_is(Meta)) {
        @compileError("lacuna: the metaclass of '" ++ @typeName(Class) ++ "' is '" ++
            @typeName(Meta) ++ "', which does not extend lacuna.Native.type");
    }

    const meta_index = kind_module.class_index(Meta, classes) orelse {
        @compileError("lacuna: the metaclass of '" ++ @typeName(Class) ++ "' is '" ++
            @typeName(Meta) ++ "', which the module does not declare");
    };

    const index = kind_module.class_index(Class, classes).?;

    if (meta_index > index) {
        @compileError("lacuna: the metaclass '" ++ @typeName(Meta) ++ "' must come before '" ++
            @typeName(Class) ++ "' in .classes");
    }

    assert(meta_index < index);
}

pub fn creator_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "__new__")) return;

    if (@hasDecl(Class, "init")) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' declares both init " ++
            "and __new__; __new__ builds its instances with lacuna.TypeObject.instance_new");
    }

    if (@import("native.zig").native_of(Class) != null) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends a native base, " ++
            "so it is constructed by init and cannot declare __new__");
    }

    const signature = signature_module.signature_of(
        @TypeOf(Class.__new__),
        Class,
        "__new__",
    );

    if (signature.receiver != .none) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__new__' takes an instance, " ++
            "which does not exist until __new__ returns it");
    }

    if (signature.Payload != value_module.Reference) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__new__' returns '" ++
            @typeName(signature.Payload) ++ "'; it returns the instance as a lacuna.Reference");
    }

    assert(!@hasDecl(Class, "init"));
}

pub fn subclass_hook_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "__init_subclass__")) return;

    const subclassable = @hasDecl(Class, "subclassable") and Class.subclassable;

    if (!subclassable) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++
            "' defines __init_subclass__ but is not subclassable, so it never runs");
    }

    const signature = signature_module.signature_of(
        @TypeOf(Class.__init_subclass__),
        Class,
        "__init_subclass__",
    );

    if (signature.receiver != .none) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__init_subclass__' takes an " ++
            "instance; it receives the new subclass as a lacuna.TypeObject");
    }

    assert(subclassable);
}

pub fn setter_listed(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "setters")) return false;

    inline for (@typeInfo(@TypeOf(Class.setters)).@"struct".field_names) |property| {
        if (std.mem.eql(u8, @tagName(@field(Class.setters, property)), name)) return true;
    }

    return false;
}

pub fn setter_of(comptime Class: type, comptime property: []const u8) ?[:0]const u8 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(property.len > 0);

    if (!@hasDecl(Class, "setters")) return null;
    if (!@hasField(@TypeOf(Class.setters), property)) return null;
    return @tagName(@field(Class.setters, property));
}

pub fn setters_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "setters")) return;

    for (@typeInfo(@TypeOf(Class.setters)).@"struct".field_names) |property| {
        if (!property_listed(Class, property)) {
            @compileError("lacuna: the setters of '" ++ @typeName(Class) ++ "' name '" ++
                property ++ "', which is not a property");
        }

        if (!@hasDecl(Class, @tagName(@field(Class.setters, property)))) {
            @compileError("lacuna: the setter of '" ++ @typeName(Class) ++ "." ++ property ++
                "' is not a function of the class");
        }
    }
}

pub fn generic(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "generic")) return false;

    comptime assert(@TypeOf(Class.generic) == bool);

    return Class.generic;
}

pub const generic_definition: c.PyMethodDef = .{
    .ml_name = "__class_getitem__",
    .ml_meth = c.Py_GenericAlias,
    .ml_flags = c.METH_O | c.METH_CLASS,
    .ml_doc = "__class_getitem__($cls, item, /)\n--\n\nSee PEP 585.",
};

pub fn picklable(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    return @hasDecl(Class, "pickle") and Class.pickle;
}

pub fn property_listed(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "properties")) return false;

    inline for (Class.properties) |property| {
        if (std.mem.eql(u8, @tagName(property), name)) return true;
    }

    return false;
}

pub fn doc_of(comptime Namespace: type, comptime name: []const u8) []const u8 {
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(Namespace) == .@"struct");

    if (!@hasDecl(Namespace, "docs")) return "";

    const Docs = @TypeOf(Namespace.docs);

    inline for (@typeInfo(Docs).@"struct".field_names) |field| {
        if (!@hasDecl(Namespace, field)) {
            if (!@hasField(Namespace, field)) {
                @compileError("lacuna: the docs of '" ++ @typeName(Namespace) ++ "' name '" ++
                    field ++ "', which it does not declare");
            }
        }
    }

    if (@hasField(Docs, name)) return @field(Namespace.docs, name);
    return "";
}

pub fn deprecation_of(comptime Namespace: type, comptime name: []const u8) ?[:0]const u8 {
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(Namespace) == .@"struct");

    if (!@hasDecl(Namespace, "deprecated")) return null;
    if (!@hasField(@TypeOf(Namespace.deprecated), name)) return null;
    return signature_module.terminated(@field(Namespace.deprecated, name));
}

pub fn deprecated_check(comptime Namespace: type, comptime methods: bool) void {
    comptime assert(@typeInfo(Namespace) == .@"struct");

    if (!@hasDecl(Namespace, "deprecated")) return;

    for (@typeInfo(@TypeOf(Namespace.deprecated)).@"struct".field_names) |field| {
        const declared = @hasDecl(Namespace, field) and
            @typeInfo(@TypeOf(@field(Namespace, field))) == .@"fn";

        const callable = declared and (!methods or switch (member_of(Namespace, field)) {
            .method, .static => true,
            else => false,
        });

        if (!callable) {
            @compileError("lacuna: the deprecated list of '" ++ @typeName(Namespace) ++
                "' names '" ++ field ++ "', which is not a " ++
                (if (methods) "method" else "function"));
        }

        comptime assert(@field(Namespace.deprecated, field).len > 0);
    }
}

pub fn method_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@typeInfo(Class).@"struct".decl_names.len <= 4096);

    var result: u32 = 0;

    inline for (@typeInfo(Class).@"struct".decl_names) |name| {
        switch (member_of(Class, name)) {
            .method, .static => result += 1,
            else => {},
        }
    }

    if (picklable(Class)) result += 1;
    if (generic(Class)) result += 1;
    if (@hasDecl(Class, "__getattr__")) result += 2;
    if (@hasDecl(Class, "__ipow__")) result += 1;

    return result;
}

pub fn getset_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(!@hasDecl(Class, "fields") or @typeInfo(@TypeOf(Class.fields)) == .@"struct");

    var result: u32 = 0;

    if (@hasDecl(Class, "fields")) {
        result += @typeInfo(@TypeOf(Class.fields)).@"struct".field_names.len;
    }

    if (@hasDecl(Class, "properties")) result += Class.properties.len;

    return result;
}

pub const Restoration = struct {
    class: *c.PyObject,
    fields: *c.PyObject,
};

pub const restore_name = "_lacuna_restore";
pub const deprecation_level: u32 = 1;

pub fn ClassType(comptime Binding: type, comptime Class: type) type {
    const name = from_python_module.class_name(Class);
    const Instance = instance.InstanceType(Class);
    const Slots = slot.SlotsType(Binding, Class);

    comptime signature_module.identifier_check(name);
    comptime assert(@typeInfo(Class) == .@"struct");

    return struct {
        pub const python_name: [:0]const u8 = name;
        pub const qualified_name: [:0]const u8 = Binding.name ++ "." ++ name;
        const created = @hasDecl(Class, "__new__");
        const constructible = @hasDecl(Class, "init") or created;

        const constructor_arguments = if (created)
            signature_module.signature_of(@TypeOf(Class.__new__), Class, "__new__").Arguments
        else if (constructible)
            signature_module.signature_of(@TypeOf(Class.init), Class, "init").Arguments
        else
            null;

        const doc: [:0]const u8 = signature_module.terminated((if (constructible)
            signature_module.text_signature(name, .class, constructor_arguments)
        else
            "") ++ (if (@hasDecl(Class, "doc")) Class.doc else ""));

        const methods: [method_count(Class) + 1]c.PyMethodDef = methods: {
            var result: [method_count(Class) + 1]c.PyMethodDef = undefined;
            var index: u32 = 0;

            for (@typeInfo(Class).@"struct".decl_names) |member| {
                switch (member_of(Class, member)) {
                    .method => {
                        result[index] = MethodType(member).definition;
                        index += 1;
                    },
                    .static => {
                        result[index] = StaticType(member).definition;
                        index += 1;
                    },
                    else => {},
                }
            }

            if (picklable(Class)) {
                result[index] = reduce_definition;
                index += 1;
            }

            if (generic(Class)) {
                result[index] = generic_definition;
                index += 1;
            }

            if (@hasDecl(Class, "__getattr__")) {
                result[index] = Slots.attribute_method;
                result[index + 1] = Slots.generic_method;
                index += 2;
            }

            if (@hasDecl(Class, "__ipow__")) {
                result[index] = Slots.inplace_power_method;
                index += 1;
            }

            result[index] = std.mem.zeroes(c.PyMethodDef);

            break :methods result;
        };

        const dictionary_declared = Instance.dictionary_offset != null and
            Instance.base_dictionary_offset == null;
        const getset_total = getset_count(Class) + @intFromBool(dictionary_declared);

        const dictionary_definition: c.PyGetSetDef = .{
            .name = "__dict__",
            .get = c.PyObject_GenericGetDict,
            .set = c.PyObject_GenericSetDict,
            .doc = null,
            .closure = null,
        };

        const getsets: [getset_total + 1]c.PyGetSetDef = getsets: {
            var result: [getset_total + 1]c.PyGetSetDef = undefined;
            var index: u32 = 0;

            if (@hasDecl(Class, "fields")) {
                for (@typeInfo(@TypeOf(Class.fields)).@"struct".field_names) |field| {
                    result[index] = FieldType(field, @field(Class.fields, field)).definition;
                    index += 1;
                }
            }

            if (@hasDecl(Class, "properties")) {
                for (Class.properties) |property| {
                    result[index] = PropertyType(@tagName(property)).definition;
                    index += 1;
                }
            }

            if (dictionary_declared) {
                result[index] = dictionary_definition;
                index += 1;
            }

            result[index] = std.mem.zeroes(c.PyGetSetDef);

            break :getsets result;
        };

        const sentinel_slot = [_]c.PyType_Slot{.{ .slot = 0, .pfunc = null }};

        const type_slots = base_slots ++ constructor_slots ++ member_slots ++ Slots.slots ++
            sentinel_slot;

        const member_count: u32 = @as(u32, @intFromBool(Instance.dictionary_offset != null)) +
            @intFromBool(Instance.weaklist_offset != null);

        const members: [member_count + 1]c.PyMemberDef = members: {
            var result: [member_count + 1]c.PyMemberDef = undefined;
            var index: u32 = 0;

            if (Instance.dictionary_offset) |offset| {
                result[index] = member_offset("__dictoffset__", offset);
                index += 1;
            }

            if (Instance.weaklist_offset) |offset| {
                result[index] = member_offset("__weaklistoffset__", offset);
                index += 1;
            }

            result[index] = std.mem.zeroes(c.PyMemberDef);

            break :members result;
        };

        const member_slots = if (member_count > 0)
            [_]c.PyType_Slot{.{ .slot = c.Py_tp_members, .pfunc = &members }}
        else
            [_]c.PyType_Slot{};

        const constructor_slots = if (created)
            [_]c.PyType_Slot{.{ .slot = c.Py_tp_new, .pfunc = &create }}
        else if (constructible)
            [_]c.PyType_Slot{.{ .slot = c.Py_tp_new, .pfunc = &new }}
        else
            [_]c.PyType_Slot{};

        const native_slots = if (Instance.native_base != null and !Instance.metaclass)
            [_]c.PyType_Slot{.{ .slot = c.Py_tp_init, .pfunc = &native_initialize }}
        else
            [_]c.PyType_Slot{};

        const base_slots = [_]c.PyType_Slot{
            .{ .slot = c.Py_tp_dealloc, .pfunc = &Instance.dealloc },
            .{ .slot = c.Py_tp_doc, .pfunc = doc.ptr },
            .{ .slot = c.Py_tp_methods, .pfunc = &methods },
            .{ .slot = c.Py_tp_getset, .pfunc = &getsets },
        } ++ collector_slots ++ finalizer_slots ++ native_slots;

        const finalizer_slots = if (Instance.finalizer_present)
            [_]c.PyType_Slot{.{ .slot = c.Py_tp_finalize, .pfunc = &finalize }}
        else
            [_]c.PyType_Slot{};

        const collector_slots = if (Instance.collected)
            [_]c.PyType_Slot{
                .{ .slot = c.Py_tp_traverse, .pfunc = &Instance.traverse },
                .{ .slot = c.Py_tp_clear, .pfunc = &Instance.clear },
            }
        else
            [_]c.PyType_Slot{};

        const immutable = !@hasDecl(Class, "constants");

        const flags: c_uint = c.Py_TPFLAGS_DEFAULT |
            (if (immutable) c.Py_TPFLAGS_IMMUTABLETYPE else 0) |
            (if (instantiable) 0 else c.Py_TPFLAGS_DISALLOW_INSTANTIATION) |
            (if (Instance.collected) c.Py_TPFLAGS_HAVE_GC else 0) |
            (if (Instance.subclassable) c.Py_TPFLAGS_BASETYPE else 0) |
            (if (slot.sequence(Class)) c.api_pattern.Py_TPFLAGS_SEQUENCE else 0) |
            (if (mapping) c.api_pattern.Py_TPFLAGS_MAPPING else 0);

        const mapping = @hasDecl(Class, "mapping") and Class.mapping;
        const instantiable = if (constructible) true else Instance.metaclass;

        pub const specification: c.PyType_Spec = .{
            .name = qualified_name,
            .basicsize = Instance.specification_size,
            .itemsize = 0,
            .flags = flags,
            .slots = &type_slots,
        };

        const reduce_definition: c.PyMethodDef = .{
            .ml_name = "__reduce__",
            .ml_meth = &reduce,
            .ml_flags = c.METH_NOARGS,
            .ml_doc = "__reduce__($self, /)\n--\n\nPickle the instance by its fields.",
        };

        pub const pickle_safe: bool = fields_owned(Class, 0) and
            if (Instance.base) |Base| ClassType(Binding, Base).pickle_safe else true;

        comptime {
            assert(@sizeOf(Instance.Storage) > 0);
            assert(type_slots[type_slots.len - 1].slot == 0);

            setters_check(Class);
            creator_check(Class);
            metaclass_check(Class, Binding.classes);
            subclass_hook_check(Class);
            deprecated_check(Class, true);
            @import("native.zig").native_check(Class, name);
            signature_module.names_check(Class);
            @import("derive.zig").derive_check(Class, name);

            if (mapping) {
                if (slot.sequence(Class)) {
                    @compileError("lacuna: the class '" ++ name ++
                        "' declares both sequence and mapping");
                }
            }

            if (Instance.base) |Base| {
                if (picklable(Base)) {
                    if (!picklable(Class)) {
                        @compileError("lacuna: the class '" ++ name ++
                            "' extends the picklable '" ++ @typeName(Base) ++
                            "', so it must declare pickle = true as well");
                    }
                }

                if (kind_module.class_index(Base, Binding.classes)) |base_index| {
                    if (base_index >= kind_module.class_index(Class, Binding.classes).?) {
                        @compileError("lacuna: the class '" ++ name ++ "' extends '" ++
                            from_python_module.class_name(Base) ++
                            "', which must come before it in .classes");
                    }
                } else {
                    @compileError("lacuna: the class '" ++ name ++ "' extends '" ++
                        @typeName(Base) ++ "', which the module does not declare");
                }

                if (@hasDecl(Class, "init")) {
                    const Init = @TypeOf(Class.init);
                    const signature = signature_module.signature_of(Init, Class, "init");

                    const levels = signature_module.ancestor_count(Class);
                    const complete = signature.ancestors.len == levels and
                        std.mem.allEqual(signature_module.Receiver, signature.ancestors, .mutable);

                    if (!complete) {
                        @compileError("lacuna: '" ++ name ++ ".init' must take a mutable " ++
                            "pointer to each ancestor, starting with *" ++ @typeName(Base) ++
                            ", after its receiver to initialize them");
                    }
                }
            }

            if (picklable(Class)) {
                if (!pickle_safe) {
                    @compileError("lacuna: the class '" ++ name ++
                        "' holds a field that borrows from Python, so it cannot be pickled");
                }
            }
        }

        fn member_offset(comptime member: [:0]const u8, comptime offset: u32) c.PyMemberDef {
            comptime assert(member.len > 0);
            comptime assert(offset >= @sizeOf(c.PyObject_Header));
            comptime assert(offset < Instance.basic_size);

            return .{
                .name = member,
                .type = c.api_3_12.Py_T_PYSSIZET,
                .offset = offset,
                .flags = c.api_3_12.Py_READONLY,
                .doc = null,
            };
        }

        fn new(
            class: *c.PyObject,
            arguments: *c.PyObject,
            keywords: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            assert(python.has_flag(arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            const defining = Instance.defining_of(class).?;
            const state = Binding.State.of_class(defining);
            const allocation = Instance.allocate_with(class, .{
                .arguments = arguments,
                .keywords = keywords,
            }) catch return null;

            const invocation: Call = .tuple(arguments, keywords);

            assert(!allocation.storage.initialized);

            const receiver: invoke_module.Receiver(Class) = .{
                .data = &allocation.storage.value,
                .object = allocation.object,
            };

            const result = invoke_module.InvokerType(
                Binding,
                Class,
                Class.init,
                qualified_name,
                .held,
            ).invoke(state, receiver, .{ .class = class, .defining = defining }, &invocation);

            if (result) |none| {
                c.Py_DecRef(none);
                Instance.initialized_mark(allocation.object);

                return allocation.object;
            }

            c.Py_DecRef(allocation.object);

            return null;
        }

        fn create(
            class: *c.PyObject,
            arguments: *c.PyObject,
            keywords: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            comptime assert(created);
            assert(python.has_flag(arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            const defining = Instance.defining_of(class).?;
            const state = Binding.State.of_class(defining);
            const invocation: Call = .tuple(arguments, keywords);

            const result = invoke_module.InvokerType(
                Binding,
                Class,
                Class.__new__,
                qualified_name,
                .held,
            ).invoke(state, null, .{ .class = class, .defining = defining }, &invocation) orelse {
                return null;
            };

            if (c.PyType_IsSubtype(python.type_borrowed(result), class) != 0) return result;

            c.Py_DecRef(result);

            python.exception_raise(.{
                .class_name = "TypeError",
                .message = qualified_name ++ ".__new__ returned an object that is not " ++
                    "an instance of the class it was called on",
            });

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            return null;
        }

        fn native_initialize(
            object: *c.PyObject,
            arguments: *c.PyObject,
            keywords: ?*c.PyObject,
        ) callconv(.c) c_int {
            comptime assert(Instance.native_base != null);
            assert(python.has_flag(arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            assert(Instance.owned_by(object));
            assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            return 0;
        }

        fn finalize(object: *c.PyObject) callconv(.c) void {
            comptime assert(Instance.finalizer_present);
            assert(Instance.defining_of(python.type_borrowed(object)) != null);

            const saved = exception.pending_save();
            defer exception.pending_resume(&saved);

            const context: ?value_module.Object = if (Instance.finalizer_detached)
                null
            else
                .{ .pointer = object };

            const levels = comptime signature_module.ancestor_count(Class) + 1;

            inline for (0..levels) |level| {
                const Level = if (level == 0) Class else signature_module.ancestor_of(
                    Class,
                    level - 1,
                );

                deinit_level(Level, object, context);
            }

            assert(!Instance.storage_of(object).initialized);
        }

        fn deinit_level(
            comptime Level: type,
            object: *c.PyObject,
            context: ?value_module.Object,
        ) void {
            comptime assert(@typeInfo(Level) == .@"struct");
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            if (context) |present| assert(present.pointer == object);

            const storage = instance.InstanceType(Level).storage_of(object);
            if (!storage.initialized) return;

            storage.initialized = false;

            if (comptime !@hasDecl(Level, "deinit")) return;

            if (comptime !instance.deinit_fallible(Level)) {
                storage.value.deinit();

                return;
            }

            storage.value.deinit() catch |err| deinit_report(@TypeOf(err), err, object, context);

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        }

        fn deinit_report(
            comptime ErrorSet: type,
            err: ErrorSet,
            object: *c.PyObject,
            context: ?value_module.Object,
        ) void {
            comptime assert(@typeInfo(ErrorSet) == .error_set);
            assert(@errorName(err).len > 0);
            if (context) |present| assert(present.pointer == object);

            const state = state_of(object);

            if (state.builtins.objects[0] == null) {
                python.exception_raise(.{
                    .class_name = "RuntimeError",
                    .message = qualified_name ++ ".deinit failed after the module was cleared",
                });
            } else {
                exception.raise(Binding, state, ErrorSet, err, null);
            }

            if (c.PyErr_Occurred() == null) return;

            pending.unraisable(context);
        }

        fn MethodType(comptime member: [:0]const u8) type {
            comptime assert(member.len > 0);
            comptime assert(@hasDecl(Class, member));

            const function = @field(Class, member);
            const python_member = comptime signature_module.python_name_of(Class, member);
            const signature = signature_module.signature_of(@TypeOf(function), Class, member);
            const deprecation = comptime deprecation_of(Class, member);
            const static = signature.receiver == .none;
            const bound: signature_module.Bound = if (static) .type else .instance;
            const text = signature_module.text_signature(python_member, bound, signature.Arguments);

            const flags_method = c.METH_FASTCALL | c.METH_KEYWORDS | c.METH_METHOD |
                (if (signature.receiver == .none) c.METH_CLASS else 0);

            comptime signature_module.identifier_check(python_member);

            return struct {
                const definition: c.PyMethodDef = .{
                    .ml_name = python_member,
                    .ml_meth = &call,
                    .ml_flags = flags_method,
                    .ml_doc = signature_module.terminated(text ++ doc_of(Class, member)),
                };

                fn call(
                    object: *c.PyObject,
                    defining: *c.PyObject,
                    arguments: ?[*]const *c.PyObject,
                    count: c.Py_ssize_t,
                    names: ?*c.PyObject,
                ) callconv(.c) ?*c.PyObject {
                    assert(Instance.owns(defining));
                    assert(count >= 0);
                    assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
                    assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));

                    if (deprecation) |message| {
                        pending.warn(.deprecation_warning, message, deprecation_level) catch {
                            return null;
                        };
                    }

                    const state = Binding.State.of_class(defining);
                    const vector = python.vector_of(arguments, count, names);
                    const invocation: Call = .fast(vector, count, names);

                    const receiver: ?invoke_module.Receiver(Class) = if (static)
                        null
                    else
                        .{
                            .data = Instance.data_required(object) orelse return null,
                            .object = object,
                        };

                    const context: invoke_module.Context = .{
                        .class = if (static) object else python.type_borrowed(object),
                        .defining = defining,
                    };

                    return invoke_module.InvokerType(
                        Binding,
                        Class,
                        function,
                        member,
                        .held,
                    ).invoke(state, receiver, context, &invocation);
                }
            };
        }

        fn StaticType(comptime member: [:0]const u8) type {
            comptime assert(member.len > 0);
            comptime assert(@hasDecl(Class, member));

            const function = @field(Class, member);
            const python_member = comptime signature_module.python_name_of(Class, member);
            const signature = signature_module.signature_of(@TypeOf(function), Class, member);
            const Arguments = signature.Arguments;
            const text = signature_module.text_signature(python_member, .class, Arguments);
            const deprecation = comptime deprecation_of(Class, member);

            if (signature.receiver != .none) {
                @compileError("lacuna: the static method '" ++ @typeName(Class) ++ "." ++
                    member ++ "' must not take a receiver");
            }

            if (signature.context_count() > 0) {
                @compileError("lacuna: the static method '" ++ @typeName(Class) ++ "." ++
                    member ++ "' takes a context; leave it out of static_methods to make " ++
                    "it a class method");
            }

            comptime signature_module.identifier_check(python_member);

            return struct {
                const definition: c.PyMethodDef = .{
                    .ml_name = python_member,
                    .ml_meth = &call,
                    .ml_flags = c.METH_FASTCALL | c.METH_KEYWORDS | c.METH_STATIC,
                    .ml_doc = signature_module.terminated(text ++ doc_of(Class, member)),
                };

                fn call(
                    unbound: ?*c.PyObject,
                    arguments: ?[*]const *c.PyObject,
                    count: c.Py_ssize_t,
                    names: ?*c.PyObject,
                ) callconv(.c) ?*c.PyObject {
                    assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
                    assert(unbound == null);
                    assert(count >= 0);
                    assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));

                    if (deprecation) |message| {
                        pending.warn(.deprecation_warning, message, deprecation_level) catch {
                            return null;
                        };
                    }

                    const state = Binding.state_current() orelse return null;
                    const vector = python.vector_of(arguments, count, names);
                    const invocation: Call = .fast(vector, count, names);

                    return invoke_module.InvokerType(
                        Binding,
                        Class,
                        function,
                        member,
                        .held,
                    ).invoke(state, null, .none, &invocation);
                }
            };
        }

        fn reduce(object: *c.PyObject, ignored: ?*c.PyObject) callconv(.c) ?*c.PyObject {
            assert(ignored == null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const state = state_of(object);
            const data = Instance.data_required(object) orelse return null;
            const class = python.type_borrowed(object);
            const defining = Instance.defining_of(class).?;
            const module = c.PyType_GetModule(defining) orelse return null;
            const restore = c.PyObject_GetAttrString(module, restore_name) orelse return null;
            defer c.Py_DecRef(restore);

            var section = critical.empty;

            critical.begin(&section, object);

            const converted = if (Instance.base == null)
                to_python_module.record_fields(Binding, Class, state, data)
            else
                LevelsType(Binding, Class).fields_of(state, object);

            critical.end(&section);

            const fields = converted catch return null;
            defer c.Py_DecRef(fields);

            const extra = c.PyObject_GetAttrString(object, "__dict__") orelse dictionary: {
                c.PyErr_Clear();

                break :dictionary null;
            };

            defer if (extra) |present| c.Py_DecRef(present);

            const arguments = tuple_of(.{ class, fields }) orelse return null;
            defer c.Py_DecRef(arguments);

            if (extra) |present| return tuple_of(.{ restore, arguments, present });
            return tuple_of(.{ restore, arguments });
        }

        pub fn restore_into(state: *const Binding.State, restoration: Restoration) ?*c.PyObject {
            comptime assert(picklable(Class));
            assert(Instance.defining_of(restoration.class) != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const class = restoration.class;
            const fields = restoration.fields;
            const Levels = LevelsType(Binding, Class);
            const holders = comptime Levels.holder_count();
            const locks = comptime Levels.section_count();

            var objects: [holders]*c.PyObject = undefined;
            var sections: [locks]critical.Section = undefined;

            var scope: Scope = .init(.{
                .objects = &objects,
                .sections = &sections,
                .views = &.{},
            });

            defer scope.release();

            const restored = Levels.restore(state, fields, &scope) catch return null;
            const allocation = Instance.allocate(class) catch return null;

            Instance.store(allocation, &restored);

            assert(allocation.storage.initialized);

            return allocation.object;
        }

        fn PropertyType(comptime member: [:0]const u8) type {
            comptime assert(member.len > 0);
            comptime assert(@hasDecl(Class, member));

            const function = @field(Class, member);
            const signature = signature_module.signature_of(@TypeOf(function), Class, member);

            if (signature.receiver == .none) {
                @compileError("lacuna: the property '" ++ @typeName(Class) ++ "." ++ member ++
                    "' must take its receiver");
            }

            if (signature.Arguments != null) {
                @compileError("lacuna: the property '" ++ @typeName(Class) ++ "." ++ member ++
                    "' must take no arguments");
            }

            const setter = comptime setter_of(Class, member);

            if (setter) |setter_name| setter_validate(member, setter_name);

            return struct {
                const definition: c.PyGetSetDef = .{
                    .name = signature_module.python_name_of(Class, member),
                    .get = &get,
                    .set = if (setter != null) &set else null,
                    .doc = if (doc_terminated(member)) |text| text.ptr else null,
                    .closure = null,
                };

                fn set(
                    object: *c.PyObject,
                    item: ?*c.PyObject,
                    closure: ?*anyopaque,
                ) callconv(.c) c_int {
                    assert(closure == null);
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    if (item) |given| assert(@intFromPtr(given) % @alignOf(c.PyObject_Header) == 0);

                    const state = state_of(object);

                    const present = item orelse {
                        c.PyErr_SetString(
                            state.builtins.get(.type_error),
                            "cannot delete " ++ qualified_name ++ "." ++ member,
                        );

                        return -1;
                    };

                    const vector = [_]*c.PyObject{present};
                    const invocation: Call = .fast(&vector, 1, null);
                    const defining = Instance.defining_of(python.type_borrowed(object));

                    const receiver: invoke_module.Receiver(Class) = .{
                        .data = Instance.data_required(object) orelse return -1,
                        .object = object,
                    };

                    const result = invoke_module.InvokerType(
                        Binding,
                        Class,
                        @field(Class, setter.?),
                        setter.?,
                        .held,
                    ).invoke(state, receiver, .{ .defining = defining }, &invocation) orelse {
                        return -1;
                    };

                    c.Py_DecRef(result);

                    return 0;
                }

                fn get(object: *c.PyObject, closure: ?*anyopaque) callconv(.c) ?*c.PyObject {
                    const state = state_of(object);
                    const invocation: Call = .fast(&.{}, 0, null);
                    const defining = Instance.defining_of(python.type_borrowed(object));

                    const receiver: invoke_module.Receiver(Class) = .{
                        .data = Instance.data_required(object) orelse return null,
                        .object = object,
                    };

                    assert(closure == null);
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    return invoke_module.InvokerType(
                        Binding,
                        Class,
                        function,
                        member,
                        .held,
                    ).invoke(state, receiver, .{ .defining = defining }, &invocation);
                }
            };
        }

        fn setter_validate(comptime property: []const u8, comptime setter: [:0]const u8) void {
            comptime assert(property.len > 0);
            comptime assert(@hasDecl(Class, setter));

            const signature = signature_module.signature_of(
                @TypeOf(@field(Class, setter)),
                Class,
                setter,
            );

            const label = @typeName(Class) ++ "." ++ setter;

            if (signature.receiver != .mutable) {
                @compileError("lacuna: the setter '" ++ label ++ "' must take *" ++
                    @typeName(Class));
            }

            const Arguments = signature.Arguments orelse {
                @compileError("lacuna: the setter '" ++ label ++ "' must take one argument");
            };

            if (@typeInfo(Arguments).@"struct".field_names.len != 1) {
                @compileError("lacuna: the setter '" ++ label ++ "' must take one argument");
            }

            if (signature.Payload != void) {
                @compileError("lacuna: the setter '" ++ label ++ "' must return void");
            }
        }

        fn FieldType(comptime field: [:0]const u8, comptime access: Access) type {
            comptime assert(@hasField(Class, field));
            comptime assert(field.len > 0);

            const Field = @FieldType(Class, field);
            const label = qualified_name ++ "." ++ field;

            comptime signature_module.identifier_check(field);

            if (access == .read_write) {
                if (Field != value_module.Reference) {
                    if (!owned(Field, 0)) {
                        @compileError("lacuna: the field '" ++ label ++
                            "' borrows from Python and cannot be written");
                    }
                }
            }

            return struct {
                const definition: c.PyGetSetDef = .{
                    .name = signature_module.python_name_of(Class, field),
                    .get = &get,
                    .set = if (access == .read_write) &set else null,
                    .doc = if (doc_terminated(field)) |text| text.ptr else null,
                    .closure = null,
                };

                fn get(object: *c.PyObject, closure: ?*anyopaque) callconv(.c) ?*c.PyObject {
                    const state = state_of(object);
                    const data = Instance.data_required(object) orelse return null;

                    assert(closure == null);
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    var section = critical.empty;

                    critical.begin(&section, object);
                    defer critical.end(&section);

                    return to_python_module.to_python(
                        Binding,
                        Field,
                        state,
                        &@field(data, field),
                    ) catch null;
                }

                fn set(
                    object: *c.PyObject,
                    item: ?*c.PyObject,
                    closure: ?*anyopaque,
                ) callconv(.c) c_int {
                    assert(closure == null);
                    assert(@intFromPtr(item) % @alignOf(*c.PyObject) == 0);

                    const state = state_of(object);
                    const data = Instance.data_required(object) orelse return -1;

                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

                    const present = item orelse {
                        c.PyErr_SetString(
                            state.builtins.get(.type_error),
                            "cannot delete " ++ label,
                        );

                        return -1;
                    };

                    if (Field == value_module.Reference) {
                        var guard = critical.empty;

                        critical.begin(&guard, object);
                        defer critical.end(&guard);

                        if (present == state.builtins.get(.none)) {
                            @field(data, field).release();
                        } else {
                            @field(data, field).assign(.{ .pointer = present });
                        }

                        return 0;
                    }

                    const holders = comptime scope_module.holder_count(Field, Binding.declared, 0);
                    const locks = comptime scope_module.section_count(Field, Binding.declared, 0);

                    var objects: [holders]*c.PyObject = undefined;
                    var sections: [locks]critical.Section = undefined;

                    var scope: Scope = .init(.{
                        .objects = &objects,
                        .sections = &sections,
                        .views = &.{},
                    });

                    defer scope.release();

                    var section = critical.empty;

                    critical.begin(&section, object);
                    defer critical.end(&section);

                    @field(data, field) = from_python_module.from_python(
                        Binding,
                        Field,
                        label,
                        state,
                        present,
                        &scope,
                    ) catch return -1;

                    return 0;
                }
            };
        }

        fn tuple_of(items: anytype) ?*c.PyObject {
            comptime assert(@typeInfo(@TypeOf(items)).@"struct".is_tuple);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const Items = @TypeOf(items);
            const count = @typeInfo(Items).@"struct".field_names.len;
            const result = c.PyTuple_New(count) orelse return null;

            inline for (@typeInfo(Items).@"struct".field_names, 0..) |field, index| {
                const item = python.reference_new(@field(items, field));
                const status = c.PyTuple_SetItem(result, index, item);

                assert(status == 0);
            }

            return result;
        }

        fn doc_terminated(comptime member: []const u8) ?[:0]const u8 {
            comptime assert(member.len > 0);

            const text = doc_of(Class, member);

            comptime assert(text.len < 1 << 20);

            return if (text.len > 0) signature_module.terminated(text) else null;
        }

        fn state_of(object: *c.PyObject) *const Binding.State {
            const class = python.type_borrowed(object);
            const defining = Instance.defining_of(class).?;

            assert(Instance.owns(defining));
            assert(class != object);

            return Binding.State.of_class(defining);
        }

        fn owned(comptime T: type, comptime depth: u32) bool {
            comptime assert(depth < kind_module.depth_max);
            comptime assert(Binding.classes.len > 0);

            return switch (comptime kind_module.kind_of(T, Binding.declared)) {
                .array => owned(@typeInfo(T).array.child, depth + 1),
                .boolean, .class_value, .enumeration, .float, .integer => true,
                .complex, .decimal, .fraction, .ip_address, .slice, .union_class, .uuid => true,
                .class_extended => false,
                .bytes_owned, .date, .datetime, .duration, .text_owned, .time => true,
                .map => owned(T.Key, depth + 1) and owned(T.Value, depth + 1),
                .set => owned(T.Item, depth + 1),
                .variant => variants_owned(T, depth),
                .list => owned(T.Item, depth + 1),
                .optional => owned(@typeInfo(T).optional.child, depth + 1),
                .record, .tuple => fields_owned(T, depth),
                else => false,
            };
        }

        fn variants_owned(comptime T: type, comptime depth: u32) bool {
            comptime assert(@typeInfo(T) == .@"union");
            comptime assert(depth < kind_module.depth_max);

            inline for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) {
                    if (!owned(Payload, depth + 1)) return false;
                }
            }

            return true;
        }

        fn fields_owned(comptime T: type, comptime depth: u32) bool {
            comptime assert(@typeInfo(T) == .@"struct");
            comptime assert(depth < kind_module.depth_max);

            inline for (@typeInfo(T).@"struct".field_types) |Field| {
                if (!owned(Field, depth + 1)) return false;
            }

            return true;
        }
    };
}

const Fill = struct {
    object: *c.PyObject,
    tuple: *c.PyObject,
};

fn LevelsType(comptime Binding: type, comptime Class: type) type {
    const Instance = instance.InstanceType(Class);
    const label = Binding.name ++ "." ++ from_python_module.class_name(Class) ++
        ".__reduce__() state";

    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(label.len > 0);

    return struct {
        const Base = Instance.base;
        const Parent = if (Base) |Known| LevelsType(Binding, Known) else void;
        pub const count: u32 = if (Base != null) Parent.count + 1 else 1;

        pub fn holder_count() u32 {
            const own = scope_module.record_holder_count(Class, Binding.declared);
            const result = own + if (Base != null) Parent.holder_count() else 0;

            assert(result <= count * scope_module.holder_count_max);

            return result;
        }

        pub fn section_count() u32 {
            const own = scope_module.record_section_count(Class, Binding.declared);
            const result = own + if (Base != null) Parent.section_count() else 0;

            assert(result <= count * scope_module.holder_count_max);

            return result;
        }

        pub fn fields_of(
            state: *const Binding.State,
            object: *c.PyObject,
        ) error{Raised}!*c.PyObject {
            comptime assert(Base != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const tuple = c.PyTuple_New(count) orelse return error.Raised;
            errdefer c.Py_DecRef(tuple);

            try fill(state, .{ .object = object, .tuple = tuple }, 0);

            return tuple;
        }

        fn fill(state: *const Binding.State, target: Fill, comptime index: u32) error{Raised}!void {
            comptime assert(index < 64);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(c.PyTuple_Size(target.tuple) > index);

            const data = Instance.data_required(target.object) orelse return error.Raised;
            const fields = try to_python_module.record_fields(Binding, Class, state, data);
            const status = c.PyTuple_SetItem(target.tuple, index, fields);

            assert(status == 0);

            if (Base != null) try Parent.fill(state, target, index + 1);
        }

        pub fn restore(
            state: *const Binding.State,
            fields: *c.PyObject,
            scope: *Scope,
        ) error{Raised}!Instance.Extended {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(scope.object_count == 0);

            const builtins = &state.builtins;

            if (Base == null) {
                return from_python_module.record_restore(
                    Binding,
                    Class,
                    label,
                    state,
                    fields,
                    scope,
                );
            }

            if (!python.has_flag(fields, c.Py_TPFLAGS_TUPLE_SUBCLASS)) {
                return from_python_module.mismatch(builtins, label ++ " must be a tuple", fields);
            }

            if (c.PyTuple_Size(fields) != count) {
                c.PyErr_SetString(builtins.get(.value_error), label ++ " has the wrong length");

                return error.Raised;
            }

            return level_restore(state, fields, scope, 0);
        }

        fn level_restore(
            state: *const Binding.State,
            tuple: *c.PyObject,
            scope: *Scope,
            comptime index: u32,
        ) error{Raised}!Instance.Extended {
            comptime assert(index < count + 64);
            assert(c.PyTuple_Size(tuple) > index);

            const fields = c.PyTuple_GetItem(tuple, index).?;

            const value = try from_python_module.record_restore(
                Binding,
                Class,
                label,
                state,
                fields,
                scope,
            );

            if (Base == null) return value;

            const base = try Parent.level_restore(state, tuple, scope, index + 1);

            return .{ .value = value, .base = base };
        }
    };
}

test member_of {
    const Counter = struct {
        count: u32,

        pub const doc = "A counter.";
        pub const docs = .{ .increment = "Add one." };
        pub const fields = .{ .count = .read };
        pub const properties = .{.doubled};
        pub const Arguments = struct { step: u32 };

        pub fn init(counter: *@This()) void {
            assert(@intFromPtr(counter) % @alignOf(@This()) == 0);

            counter.count = 0;

            assert(counter.count == 0);
        }

        pub fn increment(counter: *@This()) void {
            assert(counter.count < std.math.maxInt(u32));

            counter.count += 1;

            assert(counter.count > 0);
        }

        pub fn doubled(counter: *const @This()) u32 {
            assert(counter.count <= @divFloor(std.math.maxInt(u32), 2));

            const result = counter.count * 2;

            assert(result % 2 == 0);

            return result;
        }

        pub fn __bool__(counter: *const @This()) bool {
            assert(counter.count <= std.math.maxInt(u32));

            return counter.count > 0;
        }
    };

    comptime {
        assert(member_of(Counter, "doc") == .reserved);
        assert(member_of(Counter, "Arguments") == .skipped);
        assert(member_of(Counter, "init") == .constructor);
        assert(member_of(Counter, "increment") == .method);
        assert(member_of(Counter, "doubled") == .property);
        assert(member_of(Counter, "__bool__") == .slot);
        assert(method_count(Counter) == 1);
        assert(getset_count(Counter) == 2);
        assert(std.mem.eql(u8, doc_of(Counter, "increment"), "Add one."));
        assert(doc_of(Counter, "doubled").len == 0);
    }
}
