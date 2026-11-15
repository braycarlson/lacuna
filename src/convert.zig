const std = @import("std");

const c = @import("c.zig");
const kind_module = @import("kind.zig");
const registry = @import("registry.zig");
const scope_module = @import("scope.zig");
const value = @import("value.zig");

const assert = std.debug.assert;
const root = @import("root");

const BindingType = @import("module.zig").BindingType;
const Module = registry.Module;
const Scope = scope_module.Scope;
const from_python = @import("from_python.zig").from_python;
const kind_of = kind_module.kind_of;
const to_python = @import("to_python.zig").to_python;

pub const Error = error{PythonError};

pub fn object_new(comptime T: type, item: T) Error!*c.PyObject {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    comptime assert(T != type);
    assert(item_valid(T, &item));

    const Converted = Normalized(T);
    const converted: Converted = if (@typeInfo(T) == .null) null else item;
    const Binding = BindingOf(Converted);
    const state = try state_of(Binding);

    return to_python(Binding, Converted, state, &converted) catch {
        return error.PythonError;
    };
}

pub fn item_valid(comptime T: type, item: *const T) bool {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    return switch (@typeInfo(T)) {
        .optional => |optional| optional: {
            const present = if (item.*) |*inner| inner else break :optional true;

            break :optional item_valid(optional.child, present);
        },
        .pointer => |pointer| if (comptime textual(pointer))
            std.unicode.utf8ValidateSlice(item.*)
        else
            true,
        else => true,
    };
}

fn textual(comptime pointer: std.lang.Type.Pointer) bool {
    comptime assert(pointer.child != void);

    if (text_pointer(pointer)) return true;
    return text_slice(pointer);
}

pub fn value_of(comptime T: type, object: *c.PyObject) Error!T {
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(object) % c.object_alignment == 0);

    const Binding = BindingOf(T);
    const holders = comptime scope_module.holder_count(T, Binding.declared, 0);
    const views = comptime scope_module.view_count(T, Binding.declared, false);
    const label = "a callback result";

    comptime convertible_check(T, Binding.declared);

    const state = try state_of(Binding);

    var objects: [holders]*c.PyObject = undefined;
    var buffers: [views]c.Py_buffer = undefined;

    var scope: Scope = .init(.{ .objects = &objects, .views = &buffers });
    defer scope.release();

    return from_python(Binding, T, label, state, object, &scope) catch {
        return error.PythonError;
    };
}

pub fn BindingOf(comptime T: type) type {
    comptime assert(T != type);

    const Matcher = struct {
        pub fn matches(comptime module: Module) bool {
            if (kind_module.class_index(T, module.classes ++ module.unions) != null) return true;
            if (@typeInfo(T) != .@"enum") return false;
            return kind_module.class_index(T, module.enums) != null;
        }
    };

    const found = BindingSearched(Matcher, "converting '" ++ @typeName(T) ++ "'");

    return found orelse BindingType(root.lacuna_module);
}

pub fn BindingWarning(comptime name: []const u8) type {
    comptime assert(name.len > 0);

    const Matcher = struct {
        pub fn matches(comptime module: Module) bool {
            comptime assert(module.name.len > 0);

            return registry.warning_is(module, name);
        }
    };

    return BindingSearched(Matcher, "the warning '" ++ name ++ "'") orelse {
        @compileError("lacuna: no module of '" ++ root.lacuna_module.name ++ "' declares the " ++
            "warning '" ++ name ++ "' in its bases");
    };
}

fn BindingSearched(comptime Matcher: type, comptime subject: []const u8) ?type {
    comptime assert(@hasDecl(Matcher, "matches"));
    comptime assert(subject.len > 0);

    if (!@hasDecl(root, "lacuna_module")) {
        @compileError("lacuna: " ++ subject ++ " needs the module of an extension that " ++
            "lacuna.add_extension builds");
    }

    if (Matcher.matches(root.lacuna_module)) return BindingType(root.lacuna_module);

    var layer: []const Module = root.lacuna_module.submodules;

    for (0..kind_module.depth_max) |_| {
        var next: []const Module = &.{};

        for (layer) |submodule| {
            if (Matcher.matches(submodule)) return BindingType(submodule);

            next = next ++ submodule.submodules;
        }

        if (next.len == 0) return null;

        layer = next;
    }

    @compileError("lacuna: the submodules of '" ++ root.lacuna_module.name ++ "' nest deeper " ++
        "than the search for " ++ subject ++ " reaches");
}

pub fn state_of(comptime Binding: type) Error!*const Binding.State {
    comptime assert(@hasDecl(Binding, "current"));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    if (Binding.current) |state| return state;
    return Binding.state_current() orelse error.PythonError;
}

fn Normalized(comptime T: type) type {
    comptime assert(T != type);

    return switch (@typeInfo(T)) {
        .comptime_int => i64,
        .comptime_float => f64,
        .null => ?value.Object,
        .pointer => |pointer| if (text_pointer(pointer)) []const u8 else T,
        else => T,
    };
}

fn text_pointer(comptime pointer: std.lang.Type.Pointer) bool {
    comptime assert(pointer.child != void);

    return switch (pointer.size) {
        .one => switch (@typeInfo(pointer.child)) {
            .array => |array| array.child == u8,
            else => false,
        },
        .slice => pointer.child == u8 and !pointer.attrs.@"const",
        .c, .many => false,
    };
}

fn text_slice(comptime pointer: std.lang.Type.Pointer) bool {
    comptime assert(pointer.child != void);

    if (pointer.size != .slice) return false;
    return pointer.child == u8;
}

fn convertible_check(comptime T: type, comptime classes: []const type) void {
    comptime assert(T != type);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (source_bound(T, classes)) return;

    if (kind_of(T, classes) == .optional) {
        if (source_bound(@typeInfo(T).optional.child, classes)) return;
    }

    if (kind_module.owned(T, classes, 0)) return;

    @compileError("lacuna: '" ++ @typeName(T) ++ "' would borrow from Python past the " ++
        "conversion; convert to an owned type, such as lacuna.TextType in place of a nested " ++
        "slice or a class by value in place of a pointer");
}

fn source_bound(comptime T: type, comptime classes: []const type) bool {
    comptime assert(T != type);
    comptime assert(classes.len <= std.math.maxInt(u32));

    return switch (kind_of(T, classes)) {
        .bytes, .container, .object, .reference, .text, .text_terminated => true,
        else => false,
    };
}

test Normalized {
    comptime {
        assert(Normalized(comptime_int) == i64);
        assert(Normalized(comptime_float) == f64);
        assert(Normalized(@TypeOf(null)) == ?value.Object);
        assert(Normalized(*const [3:0]u8) == []const u8);
        assert(Normalized([]u8) == []const u8);
        assert(Normalized([]const u8) == []const u8);
        assert(Normalized([:0]const u8) == [:0]const u8);
        assert(Normalized(u32) == u32);
    }
}

test item_valid {
    const text: []const u8 = "caf\xc3\xa9";
    const broken: []const u8 = "\xff";
    const missing: ?[]const u8 = null;
    const count: u32 = 7;

    try std.testing.expect(item_valid([]const u8, &text));
    try std.testing.expect(!item_valid([]const u8, &broken));
    try std.testing.expect(item_valid(?[]const u8, &missing));
    try std.testing.expect(item_valid(u32, &count));
}

test source_bound {
    comptime {
        assert(source_bound([]const u8, &.{}));
        assert(source_bound(value.Object, &.{}));
        assert(source_bound(value.ListObject, &.{}));
        assert(!source_bound(u32, &.{}));
        assert(!source_bound([]const f64, &.{}));
        assert(kind_module.owned(struct { count: u32 }, &.{}, 0));
        assert(!kind_module.owned(struct { name: []const u8 }, &.{}, 0));
    }
}
