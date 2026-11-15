const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const calendar = @import("calendar.zig");
const exception = @import("exception.zig");
const kind_module = @import("kind.zig");
const list = @import("list.zig");
const native_module = @import("native.zig");
const python = @import("python.zig");
const text = @import("text.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

const ListType = list.ListType;
const Native = native_module.Native;
const TextType = text.TextType;
const native_of = native_module.native_of;

pub const alignment_max: u32 = 2 * @sizeOf(?*c.PyObject);
pub const base_depth_max: u32 = std.math.maxInt(u32);
pub const dealloc_depth_max: u32 = 64;
pub const pool_capacity_max: u32 = 4096;
pub const pool_lock_attempt_max: u32 = 1 << 16;
pub const references_depth_max: u32 = 16;

pub fn PoolType(comptime classes: []const type) type {
    comptime assert(classes.len <= std.math.maxInt(u8));

    const total = total: {
        var result: u32 = 0;

        for (classes) |Class| result += InstanceType(Class).pool_capacity;

        break :total result;
    };

    if (total == 0) return void;

    const capacities = capacities: {
        var result: [classes.len]u32 = undefined;

        for (classes, &result) |Class, *capacity| capacity.* = InstanceType(Class).pool_capacity;

        break :capacities result;
    };

    return struct {
        closed: bool,
        counts: [classes.len]u32,
        mutex: std.atomic.Mutex,
        objects: [total]?*c.PyObject,

        const Pool = @This();

        pub fn keep(pool: *Pool, comptime index: u32, object: *c.PyObject) bool {
            comptime assert(index < classes.len);
            comptime assert(capacities[index] > 0);
            assert(@intFromPtr(object) % c.object_alignment == 0);

            if (!pool.mutex.tryLock()) return false;
            defer pool.mutex.unlock();

            if (pool.closed) return false;

            const count = pool.counts[index];

            assert(count <= capacities[index]);

            if (count == capacities[index]) return false;

            const offset = comptime offset_of(index);

            pool.objects[offset + count] = object;
            pool.counts[index] = count + 1;

            return true;
        }

        pub fn take(pool: *Pool, comptime index: u32) ?*c.PyObject {
            comptime assert(index < classes.len);
            comptime assert(capacities[index] > 0);

            if (!pool.mutex.tryLock()) return null;
            defer pool.mutex.unlock();

            if (pool.closed) return null;

            const count = pool.counts[index];

            assert(count <= capacities[index]);

            if (count == 0) return null;

            const offset = comptime offset_of(index);
            const slot = &pool.objects[offset + count - 1];
            const object = slot.*.?;

            slot.* = null;
            pool.counts[index] = count - 1;

            return object;
        }

        pub fn drain(pool: *Pool, state: anytype) void {
            comptime assert(@typeInfo(@TypeOf(state)) == .pointer);
            comptime assert(@hasDecl(@typeInfo(@TypeOf(state)).pointer.child, "class_get"));

            for (0..pool_lock_attempt_max) |_| {
                if (pool.mutex.tryLock()) break;

                std.atomic.spinLoopHint();
            } else return;

            defer pool.mutex.unlock();

            if (pool.closed) return;

            pool.closed = true;

            inline for (0..classes.len) |index| {
                if (capacities[index] > 0) {
                    if (pool.counts[index] > 0) pool.drain_class(index, state.class_get(index));
                }
            }
        }

        fn drain_class(pool: *Pool, comptime index: u32, class: *c.PyObject) void {
            comptime assert(index < classes.len);
            assert(pool.closed);

            const count = pool.counts[index];

            assert(count <= capacities[index]);

            const slot = c.PyType_GetSlot(class, c.Py_tp_free).?;
            const free: *const fn (?*anyopaque) callconv(.c) void = @ptrCast(@alignCast(slot));

            for (pool.objects[offset_of(index)..][0..count]) |*entry| {
                const object = entry.*.?;

                assert(python.type_borrowed(object) == class);

                entry.* = null;
                free(object);
            }

            pool.counts[index] = 0;
        }

        fn offset_of(comptime index: u32) u32 {
            comptime assert(index < classes.len);

            var result: u32 = 0;

            for (capacities[0..index]) |capacity| result += capacity;

            return result;
        }
    };
}

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
    const native: ?Native = native_of(Class);

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
            exports: Exports,
            dictionary: SlotOwned(dictionary_owned),
            weaklist: SlotOwned(weaklist_owned),
            link: SlotOwned(c.opaque_object),
            thread: Thread,
        };

        pub const Exports = if (@hasDecl(Class, "__buffer__")) std.atomic.Value(u32) else void;
        pub const Thread = if (thread_affine) std.Thread.Id else void;
        pub const thread_affine = @hasDecl(Class, "thread_affine") and Class.thread_affine;

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
        const Traverse = *const fn (*c.PyObject, c.visitproc, c.VisitArgument) callconv(.c) c_int;
        const Inquiry = *const fn (*c.PyObject) callconv(.c) c_int;
        const Finalize = *const fn (*c.PyObject) callconv(.c) void;
        const Free = *const fn (?*anyopaque) callconv(.c) void;
        const pointer_size: u32 = @sizeOf(*c.PyObject);

        pub const base: ?type = Base;
        pub const native_base: ?Native = native;
        pub const metaclass = native == .type;
        pub const subclassable = @hasDecl(Class, "subclassable") and Class.subclassable;
        pub const frozen = @hasDecl(Class, "frozen") and Class.frozen;

        const header_size: u32 = if (c.opaque_object) 0 else @sizeOf(c.PyObject_Header);
        const prefix_size: u32 = if (Base != null) Parent.basic_size else header_size;
        const dictionary_inherited: ?u32 = if (Base != null) Parent.dictionary_offset else null;
        const weaklist_inherited: ?u32 = if (Base != null) Parent.weaklist_offset else null;
        const dictionary_requested = @hasDecl(Class, "dictionary") and Class.dictionary;
        const weaklist_requested = @hasDecl(Class, "weakref") and Class.weakref;
        pub const dictionary_owned = dictionary_requested and dictionary_inherited == null and
            native == null;
        pub const weaklist_owned = weaklist_requested and weaklist_inherited == null and
            native == null;
        const owned_first: u32 = std.mem.alignForward(u32, prefix_size, pointer_size);

        pub const dictionary_offset: ?u32 = if (!dictionary_owned)
            dictionary_inherited
        else if (c.opaque_object)
            @offsetOf(Storage, "dictionary")
        else
            owned_first;

        pub const base_dictionary_offset: ?u32 = dictionary_inherited;

        pub const weaklist_offset: ?u32 = if (!weaklist_owned)
            weaklist_inherited
        else if (c.opaque_object)
            @offsetOf(Storage, "weaklist")
        else
            owned_first + @as(u32, if (dictionary_owned) pointer_size else 0);

        const owned_count: u32 = @as(u32, @intFromBool(dictionary_owned)) +
            @intFromBool(weaklist_owned);

        const owned_end: u32 = owned_first + pointer_size * owned_count;

        pub const referencing = references_present(Class, 0) or
            (Base != null and Parent.referencing);

        pub const collected = referencing or dictionary_offset != null or traversed;
        pub const traversed = traverse_hooked(Class) or (Base != null and Parent.traversed);

        pub const finalizer_present: bool = deinit_fallible(Class) or
            (Base != null and Parent.finalizer_present);

        pub const pool_capacity: u32 = if (@hasDecl(Class, "freelist")) pool: {
            const requested: u32 = Class.freelist;

            const refused = std.fmt.comptimePrint("lacuna: the freelist of '{s}' holds {d} " ++
                "instances; it holds from 1 to {d}", .{
                @typeName(Class),
                requested,
                pool_capacity_max,
            });

            if (requested == 0) @compileError(refused);
            if (requested > pool_capacity_max) @compileError(refused);

            if (native != null) {
                @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' extends a native " ++
                    "base, which allocates its instances, so it keeps no freelist");
            }

            if (finalizer_present) {
                @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' has a fallible " ++
                    "deinit, which runs as a finalizer, so it keeps no freelist");
            }

            if (c.pypy) break :pool 0;
            if (c.opaque_object) break :pool 0;

            break :pool requested;
        } else 0;

        pub const storage_offset: u32 = std.mem.alignForward(
            u32,
            owned_end,
            @alignOf(Storage),
        );

        pub const basic_size: u32 = storage_offset + @sizeOf(Storage);

        pub const specification_size: c_int = if (type_data)
            -@as(c_int, @sizeOf(Storage))
        else
            basic_size;

        const type_data = native != null or c.opaque_object;

        threadlocal var dealloc_depth: u32 = 0;
        threadlocal var dealloc_deferred: ?*c.PyObject = null;
        pub threadlocal var finalizer_detached: bool = false;

        comptime {
            assert(@alignOf(Storage) <= alignment_max);
            assert(@sizeOf(Storage) <= std.math.maxInt(c_int));

            if (!c.opaque_object) {
                assert(basic_size <= std.math.maxInt(c_int));
                assert(storage_offset >= prefix_size);
                assert(storage_offset % @alignOf(Storage) == 0);

                if (dictionary_offset) |offset| assert(offset >= header_size);
                if (weaklist_offset) |offset| assert(offset >= header_size);
            }
        }

        pub fn allocate(class: *c.PyObject) error{Raised}!Allocation {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(defining_of(class) != null);

            if (native != null) {
                const arguments = c.PyTuple_New(0) orelse return error.Raised;
                defer c.Py_DecRef(arguments);

                return native_allocate(class, .{ .arguments = arguments, .keywords = null });
            }

            if (pool_capacity > 0) {
                if (pool_take(class)) |object| {
                    pool_revive(.{ .class = class, .object = object });

                    const revived = storage_of(object);

                    thread_claim(revived);

                    return .{ .object = object, .storage = revived };
                }
            }

            const slot = c.PyType_GetSlot(class, c.Py_tp_alloc) orelse return error.Raised;
            const function: Allocate = @ptrCast(@alignCast(slot));
            const object = function(class, 0) orelse return error.Raised;
            const storage = storage_of(object);

            assert(!storage.initialized);

            thread_claim(storage);

            return .{ .object = object, .storage = storage };
        }

        fn thread_claim(storage: *Storage) void {
            assert(!storage.initialized);
            assert(@intFromPtr(storage) % @alignOf(Storage) == 0);

            if (thread_affine) storage.thread = std.Thread.getCurrentId();
        }

        pub fn thread_foreign(object: *c.PyObject) bool {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            if (comptime !thread_affine) return false;
            if (!owned_by(object)) return false;

            const storage = storage_of(object);

            return storage.initialized and storage.thread != std.Thread.getCurrentId();
        }

        pub fn thread_refuse() void {
            comptime assert(thread_affine);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const message = "the '" ++ @typeName(Class) ++ "' object belongs to the thread " ++
                "that created it";
            const kind = python.builtin_new("RuntimeError") orelse return;
            defer c.Py_DecRef(kind);

            c.PyErr_SetString(kind, message);
        }

        fn pool_state_of(class: *c.PyObject) ?*PoolBinding().State {
            comptime assert(pool_capacity > 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (!owns(class)) return null;

            const module = c.PyType_GetModule(class) orelse {
                c.PyErr_Clear();

                return null;
            };

            return PoolBinding().State.of_module(module);
        }

        fn PoolBinding() type {
            comptime assert(pool_capacity > 0);
            comptime assert(@typeInfo(Class) == .@"struct");

            return @import("convert.zig").BindingOf(Class);
        }

        fn pool_index() u32 {
            comptime assert(pool_capacity > 0);

            return comptime kind_module.class_index(Class, PoolBinding().classes).?;
        }

        fn pool_take(class: *c.PyObject) ?*c.PyObject {
            comptime assert(pool_capacity > 0);
            assert(@intFromPtr(class) % c.object_alignment == 0);

            const state = pool_state_of(class) orelse return null;

            return state.pool.take(pool_index());
        }

        fn pool_keep(pooled: Pooled) bool {
            comptime assert(pool_capacity > 0);
            assert(python.type_borrowed(pooled.object) == pooled.class);

            const state = pool_state_of(pooled.class) orelse return false;

            return state.pool.keep(pool_index(), pooled.object);
        }

        fn pool_revive(pooled: Pooled) void {
            comptime assert(pool_capacity > 0);
            comptime assert(!c.opaque_object);
            assert(python.type_borrowed(pooled.object) == pooled.class);

            const object = pooled.object;
            const class = pooled.class;
            const bytes: *[basic_size]u8 = @ptrCast(object);

            @memset(bytes, 0);

            const initialized = c.PyObject_Init(object, class);

            assert(initialized == object);
            assert(python.type_borrowed(object) == class);

            if (collected) c.PyObject_GC_Track(object);
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

            thread_claim(storage);

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
            if (thread_foreign(object)) return null;
            return &storage.value;
        }

        pub fn data_required(object: *c.PyObject) ?*Class {
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            if (data_of(object)) |data| return data;

            if (thread_affine) {
                if (c.PyErr_Occurred() == null) {
                    if (thread_foreign(object)) thread_refuse();
                }
            }

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
            assert(@intFromPtr(object) % c.object_alignment == 0);
            assert(defining_of(python.type_borrowed(object)) != null);

            if (type_data) {
                const defining = defining_of(python.type_borrowed(object)).?;
                const pointer = c.PyObject_GetTypeData(object, defining).?;

                return @ptrCast(@alignCast(pointer));
            }

            return python.storage_at(Storage, object, storage_offset);
        }

        pub fn dictionary_get(object: *c.PyObject) ?*c.PyObject {
            comptime assert(dictionary_offset != null);
            assert(owned_by(object));

            if (!c.opaque_object) {
                return python.storage_at(?*c.PyObject, object, dictionary_offset.?).*;
            }

            if (dictionary_owned) return storage_of(object).dictionary;
            return Parent.dictionary_get(object);
        }

        pub fn dictionary_take(object: *c.PyObject) ?*c.PyObject {
            comptime assert(dictionary_offset != null);
            assert(owned_by(object));

            if (!c.opaque_object) {
                const slot = python.storage_at(?*c.PyObject, object, dictionary_offset.?);
                const previous = slot.*;

                slot.* = null;

                return previous;
            }

            if (!dictionary_owned) return Parent.dictionary_take(object);

            const storage = storage_of(object);
            const previous = storage.dictionary;

            storage.dictionary = null;

            return previous;
        }

        pub fn weaklist_get(object: *c.PyObject) ?*c.PyObject {
            comptime assert(weaklist_offset != null);
            assert(owned_by(object));

            if (!c.opaque_object) {
                return python.storage_at(?*c.PyObject, object, weaklist_offset.?).*;
            }

            if (weaklist_owned) return storage_of(object).weaklist;
            return Parent.weaklist_get(object);
        }

        pub fn owns(class: *c.PyObject) bool {
            const slot = c.PyType_GetSlot(class, c.Py_tp_dealloc);
            const expected = @intFromPtr(&dealloc);

            assert(expected != 0);
            assert(@intFromPtr(class) % @alignOf(*c.PyObject) == 0);

            if (@intFromPtr(slot) != expected) return false;
            if (c.pypy) return module_owned(class);
            if (c.graalpy) return module_owned(class);

            return true;
        }

        fn module_owned(class: *c.PyObject) bool {
            comptime assert(c.pypy or c.graalpy);
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

            if (!c.graalpy) {
                if (class == defining) {
                    c.Py_IncRef(object);
                    finalizer(object);

                    assert(!storage_of(object).initialized);

                    c.Py_DecRef(object);

                    return true;
                }
            }

            assert(!finalizer_detached);

            finalizer_detached = true;
            finalizer(object);
            finalizer_detached = false;

            assert(!storage_of(object).initialized);

            return false;
        }

        fn link_get(object: *c.PyObject) ?*c.PyObject {
            assert(@intFromPtr(object) % c.object_alignment == 0);

            if (c.opaque_object) return storage_of(object).link;

            const Address = @Int(.unsigned, @bitSizeOf(c.Py_ssize_t));
            const address: Address = @bitCast(link_word(object).*);
            const result: ?*c.PyObject = @ptrFromInt(address);

            if (result) |next| assert(@intFromPtr(next) % c.object_alignment == 0);

            return result;
        }

        fn link_set(object: *c.PyObject, next: ?*c.PyObject) void {
            assert(@intFromPtr(object) % c.object_alignment == 0);
            assert(@intFromPtr(next) % c.object_alignment == 0);

            if (c.opaque_object) {
                storage_of(object).link = next;

                return;
            }

            link_word(object).* = @bitCast(@intFromPtr(next));
        }

        fn link_word(object: *c.PyObject) *c.Py_ssize_t {
            assert(@intFromPtr(object) % c.object_alignment == 0);

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

            if (weaklist_offset != null) {
                if (weaklist_get(object) != null) c.PyObject_ClearWeakRefs(object);
            }

            finalize(object);

            if (dictionary_offset != null) c.Py_DecRef(dictionary_take(object));

            if (native != null) {
                const native_slot = c.PyType_GetSlot(native_type_of(class), c.Py_tp_dealloc).?;
                const native_dealloc: Dealloc = @ptrCast(@alignCast(native_slot));

                native_dealloc(object);
                c.Py_DecRef(class);

                return;
            }

            const slot = c.PyType_GetSlot(class, c.Py_tp_free);

            assert(slot != null);

            if (pool_capacity > 0) {
                if (pool_keep(.{ .class = class, .object = object })) {
                    c.Py_DecRef(class);

                    return;
                }
            }

            const free: Free = @ptrCast(@alignCast(slot.?));

            free(object);
            c.Py_DecRef(class);
        }

        fn thread_deinit_skipped(object: *c.PyObject) void {
            comptime assert(thread_affine);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const class = python.type_borrowed(object);
            const message = "the '" ++ @typeName(Class) ++ "' object was released on another " ++
                "thread, so its deinit did not run";
            const kind = python.builtin_new("RuntimeError") orelse {
                c.PyErr_WriteUnraisable(class);

                return;
            };

            defer c.Py_DecRef(kind);

            c.PyErr_SetString(kind, message);
            c.PyErr_WriteUnraisable(class);

            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        }

        pub fn finalize(object: *c.PyObject) void {
            const storage = storage_of(object);

            if (storage.initialized) {
                if (@hasDecl(Class, "deinit")) {
                    if (comptime deinit_fallible(Class)) unreachable;

                    if (comptime !thread_affine) {
                        storage.value.deinit();
                    } else if (storage.thread == std.Thread.getCurrentId()) {
                        storage.value.deinit();
                    } else {
                        thread_deinit_skipped(object);
                    }
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
            argument: c.VisitArgument,
        ) callconv(.c) c_int {
            comptime assert(collected);
            assert(visitor != null);

            const class = python.type_borrowed(object);

            var walk: Walk = .{
                .status = visitor.?(class, argument),
                .visit = .{ .argument = argument, .procedure = visitor },
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

            if (dictionary_offset != null) {
                if (walk.status == 0) {
                    const dictionary = dictionary_get(object);

                    if (dictionary) |present| walk.status = visitor.?(present, argument);
                }
            }

            return walk.status;
        }

        pub fn contents_visit(object: *c.PyObject, walk: *Walk) void {
            assert(walk.visit.procedure != null);

            if (comptime references_present(Class, 0)) {
                references_visit(Class, &storage_of(object).value, walk, 0);
            }

            if (comptime traverse_hooked(Class)) {
                if (walk.status == 0) {
                    const storage = storage_of(object);

                    if (storage.initialized) Class.__traverse__(&storage.value, .{ .walk = walk });
                }
            }

            if (Base != null) Parent.contents_visit(object, walk);
        }

        pub fn clear(object: *c.PyObject) callconv(.c) c_int {
            comptime assert(collected);
            assert(@intFromPtr(object) % @alignOf(*c.PyObject) == 0);

            contents_clear(object);

            if (dictionary_offset != null) c.Py_DecRef(dictionary_take(object));

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

            if (comptime @hasDecl(Class, "__clear__")) {
                const storage = storage_of(object);

                if (storage.initialized) Class.__clear__(&storage.value);
            }

            if (Base != null) Parent.contents_clear(object);
        }
    };
}

fn SlotOwned(comptime owned: bool) type {
    comptime assert(@bitSizeOf(?*c.PyObject) == builtin.target.ptrBitWidth());
    comptime assert(c.object_alignment > 0);

    if (!c.opaque_object) return void;
    if (owned) return ?*c.PyObject;
    return void;
}

pub fn deinit_fallible(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "deinit")) return false;

    const Function = @TypeOf(Class.deinit);

    comptime assert(@typeInfo(Function) == .@"fn");

    return @typeInfo(@typeInfo(Function).@"fn".return_type.?) == .error_union;
}

pub fn references_present(comptime T: type, comptime depth: u32) bool {
    comptime assert(depth <= references_depth_max);
    comptime assert(T != type);

    @setEvalBranchQuota(kind_module.eval_branch_quota);

    if (T == value.Reference) return true;
    if (value.container_is(T)) return true;
    if (text.is_text(T)) return false;
    if (text.is_blob(T)) return false;
    if (leaf_value(T)) return false;

    if (depth == references_depth_max) {
        switch (@typeInfo(T)) {
            .array, .optional, .@"struct", .@"union" => {
                @compileError("lacuna: the type '" ++ @typeName(T) ++ "' nests deeper than " ++
                    std.fmt.comptimePrint("{d}", .{references_depth_max}) ++ " levels");
            },
            else => {},
        }
    }

    kind_module.layout_check(T);

    if (@typeInfo(T) == .@"struct") {
        if (container(T)) return container_references_present(T, depth);
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

fn leaf_value(comptime T: type) bool {
    comptime assert(T != type);
    comptime assert(T != value.Reference);

    const leaves = .{
        calendar.Date,
        calendar.DateTime,
        calendar.Duration,
        calendar.Time,
        std.math.Complex(f32),
        std.math.Complex(f64),
        std.math.big.int.Const,
        value.Bytes,
        value.Decimal,
        value.Fraction,
        value.IPAddress,
        value.Object,
        value.Path,
        value.Slice,
        value.UUID,
    };

    inline for (leaves) |Leaf| {
        if (T == Leaf) return true;
    }

    return false;
}

fn references_present_struct(comptime T: type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < references_depth_max);

    return for (@typeInfo(T).@"struct".field_types) |Field| {
        if (references_present(Field, depth + 1)) break true;
    } else false;
}

fn container_references_present(comptime T: type, comptime depth: u32) bool {
    comptime assert(container(T));
    comptime assert(depth < references_depth_max);

    const found = if (list.is_map(T))
        references_present(T.Key, depth + 1) or references_present(T.Value, depth + 1)
    else
        references_present(T.Item, depth + 1);

    if (found) {
        @compileError("lacuna: the container '" ++ @typeName(T) ++
            "' holds an lacuna.Reference, which only a struct, an array, " ++
            "or an optional may hold");
    }

    return false;
}

fn container(comptime T: type) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(T != value.Reference);

    if (list.is_list(T)) return true;
    if (list.is_map(T)) return true;
    return list.is_set(T);
}

const Pooled = struct {
    class: *c.PyObject,
    object: *c.PyObject,
};

pub const Walk = struct {
    status: c_int,
    visit: python.Visit,
};

pub const Visitor = struct {
    walk: *Walk,

    pub fn visit(visitor: Visitor, reference: value.Reference) bool {
        assert(visitor.walk.visit.procedure != null);
        if (reference.pointer) |pointer| assert(@intFromPtr(pointer) % c.object_alignment == 0);

        if (visitor.walk.status != 0) return false;

        const pointer = reference.pointer orelse return true;

        visitor.walk.status = visitor.walk.visit.procedure.?(pointer, visitor.walk.visit.argument);

        return visitor.walk.status == 0;
    }
};

pub fn traverse_hooked(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    const traversing = @hasDecl(Class, "__traverse__");
    const clearing = @hasDecl(Class, "__clear__");

    if (clearing) {
        if (!traversing) {
            @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' declares __clear__ " ++
                "without __traverse__, so the collector never finds the cycles it breaks");
        }
    }

    if (traversing) {
        const Expected = fn (*const Class, Visitor) void;

        if (@TypeOf(Class.__traverse__) != Expected) {
            @compileError("lacuna: '" ++ @typeName(Class) ++ ".__traverse__' must be " ++
                "fn (*const " ++ @typeName(Class) ++ ", lacuna.Visitor) void");
        }
    }

    if (clearing) {
        if (@TypeOf(Class.__clear__) != fn (*Class) void) {
            @compileError("lacuna: '" ++ @typeName(Class) ++ ".__clear__' must be fn (*" ++
                @typeName(Class) ++ ") void");
        }
    }

    return traversing;
}

pub fn references_visit(comptime T: type, item: *T, walk: *Walk, comptime depth: u32) void {
    comptime assert(depth < references_depth_max);
    assert(walk.visit.procedure != null);

    if (walk.status != 0) return;

    if (T == value.Reference) {
        const pointer = item.pointer orelse return;

        walk.status = walk.visit.procedure.?(pointer, walk.visit.argument);

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
    comptime assert(depth < references_depth_max);
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

test "a type that nests no further may sit at the depth limit" {
    const Leaves = struct { count: u32, name: []const u8 };
    const Held = struct { count: u32, held: value.Reference };

    comptime {
        assert(!references_present([]const u8, references_depth_max));
        assert(!references_present(u32, references_depth_max));
        assert(references_present(value.Reference, references_depth_max));
        assert(!references_present(Leaves, references_depth_max - 1));
        assert(references_present(Held, references_depth_max - 1));
    }
}

test "lacuna's own containers and value types count as one level, as the kind limit does" {
    const Times = ListType(calendar.DateTime, 2);
    const Index = list.MapType(TextType(4), Times, 2);
    const Inner = struct { index: ListType(Index, 2) };
    const Deep = struct { outer: struct { middle: struct { inner: Inner } } };
    const Held = struct { outer: struct { middle: struct { held: [2]?value.Reference } } };

    comptime {
        @setEvalBranchQuota(10_000);

        assert(!references_present(Deep, 0));
        assert(references_present(Held, 0));
        assert(!references_present(value.IPAddress, 0));
    }
}

test "the class walkers raise their own branch quota for a wide type" {
    const Leaf = struct {
        codes: list.SetType(u32, 4),
        flags: ?[3]bool,
        label: TextType(8),
        names: list.MapType([]const u8, ListType(u16, 4), 4),
    };
    const Wide = struct {
        first: Leaf,
        second: Leaf,
        third: Leaf,
        fourth: Leaf,
        pair: [2]Leaf,
        spare: ?Leaf,
    };

    comptime {
        assert(!references_present(Wide, 0));
        assert(!kind_module.owned(Wide, &.{}, 0));
    }
}
