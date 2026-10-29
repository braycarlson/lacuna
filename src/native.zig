const std = @import("std");

const c = @import("c.zig");
const value = @import("value.zig");
const version_module = @import("version.zig");

const assert = std.debug.assert;

pub const Native = enum {
    dictionary,
    list,
    set,
    string,
    bytes,
    exception,
    integer,
    float,
    type,
};

pub const available = c.api_3_12_linked;
pub const metaclass_available = c.api_3_12_linked and !c.pypy;

const python_names = [_][:0]const u8{
    "dict",
    "list",
    "set",
    "str",
    "bytes",
    "Exception",
    "int",
    "float",
    "type",
};

comptime {
    assert(python_names.len == @typeInfo(Native).@"enum".field_names.len);
}

pub fn native_of(comptime Class: type) ?Native {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "extends")) return null;
    if (@TypeOf(Class.extends) != Native) return null;
    return Class.extends;
}

pub fn lacuna_base_of(comptime Class: type) ?type {
    comptime assert(@typeInfo(Class) == .@"struct");

    if (!@hasDecl(Class, "extends")) return null;
    if (@TypeOf(Class.extends) != type) return null;
    return Class.extends;
}

pub fn python_name_of(comptime native: Native) [:0]const u8 {
    comptime assert(@backingInt(native) < python_names.len);
    comptime assert(python_names.len == 9);

    return python_names[@backingInt(native)];
}

pub fn variable_size(comptime native: Native) bool {
    comptime assert(@backingInt(native) < python_names.len);
    comptime assert(python_names.len == 9);

    return switch (native) {
        .bytes, .integer, .string => true,
        .dictionary, .exception, .float, .list, .set, .type => false,
    };
}

pub fn annotation_of(comptime native: Native) []const u8 {
    comptime assert(@backingInt(native) < python_names.len);
    comptime assert(!variable_size(native));

    return switch (native) {
        .dictionary => "dict[Any, Any]",
        .list => "list[Any]",
        .set => "set[Any]",
        else => python_name_of(native),
    };
}

pub fn native_check(comptime Class: type, comptime name: []const u8) void {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    const native = native_of(Class) orelse return;

    if (variable_size(native)) {
        @compileError("lacuna: the class '" ++ name ++ "' extends the native '" ++
            @tagName(native) ++ "', which is variable-size and has no type data to place " ++
            "fields after");
    }

    methods_check(Class, name);

    if (native == .type) metaclass_check(Class, name);

    if (!available) {
        const floor: version_module.Version = .{
            .major = version_module.floor.major,
            .minor = c.stable_minor,
        };

        @compileError(std.fmt.comptimePrint("lacuna: the class '{s}' extends the native " ++
            "'{s}', which needs Python 3.12; this build's floor is Python {d}.{d}", .{
            name,
            @tagName(native),
            floor.major,
            floor.minor,
        }));
    }
}

pub fn metaclass_is(comptime Class: type) bool {
    comptime assert(@typeInfo(Class) == .@"struct");

    const native = native_of(Class) orelse return false;
    return native == .type;
}

fn metaclass_check(comptime Class: type, comptime name: []const u8) void {
    comptime assert(metaclass_is(Class));
    comptime assert(name.len > 0);

    if (@typeInfo(Class).@"struct".field_names.len > 0) {
        @compileError("lacuna: the metaclass '" ++ name ++ "' has fields; a metaclass " ++
            "carries no Zig state, so keep per-class state in class attributes");
    }

    inline for (.{ "init", "deinit", "__new__", "derive", "pickle" }) |forbidden| {
        if (@hasDecl(Class, forbidden)) {
            @compileError("lacuna: the metaclass '" ++ name ++ "' declares " ++ forbidden ++
                ", which a metaclass cannot have; its instances are classes that type creates");
        }
    }

    if (c.pypy) {
        @compileError("lacuna: the metaclass '" ++ name ++ "' extends type, which PyPy " ++
            "cannot extend with type data; list it only where lacuna.native_metaclasses holds");
    }
}

fn methods_check(comptime Class: type, comptime name: []const u8) void {
    comptime assert(native_of(Class) != null);
    comptime assert(name.len > 0);

    const declarations = @typeInfo(Class).@"struct".decl_names;

    inline for (declarations) |declaration| {
        const Declaration = @TypeOf(@field(Class, declaration));

        if (comptime method_takes_object(Declaration, declaration)) {
            @compileError("lacuna: '" ++ name ++ "." ++ declaration ++ "' takes a " ++
                "lacuna.Object, which only init receives as the native base");
        }
    }
}

fn method_takes_object(comptime Declaration: type, comptime declaration: []const u8) bool {
    comptime assert(declaration.len > 0);

    if (std.mem.eql(u8, declaration, "init")) return false;

    const function = switch (@typeInfo(Declaration)) {
        .@"fn" => |function| function,
        else => return false,
    };

    comptime assert(function.param_types.len <= std.math.maxInt(u16));

    for (function.param_types) |parameter| {
        if (parameter == value.Object) return true;
    }

    return false;
}

test native_of {
    const Plain = struct {
        count: u32,
    };

    const Mapped = struct {
        count: u32,

        pub const extends = Native.dictionary;
    };

    const Meta = struct {
        pub const extends = Native.type;
    };

    comptime {
        assert(native_of(Plain) == null);
        assert(native_of(Mapped).? == .dictionary);
        assert(lacuna_base_of(Mapped) == null);
        assert(variable_size(.integer));
        assert(!variable_size(.exception));
        assert(std.mem.eql(u8, python_name_of(.exception), "Exception"));
        assert(std.mem.eql(u8, python_name_of(.type), "type"));
        assert(!variable_size(.type));
        assert(metaclass_is(Meta));
        assert(!metaclass_is(Mapped));
        assert(!metaclass_is(Plain));
    }
}
