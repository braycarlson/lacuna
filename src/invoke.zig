const std = @import("std");

const arena_module = @import("arena.zig");
const arguments_module = @import("arguments.zig");
const c = @import("c.zig");
const cancellation_module = @import("cancellation.zig");
const exception = @import("exception.zig");
const instance = @import("instance.zig");
const kind_module = @import("kind.zig");
const panic_module = @import("panic.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const snapshot_module = @import("snapshot.zig");
const thread_module = @import("thread.zig");

const assert = std.debug.assert;

const Call = arguments_module.Call;
const InstanceType = instance.InstanceType;
const Scope = scope_module.Scope;
const Signature = signature_module.Signature;
const signature_of = signature_module.signature_of;
const snapshot = snapshot_module.snapshot;
const to_python = @import("to_python.zig").to_python;

pub const Counts = struct {
    holders: u32,
    limbs: u32,
    locks: u32,
    views: u32,

    pub const zero: Counts = .{ .holders = 0, .limbs = 0, .locks = 0, .views = 0 };
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
    coroutine,
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

    const signature = signature_of(@TypeOf(function), Class, name);
    const Diagnostic = signature.Diagnostic orelse void;
    const Self = Class orelse void;
    const counts = scope_counts(Binding, signature.Arguments);

    comptime assert(signature.receiver == .none or Class != null);
    comptime assert(mode != .released or signature.receiver == .none);
    comptime assert(mode != .coroutine or signature.receiver == .none or instance_frozen(Class));

    const receiver_locked = signature.receiver != .none and !instance_frozen(Class);

    comptime {
        const label = if (Class) |Known| @typeName(Known) ++ "." ++ name else name;
        const locks = @intFromBool(receiver_locked) +
            @intFromBool(signature.State != null) + counts.locks;

        scope_module.locks_check(label, locks);
        state_check(Binding, signature.State, label);
        arena_check(signature, label);

        if (signature.token_taken()) {
            if (mode != .coroutine) {
                const taken = if (signature.loop) "lacuna.Loop" else "lacuna.Cancellation";

                @compileError("lacuna: '" ++ label ++ "' takes a " ++ taken ++ ", which " ++
                    "only a coroutine receives");
            }
        }

        if (mode != .coroutine) {
            if (loop_objects_present(signature.Arguments)) {
                @compileError("lacuna: '" ++ label ++ "' takes a lacuna.LoopObject, which only " ++
                    "a coroutine that takes a lacuna.Loop can use");
            }
        }
    }

    const qualified = std.mem.findScalar(u8, name, '.') != null;
    const call_label: [:0]const u8 = if (qualified)
        name
    else if (Class) |Known|
        Binding.name ++ "." ++ @import("from_python.zig").class_name(Known) ++ "." ++ name
    else
        Binding.name ++ "." ++ name;

    return struct {
        const Entered = struct {
            call: ?[:0]const u8,
            state: ?*const Binding.State,
        };

        const Prepared = struct {
            call: Call,
            capsule: ?*c.PyObject,
            token: ?*cancellation_module.Token,
        };

        const Filling = struct {
            arena: ?std.mem.Allocator,
            capsule: ?*c.PyObject,
            token: ?*cancellation_module.Token,
            context: *const Context,
            native_base: ?*c.PyObject,
            user: *Binding.State.User,
        };

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

            const entered = enter(state);
            defer leave(entered);

            var limbs: [counts.limbs]std.math.big.Limb = undefined;
            var objects: [counts.holders]*c.PyObject = undefined;
            var views: [counts.views]c.Py_buffer = undefined;
            var scratch: if (signature.arena) arena_module.Scratch else void = undefined;

            if (signature.arena) scratch.start();
            defer if (signature.arena) scratch.finish();

            var scope: Scope = .init(.{ .limbs = &limbs, .objects = &objects, .views = &views });
            defer scope.release();

            locks_add(&scope, receiver, &context) catch return null;

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

            const prepared = prepared_of(call) catch return null;

            const filling: Filling = .{
                .arena = if (signature.arena) scratch.allocator() else null,
                .capsule = prepared.capsule,
                .token = prepared.token,
                .context = &context,
                .native_base = native_base,
                .user = @constCast(&state.user),
            };

            contexts_fill(&parameters, receiver, filling) catch return null;
            arguments_fill(&parameters, state, &prepared.call, &scope) catch return null;

            scope.lock_acquire();

            const outcome = invoke_call(&parameters);

            const payload = if (signature.Errors) |Errors| outcome catch |err| {
                const detail = if (signature.Diagnostic != null) &diagnostic else null;

                exception.raise(Binding, state, Errors, err, detail);

                return null;
            } else outcome;

            return finished(state, receiver, &payload, scope.lock_count > 0);
        }

        fn finished(
            state: *const Binding.State,
            receiver: ?Receiver(Self),
            payload: *const signature.Payload,
            locked: bool,
        ) ?*c.PyObject {
            assert((receiver != null) == (signature.receiver != .none));
            assert(@intFromPtr(state) % @alignOf(Binding.State) == 0);

            if (c.graalpy) {
                if (mode != .held) {
                    if (c.PyErr_Occurred() != null) return interrupted(payload);
                }
            }

            return result_of(Binding, Self, signature.Payload, state, receiver, payload, locked);
        }

        fn interrupted(payload: *const signature.Payload) ?*c.PyObject {
            comptime assert(c.graalpy);
            assert(c.PyErr_Occurred() != null);

            if (comptime instance.references_present(signature.Payload, 0)) {
                var consumed = payload.*;

                instance.references_release(signature.Payload, &consumed, 0);
            }

            return null;
        }

        fn prepared_of(call: *const Call) error{Raised}!Prepared {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(call.positional_count() <= std.math.maxInt(u32));

            const untouched: Prepared = .{ .call = call.*, .capsule = null, .token = null };

            if (!signature.token_taken()) return untouched;

            if (call.positional_count() == 0) {
                python.exception_raise(.{
                    .class_name = "TypeError",
                    .message = call_label ++ "() runs only through its coroutine wrapper",
                });

                return error.Raised;
            }

            const capsule = call.positional_get(0);
            const token = cancellation_module.token_of(capsule) orelse return error.Raised;

            return .{ .call = call.shifted(), .capsule = capsule, .token = token };
        }

        fn enter(state: *const Binding.State) Entered {
            assert(@intFromPtr(state) % @alignOf(Binding.State) == 0);
            assert(call_label.len > 0);

            const entered: Entered = .{ .call = panic_module.call, .state = Binding.current };

            Binding.current = state;
            panic_module.call = call_label;

            return entered;
        }

        fn leave(entered: Entered) void {
            assert(Binding.current != null);
            assert(panic_module.call.?.ptr == call_label.ptr);
            if (entered.state) |state| assert(@intFromPtr(state) % @alignOf(Binding.State) == 0);

            Binding.current = entered.state;
            panic_module.call = entered.call;
        }

        fn arguments_fill(
            parameters: *std.meta.ArgsTuple(@TypeOf(function)),
            state: *const Binding.State,
            call: *const Call,
            scope: *Scope,
        ) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(scope.lock_count <= scope_module.lock_count_max);

            const Arguments = signature.Arguments orelse {
                return arguments_module.bind_none(name, &state.builtins, call);
            };

            parameters[argument_index] = try arguments_module.bind(
                Binding,
                Arguments,
                name,
                state,
                call,
                scope,
            );
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

        fn locks_add(
            scope: *Scope,
            receiver: ?Receiver(Self),
            context: *const Context,
        ) error{Raised}!void {
            assert(scope.lock_count == 0);
            assert((receiver != null) == (signature.receiver != .none));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            if (receiver_locked) scope.lock_add(receiver.?.object);

            if (signature.State != null) scope.lock_add(try context.module_of());

            assert(scope.lock_count <= scope_module.lock_count_max);
        }

        fn contexts_fill(
            parameters: *std.meta.ArgsTuple(@TypeOf(function)),
            receiver: ?Receiver(Self),
            filling: Filling,
        ) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert((receiver != null) == (signature.receiver != .none));
            assert((filling.native_base != null) == signature.native_base);

            const context = filling.context;

            comptime var index = context_first;

            if (signature.native_base) {
                parameters[index] = .{ .pointer = filling.native_base.? };
                index += 1;
            }

            inline for (0..signature.ancestors.len) |level| {
                const Ancestor = signature_module.ancestor_of(Self, level);
                const data = InstanceType(Ancestor).ancestor_of(receiver.?.object);

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

            if (signature.State != null) {
                parameters[index] = .{ .data = filling.user };
                index += 1;
            }

            if (signature.arena) {
                parameters[index] = filling.arena.?;
                index += 1;
            }

            if (signature.cancellation) {
                parameters[index] = .{ .flag = &filling.token.?.flag };
                index += 1;
            }

            if (signature.loop) {
                parameters[index] = .{ .capsule = filling.capsule.?, .token = filling.token.? };
                index += 1;
            }

            comptime assert(index == argument_index);
        }

        fn native_base_of(object: *c.PyObject) error{Raised}!*c.PyObject {
            comptime assert(signature.native_base);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const class = python.type_borrowed(object);
            const defining = InstanceType(Self).defining_of(class).?;
            const slot = c.PyType_GetSlot(defining, c.Py_tp_base) orelse return error.Raised;
            const base: *c.PyObject = @ptrCast(@alignCast(slot));
            const unbound = python.attribute_get(base, "__init__") orelse return error.Raised;
            defer c.Py_DecRef(unbound);

            const getter = python.attribute_get(unbound, "__get__") orelse return error.Raised;
            defer c.Py_DecRef(getter);

            return c.PyObject_CallFunction(getter, "OO", object, class) orelse {
                return error.Raised;
            };
        }

        fn invoke_call(
            parameters: *const std.meta.ArgsTuple(@TypeOf(function)),
        ) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            switch (mode) {
                .held => return @call(.auto, function, parameters.*),
                .coroutine, .released => {
                    const detached = thread_module.detach();
                    const result = @call(.auto, function, parameters.*);

                    detached.reattach();

                    return result;
                },
            }
        }
    };
}

fn loop_objects_present(comptime Arguments: ?type) bool {
    comptime assert(Arguments == null or @typeInfo(Arguments.?) == .@"struct");

    const Struct = Arguments orelse return false;

    for (@typeInfo(Struct).@"struct".field_types) |Field| {
        if (Field == cancellation_module.LoopObject) return true;
        if (Field == ?cancellation_module.LoopObject) return true;
    }

    return false;
}

fn instance_frozen(comptime Class: ?type) bool {
    comptime assert(Class == null or @typeInfo(Class.?) == .@"struct");

    const Known = Class orelse return false;
    return InstanceType(Known).frozen;
}

fn arena_check(comptime signature: Signature, comptime label: []const u8) void {
    comptime assert(label.len > 0);
    comptime assert(signature.context_count() <= signature_module.argument_count_max);

    if (!signature.arena) return;

    const problem = "lacuna: '" ++ label ++ "' takes the per-call arena, which is freed when " ++
        "the call returns, ";

    if (signature.receiver == .mutable) {
        @compileError(problem ++ "so it cannot also take a mutable receiver that could keep " ++
            "its memory");
    }

    if (signature.State != null) {
        @compileError(problem ++ "so it cannot also take the module state that could keep " ++
            "its memory");
    }
}

fn state_check(comptime Binding: type, comptime State: ?type, comptime label: []const u8) void {
    comptime assert(label.len > 0);
    comptime assert(@hasDecl(Binding.State, "User"));

    const Taken = State orelse return;

    if (Taken == Binding.State.User) return;

    const declared = if (Binding.State.User == void)
        "declares no state"
    else
        "declares the state '" ++ @typeName(Binding.State.User) ++ "'";

    @compileError("lacuna: '" ++ label ++ "' takes the state '" ++ @typeName(Taken) ++
        "', but its module " ++ declared);
}

pub fn result_of(
    comptime Binding: type,
    comptime Class: type,
    comptime Payload: type,
    state: *const Binding.State,
    receiver: ?Receiver(Class),
    payload: *const Payload,
    locked: bool,
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

    if (comptime snapshot_module.borrowed(Payload, Binding.declared, 0)) {
        if (locked) return result_snapshot(Binding, Payload, state, payload);
    }

    return result_converted(Binding, Payload, state, payload);
}

fn result_converted(
    comptime Binding: type,
    comptime Payload: type,
    state: *const Binding.State,
    payload: *const Payload,
) ?*c.PyObject {
    comptime assert(Payload != type);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(state) % @alignOf(Binding.State) == 0);

    const result = to_python(Binding, Payload, state, payload) catch null;

    if (comptime instance.references_present(Payload, 0)) {
        var consumed = payload.*;

        instance.references_release(Payload, &consumed, 0);
    }

    if (std.debug.runtime_safety) assert((result == null) == (c.PyErr_Occurred() != null));

    return result;
}

fn result_snapshot(
    comptime Binding: type,
    comptime Payload: type,
    state: *const Binding.State,
    payload: *const Payload,
) ?*c.PyObject {
    comptime assert(snapshot_module.borrowed(Payload, Binding.declared, 0));
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(@intFromPtr(payload) % @alignOf(Payload) == 0);

    const size = snapshot_module.size_of(Payload, Binding.declared, payload);
    if (size == 0) return result_converted(Binding, Payload, state, payload);

    var buffer = snapshot_module.Buffer.acquire(size) orelse {
        if (comptime instance.references_present(Payload, 0)) {
            var consumed = payload.*;

            instance.references_release(Payload, &consumed, 0);
        }

        return null;
    };
    defer buffer.release();

    const copied = snapshot(Payload, Binding.declared, 0, &buffer.region, payload);

    assert(buffer.region.used == size);

    return result_converted(Binding, Payload, state, &copied);
}

pub fn limbs_of(comptime T: type, comptime classes: []const type) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(kind_module.big_integer_limb_count_max > 0);

    const result = scope_module.big_integer_count(T, classes, false) *
        kind_module.big_integer_limb_count_max;

    comptime assert(result <= kind_module.big_integer_limb_count_max);

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

    const Struct = Arguments orelse return .zero;

    var result: Counts = .zero;

    inline for (@typeInfo(Struct).@"struct".field_types) |Field| {
        result.holders += scope_module.holder_count(Field, Binding.declared, 0);
        result.locks += scope_module.lock_count(Field, Binding.declared, 0);
        result.views += scope_module.view_count(Field, Binding.declared, false);
        result.limbs += limbs_of(Field, Binding.declared);
    }

    if (@hasDecl(Struct, "keywords")) {
        const Extra = @FieldType(Struct, @tagName(Struct.keywords));

        if (Extra == @import("value.zig").Object) result.holders += 1;
    }

    if (@hasDecl(Struct, "variadic")) {
        const Rest = @FieldType(Struct, @tagName(Struct.variadic));

        if (Rest == @import("value.zig").TupleObject) result.holders += 1;
    }

    if (result.holders > scope_module.holder_count_max) {
        @compileError("lacuna: the arguments '" ++ @typeName(Struct) ++ "' hold too many objects");
    }

    if (result.limbs > scope_module.limb_count_max) {
        @compileError(std.fmt.comptimePrint("lacuna: the arguments '{s}' take more than {d} " ++
            "big integers", .{ @typeName(Struct), kind_module.big_integer_count_max }));
    }

    if (result.views > scope_module.view_count_max) {
        @compileError("lacuna: the arguments '" ++ @typeName(Struct) ++ "' hold too many buffers");
    }

    return result;
}
