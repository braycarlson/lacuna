const std = @import("std");

const c = @import("c.zig");
const limited = @import("limited");
const limited_3_12 = @import("limited_3_12");
const options = @import("options");
const version = @import("version.zig");

const assert = std.debug.assert;

pub const lacuna_abi: c.ABI = .select(.{
    .free_threaded_minor = options.free_threaded_minor,
    .pypy_minor = options.pypy_minor,
    .versioned_minor = options.versioned_minor,
});

const Class = union(enum) {
    float: u16,
    int: std.lang.Type.Int,
    pointer,
    void,
};

const Layout = struct {
    ours: type,
    theirs: type,
};

const layouts = [_]Layout{
    .{ .ours = c.PyGetSetDef, .theirs = limited.PyGetSetDef },
    .{ .ours = c.PyMethodDef, .theirs = limited.PyMethodDef },
    .{ .ours = c.PyModuleDef, .theirs = limited.PyModuleDef },
    .{ .ours = c.PyModuleDef_Base, .theirs = limited.PyModuleDef_Base },
    .{ .ours = c.PyModuleDef_Slot, .theirs = limited.PyModuleDef_Slot },
    .{ .ours = c.PyType_Slot, .theirs = limited.PyType_Slot },
    .{ .ours = c.PyType_Spec, .theirs = limited.PyType_Spec },
    .{ .ours = c.Py_buffer, .theirs = limited.Py_buffer },
};

comptime {
    @setEvalBranchQuota(1_000_000);

    const floor = version.floor;

    if (limited.PY_VERSION_HEX >> 16 < floor.rank()) {
        @compileError(std.fmt.comptimePrint("lacuna: the headers predate Python {d}.{d}", .{
            floor.major,
            floor.minor,
        }));
    }

    assert(@sizeOf(c.Py_ssize_t) == @sizeOf(limited.Py_ssize_t));
    assert(@sizeOf(c.Py_hash_t) == @sizeOf(limited.Py_hash_t));
    assert(@sizeOf(c.PyObject_Header) == @sizeOf(limited.PyObject));

    var missing: []const u8 = "";

    for (c.exports) |name| {
        if (pypy_unavailable(name)) continue;
        if (headers_removed(name)) continue;
        if (!@hasDecl(limited, name)) missing = missing ++ " " ++ name;
    }

    if (missing.len > 0) {
        @compileError("lacuna: missing from the target limited API:" ++ missing);
    }

    for (c.exports) |name| {
        if (pypy_unavailable(name)) continue;
        if (headers_removed(name)) continue;

        function_check(name);
    }

    for (@typeInfo(c).@"struct".decl_names) |name| {
        if (@TypeOf(@field(c, name)) == comptime_int) constant_check(c, limited, name);
    }

    if (c.pypy) {
        for (c.exports_pypy) |name| function_check(name);

        layout_check(c.PyObject_Header, limited.PyObject);
        layout_check(c.PyMemberDef, limited.PyMemberDef);
        pattern_check();

        if (c.api_3_12_linked) {
            for (c.exports_3_12) |name| function_check_in(limited, name);
        }
    } else if (limited_3_12.PY_VERSION_HEX >= c.api_3_12.version_hex) {
        for (@typeInfo(c.api_3_12).@"struct".decl_names) |name| {
            if (std.mem.eql(u8, name, "version_hex")) continue;

            constant_check(c.api_3_12, limited_3_12, name);
        }

        for (c.exports_3_12) |name| function_check_in(limited_3_12, name);

        layout_check(c.PyMemberDef, limited_3_12.PyMemberDef);
    } else {
        assert(limited_3_12.PY_VERSION_HEX >> 16 == floor.rank());
        assert(@typeInfo(limited_3_12.PyMemberDef) == .@"opaque");
    }

    for (layouts) |layout| layout_check(layout.ours, layout.theirs);

    if (c.free_threaded) free_threaded_check();
    if (c.versioned) versioned_check();
}

fn pattern_check() void {
    comptime assert(c.abi != .stable);
    comptime assert(@typeInfo(c.api_pattern).@"struct".decl_names.len == 2);

    for (@typeInfo(c.api_pattern).@"struct".decl_names) |name| {
        constant_check(c.api_pattern, limited, name);
    }
}

fn pypy_unavailable(comptime name: []const u8) bool {
    comptime assert(name.len > 0);

    if (!c.pypy) return false;

    for (c.pypy_unavailable) |entry| {
        if (std.mem.eql(u8, entry, name)) return true;
    }

    if (c.abi.pypy.minor < 12) {
        for (c.pypy_unavailable_3_11) |entry| {
            if (std.mem.eql(u8, entry, name)) return true;
        }
    }

    return false;
}

fn headers_removed(comptime name: []const u8) bool {
    comptime assert(name.len > 0);
    comptime assert(c.headers_removed_3_15.len > 0);

    const listed = for (c.headers_removed_3_15) |entry| {
        if (std.mem.eql(u8, entry, name)) break true;
    } else false;

    if (!listed) return false;
    if (c.pypy) return false;
    if (limited.PY_VERSION_HEX < 0x030f0000) return false;

    if (@hasDecl(limited, name)) {
        @compileError("lacuna: '" ++ name ++ "' is listed as removed but the headers declare it");
    }

    return true;
}

fn renumbered(comptime Theirs: type, comptime name: []const u8, comptime value: comptime_int) bool {
    comptime assert(name.len > 0);
    comptime assert(value >= 0);

    const table = c.slots_renumbered_3_15;

    if (!@hasDecl(Theirs, "PY_VERSION_HEX")) return false;
    if (Theirs.PY_VERSION_HEX < table.version_hex) return false;
    if (!@hasDecl(table, name)) return false;
    return @field(table, name) == value;
}

fn free_threaded_check() void {
    comptime assert(c.free_threaded);
    comptime assert(c.exports_free_threaded.len > 0);

    for (c.exports_free_threaded) |name| {
        if (!@hasDecl(limited, name)) {
            @compileError("lacuna: '" ++ name ++ "' is missing from the free-threaded API");
        }

        function_check(name);
    }

    for (@typeInfo(c.api_free_threaded).@"struct".decl_names) |name| {
        if (std.mem.eql(u8, name, "_Py_STATICALLY_ALLOCATED_FLAG")) {
            if (c.abi.free_threaded.minor < 14) continue;
        }

        constant_check(c.api_free_threaded, limited, name);
    }

    layout_check(c.PyObject_Header, limited.PyObject);
    layout_check(c.PyCriticalSection, limited.PyCriticalSection);
    pattern_check();

    for (c.exports_3_13) |name| function_check(name);
}

fn versioned_check() void {
    comptime assert(c.versioned);
    comptime assert(c.exports_versioned.len > 0);

    if (limited.PY_MAJOR_VERSION != c.abi.versioned.major) {
        @compileError("lacuna: the headers are not the major version the build names");
    }

    if (limited.PY_MINOR_VERSION != c.abi.versioned.minor) {
        @compileError("lacuna: the headers are not the minor version the build names");
    }

    for (c.exports_versioned) |name| {
        if (!@hasDecl(limited, name)) {
            @compileError("lacuna: '" ++ name ++ "' is missing from the version-specific API");
        }

        function_check(name);
    }

    for (@typeInfo(c.api_versioned).@"struct".decl_names) |name| {
        constant_check(c.api_versioned, limited, name);
    }

    pattern_check();

    if (c.api_3_13_linked) {
        for (c.exports_3_13) |name| function_check(name);
    }

    layout_check(c.PyVarObject_Header, limited.PyVarObject);
    layout_check(c.PyListObject, limited.PyListObject);
    layout_check(c.PyFloatObject, limited.PyFloatObject);
    layout_check(c.PyLongValue, limited._PyLongValue);
    layout_check(c.PyLongObject, limited.PyLongObject);
    layout_check(c.PyDictObject, limited.PyDictObject);
    layout_check(c.PyDictKeysObject, limited.PyDictKeysObject);
    layout_check(c.PyDictKeyEntry, limited.PyDictKeyEntry);
    layout_check(c.PyDictUnicodeEntry, limited.PyDictUnicodeEntry);
}

fn function_check(comptime name: []const u8) void {
    comptime assert(name.len > 0);
    comptime assert(@hasDecl(c, name));

    function_check_in(limited, name);
}

fn function_check_in(comptime Headers: type, comptime name: []const u8) void {
    comptime assert(name.len > 0);
    comptime assert(@hasDecl(c, name));
    comptime assert(@typeInfo(Headers) == .@"struct");

    if (!@hasDecl(Headers, name)) {
        @compileError("lacuna: '" ++ name ++ "' is missing from the target API");
    }

    const ours = function_information(@TypeOf(@field(c, name)));
    const theirs = function_information(@TypeOf(@field(Headers, name)));

    if (ours.param_types.len != theirs.param_types.len) {
        @compileError("lacuna: '" ++ name ++ "' takes a different number of parameters");
    }

    if (ours.attrs.varargs != theirs.attrs.varargs) {
        @compileError("lacuna: '" ++ name ++ "' disagrees on being variadic");
    }

    if (!std.meta.eql(class_of(ours.return_type.?), class_of(theirs.return_type.?))) {
        @compileError("lacuna: '" ++ name ++ "' returns a different type");
    }

    for (ours.param_types, theirs.param_types, 0..) |left, right, index| {
        if (!std.meta.eql(class_of(left.?), class_of(right.?))) {
            @compileError(std.fmt.comptimePrint("lacuna: parameter {d} of '{s}' differs", .{
                index,
                name,
            }));
        }
    }
}

fn function_information(comptime T: type) std.lang.Type.Fn {
    comptime assert(T != type);

    const result = switch (@typeInfo(T)) {
        .@"fn" => |function| function,
        .pointer => |pointer| @typeInfo(pointer.child).@"fn",
        else => @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a function"),
    };

    comptime assert(!result.is_generic);

    return result;
}

fn constant_check(comptime Ours: type, comptime Theirs: type, comptime name: []const u8) void {
    comptime assert(name.len > 0);
    comptime assert(@TypeOf(@field(Ours, name)) == comptime_int);

    if (!@hasDecl(Theirs, name)) {
        @compileError("lacuna: the constant '" ++ name ++ "' is not in the limited API");
    }

    const theirs = @field(Theirs, name);

    const value: comptime_int = switch (@typeInfo(@TypeOf(theirs))) {
        .comptime_int, .int => theirs,
        .optional, .pointer => @intFromPtr(theirs),
        else => @compileError("lacuna: the constant '" ++ name ++ "' has no integer value"),
    };

    if (value != @field(Ours, name)) {
        if (renumbered(Theirs, name, value)) return;

        @compileError(std.fmt.comptimePrint("lacuna: the constant '{s}' is {d}, not {d}", .{
            name,
            value,
            @field(Ours, name),
        }));
    }
}

fn layout_check(comptime Ours: type, comptime Theirs: type) void {
    comptime assert(@typeInfo(Ours) == .@"struct");
    comptime assert(@typeInfo(Theirs) == .@"struct");

    const ours = @typeInfo(Ours).@"struct";
    const theirs = @typeInfo(Theirs).@"struct";

    if (@sizeOf(Ours) != @sizeOf(Theirs)) {
        @compileError("lacuna: the size of '" ++ @typeName(Ours) ++ "' differs");
    }

    if (ours.field_names.len != theirs.field_names.len) {
        @compileError("lacuna: the field count of '" ++ @typeName(Ours) ++ "' differs");
    }

    for (
        ours.field_names,
        theirs.field_names,
        ours.field_types,
        theirs.field_types,
    ) |left, right, LeftType, RightType| {
        if (@offsetOf(Ours, left) != @offsetOf(Theirs, right)) {
            @compileError(
                "lacuna: the offset of '" ++ @typeName(Ours) ++ "." ++ left ++ "' differs",
            );
        }

        if (@sizeOf(LeftType) != @sizeOf(RightType)) {
            @compileError("lacuna: the size of '" ++ @typeName(Ours) ++ "." ++ left ++ "' differs");
        }
    }
}

fn class_of(comptime T: type) Class {
    comptime assert(T != type);
    comptime assert(T != noreturn);

    return switch (@typeInfo(T)) {
        .@"enum" => |enumeration| class_of(enumeration.tag_type),
        .float => |float| .{ .float = float.bits },
        .int => |int| .{ .int = int },
        .optional => |optional| switch (@typeInfo(optional.child)) {
            .pointer => .pointer,
            else => @compileError("lacuna: an optional of '" ++ @typeName(optional.child) ++ "'"),
        },
        .pointer => .pointer,
        .void => .void,
        else => @compileError("lacuna: the type '" ++ @typeName(T) ++ "' has no C class"),
    };
}
