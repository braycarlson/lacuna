const std = @import("std");

const c = @import("c.zig");
const diagnostic_module = @import("diagnostic.zig");
const native_module = @import("native.zig");
const value_module = @import("value.zig");

const assert = std.debug.assert;

pub const Receiver = enum {
    constant,
    mutable,
    none,
};

pub const Signature = struct {
    Arguments: ?type,
    Diagnostic: ?type,
    Errors: ?type,
    Payload: type,
    ancestors: []const Receiver,
    module_object: bool,
    native_base: bool,
    receiver: Receiver,
    type_object: bool,

    pub fn context_count(signature: Signature) u32 {
        if (signature.ancestors.len > 0) assert(signature.receiver != .none);
        if (signature.native_base) assert(signature.receiver != .none);

        return @as(u32, @intCast(signature.ancestors.len)) +
            @intFromBool(signature.native_base) +
            @intFromBool(signature.type_object) +
            @intFromBool(signature.module_object);
    }
};

pub const ancestor_count_max: u32 = 8;

const Contexts = struct {
    ancestors: []const Receiver,
    count: u32,
    module_object: bool,
    native_base: bool,
    type_object: bool,
};

pub fn ancestor_of(comptime Class: type, comptime index: u32) type {
    comptime assert(index < ancestor_count_max);
    comptime assert(@hasDecl(Class, "extends"));

    var Current = native_module.lacuna_base_of(Class).?;

    for (0..index) |_| Current = native_module.lacuna_base_of(Current).?;

    return Current;
}

pub fn ancestor_count(comptime Class: type) u32 {
    comptime assert(@typeInfo(Class) == .@"struct");

    var Current = Class;
    var result: u32 = 0;

    for (0..ancestor_count_max + 1) |_| {
        Current = native_module.lacuna_base_of(Current) orelse return result;
        result += 1;
    }

    @compileError("lacuna: the class '" ++ @typeName(Class) ++ "' has more than " ++
        std.fmt.comptimePrint("{d}", .{ancestor_count_max}) ++ " ancestors");
}

pub const argument_count_max: u32 = 64;

const python_keywords = [_][]const u8{
    "False",
    "None",
    "True",
    "and",
    "as",
    "assert",
    "async",
    "await",
    "break",
    "class",
    "continue",
    "def",
    "del",
    "elif",
    "else",
    "except",
    "finally",
    "for",
    "from",
    "global",
    "if",
    "import",
    "in",
    "is",
    "lambda",
    "nonlocal",
    "not",
    "or",
    "pass",
    "raise",
    "return",
    "try",
    "while",
    "with",
    "yield",
};

pub fn signature_of(
    comptime Function: type,
    comptime Class: ?type,
    comptime name: []const u8,
) Signature {
    comptime assert(name.len > 0);
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const function = switch (@typeInfo(Function)) {
        .@"fn" => |function| function,
        else => @compileError("lacuna: '" ++ name ++ "' is not a function"),
    };

    if (function.is_generic) @compileError("lacuna: the function '" ++ name ++ "' is generic");
    if (function.attrs.varargs) @compileError("lacuna: the function '" ++ name ++ "' is variadic");

    const receiver = receiver_of(function.param_types, Class);
    const after: usize = if (receiver == .none) 0 else 1;
    const contexts = contexts_of(function.param_types[after..], Class, receiver, name);
    const first = after + contexts.count;
    const Diagnostic = diagnostic_of(function.param_types[first..]);
    const last = function.param_types.len - @intFromBool(Diagnostic != null);
    const rest = function.param_types[first..last];

    if (rest.len > 1) {
        @compileError("lacuna: the function '" ++ name ++ "' takes its arguments as one struct");
    }

    const Arguments: ?type = if (rest.len == 1) arguments_of(rest[0].?, name) else null;
    const Return = function.return_type.?;

    if (Diagnostic != null) {
        if (@typeInfo(Return) != .error_union) {
            @compileError("lacuna: the function '" ++ name ++
                "' takes a diagnostic but returns no error");
        }
    }

    return switch (@typeInfo(Return)) {
        .error_union => |error_union| .{
            .Arguments = Arguments,
            .Diagnostic = Diagnostic,
            .Errors = errors_of(error_union.error_set, name),
            .Payload = error_union.payload,
            .ancestors = contexts.ancestors,
            .module_object = contexts.module_object,
            .native_base = contexts.native_base,
            .receiver = receiver,
            .type_object = contexts.type_object,
        },
        else => .{
            .Arguments = Arguments,
            .Diagnostic = null,
            .Errors = null,
            .Payload = Return,
            .ancestors = contexts.ancestors,
            .module_object = contexts.module_object,
            .native_base = contexts.native_base,
            .receiver = receiver,
            .type_object = contexts.type_object,
        },
    };
}

fn contexts_of(
    comptime parameters: []const ?type,
    comptime Class: ?type,
    comptime receiver: Receiver,
    comptime name: []const u8,
) Contexts {
    comptime assert(parameters.len <= argument_count_max);
    comptime assert(name.len > 0);
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const native_base = native_base_taken(parameters, Class, receiver, name);

    var result: Contexts = .{
        .ancestors = &.{},
        .count = @intFromBool(native_base),
        .module_object = false,
        .native_base = native_base,
        .type_object = false,
    };

    if (Class) |class| {
        for (0..ancestor_count(class)) |index| {
            if (result.count == parameters.len) break;

            const Parameter = parameters[result.count].?;
            const Ancestor = ancestor_of(class, index);

            const access: Receiver = if (Parameter == *Ancestor)
                .mutable
            else if (Parameter == *const Ancestor)
                .constant
            else
                .none;

            if (access == .none) continue;

            if (receiver == .none) {
                @compileError("lacuna: '" ++ name ++ "' takes a base without taking its receiver");
            }

            result.ancestors = result.ancestors ++ .{access};
            result.count += 1;
        }
    }

    if (result.count < parameters.len) {
        if (parameters[result.count].? == value_module.TypeObject) {
            if (Class == null) {
                @compileError("lacuna: the module function '" ++ name ++
                    "' takes a lacuna.TypeObject, which only a class member receives");
            }

            result.type_object = true;
            result.count += 1;
        }
    }

    if (result.count < parameters.len) {
        if (parameters[result.count].? == value_module.ModuleObject) {
            result.module_object = true;
            result.count += 1;
        }
    }

    comptime assert(result.count <= ancestor_count_max + 3);

    return result;
}

fn native_base_taken(
    comptime parameters: []const ?type,
    comptime Class: ?type,
    comptime receiver: Receiver,
    comptime name: []const u8,
) bool {
    comptime assert(parameters.len <= argument_count_max);
    comptime assert(name.len > 0);
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const class = Class orelse return false;

    if (native_module.native_of(class) == null) return false;
    if (parameters.len == 0) return false;
    if (parameters[0].? != value_module.Object) return false;

    if (receiver == .none) {
        @compileError("lacuna: '" ++ name ++ "' takes the native base without taking its receiver");
    }

    return true;
}

fn diagnostic_of(comptime parameters: []const ?type) ?type {
    comptime assert(parameters.len <= argument_count_max);

    if (parameters.len == 0) return null;

    const Last = parameters[parameters.len - 1].?;
    if (@typeInfo(Last) != .pointer) return null;

    const pointer = @typeInfo(Last).pointer;
    if (pointer.size != .one) return null;
    if (!diagnostic_module.is_diagnostic(pointer.child)) return null;

    if (pointer.attrs.@"const") {
        @compileError("lacuna: a diagnostic parameter must be a mutable pointer");
    }

    return pointer.child;
}

pub fn receiver_of(comptime parameters: []const ?type, comptime Class: ?type) Receiver {
    comptime assert(parameters.len <= argument_count_max);
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const class = Class orelse return .none;

    if (parameters.len == 0) return .none;

    const First = parameters[0].?;

    if (native_module.metaclass_is(class)) {
        const pointer = if (First == *class) true else First == *const class;

        if (pointer) {
            @compileError("lacuna: a method of the metaclass '" ++ @typeName(class) ++
                "' takes the class it is bound to as a lacuna.TypeObject, not a pointer");
        }

        return if (First == value_module.TypeObject) .constant else .none;
    }

    if (First == *class) return .mutable;
    if (First == *const class) return .constant;
    return .none;
}

pub fn ReceiverArgument(comptime Class: type) type {
    comptime assert(@typeInfo(Class) == .@"struct");

    return if (native_module.metaclass_is(Class)) value_module.TypeObject else *Class;
}

pub fn receiver_argument(
    comptime Class: type,
    data: *Class,
    object: *c.PyObject,
) ReceiverArgument(Class) {
    assert(@intFromPtr(object) % @alignOf(c.PyObject_Header) == 0);
    assert(@intFromPtr(data) > @intFromPtr(object));

    if (comptime native_module.metaclass_is(Class)) return .{ .object = .{ .pointer = object } };
    return data;
}

pub fn errors_of(comptime ErrorSet: type, comptime name: []const u8) type {
    comptime assert(@typeInfo(ErrorSet) == .error_set);
    comptime assert(name.len > 0);

    if (@typeInfo(ErrorSet).error_set.error_names == null) {
        @compileError("lacuna: the function '" ++ name ++ "' returns anyerror; name its errors");
    }

    return ErrorSet;
}

pub const Layout = struct {
    keyword_first: u32,
    keywords: ?u32,
    positional_end: u32,
    positional_only_count: u32,
    variadic: ?u32,

    pub fn nameable(layout: Layout, index: u32) bool {
        assert(index < argument_count_max);
        assert(layout.positional_only_count <= layout.positional_end);

        if (index < layout.positional_only_count) return false;
        return layout.slotted(index);
    }

    pub fn slotted(layout: Layout, index: u32) bool {
        assert(index < argument_count_max);
        assert(layout.positional_end <= argument_count_max);

        if (layout.variadic == index) return false;
        return layout.keywords != index;
    }
};

fn arguments_of(comptime Arguments: type, comptime name: []const u8) type {
    comptime assert(name.len > 0);
    comptime assert(Arguments != void);

    const structure = switch (@typeInfo(Arguments)) {
        .@"struct" => |structure| structure,
        else => @compileError("lacuna: the arguments of '" ++ name ++ "' must be a struct"),
    };

    if (structure.is_tuple) {
        @compileError("lacuna: the arguments of '" ++ name ++ "' must be named");
    }

    if (structure.field_names.len > argument_count_max) {
        @compileError("lacuna: the function '" ++ name ++ "' takes too many arguments");
    }

    const layout = layout_of(Arguments, name);

    var defaulted = false;

    inline for (structure.field_names, structure.field_attrs, 0..) |field_name, attributes, index| {
        identifier_check(field_name);

        if (index < layout.positional_end) {
            const default = attributes.default_value_ptr != null;

            if (defaulted) {
                if (!default) {
                    @compileError("lacuna: the required argument '" ++ field_name ++ "' of '" ++
                        name ++ "' follows an argument with a default");
                }
            }

            defaulted = default;
        }
    }

    return Arguments;
}

pub fn layout_of(comptime Arguments: type, comptime name: []const u8) Layout {
    comptime assert(@typeInfo(Arguments) == .@"struct");
    comptime assert(name.len > 0);

    names_check(Arguments);

    const names = @typeInfo(Arguments).@"struct".field_names;
    const count: u32 = names.len;
    const variadic = marker_index(Arguments, .variadic, name);
    const keywords = marker_index(Arguments, .keywords, name);
    const listed_end = count - @intFromBool(keywords != null);

    if (keywords) |index| {
        if (index != count - 1) {
            @compileError("lacuna: the keywords field of '" ++ name ++ "' must be its last field");
        }
    }

    const positional_only_count = prefix_count(Arguments, name);
    const keyword_listed = suffix_first(Arguments, name, listed_end);
    const keyword_first = if (variadic) |index| index + 1 else keyword_listed;

    if (variadic != null) {
        if (keyword_listed != listed_end) {
            if (keyword_listed != keyword_first) {
                @compileError("lacuna: the keyword-only fields of '" ++ name ++
                    "' must be exactly those after its variadic field");
            }
        }
    }

    const positional_end = variadic orelse keyword_first;

    if (positional_only_count > positional_end) {
        @compileError("lacuna: the positional-only fields of '" ++ name ++
            "' overlap its variadic or keyword-only fields");
    }

    return .{
        .keyword_first = keyword_first,
        .keywords = keywords,
        .positional_end = positional_end,
        .positional_only_count = positional_only_count,
        .variadic = variadic,
    };
}

const Marker = enum {
    keywords,
    variadic,
};

fn marker_index(comptime Arguments: type, comptime which: Marker, comptime name: []const u8) ?u32 {
    comptime assert(@typeInfo(Arguments) == .@"struct");
    comptime assert(name.len > 0);

    const marker = @tagName(which);
    if (!@hasDecl(Arguments, marker)) return null;

    const field = @tagName(@field(Arguments, marker));
    const names = @typeInfo(Arguments).@"struct".field_names;

    for (names, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, field)) return index;
    }

    @compileError("lacuna: the " ++ marker ++ " field '" ++ field ++ "' of '" ++ name ++
        "' is not a field");
}

fn prefix_count(comptime Arguments: type, comptime name: []const u8) u32 {
    comptime assert(@typeInfo(Arguments) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Arguments, "positional_only")) return 0;

    const names = @typeInfo(Arguments).@"struct".field_names;
    const listed = Arguments.positional_only;

    if (listed.len > names.len) @compileError("lacuna: '" ++ name ++ "' lists too many fields");

    for (listed, 0..) |field, index| {
        if (!std.mem.eql(u8, @tagName(field), names[index])) {
            @compileError("lacuna: the positional-only fields of '" ++ name ++
                "' must be its first fields, in order");
        }
    }

    return listed.len;
}

fn suffix_first(comptime Arguments: type, comptime name: []const u8, comptime end: u32) u32 {
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(Arguments) == .@"struct");
    comptime assert(end <= @typeInfo(Arguments).@"struct".field_names.len);

    if (!@hasDecl(Arguments, "keyword_only")) return end;

    const names = @typeInfo(Arguments).@"struct".field_names;
    const listed = Arguments.keyword_only;

    if (listed.len > end) @compileError("lacuna: '" ++ name ++ "' lists too many fields");

    const first = end - listed.len;

    for (listed, 0..) |field, index| {
        if (!std.mem.eql(u8, @tagName(field), names[first + index])) {
            @compileError("lacuna: the keyword-only fields of '" ++ name ++
                "' must be its last fields, in order");
        }
    }

    comptime assert(first <= end);

    return first;
}

pub fn identifier_check(comptime name: []const u8) void {
    comptime assert(python_keywords.len > 0);
    comptime assert(name.len > 0);

    @setEvalBranchQuota(100_000);

    if (!identifier_valid(name)) {
        @compileError("lacuna: '" ++ name ++ "' is not a Python identifier");
    }

    inline for (python_keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) {
            @compileError("lacuna: '" ++ name ++ "' is a Python keyword");
        }
    }
}

pub fn module_name_check(comptime name: []const u8) void {
    comptime assert(name.len > 0);
    comptime assert(name.len < 1 << 12);

    var parts = std.mem.splitScalar(u8, name, '.');

    for (0..name.len) |_| {
        const part = parts.next() orelse break;

        identifier_check(part);
    }
}

pub fn module_name_valid(name: []const u8) bool {
    assert(name.len < 1 << 16);
    assert(python_keywords.len > 0);

    if (name.len == 0) return false;

    var parts = std.mem.splitScalar(u8, name, '.');

    for (0..name.len) |_| {
        const part = parts.next() orelse break;
        if (!identifier_valid(part)) return false;
    }

    return true;
}

pub fn module_leaf(comptime name: []const u8) []const u8 {
    comptime assert(name.len > 0);
    comptime assert(name[name.len - 1] != '.');

    const start = if (std.mem.findScalarLast(u8, name, '.')) |dot| dot + 1 else 0;
    return name[start..];
}

pub fn python_name_of(comptime Namespace: type, comptime zig_name: [:0]const u8) [:0]const u8 {
    comptime assert(zig_name.len > 0);
    comptime assert(@typeInfo(Namespace) != .pointer);

    if (!@hasDecl(Namespace, "names")) return zig_name;
    if (!@hasField(@TypeOf(Namespace.names), zig_name)) return zig_name;
    return terminated(@field(Namespace.names, zig_name));
}

pub fn names_check(comptime Namespace: type) void {
    comptime assert(@typeInfo(Namespace) != .pointer);

    if (!@hasDecl(Namespace, "names")) return;

    @setEvalBranchQuota(100_000);

    for (@typeInfo(@TypeOf(Namespace.names)).@"struct".field_names) |field| {
        const declared = @hasDecl(Namespace, field) or @hasField(Namespace, field);
        const python = @field(Namespace.names, field);

        if (!declared) {
            @compileError("lacuna: the names of '" ++ @typeName(Namespace) ++ "' rename '" ++
                field ++ "', which it does not declare");
        }

        if (!python_name_valid(python)) {
            const label = @typeName(Namespace) ++ "." ++ field;

            @compileError("lacuna: the Python name '" ++ python ++ "' of '" ++ label ++
                "' is not an identifier");
        }
    }
}

fn python_name_valid(comptime name: []const u8) bool {
    comptime assert(name.len < 1 << 12);
    comptime assert(python_keywords.len > 0);

    if (!identifier_valid(name)) return false;

    for (python_keywords) |keyword| {
        if (std.mem.eql(u8, name, keyword)) return false;
    }

    return true;
}

pub fn identifier_valid(name: []const u8) bool {
    assert(name.len <= std.math.maxInt(u32));
    assert(python_keywords.len > 0);

    if (name.len == 0) return false;
    if (std.ascii.isDigit(name[0])) return false;

    for (name) |character| {
        if (!std.ascii.isAlphanumeric(character)) {
            if (character != '_') return false;
        }
    }

    return true;
}

pub const Bound = enum {
    class,
    instance,
    module,
    type,
};

pub fn text_signature(
    comptime name: []const u8,
    comptime bound: Bound,
    comptime Arguments: ?type,
) []const u8 {
    comptime assert(name.len > 0);
    comptime assert(Arguments == null or @typeInfo(Arguments.?) == .@"struct");

    const receiver = switch (bound) {
        .class => "",
        .instance => "$self, /",
        .module => "$module, /",
        .type => "$type, /",
    };

    const Struct = Arguments orelse return name ++ "(" ++ receiver ++ ")\n--\n\n";
    const layout = layout_of(Struct, name);

    const shared = if (bound == .class)
        receiver
    else if (layout.positional_only_count > 0)
        receiver[0 .. receiver.len - 3]
    else
        receiver;

    const parts = parameter_parts(Struct, layout);
    const separator = if (shared.len == 0) "" else separator_of(parts);

    return name ++ "(" ++ shared ++ separator ++ parts ++ ")\n--\n\n";
}

pub fn parameter_parts(comptime Struct: type, comptime layout: Layout) []const u8 {
    comptime assert(@typeInfo(Struct) == .@"struct");
    comptime assert(layout.positional_end <= @typeInfo(Struct).@"struct".field_names.len);

    const structure = @typeInfo(Struct).@"struct";

    var result: []const u8 = "";

    for (structure.field_names, structure.field_attrs, 0..) |field, attributes, position| {
        const Field = @FieldType(Struct, field);
        const index: u32 = position;

        if (index == layout.keyword_first) {
            if (layout.variadic == null) {
                if (index != layout.keywords) result = result ++ separator_of(result) ++ "*";
            }
        }

        const prefix = marker_prefix(layout, index);

        const default = if (prefix.len > 0)
            ""
        else if (attributes.defaultValue(Field)) |value|
            "=" ++ (literal_of(Field, value) orelse "...")
        else
            "";

        const python = python_name_of(Struct, field);

        result = result ++ separator_of(result) ++ prefix ++ python ++ default;

        if (index + 1 == layout.positional_only_count) result = result ++ ", /";
    }

    return result;
}

pub fn separator_of(comptime text: []const u8) []const u8 {
    comptime assert(text.len < 1 << 20);

    return if (text.len == 0) "" else ", ";
}

pub fn marker_prefix(comptime layout: Layout, comptime index: u32) []const u8 {
    comptime assert(layout.positional_end <= argument_count_max);
    comptime assert(index < argument_count_max);

    if (layout.variadic == index) return "*";
    if (layout.keywords == index) return "**";
    return "";
}

pub fn terminated(comptime text: []const u8) [:0]const u8 {
    comptime assert(text.len < 1 << 20);

    const bytes = text ++ "\x00";

    comptime assert(bytes[text.len] == 0);

    return bytes[0..text.len :0];
}

fn enum_literal(comptime T: type, comptime value: T) []const u8 {
    comptime assert(@typeInfo(T) == .@"enum");
    comptime assert(@typeName(T).len > 0);
    comptime assert(std.enums.tagName(T, value) != null);

    const full = @typeName(T);
    const start = if (std.mem.findScalarLast(u8, full, '.')) |dot| dot + 1 else 0;

    return full[start..] ++ "." ++ @tagName(value);
}

pub fn literal_of(comptime T: type, comptime value: T) ?[]const u8 {
    comptime assert(T != type);
    comptime assert(@TypeOf(value) == T);

    return switch (@typeInfo(T)) {
        .bool => if (value) "True" else "False",
        .comptime_int, .int => std.fmt.comptimePrint("{d}", .{value}),
        .comptime_float, .float => float_literal(value),
        .@"enum" => enum_literal(T, value),
        .optional => |optional| if (value) |present|
            literal_of(optional.child, present)
        else
            "None",
        .pointer => if (text_type(T)) quote(value) else null,
        else => null,
    };
}

fn text_type(comptime T: type) bool {
    comptime assert(@typeInfo(T) == .pointer);
    comptime assert(T != type);

    const pointer = @typeInfo(T).pointer;
    if (pointer.child != u8) return false;
    return pointer.size == .slice;
}

fn float_literal(comptime value: anytype) ?[]const u8 {
    comptime assert(@typeInfo(@TypeOf(value)) == .float or @TypeOf(value) == comptime_float);
    comptime assert(@sizeOf(@TypeOf(value)) <= 16);

    if (!std.math.isFinite(@as(f64, value))) return null;

    const text = std.fmt.comptimePrint("{d}", .{@as(f64, value)});
    if (std.mem.findAny(u8, text, ".e") == null) return text ++ ".0";
    return text;
}

pub fn quote(comptime text: []const u8) []const u8 {
    comptime assert(text.len <= 4096);
    comptime assert(std.unicode.utf8ValidateSlice(text));

    var result: []const u8 = "'";

    @setEvalBranchQuota(64 * text.len + 1000);

    for (text) |character| {
        result = result ++ switch (character) {
            '\\' => "\\\\",
            '\'' => "\\'",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
            0...8, 11, 12, 14...31, 127 => std.fmt.comptimePrint("\\x{x:0>2}", .{character}),
            else => &[_]u8{character},
        };
    }

    return result ++ "'";
}

const Point = struct {
    horizontal: f64,

    fn scale(point: *Point, arguments: struct { factor: f64 = 1.0 }) error{Overflow}!f64 {
        assert(std.math.isFinite(arguments.factor));
        assert(std.math.isFinite(point.horizontal));

        const result = point.horizontal * arguments.factor;
        if (!std.math.isFinite(result)) return error.Overflow;

        assert(!std.math.isNan(result));

        return result;
    }

    fn origin() Point {
        return .{ .horizontal = 0 };
    }
};

test signature_of {
    const scale = comptime signature_of(@TypeOf(Point.scale), Point, "scale");
    const origin = comptime signature_of(@TypeOf(Point.origin), Point, "origin");

    try std.testing.expect(scale.receiver == .mutable);
    try std.testing.expect(scale.Payload == f64);
    try std.testing.expect(scale.Errors.? == error{Overflow});
    try std.testing.expect(origin.receiver == .none);
    try std.testing.expect(origin.Arguments == null);
}

const Speed = enum { fast, slow };

test text_signature {
    const Arguments = struct {
        left: i64,
        right: i64 = 2,
        label: []const u8 = "it's",
        mode: Speed = .slow,
        scale: ?f64 = null,
        ratio: f32 = 3,
    };

    const expected = "add($module, /, left, right=2, label='it\\'s', mode=Speed.slow, " ++
        "scale=None, ratio=3.0)\n--\n\n";

    try std.testing.expectEqualStrings(
        expected,
        comptime text_signature("add", .module, Arguments),
    );

    try std.testing.expectEqualStrings(
        "Point()\n--\n\n",
        comptime text_signature("Point", .class, null),
    );

    try std.testing.expectEqualStrings(
        "norm($self, /)\n--\n\n",
        comptime text_signature("norm", .instance, null),
    );
}

test identifier_valid {
    try std.testing.expect(identifier_valid("snake_case"));
    try std.testing.expect(identifier_valid("_private2"));
    try std.testing.expect(!identifier_valid("2fast"));
    try std.testing.expect(!identifier_valid("with-dash"));
    try std.testing.expect(!identifier_valid(""));
}

test module_name_valid {
    try std.testing.expect(module_name_valid("faker_zig"));
    try std.testing.expect(module_name_valid("faker_zig._core"));
    try std.testing.expect(!module_name_valid("faker_zig."));
    try std.testing.expect(!module_name_valid(".core"));
    try std.testing.expect(!module_name_valid("faker-zig"));
    try std.testing.expect(!module_name_valid(""));
    try std.testing.expectEqualStrings("_core", comptime module_leaf("faker_zig._core"));
    try std.testing.expectEqualStrings("sample", comptime module_leaf("sample"));
}

test quote {
    try std.testing.expectEqualStrings("'a\\\\b\\n\\x01'", comptime quote("a\\b\n\x01"));
}

test terminated {
    comptime {
        const repeat_count = 512;
        const text: [200]u8 = @splat('a');
        const empty = terminated("");

        @setEvalBranchQuota(repeat_count * (text.len + 50));

        assert(empty.len == 0);
        assert(empty[0] == 0);

        for (0..repeat_count) |_| {
            const result = terminated(&text);

            assert(result.len == text.len);
            assert(result[text.len] == 0);
            assert(std.mem.eql(u8, result, &text));
        }
    }
}
