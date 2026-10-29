const std = @import("std");

const c = @import("c.zig");
const exception = @import("exception.zig");
const kind_module = @import("kind.zig");
const list = @import("list.zig");
const native_module = @import("native.zig");
const python = @import("python.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

pub const alignment_max: u32 = @sizeOf(c.PyObject_Header);
pub const base_depth_max: u32 = std.math.maxInt(u32);
pub const dealloc_depth_max: u32 = 64;

pub fn ExtendedType(comptime Class: type) type {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@hasDecl(Class, "extends"));

    return InstanceType(Class).Extended;
}

pub fn InstanceType(comptime Class: type) type {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@alignOf(Class) <= alignment_max);

    const Base: ?type = native_module.lacuna_base_of(Class);
    const Parent = if (Base) |Known| InstanceType(Known) else void;
    const native: ?native_module.Native = native_module.native_of(Class);

    if (Base) |Known| {
        if (Parent.native_base != null) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends '" ++
                @typeName(Known) ++ "', which extends a native base");
        }

        if (Known == Class) @compileError("lacuna: the class '" ++ @typeName(Class) ++
            "' extends itself");

        if (!Parent.subclassable) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends '" ++
                @typeName(Known) ++ "', which must declare subclassable = true");
        }
    }

    return struct {
        pub const Allocation = struct {
            object: *c.PyObject,
            storage: *Storage,
        };

        pub const Storage = struct {
            value: Class,
            initialized: bool,
        };

        pub const Construction = struct {
            arguments: *c.PyObject,
            keywords: ?*c.PyObject,
        };

        pub const Extended = if (Base) |Known| struct {
            value: Class,
            base: InstanceType(Known).Extended,

            pub const extended_class = Class;
        } else Class;

        const Allocate = *const fn (*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject;
        const Dealloc = *const fn (*c.PyObject) callconv(.c) void;
        const New = *const fn (*c.PyObject, *c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject;
        const Traverse = *const fn (*c.PyObject, c.visitproc, ?*anyopaque) callconv(.c) c_int;
        const Inquiry = *const fn (*c.PyObject) callconv(.c) c_int;
        const Finalize = *const fn (*c.PyObject) callconv(.c) void;
        const Free = *const fn (?*anyopaque) callconv(.c) void;
        const pointer_size: u32 = @sizeOf(*c.PyObject);

        pub const base: ?type = Base;
        pub const native_base: ?native_module.Native = native;
        pub const metaclass = native == .type;
        pub const subclassable = @hasDecl(Class, "subclassable") and Class.subclassable;

        const header_size: u32 = @sizeOf(c.PyObject_Header);
        const prefix_size: u32 = if (Base != null) Parent.basic_size else header_size;
        const dictionary_inherited: ?u32 = if (Base != null) Parent.dictionary_offset else null;
        const weaklist_inherited: ?u32 = if (Base != null) Parent.weaklist_offset else null;
        const dictionary_requested = @hasDecl(Class, "dictionary") and Class.dictionary;
        const weaklist_requested = @hasDecl(Class, "weakref") and Class.weakref;
        const dictionary_owned = dictionary_requested and dictionary_inherited == null and
            native == null;
        const weaklist_owned = weaklist_requested and weaklist_inherited == null and
            native == null;
        const owned_first: u32 = std.mem.alignForward(u32, prefix_size, pointer_size);

        pub const dictionary_offset: ?u32 = if (dictionary_owned)
            owned_first
        else
            dictionary_inherited;

        pub const base_dictionary_offset: ?u32 = dictionary_inherited;

        pub const weaklist_offset: ?u32 = if (weaklist_owned)
            owned_first + @as(u32, if (dictionary_owned) pointer_size else 0)
        else
            weaklist_inherited;

        const owned_count: u32 = @as(u32, @intFromBool(dictionary_owned)) +
            @intFromBool(weaklist_owned);

        const owned_end: u32 = owned_first + pointer_size * owned_count;

        pub const referencing = references_present(Class, 0) or
            (Base != null and Parent.referencing);

        pub const collected = referencing or dictionary_offset != null;

        pub const finalizer_present: bool = deinit_fallible(Class) or
            (Base != null and Parent.finalizer_present);

        pub const storage_offset: u32 = std.mem.alignForward(
            u32,
            owned_end,
            @alignOf(Storage),
        );

        pub const basic_size: u32 = storage_offset + @sizeOf(Storage);

        pub const specification_size: c_int = if (native != null)
            -@as(c_int, @sizeOf(Storage))
        else
            basic_size;

        threadlocal var dealloc_depth: u32 = 0;
        threadlocal var dealloc_deferred: ?*c.PyObject = null;
        pub threadlocal var finalizer_detached: bool = false;

        comptime {
            assert(@alignOf(Storage) <= alignment_max);
            assert(basic_size <= std.math.maxInt(c_int));
            assert(storage_offset >= prefix_size);
            assert(storage_offset % @alignOf(Storage) == 0);

            if (dictionary_offset) |offset| assert(offset >= @sizeOf(c.PyObject_Header));
            if (weaklist_offset) |offset| assert(offset >= @sizeOf(c.PyObject_Header));
        }

        pub fn allocate(class: *c.PyObject) error{Raised}!Allocation {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(defining_of(class) != null);

            if (native != null) {
                const arguments = c.PyTuple_New(0) orelse return error.Raised;
                defer c.Py_DecRef(arguments);

                return native_allocate(class, .{ .arguments = arguments, .keywords = null });
            }

            const slot = c.PyType_GetSlot(class, c.Py_tp_alloc) orelse return error.Raised;
            const function: Allocate = @ptrCast(@alignCast(slot));
            const object = function(class, 0) orelse return error.Raised;
            const storage = storage_of(object);

            assert(!storage.initialized);

            return .{ .object = object, .storage = storage };
        }

        pub fn allocate_with(
            class: *c.PyObject,
            construction: Construction,
        ) error{Raised}!Allocation {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(python.has_flag(construction.arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            assert(python.flagged_or_null(construction.keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            if (native == null) return allocate(class);
            return native_allocate(class, construction);
        }

        fn native_allocate(
            class: *c.PyObject,
            construction: Construction,
        ) error{Raised}!Allocation {
            comptime assert(native != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(python.has_flag(construction.arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            assert(python.flagged_or_null(construction.keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

            const slot = c.PyType_GetSlot(native_type_of(class), c.Py_tp_new) orelse {
                return error.Raised;
            };

            const function: New = @ptrCast(@alignCast(slot));
            const object = function(
                class,
                construction.arguments,
                construction.keywords,
            ) orelse return error.Raised;

            const storage = storage_of(object);

            assert(!storage.initialized);

            return .{ .object = object, .storage = storage };
        }

        fn native_type_of(class: *c.PyObject) *c.PyObject {
            comptime assert(native != null);
            assert(python.class_is(class));

            const defining = defining_of(class).?;
            const slot = c.PyType_GetSlot(defining, c.Py_tp_base).?;
            const result: *c.PyObject = @ptrCast(@alignCast(slot));

            assert(python.class_is(result));

            return result;
        }

        fn tracked(object: *c.PyObject) bool {
            assert(!c.pypy);
            assert(defining_of(python.type_borrowed(object)) != null);

            if (collected) return true;
            if (native == null) return false;

            const flags = c.PyType_GetFlags(python.type_borrowed(object));
            return flags & c.Py_TPFLAGS_HAVE_GC != 0;
        }

        pub fn store(allocation: Allocation, extended: *const Extended) void {
            assert(!allocation.storage.initialized);
            assert(storage_of(allocation.object) == allocation.storage);

            if (Base == null) {
                allocation.storage.value = extended.*;
            } else {
                allocation.storage.value = extended.value;

                const parent = Parent.storage_of(allocation.object);

                Parent.store(.{ .object = allocation.object, .storage = parent }, &extended.base);
            }

            allocation.storage.initialized = true;
        }

        pub fn initialized_mark(object: *c.PyObject) void {
            const storage = storage_of(object);

            assert(!storage.initialized);

            storage.initialized = true;

            if (Base != null) Parent.initialized_mark(object);
        }

        pub fn data_of(object: *c.PyObject) ?*Class {
            if (!owned_by(object)) return null;

            const storage = storage_of(object);

            assert(python.type_borrowed(object) != object);

            if (metaclass) return &storage.value;
            if (!storage.initialized) return null;
            return &storage.value;
        }

        pub fn data_required(object: *c.PyObject) ?*Class {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            if (data_of(object)) |data| return data;

            if (c.PyErr_Occurred() == null) {
                const message = "the '" ++ @typeName(Class) ++ "' object was never initialized";
                const kind = python.builtin_new("TypeError") orelse return null;
                defer c.Py_DecRef(kind);

                c.PyErr_SetString(kind, message);
            }

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() != null);

            return null;
        }

        pub fn owned_by(object: *c.PyObject) bool {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            return defining_of(python.type_borrowed(object)) != null;
        }

        pub fn ancestor_of(object: *c.PyObject) *Class {
            const storage = storage_of(object);

            assert(@intFromPtr(storage) > @intFromPtr(object));

            return &storage.value;
        }

        pub fn storage_of(object: *c.PyObject) *Storage {
            assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
            assert(defining_of(python.type_borrowed(object)) != null);

            if (native != null) {
                const defining = defining_of(python.type_borrowed(object)).?;
                const pointer = c.PyObject_GetTypeData(object, defining).?;

                return @ptrCast(@alignCast(pointer));
            }

            return python.storage_at(Storage, object, storage_offset);
        }

        pub fn owns(class: *c.PyObject) bool {
            const slot = c.PyType_GetSlot(class, c.Py_tp_dealloc);
            const expected = @intFromPtr(&dealloc);

            assert(expected != 0);
            assert(@intFromPtr(class) % @alignOf(*c.PyObject) == 0);

            if (@intFromPtr(slot) != expected) return false;
            if (!c.pypy) return true;
            return module_owned(class);
        }

        fn module_owned(class: *c.PyObject) bool {
            comptime assert(c.pypy);
            assert(@intFromPtr(class) % @alignOf(*c.PyObject) == 0);

            var pending_kind: ?*c.PyObject = null;
            var pending_value: ?*c.PyObject = null;
            var pending_traceback: ?*c.PyObject = null;

            c.PyErr_Fetch(&pending_kind, &pending_value, &pending_traceback);
            defer c.PyErr_Restore(pending_kind, pending_value, pending_traceback);

            const module = c.PyType_GetModule(class);

            if (module == null) c.PyErr_Clear();

            return module != null;
        }

        pub fn defining_of(class: *c.PyObject) ?*c.PyObject {
            assert(@intFromPtr(class) % @alignOf(*c.PyObject) == 0);

            if (owns(class)) return class;
            if (!subclassable) return null;

            var current = class;

            for (0..base_depth_max) |_| {
                const slot = c.PyType_GetSlot(current, c.Py_tp_base) orelse return null;
                const base_class: *c.PyObject = @ptrCast(@alignCast(slot));

                if (owns(base_class)) return base_class;

                current = base_class;
            }

            unreachable;
        }

        pub fn dealloc(object: *c.PyObject) callconv(.c) void {
            assert(defining_of(python.type_borrowed(object)) != null);
            assert(dealloc_depth <= dealloc_depth_max);

            if (finalizer_present) {
                if (storage_of(object).initialized) {
                    if (finalizer_resurrected(object)) return;
                }
            }

            if (!c.pypy) {
                if (!metaclass) {
                    if (tracked(object)) c.PyObject_GC_UnTrack(object);
                }
            }

            if (!c.pypy) {
                if (dealloc_depth == dealloc_depth_max) {
                    link_set(object, dealloc_deferred);
                    dealloc_deferred = object;

                    return;
                }
            }

            dealloc_depth += 1;
            defer dealloc_depth -= 1;

            release(object);

            if (dealloc_depth > 1) return;

            for (0..std.math.maxInt(u32)) |_| {
                const deferred = dealloc_deferred orelse return;

                dealloc_deferred = link_get(deferred);
                release(deferred);
            }

            unreachable;
        }

        fn finalizer_resurrected(object: *c.PyObject) bool {
            comptime assert(finalizer_present);
            assert(storage_of(object).initialized);

            const class = python.type_borrowed(object);
            const defining = defining_of(class).?;
            const slot = c.PyType_GetSlot(defining, c.Py_tp_finalize);

            assert(slot != null);

            const finalizer: Finalize = @ptrCast(@alignCast(slot.?));

            if (class == defining) {
                c.Py_IncRef(object);
                finalizer(object);

                assert(!storage_of(object).initialized);

                c.Py_DecRef(object);

                return true;
            }

            assert(!finalizer_detached);

            finalizer_detached = true;
            finalizer(object);
            finalizer_detached = false;

            assert(!storage_of(object).initialized);

            return false;
        }

        fn link_get(object: *c.PyObject) ?*c.PyObject {
            assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

            const Address = @Int(.unsigned, @bitSizeOf(c.Py_ssize_t));
            const address: Address = @bitCast(link_word(object).*);
            const result: ?*c.PyObject = @ptrFromInt(address);

            if (result) |next| assert(@intFromPtr(next) % @alignOf(c.PyObject_Header) == 0);

            return result;
        }

        fn link_set(object: *c.PyObject, next: ?*c.PyObject) void {
            assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
            assert(@intFromPtr(next) % @alignOf(c.PyObject_Header) == 0);

            link_word(object).* = @bitCast(@intFromPtr(next));
        }

        fn link_word(object: *c.PyObject) *c.Py_ssize_t {
            assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

            const header: *c.PyObject_Header = @ptrCast(@alignCast(object));
            const word = if (c.free_threaded) &header.ob_ref_shared else &header.ob_refcnt;

            comptime assert(@sizeOf(@TypeOf(word.*)) == @sizeOf(c.Py_ssize_t));

            return @ptrCast(word);
        }

        fn release(object: *c.PyObject) void {
            const class = python.type_borrowed(object);

            assert(defining_of(class) != null);

            const saved = exception.pending_save();
            defer exception.pending_resume(&saved);

            if (weaklist_offset) |offset| {
                const weaklist = python.storage_at(?*c.PyObject, object, offset);

                if (weaklist.* != null) c.PyObject_ClearWeakRefs(object);
            }

            finalize(object);

            if (dictionary_offset) |offset| slot_clear(object, offset);

            if (native != null) {
                const native_slot = c.PyType_GetSlot(native_type_of(class), c.Py_tp_dealloc).?;
                const native_dealloc: Dealloc = @ptrCast(@alignCast(native_slot));

                native_dealloc(object);
                c.Py_DecRef(class);

                return;
            }

            const slot = c.PyType_GetSlot(class, c.Py_tp_free);

            assert(slot != null);

            const free: Free = @ptrCast(@alignCast(slot.?));

            free(object);
            c.Py_DecRef(class);
        }

        pub fn finalize(object: *c.PyObject) void {
            const storage = storage_of(object);

            if (storage.initialized) {
                if (@hasDecl(Class, "deinit")) {
                    if (comptime deinit_fallible(Class)) unreachable;

                    storage.value.deinit();
                }
            }

            if (comptime references_present(Class, 0)) {
                references_release(Class, &storage.value, 0);
            }

            storage.initialized = false;

            if (Base != null) Parent.finalize(object);
        }

        pub fn traverse(
            object: *c.PyObject,
            visitor: c.visitproc,
            argument: ?*anyopaque,
        ) callconv(.c) c_int {
            comptime assert(collected);
            assert(@intFromPtr(argument) % @alignOf(*anyopaque) == 0);
            assert(visitor != null);

            const class = python.type_borrowed(object);

            var walk: Walk = .{
                .status = visitor.?(class, argument),
                .visit = .{ .argument = argument, .visitor = visitor },
            };

            if (native != null) {
                if (walk.status != 0) return walk.status;

                const slot = c.PyType_GetSlot(native_type_of(class), c.Py_tp_traverse);

                if (slot) |present| {
                    const native_traverse: Traverse = @ptrCast(@alignCast(present));

                    walk.status = native_traverse(object, visitor, argument);
                }
            }

            contents_visit(object, &walk);

            if (dictionary_offset) |offset| {
                if (walk.status == 0) {
                    const dictionary = python.storage_at(?*c.PyObject, object, offset).*;

                    if (dictionary) |present| walk.status = visitor.?(present, argument);
                }
            }

            return walk.status;
        }

        pub fn contents_visit(object: *c.PyObject, walk: *Walk) void {
            assert(walk.visit.visitor != null);

            if (comptime references_present(Class, 0)) {
                references_visit(Class, &storage_of(object).value, walk, 0);
            }

            if (Base != null) Parent.contents_visit(object, walk);
        }

        pub fn clear(object: *c.PyObject) callconv(.c) c_int {
            comptime assert(collected);
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            contents_clear(object);

            if (dictionary_offset) |offset| slot_clear(object, offset);

            if (native != null) {
                const class = python.type_borrowed(object);
                const slot = c.PyType_GetSlot(native_type_of(class), c.Py_tp_clear);

                if (slot) |present| {
                    const native_clear: Inquiry = @ptrCast(@alignCast(present));

                    return native_clear(object);
                }
            }

            return 0;
        }

        pub fn contents_clear(object: *c.PyObject) void {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            if (comptime references_present(Class, 0)) {
                references_release(Class, &storage_of(object).value, 0);
            }

            if (Base != null) Parent.contents_clear(object);
        }

        fn slot_clear(object: *c.PyObject, offset: u32) void {
            assert(offset >= @sizeOf(c.PyObject_Header));
            assert(offset < basic_size);

            const slot = python.storage_at(?*c.PyObject, object, offset);
            const previous = slot.*;

            slot.* = null;

            c.Py_DecRef(previous);
        }
    };
}

pub fn deinit_fallible(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "deinit")) return false;

    const Function = @TypeOf(Class.deinit);

    comptime assert(@typeInfo(Function) == .@"fn");

    return @typeInfo(@typeInfo(Function).@"fn".return_type.?) == .error_union;
}

pub fn references_present(comptime T: type, comptime depth: u32) bool {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(T != type);

    if (T == value.Reference) return true;
    if (value.container_is(T)) return true;

    if (depth == kind_module.depth_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' nests deeper than " ++
            std.fmt.comptimePrint("{d}", .{kind_module.depth_max}) ++ " levels");
    }

    return switch (@typeInfo(T)) {
        .array => |array| references_present(array.child, depth + 1),
        .@"struct" => references_present_struct(T, depth),
        .optional => |optional| references_present(optional.child, depth + 1),
        .@"union" => |structure| variants: {
            for (structure.field_types) |Field| {
                if (references_present(Field, depth + 1)) {
                    @compileError("lacuna: the union '" ++ @typeName(T) ++
                        "' holds an lacuna.Reference, which only a struct, an array, " ++
                        "or an optional may hold");
                }
            }

            break :variants false;
        },
        else => false,
    };
}

fn references_present_struct(comptime T: type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < kind_module.depth_max);

    const found = for (@typeInfo(T).@"struct".field_types) |Field| {
        if (references_present(Field, depth + 1)) break true;
    } else false;

    if (found) {
        if (container(T)) {
            @compileError("lacuna: the container '" ++ @typeName(T) ++
                "' holds an lacuna.Reference, which only a struct, an array, " ++
                "or an optional may hold");
        }
    }

    return found;
}

fn container(comptime T: type) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(T != value.Reference);

    if (list.is_list(T)) return true;
    if (list.is_map(T)) return true;
    return list.is_set(T);
}

pub const Walk = struct {
    status: c_int,
    visit: python.Visit,
};

fn references_visit(comptime T: type, item: *T, walk: *Walk, comptime depth: u32) void {
    comptime assert(depth < kind_module.depth_max);
    assert(walk.visit.visitor != null);

    if (walk.status != 0) return;

    if (T == value.Reference) {
        const pointer = item.pointer orelse return;

        walk.status = walk.visit.visitor.?(pointer, walk.visit.argument);

        return;
    }

    if (comptime value.container_is(T)) {
        if (item.owned) references_visit(value.Reference, &item.reference, walk, depth + 1);

        return;
    }

    switch (@typeInfo(T)) {
        .array => |array| {
            if (references_present(array.child, depth + 1)) {
                for (item) |*element| references_visit(array.child, element, walk, depth + 1);
            }
        },
        .@"struct" => |structure| {
            inline for (structure.field_names, structure.field_types) |name, Field| {
                if (comptime references_present(Field, depth + 1)) {
                    references_visit(Field, &@field(item, name), walk, depth + 1);
                }
            }
        },
        .optional => |optional| {
            if (item.*) |*present| references_visit(optional.child, present, walk, depth + 1);
        },
        else => {},
    }
}

pub fn references_release(comptime T: type, item: *T, comptime depth: u32) void {
    comptime assert(depth < kind_module.depth_max);
    assert(@intFromPtr(item) % @alignOf(T) == 0);

    if (T == value.Reference) {
        item.release();

        return;
    }

    if (comptime value.container_is(T)) {
        if (item.owned) item.reference.release();

        return;
    }

    switch (@typeInfo(T)) {
        .array => |array| {
            if (references_present(array.child, depth + 1)) {
                for (item) |*element| references_release(array.child, element, depth + 1);
            }
        },
        .@"struct" => |structure| {
            inline for (structure.field_names, structure.field_types) |name, Field| {
                if (comptime references_present(Field, depth + 1)) {
                    references_release(Field, &@field(item, name), depth + 1);
                }
            }
        },
        .optional => |optional| {
            if (item.*) |*present| references_release(optional.child, present, depth + 1);
        },
        else => {},
    }
}

test references_present {
    const Holder = struct {
        count: u32,
        items: [2]value.Reference,
    };

    comptime {
        assert(references_present(Holder, 0));
        assert(references_present(struct { inner: Holder }, 0));
        assert(!references_present(struct { count: u32 }, 0));
        assert(!references_present(value.Object, 0));
    }
}
