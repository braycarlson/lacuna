const std = @import("std");

const c = @import("c.zig");
const class_module = @import("class.zig");
const exception = @import("exception.zig");
const kind_module = @import("kind.zig");
const signature_module = @import("signature.zig");

const assert = std.debug.assert;

const signature_of = signature_module.signature_of;

pub const Interpreters = enum {
    per_interpreter_gil,
    shared_gil,
    single,
};

pub const Module = struct {
    bases: ?type = null,
    classes: []const type = &.{},
    constants: ?type = null,
    diagnostic: ?type = null,
    doc: ?[:0]const u8 = null,
    enums: []const type = &.{},
    functions: ?type = null,
    interpreters: Interpreters = .single,
    messages: ?type = null,
    name: [:0]const u8,
    state: ?type = null,
    submodules: []const Module = &.{},
    thread_safe: bool = false,
    unions: []const type = &.{},
};

pub const python_error_name = "PythonError";

pub const ErrorBase = union(enum) {
    builtin: exception.BuiltinError,
    module: u32,
    warning: exception.BuiltinWarning,
};

pub const FunctionMember = enum {
    function,
    reserved,
    skipped,
};

pub const class_count_max: u32 = 128;
pub const enum_count_max: u32 = 128;
pub const submodule_count_max: u32 = 64;
pub const union_count_max: u32 = 128;
pub const error_count_max: u32 = 512;
pub const error_depth_max: u32 = 8;
pub const name_count_max: u32 = 4096;
pub const function_reserved_names = [_][]const u8{
    "coroutines",
    "deprecated",
    "docs",
    "exec",
    "names",
    "parallel",
};

pub fn function_member_of(comptime Namespace: type, comptime name: []const u8) FunctionMember {
    comptime assert(@typeInfo(Namespace) == .@"struct");
    comptime assert(name.len > 0);

    inline for (function_reserved_names) |reserved| {
        if (std.mem.eql(u8, name, reserved)) return .reserved;
    }

    const Declaration = @TypeOf(@field(Namespace, name));
    if (Declaration == type) return .skipped;
    if (@typeInfo(Declaration) == .@"fn") return .function;

    @compileError("lacuna: the declaration '" ++ @typeName(Namespace) ++ "." ++ name ++
        "' is neither a function nor a type");
}

fn reserved_functions_check(
    comptime Namespace: type,
    comptime reserved: []const []const u8,
    comptime allowed: ?[]const u8,
) void {
    comptime assert(@typeInfo(Namespace) == .@"struct");
    comptime assert(reserved.len > 0);
    comptime assert(allowed == null or allowed.?.len > 0);

    for (reserved) |name| {
        const function = @hasDecl(Namespace, name) and
            @typeInfo(@TypeOf(@field(Namespace, name))) == .@"fn";

        if (!function) continue;
        if (allowed) |permitted| {
            if (std.mem.eql(u8, name, permitted)) continue;
        }

        @compileError("lacuna: '" ++ @typeName(Namespace) ++ "." ++ name ++ "' is a function, " ++
            "but lacuna reads '" ++ name ++ "' as configuration; give the Zig function another " ++
            "name and set its Python name through .names");
    }
}

pub fn coroutine_count(comptime Namespace: ?type) u32 {
    comptime assert(Namespace == null or @typeInfo(Namespace.?) == .@"struct");

    const namespace = Namespace orelse return 0;
    if (!@hasDecl(namespace, "coroutines")) return 0;

    comptime assert(namespace.coroutines.len <= name_count_max);

    return namespace.coroutines.len;
}

pub const Members = enum {
    functions,
    methods,
};

pub fn cancellable_count(comptime Namespace: ?type, comptime members: Members) u32 {
    comptime assert(Namespace == null or @typeInfo(Namespace.?) == .@"struct");
    comptime assert(members == .functions or Namespace != null);

    const namespace = Namespace orelse return 0;
    const Self = if (members == .methods) namespace else null;
    if (!@hasDecl(namespace, "coroutines")) return 0;

    var result: u32 = 0;

    for (namespace.coroutines) |entry| {
        const Function = @TypeOf(@field(namespace, @tagName(entry)));

        if (signature_of(Function, Self, @tagName(entry)).token_taken()) {
            result += 1;
        }
    }

    comptime assert(result <= namespace.coroutines.len);

    return result;
}

pub const List = enum {
    coroutines,
    parallel,
};

pub fn release_of(comptime Namespace: type, comptime name: []const u8) ?List {
    comptime assert(@typeInfo(Namespace) == .@"struct");
    comptime assert(name.len > 0);

    if (listed(Namespace, .coroutines, name)) return .coroutines;
    if (listed(Namespace, .parallel, name)) return .parallel;
    return null;
}

pub fn listed(comptime Namespace: type, comptime list: List, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Namespace) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Namespace, @tagName(list))) return false;

    comptime assert(@field(Namespace, @tagName(list)).len <= name_count_max);

    inline for (@field(Namespace, @tagName(list))) |entry| {
        if (std.mem.eql(u8, @tagName(entry), name)) return true;
    }

    return false;
}

fn lists_check(comptime Namespace: type) void {
    comptime assert(@typeInfo(Namespace) == .@"struct");

    inline for (.{ "coroutines", "parallel" }) |list| {
        if (@hasDecl(Namespace, list)) {
            inline for (@field(Namespace, list)) |entry| {
                const declared = @hasDecl(Namespace, @tagName(entry)) and
                    @typeInfo(@TypeOf(@field(Namespace, @tagName(entry)))) == .@"fn";

                if (!declared) {
                    @compileError("lacuna: the " ++ list ++ " list names '" ++
                        @tagName(entry) ++ "', which is not a function");
                }
            }
        }
    }

    if (!@hasDecl(Namespace, "coroutines")) return;

    inline for (Namespace.coroutines) |entry| {
        if (listed(Namespace, .parallel, @tagName(entry))) {
            @compileError("lacuna: '" ++ @tagName(entry) ++ "' is listed in both parallel " ++
                "and coroutines; a coroutine already runs without the GIL");
        }
    }
}

pub fn function_count(comptime Namespace: ?type) u32 {
    comptime assert(Namespace == null or @typeInfo(Namespace.?) == .@"struct");

    const namespace = Namespace orelse return 0;

    comptime assert(@typeInfo(namespace) == .@"struct");
    comptime assert(@typeInfo(namespace).@"struct".decl_names.len <= name_count_max);

    var result: u32 = 0;

    inline for (@typeInfo(namespace).@"struct".decl_names) |name| {
        if (function_member_of(namespace, name) == .function) result += 1;
    }

    return result;
}

pub fn validate(comptime module: Module) void {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= class_count_max);

    signature_module.module_name_check(module.name);

    for (module.classes) |Class| {
        reserved_functions_check(Class, &class_module.reserved_names, null);
    }

    if (module.functions) |Namespace| {
        reserved_functions_check(Namespace, &function_reserved_names, "exec");
        class_module.deprecated_check(Namespace, false);
        signature_module.names_check(Namespace);
        lists_check(Namespace);
        exec_check(Namespace);
    }

    state_check(module);
    diagnostics_check(module);
    bases_check(module);
    unions_check(module);
    enums_check(module);
    submodules_check(module);

    const names = names_of(module);

    @setEvalBranchQuota(names.len * names.len * 64 + 100_000);

    inline for (names, 0..) |left, index| {
        inline for (names[index + 1 ..]) |right| {
            if (std.mem.eql(u8, left, right)) {
                @compileError("lacuna: the module '" ++ module.name ++ "' declares '" ++
                    left ++ "' twice");
            }
        }
    }
}

fn exec_check(comptime Namespace: type) void {
    comptime assert(@typeInfo(Namespace) == .@"struct");

    if (!@hasDecl(Namespace, "exec")) return;

    const Exec = @TypeOf(Namespace.exec);

    if (@typeInfo(Exec) != .@"fn") {
        @compileError("lacuna: the exec hook of '" ++ @typeName(Namespace) ++
            "' is not a function");
    }

    const signature = signature_of(Exec, null, "exec");

    if (signature.Arguments != null) {
        @compileError("lacuna: the exec hook of '" ++ @typeName(Namespace) ++
            "' takes Python arguments; it takes only contexts");
    }

    if (signature.Payload != void) {
        @compileError("lacuna: the exec hook of '" ++ @typeName(Namespace) ++ "' returns '" ++
            @typeName(signature.Payload) ++ "'; it returns void");
    }

    inline for (.{ List.coroutines, List.parallel }) |list| {
        if (listed(Namespace, list, "exec")) {
            @compileError("lacuna: the exec hook of '" ++ @typeName(Namespace) ++
                "' is listed in " ++ @tagName(list) ++ "; it runs once, holding the GIL");
        }
    }

    comptime assert(signature.receiver == .none);
}

fn state_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);

    const State = module.state orelse return;

    if (@typeInfo(State) != .@"struct") {
        @compileError("lacuna: the state of '" ++ module.name ++ "' is '" ++
            @typeName(State) ++ "', which is not a struct");
    }

    if (!@hasDecl(State, "empty")) {
        @compileError("lacuna: the state '" ++ @typeName(State) ++ "' of '" ++ module.name ++
            "' declares no empty value to start from");
    }

    if (@TypeOf(State.empty) != State) {
        @compileError("lacuna: the empty value of the state '" ++ @typeName(State) ++
            "' is not a '" ++ @typeName(State) ++ "'");
    }

    if (@alignOf(State) > @import("state.zig").alignment_max) {
        @compileError("lacuna: the state '" ++ @typeName(State) ++ "' of '" ++ module.name ++
            "' needs more than 8-byte alignment, which module state does not promise");
    }

    if (@hasDecl(State, "deinit")) {
        if (@TypeOf(State.deinit) != fn (*State) void) {
            @compileError("lacuna: the deinit of the state '" ++ @typeName(State) ++
                "' must be fn (*" ++ @typeName(State) ++ ") void");
        }
    }

    comptime assert(@typeInfo(State) == .@"struct");
}

fn enums_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);

    if (module.enums.len > enum_count_max) {
        @compileError("lacuna: the module '" ++ module.name ++ "' declares too many enums");
    }

    for (module.enums) |Enum| {
        if (@typeInfo(Enum) != .@"enum") {
            @compileError("lacuna: '" ++ @typeName(Enum) ++ "' in .enums is not an enum");
        }

        signature_module.names_check(Enum);

        if (@typeInfo(Enum).@"enum".mode != .exhaustive) {
            @compileError("lacuna: the enum '" ++ @typeName(Enum) ++ "' must be exhaustive");
        }

        if (@typeInfo(@typeInfo(Enum).@"enum".tag_type).int.bits > kind_module.integer_bits_max) {
            @compileError(std.fmt.comptimePrint("lacuna: the enum '{s}' is wider than {d} bits", .{
                @typeName(Enum),
                kind_module.integer_bits_max,
            }));
        }

        for (@typeInfo(Enum).@"enum".field_names) |field| {
            signature_module.identifier_check(field);

            if (field[0] == '_') {
                @compileError("lacuna: the enum member '" ++ @typeName(Enum) ++ "." ++ field ++
                    "' starts with an underscore, which enum.Enum reserves");
            }
        }
    }
}

fn unions_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);

    if (module.unions.len > union_count_max) {
        @compileError("lacuna: the module '" ++ module.name ++ "' lists too many unions");
    }

    @import("variant.zig").unions_check(module);

    comptime assert(module.unions.len <= union_count_max);
}

fn submodules_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);

    if (module.submodules.len > submodule_count_max) {
        @compileError("lacuna: the module '" ++ module.name ++ "' declares too many submodules");
    }

    for (module.submodules) |submodule| {
        const prefix = module.name ++ ".";
        const leaf = submodule.name[@min(prefix.len, submodule.name.len)..];

        const nested = std.mem.startsWith(u8, submodule.name, prefix) and leaf.len > 0 and
            std.mem.findScalar(u8, leaf, '.') == null;

        if (!nested) {
            @compileError("lacuna: the submodule '" ++ submodule.name ++ "' must be named '" ++
                prefix ++ "<name>'");
        }

        if (submodule.thread_safe != module.thread_safe) {
            @compileError("lacuna: the submodule '" ++ submodule.name ++
                "' must match the thread safety of '" ++ module.name ++ "'");
        }

        if (submodule.interpreters != module.interpreters) {
            @compileError("lacuna: the submodule '" ++ submodule.name ++
                "' must match the interpreter support of '" ++ module.name ++ "'");
        }
    }
}

fn bases_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= class_count_max);

    const Bases = module.bases orelse return;
    const errors = errors_of(module);

    for (@typeInfo(Bases).@"struct".decl_names) |name| {
        const Base = @TypeOf(@field(Bases, name));

        if (Base != exception.BuiltinError) {
            if (Base != exception.BuiltinWarning) bases_module_check(errors, Bases, name);
        }

        if (error_index_of(errors, name) == null) {
            @compileError("lacuna: the bases of '" ++ module.name ++ "' name '" ++ name ++
                "', which no function raises as a module error");
        }

        base_chain_check(module, name);
    }
}

fn base_chain_check(comptime module: Module, comptime name: []const u8) void {
    comptime assert(module.name.len > 0);
    comptime assert(name.len > 0);

    const errors = errors_of(module);

    var visited: []const []const u8 = &.{name};
    var current: []const u8 = name;

    for (0..error_depth_max + 1) |_| {
        const base = base_of(module, current) orelse return;

        const parent = switch (base) {
            .builtin, .warning => return,
            .module => |index| errors[index],
        };

        for (visited) |seen| {
            if (std.mem.eql(u8, seen, parent)) {
                @compileError("lacuna: the bases of '" ++ module.name ++
                    "' form a cycle through '" ++ parent ++ "'");
            }
        }

        visited = visited ++ .{parent};
        current = parent;
    }

    @compileError(std.fmt.comptimePrint("lacuna: the bases of '{s}' chain '{s}' deeper " ++
        "than {d} errors", .{ module.name, name, error_depth_max }));
}

fn error_index_of(comptime errors: []const [:0]const u8, comptime name: []const u8) ?u32 {
    comptime assert(errors.len <= error_count_max);
    comptime assert(name.len > 0);

    for (errors, 0..) |error_name, index| {
        if (std.mem.eql(u8, error_name, name)) return index;
    }

    return null;
}

pub fn base_of(comptime module: Module, comptime name: []const u8) ?ErrorBase {
    comptime assert(name.len > 0);
    comptime assert(module.name.len > 0);

    const declared = if (module.bases) |Bases| @hasDecl(Bases, name) else false;

    if (!declared) {
        const standard = exception.standard_base_of(name) orelse return null;

        return .{ .builtin = standard };
    }

    const base = @field(module.bases.?, name);

    if (@TypeOf(base) == exception.BuiltinError) return .{ .builtin = base };
    if (@TypeOf(base) == exception.BuiltinWarning) return .{ .warning = base };

    const index = error_index_of(errors_of(module), @errorName(base)).?;

    return .{ .module = index };
}

pub fn warning_is(comptime module: Module, comptime name: []const u8) bool {
    comptime assert(name.len > 0);
    comptime assert(module.name.len > 0);

    const Bases = module.bases orelse return false;

    return warning_chained(Bases, name);
}

fn warning_chained(comptime Bases: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Bases) == .@"struct");
    comptime assert(name.len > 0);

    var current: []const u8 = name;

    for (0..error_depth_max + 1) |_| {
        if (!@hasDecl(Bases, current)) return false;

        const base = @field(Bases, current);
        const Base = @TypeOf(base);

        if (Base == exception.BuiltinWarning) return true;
        if (@typeInfo(Base) != .error_set) return false;

        current = @errorName(base);
    }

    return false;
}

pub fn errors_ordered(comptime module: Module) []const u32 {
    comptime assert(module.name.len > 0);

    const errors = errors_of(module);

    var order: [errors.len]u32 = undefined;
    var emitted: [errors.len]bool = @splat(false);
    var count: u32 = 0;

    for (0..error_depth_max + 1) |_| {
        for (errors, 0..) |name, index| {
            if (emitted[index]) continue;

            const ready = if (base_of(module, name)) |base| switch (base) {
                .builtin, .warning => true,
                .module => |parent| emitted[parent],
            } else true;

            if (ready) {
                order[count] = index;
                emitted[index] = true;
                count += 1;
            }
        }
    }

    comptime assert(count == errors.len);

    const frozen = order;

    return &frozen;
}

fn diagnostics_check(comptime module: Module) void {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= class_count_max);

    if (module.diagnostic) |Diagnostic| {
        if (!@import("diagnostic.zig").is_diagnostic(Diagnostic)) {
            @compileError("lacuna: the diagnostic of '" ++ module.name ++
                "' must come from lacuna.DiagnosticType");
        }
    }

    if (module.functions) |Namespace| {
        for (@typeInfo(Namespace).@"struct".decl_names) |name| {
            if (function_member_of(Namespace, name) == .function) {
                diagnostic_check(module, @TypeOf(@field(Namespace, name)), null, name);
            }
        }

        if (@hasDecl(Namespace, "exec")) {
            diagnostic_check(module, @TypeOf(Namespace.exec), null, "exec");
        }
    }

    for (module.classes) |Class| {
        for (@typeInfo(Class).@"struct".decl_names) |name| {
            switch (class_module.member_of(Class, name)) {
                .constructor, .creator, .method, .property, .setter => diagnostic_check(
                    module,
                    @TypeOf(@field(Class, name)),
                    Class,
                    name,
                ),
                else => {},
            }
        }
    }
}

fn diagnostic_check(
    comptime module: Module,
    comptime Function: type,
    comptime Class: ?type,
    comptime name: []const u8,
) void {
    comptime assert(module.name.len > 0);
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(Function) == .@"fn");

    const signature = signature_of(Function, Class, name);
    const Diagnostic = signature.Diagnostic orelse return;

    if (module.diagnostic != Diagnostic) {
        @compileError("lacuna: '" ++ name ++ "' takes a diagnostic of type '" ++
            @typeName(Diagnostic) ++ "', so the module must declare .diagnostic = " ++
            @typeName(Diagnostic));
    }
}

fn names_of(comptime module: Module) []const []const u8 {
    comptime assert(module.classes.len <= class_count_max);
    comptime assert(module.name.len > 0);

    var result: []const []const u8 = &.{"Error"};

    if (module.functions) |Namespace| {
        for (@typeInfo(Namespace).@"struct".decl_names) |name| {
            if (function_member_of(Namespace, name) == .function) {
                result = result ++ .{signature_module.python_name_of(Namespace, name)};
            }
        }
    }

    if (module.constants) |Namespace| {
        for (@typeInfo(Namespace).@"struct".decl_names) |name| result = result ++ .{name};
    }

    for (module.classes) |Class| {
        result = result ++ .{@import("from_python.zig").class_name(Class)};
    }

    for (module.enums) |Enum| {
        result = result ++ .{@import("from_python.zig").class_name(Enum)};
    }

    for (module.unions) |Union| {
        result = result ++ .{@import("from_python.zig").class_name(Union)};
    }

    for (errors_of(module)) |name| result = result ++ .{name};

    for (module.submodules) |submodule| {
        result = result ++ .{signature_module.module_leaf(submodule.name)};
    }

    if (result.len > name_count_max) @compileError("lacuna: the module declares too many names");

    comptime assert(std.mem.eql(u8, result[0], "Error"));

    return result;
}

pub fn errors_of(comptime module: Module) []const [:0]const u8 {
    comptime assert(module.classes.len <= class_count_max);
    comptime assert(module.name.len > 0);

    var declaration_count: u32 = 1;

    if (module.functions) |Namespace| {
        declaration_count += @intCast(@typeInfo(Namespace).@"struct".decl_names.len);
    }

    for (module.classes) |Class| {
        declaration_count += @intCast(@typeInfo(Class).@"struct".decl_names.len);
    }

    if (module.bases) |Bases| {
        declaration_count += @intCast(@typeInfo(Bases).@"struct".decl_names.len);
    }

    @setEvalBranchQuota(declaration_count * 8_000 + 100_000);

    var result: []const [:0]const u8 = &.{};

    if (module.functions) |Namespace| {
        for (@typeInfo(Namespace).@"struct".decl_names) |name| {
            if (function_member_of(Namespace, name) == .function) {
                result = errors_merge(result, @TypeOf(@field(Namespace, name)));
            }
        }

        if (@hasDecl(Namespace, "exec")) result = errors_merge(result, @TypeOf(Namespace.exec));
    }

    for (module.classes) |Class| {
        for (@typeInfo(Class).@"struct".decl_names) |name| {
            switch (class_module.member_of(Class, name)) {
                .reserved, .skipped => {},
                else => result = errors_merge(result, @TypeOf(@field(Class, name))),
            }
        }
    }

    if (module.bases) |Bases| result = warnings_merge(result, Bases);

    if (result.len > error_count_max) @compileError("lacuna: the module raises too many errors");

    return result;
}

fn warnings_merge(
    comptime known: []const [:0]const u8,
    comptime Bases: type,
) []const [:0]const u8 {
    comptime assert(@typeInfo(Bases) == .@"struct");
    comptime assert(known.len <= error_count_max);

    var result = known;

    for (@typeInfo(Bases).@"struct".decl_names) |name| {
        if (!warning_chained(Bases, name)) continue;
        if (exception.builtin_of(name) != null) continue;
        if (std.mem.eql(u8, name, python_error_name)) continue;

        const present = for (result) |existing| {
            if (std.mem.eql(u8, existing, name)) break true;
        } else false;

        if (!present) result = result ++ .{name};
    }

    return result;
}

fn errors_merge(
    comptime known: []const [:0]const u8,
    comptime Function: type,
) []const [:0]const u8 {
    comptime assert(@typeInfo(Function) == .@"fn");
    comptime assert(known.len <= error_count_max);

    const Return = @typeInfo(Function).@"fn".return_type.?;

    const ErrorSet = switch (@typeInfo(Return)) {
        .error_union => |error_union| error_union.error_set,
        else => return known,
    };

    const error_names = @typeInfo(ErrorSet).error_set.error_names orelse {
        @compileError("lacuna: a function returns anyerror; name its errors");
    };

    var result = known;

    for (error_names) |name| {
        if (exception.builtin_of(name) != null) continue;
        if (std.mem.eql(u8, name, python_error_name)) continue;

        const present = for (result) |existing| {
            if (std.mem.eql(u8, existing, name)) break true;
        } else false;

        if (!present) result = result ++ .{name};
    }

    return result;
}

fn bases_module_check(
    comptime errors: []const [:0]const u8,
    comptime Bases: type,
    comptime name: []const u8,
) void {
    comptime assert(errors.len <= error_count_max);
    comptime assert(@hasDecl(Bases, name));

    if (@typeInfo(@TypeOf(@field(Bases, name))) != .error_set) {
        @compileError("lacuna: the base of '" ++ name ++ "' must be a " ++
            "lacuna.BuiltinError, a lacuna.BuiltinWarning, or an error of the module");
    }

    const base_name = @errorName(@field(Bases, name));

    if (error_index_of(errors, base_name) == null) {
        @compileError("lacuna: the base of '" ++ name ++ "' is '" ++ base_name ++
            "', which no function raises as a module error");
    }
}

test errors_of {
    const Functions = struct {
        pub const Arguments = struct { value: u32 };
        pub const docs = .{ .open = "Open it." };

        pub fn open() error{ Busy, IndexError }!void {}

        pub fn close() error{ Busy, Closed, OutOfMemory }!void {}

        pub fn count() u32 {
            return 0;
        }
    };

    const module: Module = .{ .name = "device", .functions = Functions };
    const errors = comptime errors_of(module);

    comptime validate(module);

    try std.testing.expectEqual(2, errors.len);
    try std.testing.expectEqualStrings("Busy", errors[0]);
    try std.testing.expectEqualStrings("Closed", errors[1]);
    try std.testing.expectEqual(3, comptime function_count(Functions));
    try std.testing.expect(comptime function_member_of(Functions, "docs") == .reserved);
}

test base_of {
    const Functions = struct {
        pub fn open() error{ AccessDenied, FileNotFound, NotDir }!void {}
    };

    const Bases = struct {
        pub const Faint = error.Slow;
        pub const NotDir: exception.BuiltinError = .value_error;
        pub const Slow: exception.BuiltinWarning = .resource_warning;
    };

    const module: Module = .{ .bases = Bases, .functions = Functions, .name = "files" };
    const errors = comptime errors_of(module);

    comptime validate(module);

    try std.testing.expectEqual(5, errors.len);
    try std.testing.expectEqualStrings("Faint", errors[3]);
    try std.testing.expectEqualStrings("Slow", errors[4]);

    const denied = comptime base_of(module, "AccessDenied").?;
    const missing = comptime base_of(module, "FileNotFound").?;

    try std.testing.expect(denied.builtin == .permission_error);
    try std.testing.expect(missing.builtin == .file_not_found_error);
    try std.testing.expect(comptime base_of(module, "NotDir").?.builtin == .value_error);
    try std.testing.expect(comptime base_of(module, "Slow").?.warning == .resource_warning);
    try std.testing.expectEqual(4, comptime base_of(module, "Faint").?.module);
    try std.testing.expect(comptime warning_is(module, "Faint"));
    try std.testing.expect(comptime !warning_is(module, "AccessDenied"));

    const order = comptime errors_ordered(module);
    const slow_position = std.mem.findScalar(u32, order, 4).?;
    const faint_position = std.mem.findScalar(u32, order, 3).?;

    try std.testing.expect(slow_position < faint_position);
}

test Module {
    const Counter = struct {
        count: u32,

        pub fn init(counter: *@This()) void {
            counter.count = 0;
        }

        pub fn increment(counter: *@This()) error{Saturated}!void {
            counter.count = std.math.add(u32, counter.count, 1) catch return error.Saturated;
        }
    };

    const Functions = struct {
        pub fn reset() error{Busy}!void {}
    };

    const module: Module = .{
        .name = "counter",
        .classes = &.{Counter},
        .functions = Functions,
    };

    const errors = comptime errors_of(module);

    comptime validate(module);

    try std.testing.expectEqual(2, errors.len);
    try std.testing.expectEqualStrings("Busy", errors[0]);
    try std.testing.expectEqualStrings("Saturated", errors[1]);
}
