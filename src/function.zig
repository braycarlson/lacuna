const std = @import("std");

const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const class_module = @import("class.zig");
const invoke_module = @import("invoke.zig");
const kind_module = @import("kind.zig");
const pending = @import("pending.zig");
const python = @import("python.zig");
const registry = @import("registry.zig");
const signature_module = @import("signature.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;

pub fn FunctionType(
    comptime Binding: type,
    comptime Namespace: type,
    comptime name: [:0]const u8,
) type {
    comptime assert(name.len > 0);
    comptime assert(@hasDecl(Namespace, name));

    const function = @field(Namespace, name);
    const python_name = comptime signature_module.python_name_of(Namespace, name);
    const signature = signature_module.signature_of(@TypeOf(function), null, python_name);
    const release = registry.release_of(Namespace, name);
    const coroutine = release == .coroutines;
    const deprecation = comptime class_module.deprecation_of(Namespace, name);
    const mode: invoke_module.Mode = if (release != null) .released else .held;
    const text = signature_module.text_signature(python_name, .module, signature.Arguments);

    comptime signature_module.identifier_check(python_name);
    comptime assert(signature.receiver == .none);

    if (release) |list| {
        parallel_check(Binding, signature.Arguments, name, list);

        if (signature.module_object) {
            @compileError("lacuna: the " ++ label_of(list) ++ " function '" ++ name ++
                "' takes the module object, which it cannot touch without the GIL");
        }
    }

    return struct {
        pub const definition: c.PyMethodDef = .{
            .ml_name = python_name,
            .ml_meth = &call,
            .ml_flags = c.METH_FASTCALL | c.METH_KEYWORDS,
            .ml_doc = signature_module.terminated(text ++ class_module.doc_of(Namespace, name)),
        };

        fn call(
            module: *c.PyObject,
            arguments: ?[*]const *c.PyObject,
            count: c.Py_ssize_t,
            names: ?*c.PyObject,
        ) callconv(.c) ?*c.PyObject {
            assert(count >= 0);
            assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
            assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (!coroutine) {
                if (deprecation) |message| {
                    pending.warn(
                        .deprecation_warning,
                        message,
                        class_module.deprecation_level,
                    ) catch return null;
                }
            }

            const state = Binding.State.of_module(module);
            const vector = python.vector_of(arguments, count, names);
            const invocation: Call = .fast(vector, count, names);

            return invoke_module.InvokerType(
                Binding,
                null,
                function,
                python_name,
                mode,
            ).invoke(state, null, .{ .module = module }, &invocation);
        }
    };
}

fn label_of(comptime list: registry.List) []const u8 {
    comptime assert(@tagName(list).len > 0);
    comptime assert(@typeInfo(registry.List).@"enum".field_names.len == 2);

    return switch (list) {
        .coroutines => "coroutine",
        .parallel => "parallel",
    };
}

fn parallel_check(
    comptime Binding: type,
    comptime Arguments: ?type,
    comptime name: []const u8,
    comptime list: registry.List,
) void {
    comptime assert(name.len > 0);
    comptime assert(@tagName(list).len > 0);
    comptime assert(Arguments == null or @typeInfo(Arguments.?) == .@"struct");
    comptime assert(Binding.classes.len <= registry.class_count_max);

    const Struct = Arguments orelse return;

    inline for (@typeInfo(Struct).@"struct".field_types) |Field| {
        if (comptime shared_of(Field, Binding.declared, 0)) {
            @compileError("lacuna: the " ++ label_of(list) ++ " function '" ++ name ++
                "' takes a Python object, which it cannot touch without the GIL");
        }
    }
}

fn shared_of(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(classes.len <= registry.class_count_max);

    if (depth == kind_module.depth_max) return false;

    return switch (kind_module.kind_of(T, classes)) {
        .class_extended, .class_pointer, .class_pointer_mutable, .class_value => true,
        .container, .object, .reference => true,
        .array => shared_of(@typeInfo(T).array.child, classes, depth + 1),
        .list, .set => shared_of(T.Item, classes, depth + 1),
        .map => shared_of(T.Key, classes, depth + 1) or shared_of(T.Value, classes, depth + 1),
        .optional => shared_of(@typeInfo(T).optional.child, classes, depth + 1),
        .record, .tuple => fields: {
            for (@typeInfo(T).@"struct".field_types) |Field| {
                if (shared_of(Field, classes, depth + 1)) break :fields true;
            }

            break :fields false;
        },
        .variant => payloads: {
            for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) {
                    if (shared_of(Payload, classes, depth + 1)) break :payloads true;
                }
            }

            break :payloads false;
        },
        else => false,
    };
}
