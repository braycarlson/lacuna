const std = @import("std");

const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const critical = @import("critical.zig");
const exception = @import("exception.zig");
const instance = @import("instance.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const thread_module = @import("thread.zig");
const to_python_module = @import("to_python.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const Scope = scope_module.Scope;

pub const Counts = struct {
    holders: u32,
    sections: u32,
    views: u32,
};

pub const Context = struct {
    class: ?*c.PyObject = null,
    defining: ?*c.PyObject = null,
    module: ?*c.PyObject = null,

    pub const none: Context = .{};

    fn module_of(context: *const Context) error{Raised}!*c.PyObject {
        assert(context.module != null or context.defining != null);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        if (context.module) |module| return module;
        return c.PyType_GetModule(context.defining.?) orelse error.Raised;
    }
};

pub const Mode = enum {
    held,
    released,
};

pub fn Receiver(comptime Class: type) type {
    comptime assert(Class == void or @typeInfo(Class) == .@"struct");
    comptime assert(@typeInfo(Class) != .pointer);

    return struct {
        data: *Class,
        object: *c.PyObject,
    };
}

pub fn InvokerType(
    comptime Binding: type,
    comptime Class: ?type,
    comptime function: anytype,
    comptime name: [:0]const u8,
    comptime mode: Mode,
) type {
    comptime assert(name.len > 0);
    comptime assert(@typeInfo(@TypeOf(function)) == .@"fn");
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const signature = signature_module.signature_of(@TypeOf(function), Class, name);
    const Diagnostic = signature.Diagnostic orelse void;
    const Self = Class orelse void;
    const counts = scope_counts(Binding, signature.Arguments);

    comptime assert(signature.receiver == .none or Class != null);
    comptime assert(mode == .held or signature.receiver == .none);

    return struct {
        const context_first: u32 = @intFromBool(signature.receiver != .none);
        const argument_index: u32 = context_first + signature.context_count();

        pub fn invoke(
            state: *const Binding.State,
            receiver: ?Receiver(Self),
            context: Context,
            call: *const Call,
        ) ?*c.PyObject {
            assert((receiver != null) == (signature.receiver != .none));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(call.positional_count() <= std.math.maxInt(u32));
            if (context.class) |class| assert(python.class_is(class));
            if (context.defining) |defining| assert(python.class_is(defining));

            var section = critical.empty;

            if (receiver) |held| critical.begin(&section, held.object);
            defer if (receiver != null) critical.end(&section);

            var objects: [counts.holders]*c.PyObject = undefined;
            var sections: [counts.sections]critical.Section = undefined;
            var views: [counts.views]c.Py_buffer = undefined;

            var scope: Scope = .init(.{
                .objects = &objects,
                .sections = &sections,
                .views = &views,
            });

            defer scope.release();

            var parameters: std.meta.ArgsTuple(@TypeOf(function)) = undefined;
            var diagnostic: Diagnostic = if (signature.Diagnostic) |D| D.empty else {};
            _ = &diagnostic;

            if (signature.receiver != .none) receiver_fill(&parameters, receiver.?);
            if (signature.Diagnostic != null) parameters[parameters.len - 1] = &diagnostic;

            const native_base = if (signature.native_base)
                native_base_of(receiver.?.object) catch return null
            else
                null;

            defer c.Py_DecRef(native_base);

            contexts_fill(&parameters, receiver, &context, native_base) catch return null;

            if (signature.Arguments) |Arguments| {
                parameters[argument_index] = arguments_module.bind(
                    Binding,
                    Arguments,
                    name,
                    state,
                    call,
                    &scope,
                ) catch return null;
            } else {
                arguments_module.bind_none(name, &state.builtins, call) catch return null;
            }

            const outcome = invoke_call(&parameters);

            const payload = if (signature.Errors) |Errors| outcome catch |err| {
                const detail = if (signature.Diagnostic != null) &diagnostic else null;

                exception.raise(Binding, state, Errors, err, detail);

                return null;
            } else outcome;

            return result_of(Binding, Self, signature.Payload, state, receiver, &payload);
        }

        fn receiver_fill(
            parameters: *std.meta.ArgsTuple(@TypeOf(function)),
            receiver: Receiver(Self),
        ) void {
            comptime assert(signature.receiver != .none);
            assert(@intFromPtr(receiver.data) > @intFromPtr(receiver.object));

            parameters[0] = signature_module.receiver_argument(
                Self,
                receiver.data,
                receiver.object,
            );
        }

        fn contexts_fill(
            parameters: *std.meta.ArgsTuple(@TypeOf(function)),
            receiver: ?Receiver(Self),
            context: *const Context,
            native_base: ?*c.PyObject,
        ) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert((receiver != null) == (signature.receiver != .none));
            assert((native_base != null) == signature.native_base);

            comptime var index = context_first;

            if (signature.native_base) {
                parameters[index] = .{ .pointer = native_base.? };
                index += 1;
            }

            inline for (0..signature.ancestors.len) |level| {
                const Ancestor = signature_module.ancestor_of(Self, level);
                const data = instance.InstanceType(Ancestor).ancestor_of(receiver.?.object);

                parameters[index] = data;
                index += 1;
            }

            if (signature.type_object) {
                const class = context.class orelse python.type_borrowed(receiver.?.object);

                parameters[index] = .{ .object = .{ .pointer = class } };
                index += 1;
            }

            if (signature.module_object) {
                const module = try context.module_of();

                parameters[index] = .{ .object = .{ .pointer = module } };
                index += 1;
            }

            comptime assert(index == argument_index);
        }

        fn native_base_of(object: *c.PyObject) error{Raised}!*c.PyObject {
            comptime assert(signature.native_base);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const class = python.type_borrowed(object);
            const defining = instance.InstanceType(Self).defining_of(class).?;
            const slot = c.PyType_GetSlot(defining, c.Py_tp_base) orelse return error.Raised;
            const base: *c.PyObject = @ptrCast(@alignCast(slot));
            const unbound = c.PyObject_GetAttrString(base, "__init__") orelse return error.Raised;
            defer c.Py_DecRef(unbound);

            return c.PyObject_CallMethod(unbound, "__get__", "OO", object, class) orelse {
                return error.Raised;
            };
        }

        fn invoke_call(
            parameters: *const std.meta.ArgsTuple(@TypeOf(function)),
        ) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            switch (mode) {
                .held => return @call(.auto, function, parameters.*),
                .released => {
                    const detached = thread_module.detach();
                    const result = @call(.auto, function, parameters.*);

                    detached.reattach();

                    return result;
                },
            }
        }
    };
}

pub fn result_of(
    comptime Binding: type,
    comptime Class: type,
    comptime Payload: type,
    state: *const Binding.State,
    receiver: ?Receiver(Class),
    payload: *const Payload,
) ?*c.PyObject {
    comptime assert(Payload != type);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(payload) % @alignOf(Payload) == 0);
    assert(receiver == null or @intFromPtr(receiver.?.object) % @alignOf(*c.PyObject) == 0);

    if (comptime receiver_returned(Class, Payload)) {
        assert(receiver != null);
        assert(payload.* == receiver.?.data);

        return python.reference_new(receiver.?.object);
    }

    const result = to_python_module.to_python(Binding, Payload, state, payload) catch null;

    if (comptime instance.references_present(Payload, 0)) {
        var consumed = payload.*;

        instance.references_release(Payload, &consumed, 0);
    }

    if (std.debug.runtime_safety) assert((result == null) == (c.PyErr_Occurred() != null));

    return result;
}

fn receiver_returned(comptime Class: type, comptime Payload: type) bool {
    comptime assert(Class == void or @typeInfo(Class) == .@"struct");
    comptime assert(Payload != type);

    if (Class == void) return false;
    if (Payload == *Class) return true;
    return Payload == *const Class;
}

pub fn scope_counts(comptime Binding: type, comptime Arguments: ?type) Counts {
    comptime assert(Binding.classes.len <= std.math.maxInt(u32));
    comptime assert(Arguments == null or @typeInfo(Arguments.?) == .@"struct");

    const Struct = Arguments orelse return .{ .holders = 0, .sections = 0, .views = 0 };

    var result: Counts = .{ .holders = 0, .sections = 0, .views = 0 };

    inline for (@typeInfo(Struct).@"struct".field_types) |Field| {
        result.holders += scope_module.holder_count(Field, Binding.declared, 0);
        result.sections += scope_module.section_count(Field, Binding.declared, 0);
        result.views += scope_module.view_count(Field, Binding.declared, false);
    }

    if (@hasDecl(Struct, "keywords")) {
        const Extra = @FieldType(Struct, @tagName(Struct.keywords));

        if (Extra == @import("value.zig").Object) result.holders += 1;
    }

    if (result.holders > scope_module.holder_count_max) {
        @compileError("lacuna: the arguments '" ++ @typeName(Struct) ++ "' hold too many objects");
    }

    if (result.views > scope_module.view_count_max) {
        @compileError("lacuna: the arguments '" ++ @typeName(Struct) ++ "' hold too many buffers");
    }

    return result;
}
