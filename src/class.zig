const std = @import("std");

const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const critical = @import("critical.zig");
const derive = @import("derive.zig");
const exception = @import("exception.zig");
const from_python_module = @import("from_python.zig");
const function_module = @import("function.zig");
const instance = @import("instance.zig");
const invoke_module = @import("invoke.zig");
const kind_module = @import("kind.zig");
const pending = @import("pending.zig");
const python = @import("python.zig");
const registry = @import("registry.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const slot = @import("slot.zig");
const snapshot_module = @import("snapshot.zig");
const to_python_module = @import("to_python.zig");
const value_module = @import("value.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const InstanceType = instance.InstanceType;
const Scope = scope_module.Scope;
const from_python = from_python_module.from_python;
const native_of = @import("native.zig").native_of;
const signature_of = signature_module.signature_of;
const snapshot = snapshot_module.snapshot;
const text_signature = signature_module.text_signature;
const to_python = to_python_module.to_python;

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
    "buffer_locked",
    "constants",
    "coroutines",
    "deleters",
    "deprecated",
    "derive",
    "dictionary",
    "doc",
    "docs",
    "extends",
    "fields",
    "freelist",
    "frozen",
    "generic",
    "mapping",
    "metaclass",
    "module_name",
    "names",
    "pickle",
    "properties",
    "python_name",
    "sequence",
    "setters",
    "static_methods",
    "subclassable",
    "thread_affine",
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
    if (std.mem.eql(u8, name, "format")) {
        if (derive.derived(Class, .string)) return .skipped;
    }

    if (std.mem.eql(u8, name, "__traverse__")) return .skipped;
    if (std.mem.eql(u8, name, "__clear__")) return .skipped;
    if (slot.is_slot_name(name)) return .slot;
    if (property_listed(Class, name)) return .property;
    if (setter_listed(Class, name)) return .setter;
    if (deleter_listed(Class, name)) return .setter;
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
        .python => {
            if (!@import("native.zig").metaclass_python_available) {
                @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' names a Python " ++
                    "metaclass, and GraalPy cannot build a native type from one");
            }

            return;
        },
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

    if (native_of(Class) != null) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends a native base, " ++
            "so it is constructed by init and cannot declare __new__");
    }

    const signature = signature_of(@TypeOf(Class.__new__), Class, "__new__");

    if (signature.receiver != .none) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__new__' takes an instance, " ++
            "which does not exist until __new__ returns it");
    }

    if (signature.Payload != value_module.Reference) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__new__' returns '" ++
            @typeName(signature.Payload) ++ "'; it returns the instance as a lacuna.Reference");
    }

    if (signature.arena) {
        @compileError("lacuna: '" ++ @typeName(Class) ++ ".__new__' takes the per-call " ++
            "arena, which is freed before the instance it builds is used");
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

    const signature = signature_of(@TypeOf(Class.__init_subclass__), Class, "__init_subclass__");

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

pub fn deleter_listed(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "deleters")) return false;

    inline for (@typeInfo(@TypeOf(Class.deleters)).@"struct".field_names) |property| {
        if (std.mem.eql(u8, @tagName(@field(Class.deleters, property)), name)) return true;
    }

    return false;
}

pub fn deleter_of(comptime Class: type, comptime property: []const u8) ?[:0]const u8 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(property.len > 0);

    if (!@hasDecl(Class, "deleters")) return null;
    if (!@hasField(@TypeOf(Class.deleters), property)) return null;
    return @tagName(@field(Class.deleters, property));
}

pub fn deleters_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "deleters")) return;

    for (@typeInfo(@TypeOf(Class.deleters)).@"struct".field_names) |property| {
        if (!property_listed(Class, property)) {
            @compileError("lacuna: the deleters of '" ++ @typeName(Class) ++ "' name '" ++
                property ++ "', which is not a property");
        }

        const deleter = @tagName(@field(Class.deleters, property));

        if (!@hasDecl(Class, deleter)) {
            @compileError("lacuna: the deleter of '" ++ @typeName(Class) ++ "." ++ property ++
                "' is not a function of the class");
        }

        const signature = signature_of(@TypeOf(@field(Class, deleter)), Class, deleter);

        const refused = "lacuna: the deleter '" ++ @typeName(Class) ++ "." ++ deleter ++
            "' must take *" ++ @typeName(Class) ++ " and nothing else";

        if (signature.receiver != .mutable) @compileError(refused);
        if (signature.Arguments != null) @compileError(refused);
    }
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

pub fn buffer_locked(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "buffer_locked")) return false;

    inline for (Class.buffer_locked) |listed| {
        if (std.mem.eql(u8, @tagName(listed), name)) return true;
    }

    return false;
}

pub fn buffer_locked_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "buffer_locked")) return;

    if (!@hasDecl(Class, "__buffer__")) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' lists buffer_locked " ++
            "methods but exports no __buffer__");
    }

    inline for (Class.buffer_locked) |listed| {
        const name = @tagName(listed);
        const method = @hasDecl(Class, name) and member_of(Class, name) == .method;

        if (!method) {
            @compileError("lacuna: the buffer_locked list of '" ++ @typeName(Class) ++
                "' names '" ++ name ++ "', which is not a method");
        }

        const signature = signature_of(@TypeOf(@field(Class, name)), Class, name);

        if (signature.receiver != .mutable) {
            @compileError("lacuna: the buffer_locked method '" ++ @typeName(Class) ++ "." ++
                name ++ "' must take *" ++ @typeName(Class) ++ ", since only a mutation can " ++
                "move exported memory");
        }
    }
}

pub fn frozen_check(comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!InstanceType(Class).frozen) return;

    if (InstanceType(Class).base) |Base| {
        if (!InstanceType(Base).frozen) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' is frozen, so the " ++
                "class '" ++ @typeName(Base) ++ "' it extends is frozen as well");
        }
    }

    if (@hasDecl(Class, "setters")) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' is frozen, so it " ++
            "declares no setters");
    }

    if (@hasDecl(Class, "deleters")) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' is frozen, so it " ++
            "declares no deleters");
    }

    for (field_accesses(Class)) |entry| {
        if (entry.access != .read) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' is frozen, so " ++
                "its field '" ++ entry.name ++ "' is .read");
        }
    }

    for (@typeInfo(Class).@"struct".decl_names) |name| {
        const mutating = switch (member_of(Class, name)) {
            .method, .property, .slot => signature_module.receiver_of(
                @typeInfo(@TypeOf(@field(Class, name))).@"fn".param_types,
                Class,
            ) == .mutable,
            else => false,
        };

        if (mutating) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' is frozen, so '" ++
                name ++ "' takes *const " ++ @typeName(Class));
        }
    }
}

pub fn coroutines_check(comptime Binding: type, comptime Class: type) void {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(Binding.classes.len <= registry.class_count_max);

    if (!@hasDecl(Class, "coroutines")) return;

    if (!InstanceType(Class).frozen) {
        @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' lists coroutines, which " ++
            "run without the GIL and without the instance lock, so it must be frozen");
    }

    for (Class.coroutines) |entry| {
        const label = @typeName(Class) ++ "." ++ @tagName(entry);

        if (!@hasDecl(Class, @tagName(entry))) {
            @compileError("lacuna: the coroutine '" ++ label ++ "' is not declared");
        }

        if (member_of(Class, @tagName(entry)) != .method) {
            @compileError("lacuna: the coroutine '" ++ label ++ "' is not a method");
        }

        const Function = @TypeOf(@field(Class, @tagName(entry)));
        const signature = signature_of(Function, Class, @tagName(entry));

        if (signature.receiver == .none) {
            @compileError("lacuna: the coroutine '" ++ label ++ "' takes the instance");
        }

        const contexts = .{
            .{ signature.type_object, "the TypeObject" },
            .{ signature.module_object, "the ModuleObject" },
            .{ signature.native_base, "its native base" },
            .{ signature.State != null, "the module state" },
        };

        for (contexts) |context| {
            if (context[0]) {
                @compileError("lacuna: the coroutine '" ++ label ++ "' takes " ++ context[1] ++
                    ", which it cannot touch without the GIL");
            }
        }

        function_module.parallel_check(Binding, signature.Arguments, label, .coroutines);
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

pub fn module_name_of(comptime Type: type, comptime binding_name: [:0]const u8) [:0]const u8 {
    comptime assert(binding_name.len > 0);
    comptime assert(@typeInfo(Type) == .@"struct" or @typeInfo(Type) == .@"union");

    if (!@hasDecl(Type, "module_name")) return binding_name;

    const text = signature_module.terminated(Type.module_name);

    var parts = std.mem.splitScalar(u8, text, '.');

    for (0..text.len + 1) |_| {
        const part = parts.next() orelse break;

        if (part.len == 0) {
            @compileError("lacuna: the module_name of '" ++ @typeName(Type) ++ "' is '" ++
                text ++ "', which is not a dotted module path");
        }

        signature_module.identifier_check(part);
    }

    return text;
}

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

pub const Deprecation = struct {
    category: exception.WarningCategory,
    message: [:0]const u8,
};

pub fn deprecation_of(comptime Namespace: type, comptime name: []const u8) ?Deprecation {
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(Namespace) == .@"struct");

    if (!@hasDecl(Namespace, "deprecated")) return null;
    if (!@hasField(@TypeOf(Namespace.deprecated), name)) return null;

    const entry = @field(Namespace.deprecated, name);

    if (@typeInfo(@TypeOf(entry)) != .@"struct") {
        return .{
            .category = .{ .builtin = .deprecation_warning },
            .message = signature_module.terminated(entry),
        };
    }

    deprecation_entry_check(Namespace, name);

    return .{
        .category = exception.category_of(entry.category),
        .message = signature_module.terminated(entry.message),
    };
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

        deprecation_entry_check(Namespace, field);
    }
}

fn deprecation_entry_check(comptime Namespace: type, comptime field: []const u8) void {
    comptime assert(@hasDecl(Namespace, "deprecated"));
    comptime assert(field.len > 0);

    const entry = @field(Namespace.deprecated, field);
    const Entry = @TypeOf(entry);

    if (@typeInfo(Entry) != .@"struct") {
        comptime assert(entry.len > 0);

        return;
    }

    const fields = @typeInfo(Entry).@"struct".field_names;
    const shaped = fields.len == 2 and @hasField(Entry, "category") and @hasField(Entry, "message");

    if (!shaped) {
        @compileError("lacuna: the deprecation of '" ++ @typeName(Namespace) ++ "." ++ field ++
            "' is a message, or .{ .message = ..., .category = ... }");
    }

    comptime assert(entry.message.len > 0);
    comptime assert(exception.category_of(entry.category) == .builtin or
        exception.category_of(entry.category).module.len > 0);
}

pub fn method_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@typeInfo(Class).@"struct".decl_names.len <= 4096);

    var result: u32 = 0;

    inline for (@typeInfo(Class).@"struct".decl_names) |name| {
        switch (member_of(Class, name)) {
            .method => result += 1,
            .static => result += @intFromBool(!freezable),
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
    comptime assert(field_accesses(Class).len <= @typeInfo(Class).@"struct".field_names.len);

    var result: u32 = field_accesses(Class).len;

    if (@hasDecl(Class, "properties")) result += Class.properties.len;

    return result;
}

pub const FieldAccess = struct {
    access: Access,
    name: [:0]const u8,
};

pub fn field_accesses(comptime Class: type) []const FieldAccess {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "fields")) return &.{};

    const Fields = @TypeOf(Class.fields);
    const uniform = fields_uniform(Fields);
    const names = if (uniform)
        @typeInfo(Class).@"struct".field_names
    else
        @typeInfo(Fields).@"struct".field_names;

    var result: [names.len]FieldAccess = undefined;

    for (names, &result) |name, *entry| {
        if (!@hasField(Class, name)) {
            @compileError("lacuna: the fields of '" ++ @typeName(Class) ++ "' list '" ++ name ++
                "', which it does not declare");
        }

        const access: Access = if (uniform) Class.fields else @field(Class.fields, name);

        entry.* = .{ .access = access, .name = name };
    }

    const frozen = result;

    return &frozen;
}

fn fields_uniform(comptime Fields: type) bool {
    comptime assert(@typeInfo(Fields) != .pointer);
    comptime assert(@typeInfo(Fields) != .optional);

    if (Fields == Access) return true;
    return Fields == @EnumLiteral();
}

pub const Restoration = struct {
    class: *c.PyObject,
    fields: *c.PyObject,
};

pub const freezable = c.Gate.absence(c.raw.gates.PyType_Freeze, "PyType_Freeze") == null;

pub fn static_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@typeInfo(Class).@"struct".decl_names.len <= 4096);

    var result: u32 = 0;

    inline for (@typeInfo(Class).@"struct".decl_names) |name| {
        if (member_of(Class, name) == .static) result += 1;
    }

    return result;
}

pub fn created_mutable(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(signature_module.ancestor_count_max > 0);

    comptime var current: ?type = Class;

    inline for (0..signature_module.ancestor_count_max + 1) |_| {
        const Current = current orelse return false;

        if (@hasDecl(Current, "constants")) return true;
        if (@hasDecl(Current, "coroutines")) return true;

        if (freezable) {
            if (static_count(Current) > 0) return true;
        }

        current = InstanceType(Current).base;
    }

    return current != null;
}
pub const restore_name = "_lacuna_restore";
pub const deprecation_level: u32 = 1;

pub fn ClassType(comptime Binding: type, comptime Class: type) type {
    const name = from_python_module.class_name(Class);
    const Instance = InstanceType(Class);
    const Slots = slot.SlotsType(Binding, Class);

    comptime signature_module.identifier_check(name);
    comptime assert(@typeInfo(Class) == .@"struct");

    return struct {
        pub const python_name: [:0]const u8 = name;
        pub const qualified_name: [:0]const u8 = module_name_of(Class, Binding.name) ++ "." ++ name;
        const created = @hasDecl(Class, "__new__");
        const constructible = derive.constructible(Class) or created;
        const Constructor = if (derive.constructible(Class)) derive.Constructor(Class) else void;

        const constructor_arguments = if (created)
            signature_of(@TypeOf(Class.__new__), Class, "__new__").Arguments
        else if (constructible)
            signature_of(@TypeOf(Constructor.init), Class, "init").Arguments
        else
            null;

        const doc: [:0]const u8 = signature_module.terminated((if (constructible)
            text_signature(name, .class, constructor_arguments)
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
                    .static => if (!freezable) {
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

            for (field_accesses(Class)) |entry| {
                result[index] = FieldType(entry.name, entry.access).definition;
                index += 1;
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

        const type_slots = base_slots ++ constructor_slots ++ member_slots ++ Slots.table ++
            sentinel_slot;

        const dictionary_declared_member = if (c.opaque_object)
            Instance.dictionary_owned
        else
            Instance.dictionary_offset != null;

        const weaklist_declared_member = if (c.opaque_object)
            Instance.weaklist_owned
        else
            Instance.weaklist_offset != null;

        const member_count: u32 = @as(u32, @intFromBool(dictionary_declared_member)) +
            @intFromBool(weaklist_declared_member);

        const members: [member_count + 1]c.PyMemberDef = members: {
            var result: [member_count + 1]c.PyMemberDef = undefined;
            var index: u32 = 0;

            if (dictionary_declared_member) {
                result[index] = member_offset("__dictoffset__", Instance.dictionary_offset.?);
                index += 1;
            }

            if (weaklist_declared_member) {
                result[index] = member_offset("__weaklistoffset__", Instance.weaklist_offset.?);
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

        const immutable = !created_mutable(Class);

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
            deleters_check(Class);
            frozen_check(Class);
            coroutines_check(Binding, Class);
            buffer_locked_check(Class);
            creator_check(Class);
            metaclass_check(Class, Binding.classes);
            subclass_hook_check(Class);
            deprecated_check(Class, true);
            @import("native.zig").check(Class, name);
            signature_module.names_check(Class);
            derive.check(Class, name);

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
                    const Function = @TypeOf(Class.init);
                    const signature = signature_of(Function, Class, "init");

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
            comptime assert(offset <= std.math.maxInt(c_int));

            if (c.opaque_object) {
                comptime assert(offset < @sizeOf(Instance.Storage));
            } else {
                comptime assert(offset >= @sizeOf(c.PyObject_Header));
                comptime assert(offset < Instance.basic_size);
            }

            const relative: c_int = if (c.opaque_object) c.api_3_12.Py_RELATIVE_OFFSET else 0;

            return .{
                .name = member,
                .type = c.api_3_12.Py_T_PYSSIZET,
                .offset = offset,
                .flags = c.api_3_12.Py_READONLY | relative,
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
                Constructor.init,
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

            const storage = InstanceType(Level).storage_of(object);
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
            const signature = signature_of(@TypeOf(function), Class, member);
            const deprecation = comptime deprecation_of(Class, member);
            const locked = comptime buffer_locked(Class, member);
            const coroutine = comptime registry.listed(Class, .coroutines, member);
            const mode: invoke_module.Mode = if (coroutine) .coroutine else .held;
            const static = signature.receiver == .none;
            const bound: signature_module.Bound = if (static) .type else .instance;
            const text = text_signature(python_member, bound, signature.Arguments);

            const defining_passed = !c.graalpy;
            const flags_method = c.METH_FASTCALL | c.METH_KEYWORDS |
                (if (defining_passed) c.METH_METHOD else 0) |
                (if (signature.receiver == .none) c.METH_CLASS else 0);

            comptime signature_module.identifier_check(python_member);

            return struct {
                const definition: c.PyMethodDef = .{
                    .ml_name = python_member,
                    .ml_meth = if (defining_passed) &call else @ptrCast(&call_found),
                    .ml_flags = flags_method,
                    .ml_doc = signature_module.terminated(text ++ doc_of(Class, member)),
                };

                fn call_found(
                    object: *c.PyObject,
                    arguments: ?[*]const *c.PyObject,
                    count: c.Py_ssize_t,
                    names: ?*c.PyObject,
                ) callconv(.c) ?*c.PyObject {
                    comptime assert(!defining_passed);
                    assert(count >= 0);
                    assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
                    assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));

                    const class = if (static) object else python.type_borrowed(object);

                    const defining = Instance.defining_of(class) orelse {
                        python.exception_raise(.{
                            .class_name = "TypeError",
                            .message = qualified_name ++ "." ++ python_member ++
                                "() needs a " ++ qualified_name ++ " receiver",
                        });

                        return null;
                    };

                    return call(object, defining, arguments, count, names);
                }

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

                    const state = Binding.State.of_class(defining);

                    if (!coroutine) {
                        if (deprecation) |known| {
                            const category = Binding.category_class(state, known.category);

                            pending.warn_class(category, known.message, deprecation_level) catch {
                                return null;
                            };
                        }
                    }

                    const vector = python.vector_of(arguments, count, names);
                    const invocation: Call = .fast(vector, count, names);

                    if (locked) {
                        if (Instance.storage_of(object).exports.load(.acquire) > 0) {
                            c.PyErr_SetString(
                                state.builtins.get(.buffer_error),
                                qualified_name ++ "." ++ member ++
                                    "() cannot run while a buffer view of the instance exists",
                            );

                            return null;
                        }
                    }

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
                        mode,
                    ).invoke(state, receiver, context, &invocation);
                }
            };
        }

        pub fn StaticType(comptime member: [:0]const u8) type {
            comptime assert(member.len > 0);
            comptime assert(@hasDecl(Class, member));

            const function = @field(Class, member);
            const python_member = comptime signature_module.python_name_of(Class, member);
            const signature = signature_of(@TypeOf(function), Class, member);
            const Arguments = signature.Arguments;
            const text = text_signature(python_member, .class, Arguments);
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
                pub const name_python = python_member;

                pub const definition: c.PyMethodDef = .{
                    .ml_name = python_member,
                    .ml_meth = &call,
                    .ml_flags = c.METH_FASTCALL | c.METH_KEYWORDS |
                        (if (freezable) 0 else c.METH_STATIC),
                    .ml_doc = signature_module.terminated(text ++ doc_of(Class, member)),
                };

                fn call(
                    module_object: ?*c.PyObject,
                    arguments: ?[*]const *c.PyObject,
                    count: c.Py_ssize_t,
                    names: ?*c.PyObject,
                ) callconv(.c) ?*c.PyObject {
                    assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
                    assert((module_object != null) == freezable);
                    assert(count >= 0);
                    assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));

                    const state: *const Binding.State = if (freezable)
                        Binding.State.of_module(module_object.?)
                    else
                        Binding.state_current() orelse return null;

                    if (deprecation) |known| {
                        const category = Binding.category_class(state, known.category);

                        pending.warn_class(category, known.message, deprecation_level) catch {
                            return null;
                        };
                    }

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
            const restore = python.attribute_get(module, restore_name) orelse return null;
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

            const extra = python.attribute_get(object, "__dict__") orelse dictionary: {
                const absent = c.PyErr_ExceptionMatches(state.builtins.get(.attribute_error)) != 0;

                if (!absent) return null;

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

            var objects: [holders]*c.PyObject = undefined;

            var scope: Scope = .init(.{ .objects = &objects, .views = &.{} });
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
            const signature = signature_of(@TypeOf(function), Class, member);

            if (signature.receiver == .none) {
                @compileError("lacuna: the property '" ++ @typeName(Class) ++ "." ++ member ++
                    "' must take its receiver");
            }

            if (signature.Arguments != null) {
                @compileError("lacuna: the property '" ++ @typeName(Class) ++ "." ++ member ++
                    "' must take no arguments");
            }

            const setter = comptime setter_of(Class, member);
            const deleter = comptime deleter_of(Class, member);
            const python_member = signature_module.python_name_of(Class, member);

            if (setter) |setter_name| setter_validate(member, setter_name);

            return struct {
                const definition: c.PyGetSetDef = .{
                    .name = python_member,
                    .get = &get,
                    .set = if (setter != null or deleter != null) &set else null,
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
                    if (item) |given| assert(@intFromPtr(given) % c.object_alignment == 0);

                    const state = state_of(object);
                    const defining = Instance.defining_of(python.type_borrowed(object));

                    const receiver: invoke_module.Receiver(Class) = .{
                        .data = Instance.data_required(object) orelse return -1,
                        .object = object,
                    };

                    const present = item orelse {
                        const removal = deleter orelse {
                            c.PyErr_SetString(
                                state.builtins.get(.type_error),
                                "cannot delete " ++ qualified_name ++ "." ++ member,
                            );

                            return -1;
                        };

                        const empty: Call = .fast(&.{}, 0, null);

                        return accessor_call(removal, state, receiver, defining, &empty);
                    };

                    const assignment = setter orelse {
                        c.PyErr_SetString(
                            state.builtins.get(.attribute_error),
                            "attribute '" ++ python_member ++ "' of '" ++ qualified_name ++
                                "' objects is not writable",
                        );

                        return -1;
                    };

                    const vector = [_]*c.PyObject{present};
                    const invocation: Call = .fast(&vector, 1, null);

                    return accessor_call(assignment, state, receiver, defining, &invocation);
                }

                fn accessor_call(
                    comptime accessor: [:0]const u8,
                    state: *const Binding.State,
                    receiver: invoke_module.Receiver(Class),
                    defining: ?*c.PyObject,
                    invocation: *const Call,
                ) c_int {
                    comptime assert(@hasDecl(Class, accessor));
                    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
                    assert(@intFromPtr(receiver.data) % @alignOf(Class) == 0);
                    if (defining) |class| assert(python.class_is(class));

                    const result = invoke_module.InvokerType(
                        Binding,
                        Class,
                        @field(Class, accessor),
                        accessor,
                        .held,
                    ).invoke(state, receiver, .{ .defining = defining }, invocation) orelse {
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

            const signature = signature_of(@TypeOf(@field(Class, setter)), Class, setter);
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

                    if (comptime Instance.frozen) {
                        return to_python(Binding, Field, state, &@field(data, field)) catch null;
                    }

                    if (comptime owned(Field, 0)) {
                        const copied = copy_field(object, data);

                        return to_python(Binding, Field, state, &copied) catch null;
                    }

                    if (comptime snapshot_module.borrowed(Field, Binding.declared, 0)) {
                        return borrowed_get(object, state, data);
                    }

                    var section = critical.empty;

                    critical.begin(&section, object);
                    defer critical.end(&section);

                    return to_python(Binding, Field, state, &@field(data, field)) catch null;
                }

                fn borrowed_get(
                    object: *c.PyObject,
                    state: *const Binding.State,
                    data: *const Class,
                ) ?*c.PyObject {
                    comptime assert(snapshot_module.borrowed(Field, Binding.declared, 0));
                    comptime assert(!Instance.frozen);
                    assert(@intFromPtr(object) % c.object_alignment == 0);

                    var section = critical.empty;

                    critical.begin(&section, object);

                    const source = &@field(data, field);
                    const size = snapshot_module.size_of(Field, Binding.declared, source);

                    var buffer = snapshot_module.Buffer.acquire(size) orelse {
                        critical.end(&section);

                        return null;
                    };
                    defer buffer.release();

                    const copied = snapshot(Field, Binding.declared, 0, &buffer.region, source);

                    critical.end(&section);

                    return to_python(Binding, Field, state, &copied) catch null;
                }

                fn copy_field(object: *c.PyObject, data: *const Class) Field {
                    comptime assert(!Instance.frozen);
                    assert(@intFromPtr(object) % c.object_alignment == 0);

                    var section = critical.empty;

                    critical.begin(&section, object);
                    defer critical.end(&section);

                    return @field(data, field);
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

                    comptime assert(scope_module.lock_count(Field, Binding.declared, 0) == 0);

                    var objects: [holders]*c.PyObject = undefined;

                    var scope: Scope = .init(.{ .objects = &objects, .views = &.{} });
                    defer scope.release();

                    const converted = from_python(
                        Binding,
                        Field,
                        label,
                        state,
                        present,
                        &scope,
                    ) catch return -1;

                    assert(scope.lock_count == 0);

                    var section = critical.empty;

                    critical.begin(&section, object);
                    defer critical.end(&section);

                    @field(data, field) = converted;

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

            return kind_module.owned(T, Binding.declared, depth);
        }

        fn fields_owned(comptime T: type, comptime depth: u32) bool {
            comptime assert(@typeInfo(T) == .@"struct");
            comptime assert(depth < kind_module.depth_max);

            return kind_module.fields_owned(T, Binding.declared, depth);
        }
    };
}

const Fill = struct {
    object: *c.PyObject,
    tuple: *c.PyObject,
};

fn LevelsType(comptime Binding: type, comptime Class: type) type {
    const Instance = InstanceType(Class);
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
