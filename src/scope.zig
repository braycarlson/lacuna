const std = @import("std");

const c = @import("c.zig");
const critical = @import("critical.zig");
const kind_module = @import("kind.zig");

const assert = std.debug.assert;

const kind_of = kind_module.kind_of;

pub const holder_count_max: u32 = 1024;
pub const view_count_max: u32 = 64;

pub const Scope = struct {
    objects: []*c.PyObject,
    object_count: u32,
    sections: []critical.Section,
    section_count: u32,
    views: []c.Py_buffer,
    view_count: u32,

    pub const Storage = struct {
        objects: []*c.PyObject,
        sections: []critical.Section,
        views: []c.Py_buffer,
    };

    pub fn init(storage: Storage) Scope {
        assert(storage.objects.len <= holder_count_max);
        assert(storage.views.len <= view_count_max);
        assert(storage.sections.len <= holder_count_max);

        return .{
            .objects = storage.objects,
            .object_count = 0,
            .sections = storage.sections,
            .section_count = 0,
            .views = storage.views,
            .view_count = 0,
        };
    }

    pub fn lock(scope: *Scope, object: *c.PyObject) void {
        assert(scope.section_count < scope.sections.len);
        assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);

        scope.sections[scope.section_count] = critical.empty;

        critical.begin(&scope.sections[scope.section_count], object);
        scope.section_count += 1;
    }

    pub fn hold(scope: *Scope, object: *c.PyObject) void {
        assert(scope.object_count < scope.objects.len);
        assert(scope.object_count <= holder_count_max);

        scope.objects[scope.object_count] = object;
        scope.object_count += 1;
    }

    pub fn view_next(scope: *Scope) *c.Py_buffer {
        assert(scope.view_count < scope.views.len);
        assert(scope.view_count <= view_count_max);

        return &scope.views[scope.view_count];
    }

    pub fn view_commit(scope: *Scope) void {
        assert(scope.view_count < scope.views.len);
        assert(scope.views[scope.view_count].obj != null);

        scope.view_count += 1;
    }

    pub fn release(scope: *Scope) void {
        assert(scope.object_count <= scope.objects.len);
        assert(scope.view_count <= scope.views.len);

        while (scope.section_count > 0) {
            scope.section_count -= 1;

            critical.end(&scope.sections[scope.section_count]);
        }

        while (scope.view_count > 0) {
            scope.view_count -= 1;

            c.PyBuffer_Release(&scope.views[scope.view_count]);
        }

        while (scope.object_count > 0) {
            scope.object_count -= 1;

            c.Py_DecRef(scope.objects[scope.object_count]);
        }
    }
};

pub fn holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (depth == kind_module.depth_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' nests too deeply");
    }

    const result: u32 = switch (comptime kind_of(T, classes)) {
        .array => 1 + @typeInfo(T).array.len * holder_count(
            @typeInfo(T).array.child,
            classes,
            depth + 1,
        ),
        .list => 1 + T.capacity_max * holder_count(T.Item, classes, depth + 1),
        .map => 1 + T.capacity_max * (holder_count(T.Key, classes, depth + 1) +
            holder_count(T.Value, classes, depth + 1)),
        .optional => holder_count(@typeInfo(T).optional.child, classes, depth + 1),
        .path => 2,
        .record, .tuple => fields_holder_count(T, classes, depth),
        .set => 1 + T.capacity_max * (1 + holder_count(T.Item, classes, depth + 1)),
        .variant => variant_holder_count(T, classes, depth),
        else => 0,
    };

    if (result > holder_count_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' holds too many objects");
    }

    comptime assert(result <= holder_count_max);

    return result;
}

pub fn section_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (depth == kind_module.depth_max) return 0;

    const result: u32 = switch (comptime kind_of(T, classes)) {
        .class_pointer, .class_pointer_mutable, .class_value => 1,
        .array => @typeInfo(T).array.len * section_count(
            @typeInfo(T).array.child,
            classes,
            depth + 1,
        ),
        .list, .set => T.capacity_max * section_count(T.Item, classes, depth + 1),
        .map => T.capacity_max * (section_count(T.Key, classes, depth + 1) +
            section_count(T.Value, classes, depth + 1)),
        .optional => section_count(@typeInfo(T).optional.child, classes, depth + 1),
        .record, .tuple => fields: {
            var result: u32 = 0;

            for (@typeInfo(T).@"struct".field_types) |Field| {
                result += section_count(Field, classes, depth + 1);
            }

            break :fields result;
        },
        .variant => payloads: {
            var result: u32 = 0;

            for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) result += section_count(Payload, classes, depth + 1);
            }

            break :payloads result;
        },
        else => 0,
    };

    if (result > holder_count_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' locks too many instances");
    }

    comptime assert(result <= holder_count_max);

    return result;
}

pub fn view_count(comptime T: type, comptime classes: []const type, comptime nested: bool) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);

    const kind = comptime kind_of(T, classes);

    switch (kind) {
        .buffer, .buffer_mutable, .buffer_strided, .bytes, .bytes_owned => {
            if (nested) {
                @compileError("lacuna: the buffer type '" ++ @typeName(T) ++
                    "' is allowed only as an argument or an optional argument");
            }

            return 1;
        },
        .optional => return view_count(@typeInfo(T).optional.child, classes, nested),
        .array => {
            _ = view_count(@typeInfo(T).array.child, classes, true);

            return 0;
        },
        .list, .set => {
            _ = view_count(T.Item, classes, true);

            return 0;
        },
        .map => {
            _ = view_count(T.Key, classes, true);
            _ = view_count(T.Value, classes, true);

            return 0;
        },
        .variant => {
            var result: u32 = 0;

            inline for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) result += view_count(Payload, classes, nested);
            }

            return result;
        },
        .record, .tuple => {
            inline for (@typeInfo(T).@"struct".field_types) |Field| {
                _ = view_count(Field, classes, true);
            }

            return 0;
        },
        else => return 0,
    }
}

pub fn record_section_count(comptime T: type, comptime classes: []const type) u32 {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(classes.len <= std.math.maxInt(u32));

    var result: u32 = 0;

    for (@typeInfo(T).@"struct".field_types) |Field| result += section_count(Field, classes, 1);

    return result;
}

pub fn record_holder_count(comptime T: type, comptime classes: []const type) u32 {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(classes.len <= std.math.maxInt(u32));

    const result = fields_holder_count(T, classes, 0);

    if (result > holder_count_max) {
        @compileError("lacuna: the record '" ++ @typeName(T) ++ "' holds too many objects");
    }

    return result;
}

fn variant_holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(depth < kind_module.depth_max);

    var result: u32 = 0;

    inline for (@typeInfo(T).@"union".field_types) |Payload| {
        if (Payload != void) result += holder_count(Payload, classes, depth + 1);
    }

    return result;
}

fn fields_holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < kind_module.depth_max);

    var result: u32 = 1;

    inline for (@typeInfo(T).@"struct".field_types) |Field| {
        result += 1 + holder_count(Field, classes, depth + 1);
    }

    return result;
}

test holder_count {
    const Pair = struct { []const u8, u32 };
    const Settings = struct { name: []const u8, level: u8 };

    comptime {
        assert(holder_count(u32, &.{}, 0) == 0);
        assert(holder_count([3]u8, &.{}, 0) == 1);
        assert(holder_count([2][3]u8, &.{}, 0) == 3);
        assert(holder_count(Pair, &.{}, 0) == 3);
        assert(holder_count(Settings, &.{}, 0) == 3);
        assert(holder_count(?[2]u8, &.{}, 0) == 1);
        assert(view_count([]const f64, &.{}, false) == 1);
        assert(view_count(?[]const f64, &.{}, false) == 1);
        assert(view_count([4]u8, &.{}, false) == 0);
    }
}
