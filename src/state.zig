const std = @import("std");

const c = @import("c.zig");
const exception = @import("exception.zig");

const assert = std.debug.assert;

const Builtin = exception.Builtin;

pub const Builtins = struct {
    objects: [exception.builtin_count]?*c.PyObject,

    pub fn get(builtins: *const Builtins, which: Builtin) *c.PyObject {
        assert(@backingInt(which) < exception.builtin_count);
        assert(builtins.objects[@backingInt(which)] != null);

        const index = @backingInt(which);
        return builtins.objects[index].?;
    }

    pub fn load(builtins: *Builtins) error{Raised}!void {
        assert(builtins.objects[0] == null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const module = c.PyImport_ImportModule("builtins") orelse return error.Raised;
        defer c.Py_DecRef(module);

        for (exception.builtin_names, 0..) |name, index| {
            const object = c.PyObject_GetAttrString(module, name) orelse return error.Raised;

            builtins.objects[index] = object;
        }

        assert(builtins.objects[exception.builtin_count - 1] != null);

        for (std.enums.values(Singleton)) |which| {
            const builtin = singleton_builtins[@backingInt(which)];
            const object = builtins.objects[@backingInt(builtin)].?;

            singleton_slot(which).store(object, .release);
        }
    }
};

pub const Singleton = enum(u8) {
    none,
    ellipsis,
    not_implemented,
};

const singleton_builtins = [_]Builtin{ .none, .ellipsis, .not_implemented };

comptime {
    assert(singleton_builtins.len == std.enums.values(Singleton).len);
}

pub fn singleton_get(which: Singleton) *c.PyObject {
    assert(@backingInt(which) < singleton_builtins.len);

    const object = singleton_slot(which).load(.acquire);

    assert(object != null);

    return object.?;
}

fn singleton_slot(which: Singleton) *std.atomic.Value(?*c.PyObject) {
    const Singletons = struct {
        var objects: [singleton_builtins.len]std.atomic.Value(?*c.PyObject) = @splat(.init(null));
    };

    assert(@backingInt(which) < Singletons.objects.len);

    return &Singletons.objects[@backingInt(which)];
}

pub const Library = struct {
    objects: [library_count]?*c.PyObject,

    pub const Item = enum(u8) {
        address_v4,
        address_v6,
        date,
        datetime,
        decimal,
        enumeration,
        fraction,
        mapping,
        path,
        set,
        time,
        timedelta,
        timezone,
        uuid,
        zone,
    };

    const library_count = @typeInfo(Item).@"enum".field_names.len;

    const sources = [library_count]Source{
        .{ .module = "ipaddress", .name = "IPv4Address" },
        .{ .module = "ipaddress", .name = "IPv6Address" },
        .{ .module = "datetime", .name = "date" },
        .{ .module = "datetime", .name = "datetime" },
        .{ .module = "decimal", .name = "Decimal" },
        .{ .module = "enum", .name = "IntEnum" },
        .{ .module = "fractions", .name = "Fraction" },
        .{ .module = "collections.abc", .name = "Mapping" },
        .{ .module = "pathlib", .name = "Path" },
        .{ .module = "collections.abc", .name = "Set" },
        .{ .module = "datetime", .name = "time" },
        .{ .module = "datetime", .name = "timedelta" },
        .{ .module = "datetime", .name = "timezone" },
        .{ .module = "uuid", .name = "UUID" },
        .{ .module = "zoneinfo", .name = "ZoneInfo" },
    };

    const Source = struct {
        module: [:0]const u8,
        name: [:0]const u8,
    };

    pub const empty: Library = .{ .objects = @splat(null) };

    pub fn get(library: *Library, item: Item) error{Raised}!*c.PyObject {
        assert(@backingInt(item) < library_count);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const slot = &library.objects[@backingInt(item)];
        if (@atomicLoad(?*c.PyObject, slot, .acquire)) |present| return present;

        const source = sources[@backingInt(item)];
        const module = c.PyImport_ImportModule(source.module) orelse return error.Raised;
        defer c.Py_DecRef(module);

        const object = c.PyObject_GetAttrString(module, source.name) orelse return error.Raised;

        if (@cmpxchgStrong(?*c.PyObject, slot, null, object, .acq_rel, .acquire)) |winner| {
            c.Py_DecRef(object);

            return winner.?;
        }

        assert(@atomicLoad(?*c.PyObject, slot, .acquire) == object);

        return object;
    }

    pub fn clear(library: *Library) void {
        assert(library.objects.len == library_count);
        assert(sources.len == library_count);

        for (&library.objects) |*slot| {
            const object = slot.*;

            slot.* = null;

            c.Py_DecRef(object);
        }
    }
};

pub const Counts = struct {
    classes: u32,
    enums: u32,
    errors: u32,
    variants: u32,
};

pub fn StateType(comptime counts: Counts) type {
    comptime assert(counts.classes <= std.math.maxInt(u8));
    comptime assert(counts.errors <= std.math.maxInt(u15));

    const class_count = counts.classes;
    const enum_count = counts.enums;
    const error_count = counts.errors;
    const variant_count = counts.variants;
    const object_count = 1 + error_count + class_count + enum_count + variant_count;

    return struct {
        builtins: Builtins,
        library: Library,
        objects: [object_count]?*c.PyObject,

        const State = @This();
        const class_first = error_first + error_count;
        const enum_first = class_first + class_count;
        const variant_first = enum_first + enum_count;
        const error_base_index = 0;
        const error_first = 1;

        comptime {
            assert(@alignOf(State) <= @alignOf(*c.PyObject));
            assert(variant_first + variant_count == object_count);
        }

        pub fn of_module(module: *c.PyObject) *State {
            const pointer = c.PyModule_GetState(module);

            assert(pointer != null);
            assert(@intFromPtr(pointer.?) % @alignOf(State) == 0);

            return @ptrCast(@alignCast(pointer.?));
        }

        pub fn of_class(class: *c.PyObject) *State {
            const module = c.PyType_GetModule(class);

            assert(module != null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            return of_module(module.?);
        }

        pub fn library_get(state: *const State, item: Library.Item) error{Raised}!*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@backingInt(item) < Library.library_count);

            const library: *Library = @constCast(&state.library);
            return library.get(item);
        }

        pub fn class_get(state: *const State, index: u32) *c.PyObject {
            assert(index < class_count);
            assert(state.objects[class_first + index] != null);

            return state.objects[class_first + index].?;
        }

        pub fn class_set(state: *State, index: u32, object: *c.PyObject) void {
            assert(index < class_count);
            assert(state.objects[class_first + index] == null);

            state.objects[class_first + index] = object;
        }

        pub fn enum_get(state: *const State, index: u32) *c.PyObject {
            assert(index < enum_count);
            assert(state.objects[enum_first + index] != null);

            return state.objects[enum_first + index].?;
        }

        pub fn enum_set(state: *State, index: u32, object: *c.PyObject) void {
            assert(index < enum_count);
            assert(state.objects[enum_first + index] == null);

            state.objects[enum_first + index] = object;
        }

        pub fn variant_get(state: *const State, index: u32) *c.PyObject {
            assert(index < variant_count);
            assert(state.objects[variant_first + index] != null);

            return state.objects[variant_first + index].?;
        }

        pub fn variant_set(state: *State, index: u32, object: *c.PyObject) void {
            assert(index < variant_count);
            assert(state.objects[variant_first + index] == null);

            state.objects[variant_first + index] = object;
        }

        pub fn error_base(state: *const State) *c.PyObject {
            assert(state.objects[error_base_index] != null);
            assert(error_base_index < object_count);

            return state.objects[error_base_index].?;
        }

        pub fn error_base_set(state: *State, object: *c.PyObject) void {
            assert(state.objects[error_base_index] == null);
            assert(error_base_index < object_count);

            state.objects[error_base_index] = object;
        }

        pub fn error_class(state: *const State, index: u32) *c.PyObject {
            assert(index < error_count);
            assert(state.objects[error_first + index] != null);

            return state.objects[error_first + index].?;
        }

        pub fn error_class_set(state: *State, index: u32, object: *c.PyObject) void {
            assert(index < error_count);
            assert(state.objects[error_first + index] == null);

            state.objects[error_first + index] = object;
        }

        pub fn clear(state: *State) void {
            assert(state.objects.len == object_count);
            assert(state.builtins.objects.len == exception.builtin_count);

            for (&state.objects) |*slot| {
                const object = slot.*;

                slot.* = null;

                c.Py_DecRef(object);
            }

            for (&state.builtins.objects) |*slot| {
                const object = slot.*;

                slot.* = null;

                c.Py_DecRef(object);
            }

            state.library.clear();
        }
    };
}

test StateType {
    const State = StateType(.{ .classes = 2, .enums = 1, .errors = 3, .variants = 4 });

    const state: State = .{
        .builtins = .{ .objects = @splat(null) },
        .library = .empty,
        .objects = @splat(null),
    };

    try std.testing.expectEqual(11, state.objects.len);
    try std.testing.expectEqual(7, State.variant_first);
    try std.testing.expectEqual(4, State.class_first);
    try std.testing.expect(state.objects[State.error_base_index] == null);
}
