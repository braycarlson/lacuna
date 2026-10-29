const std = @import("std");

const class_module = @import("class.zig");
const exception = @import("exception.zig");
const from_python_module = @import("from_python.zig");
const kind_module = @import("kind.zig");
const registry = @import("registry.zig");
const signature_module = @import("signature.zig");
const slot = @import("slot.zig");
const stub_fixture = @import("stub_fixture.zig");
const value_module = @import("value.zig");
const variant_module = @import("variant.zig");

const assert = std.debug.assert;

const Module = registry.Module;
const kind_of = kind_module.kind_of;

pub const Direction = enum {
    parameter,
    result,
};

pub const Context = struct {
    classes: []const type,
    Self: ?type,
};

const Borrow = struct {
    missing: []const u8,
    present: []const u8,
};

const Definition = struct {
    doc: []const u8,
    head: []const u8,
    level: Level,
    returned: []const u8,
};

const Import = struct {
    name: []const u8,
    token: []const u8,
};

const Level = enum {
    member,
    module,
};

const Search = struct {
    body: []const u8,
    token: []const u8,
};

const Walk = struct {
    classes: []const type,
    depth: u32,

    fn deeper(walk: Walk) Walk {
        assert(walk.depth < kind_module.depth_max);
        assert(walk.classes.len <= registry.class_count_max);

        return .{ .classes = walk.classes, .depth = walk.depth + 1 };
    }
};

const imports = [_]Import{
    .{ .name = "AbstractSet", .token = "AbstractSet[" },
    .{ .name = "Any", .token = "Any" },
    .{ .name = "Awaitable", .token = "Awaitable[" },
    .{ .name = "Buffer", .token = "Buffer" },
    .{ .name = "ClassVar", .token = "ClassVar[" },
    .{ .name = "Final", .token = "Final[" },
    .{ .name = "Generic", .token = "Generic[" },
    .{ .name = "Generator", .token = "Generator[" },
    .{ .name = "Literal", .token = "Literal[" },
    .{ .name = "Mapping", .token = "Mapping[" },
    .{ .name = "Never", .token = "Never" },
    .{ .name = "Self", .token = "Self" },
    .{ .name = "Sequence", .token = "Sequence[" },
    .{ .name = "SupportsIndex", .token = "SupportsIndex" },
    .{ .name = "TypeVar", .token = "TypeVar(" },
    .{ .name = "TypedDict", .token = "TypedDict" },
    .{ .name = "disjoint_base", .token = "@disjoint_base" },
    .{ .name = "final", .token = "@final" },
};

const module_imports = [_]Import{
    .{ .name = "import datetime as _datetime", .token = "_datetime." },
    .{ .name = "import decimal as _decimal", .token = "_decimal." },
    .{ .name = "import enum as _enum", .token = "_enum." },
    .{ .name = "import fractions as _fractions", .token = "_fractions." },
    .{ .name = "import ipaddress as _ipaddress", .token = "_ipaddress." },
    .{ .name = "import os as _os", .token = "_os." },
    .{ .name = "import pathlib as _pathlib", .token = "_pathlib." },
    .{ .name = "import sys", .token = "sys." },
    .{ .name = "import types as _types", .token = "_types." },
    .{ .name = "import uuid as _uuid", .token = "_uuid." },
    .{ .name = "import warnings as _warnings", .token = "_warnings." },
};

const indent = "    ";

const Canonical = struct {
    name: []const u8,
    parameters: ?[]const u8,
    awaitable: bool,
};

const exit_parameters = ", exc_type: type[BaseException] | None, " ++
    "exc_value: BaseException | None, traceback: _types.TracebackType | None, /";

const canonical_dunders = [_]Canonical{
    .{ .name = "__aenter__", .parameters = "", .awaitable = true },
    .{ .name = "__aexit__", .parameters = exit_parameters, .awaitable = true },
    .{ .name = "__bytes__", .parameters = "", .awaitable = false },
    .{ .name = "__complex__", .parameters = "", .awaitable = false },
    .{ .name = "__copy__", .parameters = "", .awaitable = false },
    .{ .name = "__deepcopy__", .parameters = ", memo: dict[int, object], /", .awaitable = false },
    .{ .name = "__dir__", .parameters = "", .awaitable = false },
    .{ .name = "__enter__", .parameters = "", .awaitable = false },
    .{ .name = "__exit__", .parameters = exit_parameters, .awaitable = false },
    .{ .name = "__format__", .parameters = ", format_spec: str, /", .awaitable = false },
    .{ .name = "__fspath__", .parameters = "", .awaitable = false },
    .{ .name = "__getnewargs__", .parameters = "", .awaitable = false },
    .{ .name = "__length_hint__", .parameters = "", .awaitable = false },
    .{ .name = "__missing__", .parameters = null, .awaitable = false },
    .{ .name = "__reduce_ex__", .parameters = ", protocol: SupportsIndex, /", .awaitable = false },
    .{ .name = "__reversed__", .parameters = "", .awaitable = false },
    .{ .name = "__round__", .parameters = ", ndigits: int | None = None, /", .awaitable = false },
    .{ .name = "__sizeof__", .parameters = "", .awaitable = false },
};

fn canonical_of(comptime name: []const u8) ?Canonical {
    comptime assert(name.len > 0);
    comptime assert(canonical_dunders.len == 18);

    for (canonical_dunders) |canonical| {
        if (std.mem.eql(u8, canonical.name, name)) return canonical;
    }

    return null;
}

const mirrors = [_]Borrow{
    .{ .missing = "__ge__", .present = "__le__" },
    .{ .missing = "__gt__", .present = "__lt__" },
    .{ .missing = "__le__", .present = "__ge__" },
    .{ .missing = "__lt__", .present = "__gt__" },
};

pub const StubFile = struct {
    path: []const u8,
    text: []const u8,
};

pub fn stub_files(comptime module: Module) []const StubFile {
    comptime assert(module.name.len > 0);

    var pending: []const Module = &.{module};
    var result: []const StubFile = &.{};
    var index: u32 = 0;

    for (0..registry.submodule_count_max * 8) |_| {
        if (index == pending.len) break;

        const current = pending[index];

        result = result ++ .{StubFile{ .path = stub_path(current), .text = stub(current) }};
        pending = pending ++ current.submodules;
        index += 1;
    } else {
        @compileError("lacuna: the module '" ++ module.name ++ "' nests too many submodules");
    }

    comptime assert(result.len == pending.len);

    return result;
}

pub fn stub_path(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);

    var path: [module.name.len]u8 = module.name[0..module.name.len].*;

    std.mem.replaceScalar(u8, &path, '.', '/');

    const package = std.mem.findScalar(u8, module.name, '.') == null or module.submodules.len > 0;
    const frozen = path;

    return &frozen ++ if (package) "/__init__.pyi" else ".pyi";
}

pub fn stub(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= registry.class_count_max);

    @setEvalBranchQuota(10_000_000);

    comptime registry.validate(module);

    const sections = exceptions_text(module) ++ enums_text(module) ++ unions_text(module) ++
        records_text(module) ++
        functions_text(module) ++ classes_text(module) ++ constants_text(module);

    const body = std.mem.trimEnd(u8, sections, "\n") ++ "\n";
    const result = imports_text(.{
        .body = body,
        .metaclasses = metaclass_imports_text(module),
        .relative = submodules_text(module),
    }) ++ body;

    comptime assert(!std.mem.endsWith(u8, result, "\n\n"));

    return result;
}

fn enums_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.enums.len <= registry.enum_count_max);

    var result: []const u8 = "";

    for (module.enums) |Enum| {
        result = result ++ "class " ++ from_python_module.class_name(Enum) ++ "(_enum.IntEnum):\n";

        if (@hasDecl(Enum, "doc")) result = result ++ docstring(.module, Enum.doc);

        for (@typeInfo(Enum).@"enum".field_names) |field| {
            const number = std.fmt.comptimePrint("{d}", .{@backingInt(@field(Enum, field))});
            const member = signature_module.python_name_of(Enum, field);

            result = result ++ indent ++ member ++ " = " ++ number ++ "\n";
        }

        result = result ++ "\n";
    }

    return result;
}

fn unions_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.unions.len <= registry.union_count_max);

    var result: []const u8 = "";

    for (module.unions) |Union| {
        const name = from_python_module.class_name(Union);
        const structure = @typeInfo(Union).@"union";

        result = result ++ "class " ++ name ++ ":\n";

        if (@hasDecl(Union, "doc")) result = result ++ docstring(.module, Union.doc);

        for (structure.field_names, structure.field_types) |tag, Payload| {
            const text = variant_member_text(module, .{ .base = name, .tag = tag }, Payload);

            result = result ++ indented(text);
        }

        result = result ++ "\n";
    }

    return result;
}

const Member = struct {
    base: []const u8,
    tag: []const u8,
};

fn variant_member_text(
    comptime module: Module,
    comptime member: Member,
    comptime Payload: type,
) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(member.base.len > 0);
    comptime assert(member.tag.len > 0);

    const declared = module.classes ++ module.unions;
    const Fields = variant_module.FieldsType(Payload, declared);
    const fields = @typeInfo(Fields).@"struct".field_names;
    const context: Context = .{ .classes = declared, .Self = null };
    const Signature: ?type = if (fields.len == 0) null else Fields;

    var literals: []const u8 = "";

    for (fields, 0..) |field, index| {
        literals = literals ++ (if (index == 0) "" else ", ") ++ "Literal['" ++ field ++ "']";
    }

    const matched = if (fields.len == 0) "tuple[()]" else "tuple[" ++ literals ++ "]";

    var body: []const u8 = indent ++ "__match_args__: ClassVar[" ++ matched ++ "]\n";

    body = body ++ definition_text(.{
        .doc = "",
        .head = "__new__(cls" ++ parameters_text(Signature, context) ++ ")",
        .level = .member,
        .returned = "Self",
    });

    for (fields) |field| {
        body = body ++ indent ++ "@property\n" ++ definition_text(.{
            .doc = "",
            .head = field ++ "(self)",
            .level = .member,
            .returned = annotation(@FieldType(Fields, field), context, .result),
        });
    }

    body = body ++ definition_text(.{
        .doc = "",
        .head = "__eq__(self, other: object, /)",
        .level = .member,
        .returned = "bool",
    });

    if (variant_module.fields_hashable(Fields, declared)) {
        body = body ++ definition_text(.{
            .doc = "",
            .head = "__hash__(self)",
            .level = .member,
            .returned = "int",
        });
    }

    body = body ++ definition_text(.{
        .doc = "Pickle the variant by its fields.",
        .head = "__reduce__(self)",
        .level = .member,
        .returned = "tuple[object, ...]",
    });

    const name = variant_module.member_name(member.tag);

    return "@final\nclass " ++ name ++ "(" ++ member.base ++ "):\n" ++ body;
}

fn submodules_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.submodules.len <= registry.submodule_count_max);

    var result: []const u8 = "";

    for (module.submodules) |submodule| {
        const leaf = signature_module.module_leaf(submodule.name);

        result = result ++ "from . import " ++ leaf ++ " as " ++ leaf ++ "\n";
    }

    return result;
}

fn metaclass_imports_text(comptime module: Module) []const u8 {
    comptime assert(module.classes.len <= registry.class_count_max);
    comptime assert(module.name.len > 0);

    var result: []const u8 = "";

    for (module.classes) |Class| {
        const source = class_module.metaclass_of(Class) orelse continue;

        const path = switch (source) {
            .native => continue,
            .python => |known| known,
        };

        const line = "import " ++ path.module ++ "\n";

        if (std.mem.find(u8, result, line) == null) result = result ++ line;
    }

    return result;
}

fn imports_text(comptime text: struct {
    body: []const u8,
    metaclasses: []const u8,
    relative: []const u8,
}) []const u8 {
    comptime assert(text.body.len > 0);
    comptime assert(imports.len > 0);

    if (text.relative.len > 0) {
        comptime assert(std.mem.startsWith(u8, text.relative, "from . import "));
    }

    var modules: []const u8 = text.metaclasses;
    var names: []const []const u8 = &.{};

    for (module_imports) |item| {
        if (token_present(.{ .body = text.body, .token = item.token })) {
            modules = modules ++ item.name ++ "\n";
        }
    }

    for (imports) |item| {
        if (token_present(.{ .body = text.body, .token = item.token })) {
            names = names ++ .{item.name};
        }
    }

    const typing = if (names.len == 0)
        ""
    else
        "from typing_extensions import " ++ names_join(names) ++ "\n";

    const separator = if (modules.len == 0) "" else if (typing.len == 0) "" else "\n";
    const absolute = modules ++ separator ++ typing;
    const gap = if (absolute.len == 0) "" else if (text.relative.len == 0) "" else "\n";
    const result = absolute ++ gap ++ text.relative;

    assert(names.len <= imports.len);

    return if (result.len == 0) "" else result ++ "\n\n";
}

fn names_join(comptime names: []const []const u8) []const u8 {
    comptime assert(names.len > 0);
    comptime assert(names.len <= imports.len);

    var result: []const u8 = names[0];

    for (names[1..]) |name| result = result ++ ", " ++ name;

    return result;
}

fn token_present(comptime search: Search) bool {
    comptime assert(search.token.len > 0);
    comptime assert(search.body.len > 0);

    var cursor: u32 = 0;

    for (0..search.body.len) |_| {
        const offset = std.mem.findPos(u8, search.body, cursor, search.token) orelse return false;
        if (word_bounded(search, offset)) return true;

        cursor = @intCast(offset + 1);
    }

    return false;
}

fn word_bounded(comptime search: Search, comptime offset: usize) bool {
    comptime assert(offset + search.token.len <= search.body.len);
    comptime assert(search.token.len > 0);

    if (offset > 0) {
        if (identifier_character(search.body[offset - 1])) return false;
    }

    if (search.token[search.token.len - 1] == '[') return true;
    if (search.token[search.token.len - 1] == '.') return true;

    const after = offset + search.token.len;
    if (after == search.body.len) return true;
    return !identifier_character(search.body[after]);
}

fn identifier_character(character: u8) bool {
    assert(character <= std.math.maxInt(u8));
    assert(imports.len > 0);

    if (std.ascii.isAlphanumeric(character)) return true;
    return character == '_';
}

fn exceptions_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(registry.errors_of(module).len <= registry.error_count_max);

    const base_doc = "The base of every exception that " ++ module.name ++ " raises.";

    var result: []const u8 = "class Error(Exception):\n" ++ docstring(.module, base_doc) ++
        details_text(module) ++ "\n";

    const errors = registry.errors_of(module);

    for (registry.errors_ordered(module)) |index| {
        const name = errors[index];
        const doc = exception.message_of(module.messages, name);

        const bases = if (registry.base_of(module, name)) |base| switch (base) {
            .builtin => |kind| "Error, " ++
                exception.builtin_names[@backingInt(exception.builtin_of_error(kind))],
            .module => |parent| errors[parent],
        } else "Error";

        result = result ++ "class " ++ name ++ "(" ++ bases ++ "):";
        result = result ++ if (doc) |text| "\n" ++ docstring(.module, text) else " ...\n";
        result = result ++ "\n";
    }

    return result;
}

fn details_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.diagnostic == null or @hasDecl(module.diagnostic.?, "Details"));

    const Diagnostic = module.diagnostic orelse return "";
    const Details = Diagnostic.Details;
    const context: Context = .{ .classes = module.classes ++ module.unions, .Self = null };

    var result: []const u8 = "";

    for (@typeInfo(Details).@"struct".field_names) |field| {
        const type_text = optional_annotation(@FieldType(Details, field), context, .result);

        result = result ++ indent ++ field ++ ": " ++ type_text ++ "\n";
    }

    return result;
}

fn docstring(comptime level: Level, comptime text: []const u8) []const u8 {
    comptime assert(text.len > 0);
    comptime assert(std.mem.findScalar(u8, text, 0) == null);

    const prefix = switch (level) {
        .member => indent ++ indent,
        .module => indent,
    };

    return prefix ++ "\"\"\"" ++ escaped_of(text) ++ "\"\"\"\n";
}

fn escaped_of(comptime text: []const u8) []const u8 {
    comptime assert(text.len > 0);
    comptime assert(std.mem.findScalar(u8, text, 0) == null);

    var result: []const u8 = "";

    for (text) |character| {
        result = result ++ switch (character) {
            '\\' => "\\\\",
            '"' => "\\\"",
            else => &[_]u8{character},
        };
    }

    return result;
}

fn deprecated_text(
    comptime level: Level,
    comptime message: ?[:0]const u8,
    comptime text: []const u8,
) []const u8 {
    comptime assert(text.len > 0);
    comptime assert(text[text.len - 1] == '\n');
    comptime assert(message == null or message.?.len > 0);

    const present = message orelse return text;

    const prefix = switch (level) {
        .member => indent,
        .module => "",
    };

    const nested = indented(text);
    const decorator = prefix ++ indent ++ "@_warnings.deprecated(\"" ++ escaped_of(present) ++
        "\")\n";

    return prefix ++ "if sys.version_info >= (3, 13):\n" ++ decorator ++ nested ++ prefix ++
        "else:\n" ++ nested;
}

fn indented(comptime text: []const u8) []const u8 {
    comptime assert(text.len > 0);
    comptime assert(text[text.len - 1] == '\n');

    var result: []const u8 = "";
    var start: usize = 0;

    for (text, 0..) |character, index| {
        if (character == '\n') {
            result = result ++ indent ++ text[start .. index + 1];
            start = index + 1;
        }
    }

    comptime assert(start == text.len);

    return result;
}

fn records_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= registry.class_count_max);

    const context: Context = .{ .classes = module.classes ++ module.unions, .Self = null };

    var result: []const u8 = "";

    for (records_of(module)) |Record| {
        const structure = @typeInfo(Record).@"struct";

        result = result ++ "class " ++ record_name(Record) ++ "(TypedDict):\n";

        for (structure.field_names, structure.field_types) |field, Field| {
            const type_text = annotation(Field, context, .result);

            result = result ++ indent ++ field ++ ": " ++ type_text ++ "\n";
        }

        if (structure.field_names.len == 0) result = result ++ indent ++ "...\n";

        result = result ++ "\n";
    }

    return result;
}

fn records_of(comptime module: Module) []const type {
    comptime assert(module.classes.len <= registry.class_count_max);
    comptime assert(module.name.len > 0);

    const walk: Walk = .{ .classes = module.classes ++ module.unions, .depth = 0 };

    var result: []const type = &.{};

    if (module.functions) |Namespace| {
        for (@typeInfo(Namespace).@"struct".decl_names) |name| {
            if (registry.function_member_of(Namespace, name) == .function) {
                result = records_of_function(result, @TypeOf(@field(Namespace, name)), walk);
            }
        }
    }

    for (module.classes) |Class| {
        for (@typeInfo(Class).@"struct".decl_names) |name| {
            switch (class_module.member_of(Class, name)) {
                .reserved, .skipped => {},
                else => result = records_of_function(result, @TypeOf(@field(Class, name)), walk),
            }
        }

        if (@hasDecl(Class, "fields")) {
            for (@typeInfo(@TypeOf(Class.fields)).@"struct".field_names) |field| {
                result = records_walk(result, @FieldType(Class, field), walk);
            }
        }
    }

    return result;
}

fn records_of_function(
    comptime known: []const type,
    comptime Function: type,
    comptime walk: Walk,
) []const type {
    comptime assert(@typeInfo(Function) == .@"fn");
    comptime assert(known.len < 1 << 12);
    comptime assert(walk.depth == 0);

    const function = @typeInfo(Function).@"fn";

    var result = known;

    for (function.param_types) |Parameter| {
        if (diagnostic_parameter(Parameter.?)) continue;
        if (Parameter.? == value_module.ModuleObject) continue;
        if (Parameter.? == value_module.TypeObject) continue;

        if (kind_of(Parameter.?, walk.classes) == .record) {
            for (@typeInfo(Parameter.?).@"struct".field_types) |Field| {
                result = records_walk(result, Field, walk);
            }
        } else {
            result = records_walk(result, Parameter.?, walk);
        }
    }

    return records_walk(result, payload_of(function.return_type.?), walk);
}

fn diagnostic_parameter(comptime T: type) bool {
    comptime assert(T != type);

    if (@typeInfo(T) != .pointer) return false;
    return @import("diagnostic.zig").is_diagnostic(@typeInfo(T).pointer.child);
}

fn records_walk(comptime known: []const type, comptime T: type, comptime walk: Walk) []const type {
    comptime assert(walk.depth <= kind_module.depth_max);
    comptime assert(known.len < 1 << 12);

    return switch (kind_of(T, walk.classes)) {
        .array => records_walk(known, @typeInfo(T).array.child, walk.deeper()),
        .list, .set => records_walk(known, T.Item, walk.deeper()),
        .map => records_walk(
            records_walk(known, T.Key, walk.deeper()),
            T.Value,
            walk.deeper(),
        ),
        .optional => records_walk(known, @typeInfo(T).optional.child, walk.deeper()),
        .record => record_add(known, T, walk),
        .tuple => fields_walk(known, T, walk),
        .variant => variants_walk(known, T, walk),
        else => known,
    };
}

fn variants_walk(comptime known: []const type, comptime T: type, comptime walk: Walk) []const type {
    comptime assert(known.len < 1 << 12);
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(walk.depth < kind_module.depth_max);

    var result = known;

    for (@typeInfo(T).@"union".field_types) |Payload| {
        if (Payload != void) result = records_walk(result, Payload, walk.deeper());
    }

    return result;
}

fn record_add(comptime known: []const type, comptime T: type, comptime walk: Walk) []const type {
    comptime assert(!@typeInfo(T).@"struct".is_tuple);
    comptime assert(walk.depth < kind_module.depth_max);
    comptime assert(known.len < 1 << 12);

    if (!record_named(T)) return fields_walk(known, T, walk);

    for (known) |Known| {
        if (Known == T) return known;
    }

    return fields_walk(known, T, walk) ++ .{T};
}

fn fields_walk(comptime known: []const type, comptime T: type, comptime walk: Walk) []const type {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(walk.depth < kind_module.depth_max);
    comptime assert(known.len < 1 << 12);

    var result = known;

    for (@typeInfo(T).@"struct".field_types) |Field| {
        result = records_walk(result, Field, walk.deeper());
    }

    return result;
}

fn record_name(comptime T: type) []const u8 {
    comptime assert(record_named(T));
    comptime assert(@typeInfo(T) == .@"struct");

    return "_" ++ from_python_module.class_name(T);
}

pub fn record_named(comptime T: type) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(!@typeInfo(T).@"struct".is_tuple);

    const name = from_python_module.class_name(T);

    if (std.mem.find(u8, @typeName(T), "__struct") != null) return false;
    if (std.mem.findScalar(u8, @typeName(T), '(') != null) return false;
    return signature_module.identifier_valid(name);
}

pub fn annotation(
    comptime T: type,
    comptime context: Context,
    comptime direction: Direction,
) []const u8 {
    comptime assert(context.classes.len <= registry.class_count_max);
    comptime assert(context.Self == null or @typeInfo(context.Self.?) == .@"struct");

    const parameter = direction == .parameter;

    return switch (kind_of(T, context.classes)) {
        .array => array_annotation(T, context, direction),
        .boolean => "bool",
        .buffer, .buffer_mutable => if (parameter)
            "Buffer"
        else
            "list[" ++ annotation(@typeInfo(T).pointer.child, context, .result) ++ "]",
        .buffer_strided => if (parameter) "Buffer" else "memoryview",
        .bytes, .bytes_owned => if (parameter) "Buffer" else "bytes",
        .class_pointer, .class_pointer_mutable => class_annotation(
            @typeInfo(T).pointer.child,
            context,
        ),
        .class_extended => class_annotation(T.extended_class, context),
        .class_value => class_annotation(T, context),
        .complex => "complex",
        .container => T.annotation,
        .date => "_datetime.date",
        .datetime => "_datetime.datetime",
        .decimal => if (parameter) "_decimal.Decimal | int" else "_decimal.Decimal",
        .duration => "_datetime.timedelta",
        .enumeration => from_python_module.class_name(T),
        .float => "float",
        .fraction => if (parameter) "_fractions.Fraction | int" else "_fractions.Fraction",
        .integer => "int",
        .ip_address => "_ipaddress.IPv4Address | _ipaddress.IPv6Address",
        .list => if (parameter)
            sequence_annotation(annotation(T.Item, context, direction))
        else
            "list[" ++ annotation(T.Item, context, direction) ++ "]",
        .map => (if (parameter) "Mapping[" else "dict[") ++
            annotation(T.Key, context, direction) ++ ", " ++
            annotation(T.Value, context, direction) ++ "]",
        .none => "None",
        .object, .reference => "object",
        .optional => optional_annotation(@typeInfo(T).optional.child, context, direction),
        .path => if (parameter)
            "str | bytes | _os.PathLike[str] | _os.PathLike[bytes]"
        else
            "_pathlib.Path",
        .record => if (record_named(T)) record_name(T) else "dict[str, object]",
        .set => if (parameter)
            "AbstractSet[" ++ annotation(T.Item, context, direction) ++ "]"
        else if (T.frozen)
            "frozenset[" ++ annotation(T.Item, context, direction) ++ "]"
        else
            "set[" ++ annotation(T.Item, context, direction) ++ "]",
        .slice => "slice",
        .text, .text_owned, .text_terminated => "str",
        .time => "_datetime.time",
        .tuple => tuple_annotation(T, context, direction),
        .union_class => from_python_module.class_name(T),
        .uuid => "_uuid.UUID",
        .variant => variant_annotation(T, context, direction),
    };
}

fn optional_annotation(
    comptime Child: type,
    comptime context: Context,
    comptime direction: Direction,
) []const u8 {
    comptime assert(@typeInfo(Child) != .optional);
    comptime assert(context.classes.len <= registry.class_count_max);

    const child = annotation(Child, context, direction);
    if (std.mem.endsWith(u8, child, " | None")) return child;
    return child ++ " | None";
}

fn variant_annotation(
    comptime T: type,
    comptime context: Context,
    comptime direction: Direction,
) []const u8 {
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(context.classes.len <= registry.class_count_max);

    var result: []const u8 = "";
    var none = false;

    for (@typeInfo(T).@"union".field_types) |Payload| {
        if (Payload == void) {
            none = true;
        } else {
            const separator = if (result.len == 0) "" else " | ";

            result = result ++ separator ++ annotation(Payload, context, direction);
        }
    }

    if (none) result = result ++ " | None";

    return result;
}

fn class_annotation(comptime Class: type, comptime context: Context) []const u8 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(kind_module.class_index(Class, context.classes) != null);

    if (context.Self) |Receiver| {
        if (Receiver == Class) return "Self";
    }

    return from_python_module.class_name(Class);
}

fn sequence_annotation(comptime item: []const u8) []const u8 {
    comptime assert(item.len > 0);
    comptime assert(item[item.len - 1] != ',');

    return "Sequence[" ++ item ++ "]";
}

fn array_annotation(
    comptime T: type,
    comptime context: Context,
    comptime direction: Direction,
) []const u8 {
    comptime assert(@typeInfo(T) == .array);
    comptime assert(context.classes.len <= registry.class_count_max);

    const array = @typeInfo(T).array;
    const item = annotation(array.child, context, direction);
    if (direction == .parameter) return sequence_annotation(item);
    if (array.len == 0) return "tuple[()]";
    if (array.len > 8) return "tuple[" ++ item ++ ", ...]";

    var result: []const u8 = "tuple[" ++ item;

    for (1..array.len) |_| result = result ++ ", " ++ item;

    return result ++ "]";
}

fn tuple_annotation(
    comptime T: type,
    comptime context: Context,
    comptime direction: Direction,
) []const u8 {
    comptime assert(@typeInfo(T).@"struct".is_tuple);
    comptime assert(context.classes.len <= registry.class_count_max);

    const field_types = @typeInfo(T).@"struct".field_types;
    if (field_types.len == 0) return "tuple[()]";

    var result: []const u8 = "tuple[" ++ annotation(field_types[0], context, direction);

    for (field_types[1..]) |Field| result = result ++ ", " ++ annotation(Field, context, direction);

    return result ++ "]";
}

fn parameters_text(comptime Arguments: ?type, comptime context: Context) []const u8 {
    comptime assert(Arguments == null or @typeInfo(Arguments.?) == .@"struct");
    comptime assert(context.classes.len <= registry.class_count_max);

    const Struct = Arguments orelse return "";
    const structure = @typeInfo(Struct).@"struct";
    const layout = signature_module.layout_of(Struct, @typeName(Struct));

    var result: []const u8 = "";

    for (structure.field_names, structure.field_attrs, 0..) |field, attributes, position| {
        const Field = @FieldType(Struct, field);
        const index: u32 = position;

        if (index == layout.keyword_first) {
            if (layout.variadic == null) {
                if (index != layout.keywords) result = result ++ ", *";
            }
        }

        const prefix = signature_module.marker_prefix(layout, index);

        const type_text = if (layout.variadic == index)
            annotation(Field.Item, context, .parameter)
        else if (layout.keywords == index)
            keywords_annotation(Field, context)
        else
            annotation(Field, context, .parameter);

        const default = if (prefix.len > 0)
            ""
        else if (attributes.defaultValue(Field)) |item|
            " = " ++ (signature_module.literal_of(Field, item) orelse "...")
        else
            "";

        const python = signature_module.python_name_of(Struct, field);

        result = result ++ ", " ++ prefix ++ python ++ ": " ++ type_text ++ default;

        if (index + 1 == layout.positional_only_count) result = result ++ ", /";
    }

    return result;
}

fn keywords_annotation(comptime Field: type, comptime context: Context) []const u8 {
    comptime assert(Field != type);
    comptime assert(context.classes.len <= registry.class_count_max);

    if (Field == value_module.Object) return "object";
    return annotation(Field.Value, context, .parameter);
}

fn definition_text(comptime definition: Definition) []const u8 {
    comptime assert(definition.head.len > 0);
    comptime assert(definition.returned.len > 0);

    const prefix = switch (definition.level) {
        .member => indent,
        .module => "",
    };

    const line = prefix ++ "def " ++ definition.head ++ " -> " ++ definition.returned ++ ":";
    if (definition.doc.len == 0) return line ++ " ...\n";
    return line ++ "\n" ++ docstring(definition.level, definition.doc);
}

fn functions_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.functions == null or @typeInfo(module.functions.?) == .@"struct");

    const Namespace = module.functions orelse return "";
    const context: Context = .{ .classes = module.classes ++ module.unions, .Self = null };

    var result: []const u8 = "";

    for (@typeInfo(Namespace).@"struct".decl_names) |name| {
        if (registry.function_member_of(Namespace, name) != .function) continue;

        const Function = @TypeOf(@field(Namespace, name));
        const signature = signature_module.signature_of(Function, null, name);
        const parameters = parameters_text(signature.Arguments, context);

        const text = definition_text(.{
            .doc = class_module.doc_of(Namespace, name),
            .head = signature_module.python_name_of(Namespace, name) ++ "(" ++
                trim_separator(parameters) ++ ")",
            .level = .module,
            .returned = annotation(signature.Payload, context, .result),
        });

        const deprecation = class_module.deprecation_of(Namespace, name);
        const coroutine = registry.listed(Namespace, .coroutines, name);
        const marked = if (coroutine) "async " ++ text else text;

        result = result ++ deprecated_text(.module, deprecation, marked);
    }

    if (result.len > 0) result = result ++ "\n";

    return result;
}

fn trim_separator(comptime parameters: []const u8) []const u8 {
    comptime assert(parameters.len == 0 or parameters.len > 2);
    comptime assert(parameters.len == 0 or std.mem.startsWith(u8, parameters, ", "));

    return if (parameters.len == 0) "" else parameters[2..];
}

fn classes_text(comptime module: Module) []const u8 {
    comptime assert(module.classes.len <= registry.class_count_max);
    comptime assert(module.name.len > 0);

    var result: []const u8 = "";

    for (module.classes) |Class| {
        const context: Context = .{ .classes = module.classes ++ module.unions, .Self = Class };

        result = result ++ class_text(context) ++ "\n";
    }

    return result;
}

fn class_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;

    var members: []const u8 = "";

    if (@hasDecl(Class, "doc")) members = members ++ docstring(.module, Class.doc);

    members = members ++ dictionary_text(Class);

    members = members ++ constructor_text(context);

    if (class_module.generic(Class)) {
        members = members ++ indent ++ "@classmethod\n" ++ definition_text(.{
            .doc = "",
            .head = "__class_getitem__(cls, item: object, /)",
            .level = .member,
            .returned = "_types.GenericAlias",
        });
    }

    members = members ++ constants_class_text(context) ++ fields_text(context) ++
        properties_text(context) ++ methods_text(context) ++ slots_text(context) ++
        reduce_text(context);

    if (members.len == 0) members = indent ++ "...\n";

    const open = @hasDecl(Class, "subclassable") and Class.subclassable;
    const decorator = if (open) "@disjoint_base\n" else "@final\n";

    const name = from_python_module.class_name(Class);
    const variable = "_" ++ name ++ "T";

    const declaration = if (class_module.generic(Class))
        variable ++ " = TypeVar(\"" ++ variable ++ "\")\n\n"
    else
        "";

    return declaration ++ decorator ++ "class " ++ name ++ bases_text(Class) ++ ":\n" ++ members;
}

fn constructor_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;

    const member = if (@hasDecl(Class, "__new__"))
        "__new__"
    else if (@hasDecl(Class, "init"))
        "init"
    else
        return "";

    const signature = signature_module.signature_of(@TypeOf(@field(Class, member)), Class, member);

    return definition_text(.{
        .doc = "",
        .head = "__new__(cls" ++ parameters_text(signature.Arguments, context) ++ ")",
        .level = .member,
        .returned = "Self",
    });
}

fn bases_text(comptime Class: type) []const u8 {
    comptime assert(@typeInfo(Class) == .@"struct");

    const native_module = @import("native.zig");
    const name = from_python_module.class_name(Class);
    const variable = "_" ++ name ++ "T";
    const parameter = if (class_module.generic(Class)) "Generic[" ++ variable ++ "]" else "";

    const parent = if (native_module.lacuna_base_of(Class)) |Base|
        from_python_module.class_name(Base)
    else if (native_module.native_of(Class)) |native|
        native_module.annotation_of(native)
    else
        "";

    const metaclass = if (class_module.metaclass_of(Class)) |source| switch (source) {
        .native => |Meta| "metaclass=" ++ from_python_module.class_name(Meta),
        .python => |path| "metaclass=" ++ path.module ++ "." ++ path.name,
    } else "";

    var listed: []const u8 = "";

    for ([_][]const u8{ parent, parameter, metaclass }) |entry| {
        if (entry.len == 0) continue;

        listed = if (listed.len == 0) entry else listed ++ ", " ++ entry;
    }

    return if (listed.len > 0) "(" ++ listed ++ ")" else "";
}

fn dictionary_text(comptime Class: type) []const u8 {
    comptime assert(@typeInfo(Class) == .@"struct");

    const Instance = @import("instance.zig").InstanceType(Class);

    if (Instance.dictionary_offset == null) return "";
    if (Instance.base_dictionary_offset != null) return "";
    return indent ++ "__dict__: dict[str, object]\n";
}

fn constants_class_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;
    const unscoped: Context = .{ .classes = context.classes, .Self = null };

    if (!@hasDecl(Class, "constants")) return "";

    var result: []const u8 = "";

    for (@typeInfo(@TypeOf(Class.constants)).@"struct".field_names) |member| {
        const Constant = @TypeOf(@field(Class.constants, member));

        const type_text = switch (@typeInfo(Constant)) {
            .comptime_int => "int",
            .comptime_float => "float",
            .pointer => |pointer| if (@typeInfo(pointer.child) == .array)
                "str"
            else
                annotation(Constant, unscoped, .result),
            else => annotation(Constant, unscoped, .result),
        };

        result = result ++ indent ++ member ++ ": ClassVar[" ++ type_text ++ "]\n";
    }

    return result;
}

fn reduce_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    if (!class_module.picklable(context.Self.?)) return "";

    return definition_text(.{
        .doc = "Pickle the instance by its fields.",
        .head = "__reduce__(self)",
        .level = .member,
        .returned = "tuple[object, ...]",
    });
}

fn fields_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;
    if (!@hasDecl(Class, "fields")) return "";

    var result: []const u8 = "";

    for (@typeInfo(@TypeOf(Class.fields)).@"struct".field_names) |field| {
        const access: class_module.Access = @field(Class.fields, field);
        const Field = @FieldType(Class, field);
        const python = signature_module.python_name_of(Class, field);

        result = result ++ indent ++ "@property\n" ++ definition_text(.{
            .doc = class_module.doc_of(Class, field),
            .head = python ++ "(self)",
            .level = .member,
            .returned = annotation(Field, context, .result),
        });

        if (access == .read_write) {
            const parameter = annotation(Field, context, .parameter);

            result = result ++ indent ++ "@" ++ python ++ ".setter\n" ++ definition_text(.{
                .doc = "",
                .head = python ++ "(self, value: " ++ parameter ++ ")",
                .level = .member,
                .returned = "None",
            });
        }
    }

    return result;
}

fn properties_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;
    if (!@hasDecl(Class, "properties")) return "";

    var result: []const u8 = "";

    for (Class.properties) |property| {
        const member = @tagName(property);
        const python = signature_module.python_name_of(Class, member);

        const signature = signature_module.signature_of(
            @TypeOf(@field(Class, member)),
            Class,
            member,
        );

        result = result ++ indent ++ "@property\n" ++ definition_text(.{
            .doc = class_module.doc_of(Class, member),
            .head = python ++ "(self)",
            .level = .member,
            .returned = annotation(signature.Payload, context, .result),
        });

        if (class_module.setter_of(Class, member)) |setter| {
            const Setter = @TypeOf(@field(Class, setter));
            const assigned = signature_module.signature_of(Setter, Class, setter).Arguments.?;
            const Value = @typeInfo(assigned).@"struct".field_types[0];

            result = result ++ indent ++ "@" ++ python ++ ".setter\n" ++ definition_text(.{
                .doc = "",
                .head = python ++ "(self, value: " ++ annotation(Value, context, .parameter) ++ ")",
                .level = .member,
                .returned = "None",
            });
        }
    }

    return result;
}

fn methods_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;

    var result: []const u8 = "";

    for (@typeInfo(Class).@"struct".decl_names) |member| {
        const kind = class_module.member_of(Class, member);

        switch (kind) {
            .method, .static => {},
            else => continue,
        }

        const signature = signature_module.signature_of(
            @TypeOf(@field(Class, member)),
            Class,
            member,
        );

        const unbound = signature.receiver == .none;
        const seat: Seat = if (kind == .static) .none else if (unbound) .cls else .self;

        const decorator = if (kind == .static)
            indent ++ "@staticmethod\n"
        else if (unbound)
            indent ++ "@classmethod\n"
        else
            "";

        const scoped: Context = if (kind == .static)
            .{ .classes = context.classes, .Self = null }
        else
            context;

        const canonical = canonical_of(member);

        const canonical_parameters = if (canonical) |known| known.parameters else null;
        const parameters = canonical_parameters orelse parameters_text(signature.Arguments, scoped);

        const plain = annotation(signature.Payload, scoped, .result);
        const awaitable = if (canonical) |known| known.awaitable else false;
        const returned = if (awaitable) "Awaitable[" ++ plain ++ "]" else plain;

        const text = decorator ++ definition_text(.{
            .doc = class_module.doc_of(Class, member),
            .head = signature_module.python_name_of(Class, member) ++ "(" ++
                receiver_join(seat, parameters) ++ ")",
            .level = .member,
            .returned = returned,
        });

        const deprecation = class_module.deprecation_of(Class, member);

        result = result ++ deprecated_text(.member, deprecation, text);
    }

    return result;
}

const Seat = enum {
    cls,
    none,
    self,
};

fn receiver_join(comptime seat: Seat, comptime parameters: []const u8) []const u8 {
    comptime assert(@tagName(seat).len > 0);
    comptime assert(parameters.len == 0 or std.mem.startsWith(u8, parameters, ", "));

    if (seat != .none) return @tagName(seat) ++ parameters;
    return trim_separator(parameters);
}

fn slots_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;

    var result: []const u8 = "";

    for (@typeInfo(Class).@"struct".decl_names) |member| {
        if (class_module.member_of(Class, member) != .slot) continue;
        if (std.mem.eql(u8, member, "__repr__")) continue;
        if (std.mem.eql(u8, member, "__str__")) continue;

        result = result ++ slot_text(context, member);
    }

    return result ++ synthesized_text(context) ++ derived_text(context);
}

fn derived_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(context.classes.len <= registry.class_count_max);

    const Class = context.Self.?;
    const derive = @import("derive.zig");

    var result: []const u8 = "";

    if (derive.derived(Class, .equality)) {
        for ([_][]const u8{ "__eq__", "__ne__" }) |name| {
            result = result ++ definition_text(.{
                .doc = "",
                .head = name ++ "(self, other: object, /)",
                .level = .member,
                .returned = "bool",
            });
        }
    }

    if (derive.derived(Class, .ordering)) {
        for ([_][]const u8{ "__lt__", "__le__", "__gt__", "__ge__" }) |name| {
            result = result ++ definition_text(.{
                .doc = "",
                .head = name ++ "(self, other: Self, /)",
                .level = .member,
                .returned = "bool",
            });
        }
    }

    if (derive.derived(Class, .hash)) {
        result = result ++ definition_text(.{
            .doc = "",
            .head = "__hash__(self)",
            .level = .member,
            .returned = "int",
        });
    }

    return result;
}

fn synthesized_text(comptime context: Context) []const u8 {
    comptime assert(context.Self != null);
    comptime assert(mirrors.len == 4);

    const Class = context.Self.?;

    var result: []const u8 = "";

    for (mirrors) |mirror| {
        if (!@hasDecl(Class, mirror.missing)) {
            if (@hasDecl(Class, mirror.present)) result = result ++ borrowed_text(context, mirror);
        }
    }

    for (slot.entries) |entry| {
        if (entry.reflected.len == 0) continue;

        const forward = @hasDecl(Class, entry.name);
        const reflected = @hasDecl(Class, entry.reflected);

        if (forward != reflected) {
            const borrow: Borrow = if (forward)
                .{ .missing = entry.reflected, .present = entry.name }
            else
                .{ .missing = entry.name, .present = entry.reflected };

            result = result ++ if (operand_is_self(Class, borrow.present))
                borrowed_text(context, borrow)
            else
                refused_text(borrow);
        }
    }

    return result;
}

fn refused_text(comptime borrow: Borrow) []const u8 {
    comptime assert(borrow.missing.len > 4);
    comptime assert(borrow.present.len > 4);

    return definition_text(.{
        .doc = "",
        .head = borrow.missing ++ "(self, other: Never" ++ power_suffix(borrow.missing) ++ ", /)",
        .level = .member,
        .returned = "Never",
    });
}

fn power_suffix(comptime member: []const u8) []const u8 {
    comptime assert(member.len > 4);

    if (std.mem.eql(u8, member, "__pow__")) return ", mod: None = None";
    if (std.mem.eql(u8, member, "__rpow__")) return ", mod: None = None";
    if (std.mem.eql(u8, member, "__ipow__")) return ", mod: None = None";
    return "";
}

fn operand_is_self(comptime Class: type, comptime member: []const u8) bool {
    comptime assert(@hasDecl(Class, member));
    comptime assert(member.len > 4);

    const parameters = @typeInfo(@TypeOf(@field(Class, member))).@"fn".param_types;

    comptime assert(parameters.len == 2);

    const Operand = @typeInfo(parameters[1].?).@"struct".field_types[0];
    if (Operand == Class) return true;
    if (Operand == *const Class) return true;
    return Operand == *Class;
}

fn borrowed_text(comptime context: Context, comptime borrow: Borrow) []const u8 {
    comptime assert(!@hasDecl(context.Self.?, borrow.missing));
    comptime assert(@hasDecl(context.Self.?, borrow.present));

    const function = @typeInfo(@TypeOf(@field(context.Self.?, borrow.present))).@"fn";
    const operands = operands_text(function.param_types[1].?, context, false);

    return definition_text(.{
        .doc = "",
        .head = borrow.missing ++ "(self" ++ operands ++ power_suffix(borrow.missing) ++ ", /)",
        .level = .member,
        .returned = annotation(payload_of(function.return_type.?), context, .result),
    });
}

fn slot_text(comptime context: Context, comptime member: []const u8) []const u8 {
    comptime assert(std.mem.startsWith(u8, member, "__"));
    comptime assert(context.Self != null);

    const Class = context.Self.?;
    const function = @typeInfo(@TypeOf(@field(Class, member))).@"fn";
    const Payload = payload_of(function.return_type.?);
    const Arguments = if (function.param_types.len == 2) function.param_types[1].? else void;

    if (std.mem.eql(u8, member, "__call__")) {
        return definition_text(.{
            .doc = "",
            .head = member ++ "(self" ++ parameters_text(Arguments, context) ++ ")",
            .level = .member,
            .returned = annotation(Payload, context, .result),
        });
    }

    if (special_slot_text(context, member)) |text| return text;

    const equality = std.mem.eql(u8, member, "__eq__") or std.mem.eql(u8, member, "__ne__");
    const operands = operands_text(Arguments, context, equality);
    const iterated = std.mem.eql(u8, member, "__next__") or std.mem.eql(u8, member, "__anext__");

    const Returned = if (iterated) @typeInfo(Payload).optional.child else Payload;
    const inplace = slot_shape_of(member) == .inplace or slot_shape_of(member) == .inplace_power;
    const plain = annotation(Returned, context, .result);

    const returned = if (inplace)
        "Self"
    else if (std.mem.eql(u8, member, "__await__"))
        "Generator[object, None, object]"
    else if (std.mem.eql(u8, member, "__anext__"))
        "Awaitable[" ++ plain ++ "]"
    else
        plain;

    return definition_text(.{
        .doc = class_module.doc_of(Class, member),
        .head = member ++ "(self" ++ operands ++ power_suffix(member) ++
            (if (operands.len > 0) ", /)" else ")"),
        .level = .member,
        .returned = returned,
    });
}

fn slot_shape_of(comptime member: []const u8) ?slot.Shape {
    comptime assert(member.len > 4);

    for (slot.entries) |entry| {
        if (std.mem.eql(u8, entry.name, member)) return entry.shape;
    }

    return null;
}

fn special_slot_text(comptime context: Context, comptime member: []const u8) ?[]const u8 {
    comptime assert(context.Self != null);
    comptime assert(member.len > 4);

    const Class = context.Self.?;
    const function = @typeInfo(@TypeOf(@field(Class, member))).@"fn";
    const Payload = payload_of(function.return_type.?);

    if (std.mem.eql(u8, member, "__buffer__")) {
        const text = definition_text(.{
            .doc = class_module.doc_of(Class, member),
            .head = "__buffer__(self, flags: int, /)",
            .level = .member,
            .returned = "memoryview",
        });

        return indent ++ "if sys.version_info >= (3, 12):\n" ++ indented(text);
    }

    if (std.mem.eql(u8, member, "__get__")) {
        const Arguments = function.param_types[1].?;
        const fields = @typeInfo(Arguments).@"struct".field_types;
        const instance = annotation(fields[0], context, .parameter);
        const owner = annotation(fields[1], context, .parameter);

        return definition_text(.{
            .doc = class_module.doc_of(Class, member),
            .head = "__get__(self, instance: " ++ instance ++ ", owner: " ++ owner ++
                " = None, /)",
            .level = .member,
            .returned = annotation(Payload, context, .result),
        });
    }

    return null;
}

fn payload_of(comptime Return: type) type {
    comptime assert(Return != type);
    comptime assert(@typeInfo(Return) != .@"fn");

    return switch (@typeInfo(Return)) {
        .error_union => |error_union| error_union.payload,
        else => Return,
    };
}

fn operands_text(
    comptime Arguments: type,
    comptime context: Context,
    comptime equality: bool,
) []const u8 {
    comptime assert(Arguments == void or @typeInfo(Arguments) == .@"struct");
    comptime assert(context.Self != null);
    comptime assert(!equality or Arguments != void);

    if (Arguments == void) return "";

    const structure = @typeInfo(Arguments).@"struct";

    var result: []const u8 = "";

    for (structure.field_names, structure.field_types) |field, Field| {
        const type_text = if (equality) "object" else annotation(Field, context, .parameter);

        result = result ++ ", " ++ field ++ ": " ++ type_text;
    }

    return result;
}

fn constants_text(comptime module: Module) []const u8 {
    comptime assert(module.name.len > 0);
    comptime assert(module.constants == null or @typeInfo(module.constants.?) == .@"struct");

    const Namespace = module.constants orelse return "";
    const context: Context = .{ .classes = module.classes ++ module.unions, .Self = null };

    var result: []const u8 = "";

    for (@typeInfo(Namespace).@"struct".decl_names) |name| {
        const Constant = @TypeOf(@field(Namespace, name));

        const type_text = switch (@typeInfo(Constant)) {
            .comptime_int => "int",
            .comptime_float => "float",
            .pointer => |pointer| if (@typeInfo(pointer.child) == .array)
                "str"
            else
                annotation(Constant, context, .result),
            else => annotation(Constant, context, .result),
        };

        result = result ++ name ++ ": Final[" ++ type_text ++ "]\n";
    }

    return result;
}

test stub {
    const text = comptime stub(stub_fixture.module);

    const header =
        \\from typing_extensions import Final, Self, TypedDict, final
        \\
        \\
        \\class Error(Exception):
        \\    """The base of every exception that sample raises."""
        \\
        \\class Negative(Error): ...
        \\
        \\class _Point(TypedDict):
        \\    horizontal: float
        \\    vertical: float
        \\
        \\def distance(left: _Point, right: _Point) -> float:
        \\    """The distance between two points."""
        \\def origin() -> _Point: ...
        \\def scale(factor: float = 2.0, label: str | None = None) -> None: ...
        \\
        \\
    ;

    try std.testing.expect(std.mem.startsWith(u8, text, header));
}

test "a stub lists each class member and each constant" {
    const text = comptime stub(stub_fixture.module);

    const tail =
        \\@final
        \\class Counter:
        \\    """Counts up."""
        \\    def __new__(cls, start: int = 0) -> Self: ...
        \\    @property
        \\    def count(self) -> int: ...
        \\    @count.setter
        \\    def count(self, value: int) -> None: ...
        \\    def step(self) -> Self: ...
        \\    def __contains__(self, value: int, /) -> bool: ...
        \\
        \\count_max: Final[int]
        \\version: Final[str]
        \\
    ;

    try std.testing.expect(std.mem.endsWith(u8, text, tail));
}

test "a stub without constants ends in a single newline" {
    const text = comptime stub(stub_fixture.module_without_constants);

    const tail =
        \\    def __contains__(self, value: int, /) -> bool: ...
        \\
    ;

    try std.testing.expect(std.mem.endsWith(u8, text, tail));
    try std.testing.expect(!std.mem.endsWith(u8, text, "\n\n"));
}

test "a stub leaves out the types of hidden fields" {
    const text = comptime stub(stub_fixture.module);

    try std.testing.expect(std.mem.find(u8, text, "_Point") != null);
    try std.testing.expect(std.mem.find(u8, text, "_Window") == null);
    try std.testing.expect(std.mem.find(u8, text, "window") == null);
}

test "a stub names metaclasses and marks coroutine functions" {
    const text = comptime stub(stub_fixture.module_metaclass);

    const expected =
        \\import registry.meta
        \\
        \\from typing_extensions import disjoint_base, final
        \\
        \\
        \\class Error(Exception):
        \\    """The base of every exception that catalog raises."""
        \\
        \\async def fetch(count: int) -> int: ...
        \\
        \\@disjoint_base
        \\class Catalog(type):
        \\    def describe(self) -> bool: ...
        \\    def __contains__(self, value: int, /) -> bool: ...
        \\
        \\@final
        \\class Palette(metaclass=Catalog):
        \\    ...
        \\
        \\@final
        \\class Plugin(metaclass=registry.meta.Registered):
        \\    ...
        \\
    ;

    try std.testing.expectEqualStrings(expected, text);
}

test "a stub marks deprecated functions and methods" {
    const text = comptime stub(stub_fixture.module_deprecated);

    const expected =
        \\import sys
        \\import warnings as _warnings
        \\
        \\from typing_extensions import final
        \\
        \\
        \\class Error(Exception):
        \\    """The base of every exception that legacy raises."""
        \\
        \\if sys.version_info >= (3, 13):
        \\    @_warnings.deprecated("use clear instead")
        \\    def reset() -> None: ...
        \\else:
        \\    def reset() -> None: ...
        \\
        \\@final
        \\class Gauge:
        \\    if sys.version_info >= (3, 13):
        \\        @_warnings.deprecated("use empty instead")
        \\        def zero(self) -> None: ...
        \\    else:
        \\        def zero(self) -> None: ...
        \\
    ;

    try std.testing.expectEqualStrings(expected, text);
}

test "a stub declares a base error before the errors that extend it" {
    const Functions = struct {
        pub fn scan() error{Unterminated}!void {}

        pub fn parse() error{Malformed}!void {}
    };

    const Bases = struct {
        pub const Malformed: @import("exception.zig").BuiltinError = .value_error;
        pub const Unterminated = error.Malformed;
    };

    const module: Module = .{ .name = "parser", .bases = Bases, .functions = Functions };
    const text = comptime stub(module);

    const expected =
        \\class Malformed(Error, ValueError): ...
        \\
        \\class Unterminated(Malformed): ...
        \\
    ;

    try std.testing.expect(std.mem.find(u8, text, expected) != null);
    try std.testing.expectEqualStrings("Unterminated", comptime registry.errors_of(module)[0]);
    try std.testing.expectEqual(1, comptime registry.errors_ordered(module)[0]);
}

test "a stub nests one final class per variant of a listed union" {
    const Reading = union(enum) {
        celsius: f64,
        missing: void,
    };

    const Functions = struct {
        pub fn echo(arguments: struct { reading: Reading }) Reading {
            if (arguments.reading == .celsius) assert(!std.math.isNan(arguments.reading.celsius));

            return arguments.reading;
        }
    };

    const module: Module = .{ .name = "sensor", .functions = Functions, .unions = &.{Reading} };
    const text = comptime stub(module);

    const expected =
        \\class Reading:
        \\    @final
        \\    class Celsius(Reading):
        \\        __match_args__: ClassVar[tuple[Literal['value']]]
        \\        def __new__(cls, value: float) -> Self: ...
        \\        @property
        \\        def value(self) -> float: ...
        \\        def __eq__(self, other: object, /) -> bool: ...
        \\        def __hash__(self) -> int: ...
        \\        def __reduce__(self) -> tuple[object, ...]:
        \\            """Pickle the variant by its fields."""
        \\    @final
        \\    class Missing(Reading):
        \\        __match_args__: ClassVar[tuple[()]]
        \\
    ;

    try std.testing.expect(std.mem.find(u8, text, expected) != null);
    try std.testing.expect(std.mem.find(u8, text, "def echo(reading: Reading) -> Reading") != null);
}

test "a stub spells renamed members with their Python names" {
    const Grade = enum {
        zig_low,
        zig_high,

        pub const names = .{ .zig_low = "low", .zig_high = "high" };
    };

    const Functions = struct {
        pub const names = .{ .zig_pick = "pick" };

        pub fn zig_pick(arguments: struct {
            zig_level: Grade,

            pub const names = .{ .zig_level = "level" };
        }) Grade {
            assert(@backingInt(arguments.zig_level) <= 1);

            return arguments.zig_level;
        }
    };

    const module: Module = .{ .name = "levels", .enums = &.{Grade}, .functions = Functions };
    const text = comptime stub(module);

    try std.testing.expect(std.mem.find(u8, text, "    low = 0\n    high = 1\n") != null);
    try std.testing.expect(std.mem.find(u8, text, "def pick(level: Grade) -> Grade") != null);
    try std.testing.expect(std.mem.find(u8, text, "zig_") == null);
}

test "a stub declares __buffer__ only where Python exposes it" {
    const Samples = struct {
        values: [2]f64,

        pub fn __buffer__(samples: *@This()) []f64 {
            assert(samples.values.len == 2);

            return &samples.values;
        }
    };

    const module: Module = .{ .name = "buffers", .classes = &.{Samples} };
    const text = comptime stub(module);

    const guarded =
        \\    if sys.version_info >= (3, 12):
        \\        def __buffer__(self, flags: int, /) -> memoryview: ...
        \\
    ;

    try std.testing.expect(std.mem.startsWith(u8, text, "import sys\n"));
    try std.testing.expect(std.mem.find(u8, text, guarded) != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "__buffer__"));
}
