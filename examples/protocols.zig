const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "protocols",
    .doc = "Inheritance, context parameters, and the protocols beyond arithmetic.",
    .classes = &[_]type{
        Shape,
        Circle,
        Ring,
        Accumulator,
        Bag,
        Clamped,
        Countdown,
        Samples,
        Handle,
        Session,
        Interned,
        Impostor,
    } ++ native_classes ++ metaclass_classes,
    .constants = Constants,
    .functions = Functions,
    .messages = Messages,
    .submodules = &.{geometry},
    .thread_safe = true,
};

const geometry: lacuna.Module = .{
    .name = "protocols.geometry",
    .doc = "A submodule registered by its parent.",
    .classes = &.{Point},
    .functions = Geometry,
    .thread_safe = true,
};

const Geometry = struct {
    pub fn distance(arguments: struct { left: *const Point, right: *const Point }) f64 {
        const result = std.math.hypot(
            arguments.left.horizontal - arguments.right.horizontal,
            arguments.left.vertical - arguments.right.vertical,
        );

        assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn qualified(module_object: lacuna.ModuleObject) lacuna.PythonError!lacuna.Reference {
        return module_object.object.attribute("__name__");
    }
};

const native_classes = if (lacuna.native_bases) [_]type{ Registry, ParseFailure } else [_]type{};

const metaclass_classes = if (lacuna.native_metaclasses)
    [_]type{ Catalog, Palette }
else
    [_]type{};

const Constants = struct {
    pub const native_bases = lacuna.native_bases;
    pub const native_metaclasses = lacuna.native_metaclasses;
};

pub const Point = struct {
    horizontal: f64,
    vertical: f64,

    pub const doc = "A point in the plane.";
    pub const fields = .{ .horizontal = .read, .vertical = .read };
    pub const pickle = true;

    pub const static_methods = .{.origin};

    pub fn init(point: *Point, arguments: struct { horizontal: f64, vertical: f64 }) void {
        point.* = .{ .horizontal = arguments.horizontal, .vertical = arguments.vertical };
    }

    pub fn origin() Point {
        return .{ .horizontal = 0, .vertical = 0 };
    }
};

pub const Error = error{ Exhausted, Negative, Unflushed };

const Messages = struct {
    pub fn message(err: Error) []const u8 {
        return switch (err) {
            error.Exhausted => "the countdown is exhausted",
            error.Negative => "the value is negative",
            error.Unflushed => "the handle was dropped with writes pending",
        };
    }
};

const Functions = struct {
    pub const docs = .{ .module_name = "The name of the module that defines this function." };

    pub fn circle_built(arguments: struct {
        kind: lacuna.Object,
        radius: f64,
    }) lacuna.PythonError!lacuna.Reference {
        const class: lacuna.TypeObject = .{ .object = arguments.kind };

        return class.instance_new(lacuna.ExtendedType(Circle){
            .value = .{ .radius = arguments.radius },
            .base = .{ .sides = 0, .scale = 1 },
        });
    }

    pub fn interned_built(arguments: struct {
        kind: lacuna.Object,
        key: i64,
    }) lacuna.PythonError!lacuna.Reference {
        const class: lacuna.TypeObject = .{ .object = arguments.kind };

        return class.instance_new(Interned{ .key = arguments.key });
    }

    pub fn module_name(module_object: lacuna.ModuleObject) lacuna.PythonError!lacuna.Reference {
        return module_object.object.attribute("__name__");
    }

    pub fn ring_of(arguments: struct { inner: f64, outer: f64 }) lacuna.ExtendedType(Ring) {
        return .{
            .value = .{ .inner = arguments.inner },
            .base = .{
                .value = .{ .radius = arguments.outer },
                .base = .{ .sides = 0, .scale = 1 },
            },
        };
    }
};

pub const Shape = struct {
    sides: u32,
    scale: f64,

    pub const doc = "A shape that other classes extend.";
    pub const fields = .{ .sides = .read, .scale = .read };
    pub const pickle = true;
    pub const properties = .{.doubled};
    pub const setters = .{ .doubled = .doubled_set };
    pub const subclassable = true;

    pub fn init(shape: *Shape, arguments: struct { sides: u32 }) void {
        shape.* = .{ .sides = arguments.sides, .scale = 1 };

        assert(shape.scale == 1);
    }

    pub fn doubled(shape: *const Shape) f64 {
        return shape.scale * 2;
    }

    pub fn doubled_set(shape: *Shape, arguments: struct { value: f64 }) Error!void {
        if (!(arguments.value >= 0)) return error.Negative;

        shape.scale = arguments.value / 2;

        assert(shape.scale >= 0);
    }

    pub fn grow(shape: *Shape, arguments: struct { factor: f64 }) void {
        shape.scale *= arguments.factor;
    }

    pub fn kind(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        return class.object.attribute("__name__");
    }

    pub fn __init_subclass__(
        class: lacuna.TypeObject,
        arguments: struct { sides: u32 = 0 },
    ) lacuna.PythonError!void {
        try class.object.attribute_set("sides_declared", arguments.sides);
    }
};

pub const Circle = struct {
    radius: f64,

    pub const dictionary = true;
    pub const doc = "A circle that extends Shape and keeps a __dict__.";
    pub const extends = Shape;
    pub const fields = .{ .radius = .read_write };
    pub const pickle = true;
    pub const subclassable = true;

    pub fn init(
        circle: *Circle,
        shape: *Shape,
        arguments: struct { radius: f64 },
    ) Error!void {
        if (!(arguments.radius >= 0)) return error.Negative;

        circle.* = .{ .radius = arguments.radius };
        shape.* = .{ .sides = 0, .scale = 1 };

        assert(circle.radius >= 0);
    }

    pub fn area(circle: *const Circle, shape: *const Shape) f64 {
        const radius = circle.radius * shape.scale;
        return std.math.pi * radius * radius;
    }

    pub fn unit(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        return class.object.call(.{1.0});
    }
};

pub const Ring = struct {
    inner: f64,

    pub const doc = "A ring two levels below Shape.";
    pub const extends = Circle;
    pub const fields = .{ .inner = .read };
    pub const pickle = true;
    pub const weakref = true;

    pub fn init(
        ring: *Ring,
        circle: *Circle,
        shape: *Shape,
        arguments: struct { inner: f64, outer: f64 },
    ) Error!void {
        if (!(arguments.inner >= 0)) return error.Negative;
        if (!(arguments.outer >= arguments.inner)) return error.Negative;

        ring.* = .{ .inner = arguments.inner };
        circle.* = .{ .radius = arguments.outer };
        shape.* = .{ .sides = 0, .scale = 1 };
    }

    pub fn width(ring: *const Ring, circle: *const Circle) f64 {
        return circle.radius - ring.inner;
    }
};

pub const Accumulator = struct {
    total: i64,

    const Operand = struct { value: i64 };

    pub const doc = "An accumulator with in-place operators.";
    pub const fields = .{ .total = .read };

    pub fn init(accumulator: *Accumulator, arguments: struct { total: i64 = 0 }) void {
        accumulator.* = .{ .total = arguments.total };
    }

    pub fn __iadd__(accumulator: *Accumulator, arguments: Operand) error{OverflowError}!void {
        accumulator.total = std.math.add(i64, accumulator.total, arguments.value) catch {
            return error.OverflowError;
        };
    }

    pub fn __isub__(accumulator: *Accumulator, arguments: Operand) error{OverflowError}!void {
        accumulator.total = std.math.sub(i64, accumulator.total, arguments.value) catch {
            return error.OverflowError;
        };
    }

    pub fn __pow__(
        accumulator: *const Accumulator,
        arguments: struct { exponent: u6 },
    ) error{OverflowError}!Accumulator {
        const total = std.math.powi(i64, accumulator.total, arguments.exponent) catch {
            return error.OverflowError;
        };

        return .{ .total = total };
    }

    pub fn __ipow__(accumulator: *Accumulator, arguments: struct { exponent: u6 }) void {
        accumulator.total = std.math.powi(i64, accumulator.total, arguments.exponent) catch 0;
    }
};

pub const Bag = struct {
    names: [4][8]u8,
    lengths: [4]u8,
    values: [4]i64,
    count: u8,

    pub const doc = "A bag of attributes served by __getattr__ and __setattr__.";
    pub const generic = true;
    pub const subclassable = true;

    pub fn init(bag: *Bag) void {
        bag.* = std.mem.zeroes(Bag);

        assert(bag.count == 0);
    }

    pub fn size(bag: *const Bag) u8 {
        return bag.count;
    }

    pub fn __getattr__(
        bag: *const Bag,
        arguments: struct { name: []const u8 },
    ) error{AttributeError}!i64 {
        const index = bag.find(arguments.name) orelse return error.AttributeError;
        return bag.values[index];
    }

    pub fn __setattr__(
        bag: *Bag,
        arguments: struct { name: []const u8, value: i64 },
    ) error{ AttributeError, MemoryError }!void {
        if (arguments.name.len > 8) return error.AttributeError;

        const index = bag.find(arguments.name) orelse slot: {
            if (bag.count == bag.values.len) return error.MemoryError;

            const created = bag.count;

            bag.count += 1;
            @memcpy(bag.names[created][0..arguments.name.len], arguments.name);
            bag.lengths[created] = @intCast(arguments.name.len);

            break :slot created;
        };

        bag.values[index] = arguments.value;

        assert(bag.count <= bag.values.len);
    }

    pub fn __delattr__(
        bag: *Bag,
        arguments: struct { name: []const u8 },
    ) error{AttributeError}!void {
        const index = bag.find(arguments.name) orelse return error.AttributeError;
        const last = bag.count - 1;

        bag.names[index] = bag.names[last];
        bag.lengths[index] = bag.lengths[last];
        bag.values[index] = bag.values[last];
        bag.count = last;
    }

    fn find(bag: *const Bag, name: []const u8) ?u8 {
        assert(bag.count <= bag.values.len);

        for (0..bag.count) |index| {
            const stored = bag.names[index][0..bag.lengths[index]];
            if (std.mem.eql(u8, stored, name)) return @intCast(index);
        }

        return null;
    }
};

pub const Clamped = struct {
    low: i64,
    high: i64,
    stored: i64,

    pub const doc = "A descriptor that clamps what is assigned through it.";

    pub fn init(clamped: *Clamped, arguments: struct { low: i64, high: i64 }) Error!void {
        if (arguments.high < arguments.low) return error.Negative;

        clamped.* = .{ .low = arguments.low, .high = arguments.high, .stored = arguments.low };
    }

    pub fn __get__(clamped: *const Clamped, arguments: struct {
        instance: ?lacuna.Object,
        owner: ?lacuna.Object,
    }) ?i64 {
        assert(arguments.owner != null or arguments.instance != null);

        if (arguments.instance == null) return null;
        return clamped.stored;
    }

    pub fn __set__(clamped: *Clamped, arguments: struct {
        instance: lacuna.Object,
        value: i64,
    }) void {
        assert(!arguments.instance.none());

        clamped.stored = std.math.clamp(arguments.value, clamped.low, clamped.high);
    }

    pub fn __delete__(clamped: *Clamped, arguments: struct { instance: lacuna.Object }) void {
        assert(!arguments.instance.none());

        clamped.stored = clamped.low;
    }
};

pub const Countdown = struct {
    remaining: u32,

    pub const doc = "An async iterator that counts down to zero.";

    pub fn init(countdown: *Countdown, arguments: struct { start: u32 }) void {
        countdown.* = .{ .remaining = arguments.start };
    }

    pub fn __aiter__(countdown: *Countdown) *Countdown {
        return countdown;
    }

    pub fn __anext__(countdown: *Countdown) lacuna.PythonError!?lacuna.Reference {
        if (countdown.remaining == 0) return null;

        countdown.remaining -= 1;

        var asyncio = try lacuna.import_module("asyncio");
        defer asyncio.release();

        const awaitable = try asyncio.object().?.call_method("sleep", .{ 0, countdown.remaining });
        return awaitable;
    }

    pub fn __await__(countdown: *Countdown) lacuna.PythonError!lacuna.Reference {
        var asyncio = try lacuna.import_module("asyncio");
        defer asyncio.release();

        var sleep = try asyncio.object().?.call_method("sleep", .{ 0, countdown.remaining });
        defer sleep.release();

        return sleep.object().?.call_method("__await__", .{});
    }
};

pub const Samples = struct {
    values: [6]f64,
    flags: [4]u8,

    pub const doc = "Memory exported through the buffer protocol.";

    pub fn init(samples: *Samples, arguments: struct { start: f64 = 0 }) void {
        for (&samples.values, 0..) |*value, index| {
            value.* = arguments.start + @as(f64, @floatFromInt(index));
        }

        samples.flags = .{ 1, 2, 3, 4 };
    }

    pub fn total(samples: *const Samples) f64 {
        var sum: f64 = 0;

        for (samples.values) |value| sum += value;

        return sum;
    }

    pub fn __buffer__(samples: *Samples) []f64 {
        return &samples.values;
    }
};

pub const Handle = struct {
    pending: u32,

    pub const doc = "A handle whose deinit fails while writes are pending.";
    pub const fields = .{ .pending = .read };
    pub const subclassable = true;

    pub fn init(handle: *Handle, arguments: struct { pending: u32 = 0 }) void {
        handle.* = .{ .pending = arguments.pending };
    }

    pub fn flush(handle: *Handle) void {
        handle.pending = 0;
    }

    pub fn deinit(handle: *Handle) error{Unflushed}!void {
        if (handle.pending > 0) return error.Unflushed;
    }
};

const SessionName = lacuna.TextType(16);
const SessionFormatted = lacuna.TextType(48);

pub const Session = struct {
    name: SessionName,
    depth: u32,
    closed: bool,

    pub const doc = "A session that exercises the dunders CPython resolves by name.";
    pub const fields = .{ .name = .read, .depth = .read, .closed = .read };

    pub fn init(session: *Session, arguments: struct { name: SessionName }) void {
        session.* = .{ .name = arguments.name, .depth = 0, .closed = false };
    }

    pub fn __enter__(session: *Session) *Session {
        session.depth += 1;
        session.closed = false;

        return session;
    }

    pub fn __exit__(session: *Session, arguments: struct {
        exc_type: ?lacuna.Object,
        exc_value: ?lacuna.Object,
        traceback: ?lacuna.Object,

        pub const positional_only = .{ .exc_type, .exc_value, .traceback };
    }) bool {
        assert(session.depth > 0);

        session.depth -= 1;
        session.closed = session.depth == 0;

        return arguments.exc_type != null and arguments.exc_value == null;
    }

    pub fn __aenter__(session: *Session) lacuna.PythonError!lacuna.Reference {
        session.depth += 1;

        return awaitable_of(false);
    }

    pub fn __aexit__(session: *Session, arguments: struct {
        exc_type: ?lacuna.Object,
        exc_value: ?lacuna.Object,
        traceback: ?lacuna.Object,

        pub const positional_only = .{ .exc_type, .exc_value, .traceback };
    }) lacuna.PythonError!lacuna.Reference {
        assert(session.depth > 0);
        assert(arguments.traceback == null or arguments.exc_value != null);

        session.depth -= 1;
        session.closed = session.depth == 0;

        return awaitable_of(false);
    }

    pub fn __format__(session: *const Session, arguments: struct {
        format_spec: []const u8,

        pub const positional_only = .{.format_spec};
    }) lacuna.TextError!SessionFormatted {
        var result: SessionFormatted = .empty;

        try result.extend(session.name.slice());
        try result.extend(":");
        try result.extend(arguments.format_spec);

        return result;
    }

    pub fn __bytes__(session: *const Session) lacuna.Bytes {
        return .{ .bytes = session.name.slice() };
    }

    pub fn __reversed__(session: *const Session) lacuna.ListError!lacuna.ListType(u8, 16) {
        var result: lacuna.ListType(u8, 16) = .empty;
        const name = session.name.slice();

        for (0..name.len) |index| (try result.push_slot()).* = name[name.len - 1 - index];

        return result;
    }

    pub fn __dir__(_: *const Session) [3][]const u8 {
        return .{ "closed", "depth", "name" };
    }

    pub fn __fspath__(session: *const Session) []const u8 {
        return session.name.slice();
    }

    pub fn __missing__(_: *const Session, arguments: struct {
        key: []const u8,

        pub const positional_only = .{.key};
    }) lacuna.TextError!SessionFormatted {
        var result: SessionFormatted = .empty;

        try result.extend("missing ");
        try result.extend(arguments.key);

        return result;
    }

    pub fn __complex__(session: *const Session) std.math.Complex(f64) {
        return .{ .re = @floatFromInt(session.depth), .im = 0 };
    }

    pub fn __round__(session: *const Session, arguments: struct {
        ndigits: ?i64 = null,

        pub const positional_only = .{.ndigits};
    }) i64 {
        const length: i64 = @intCast(session.name.length);

        return if (arguments.ndigits) |digits| length + digits else length;
    }

    pub fn __sizeof__(_: *const Session) u64 {
        return @sizeOf(Session);
    }

    pub fn __length_hint__(session: *const Session) u64 {
        return session.name.length;
    }

    pub fn __copy__(session: *const Session) Session {
        return session.*;
    }

    pub fn __deepcopy__(session: *const Session, arguments: struct {
        memo: lacuna.Object,

        pub const positional_only = .{.memo};
    }) Session {
        assert(!arguments.memo.none());

        return session.*;
    }

    pub fn __reduce_ex__(session: *const Session, class: lacuna.TypeObject, arguments: struct {
        protocol: i64,

        pub const positional_only = .{.protocol};
    }) struct { lacuna.Object, struct { SessionName } } {
        assert(arguments.protocol >= 0);

        return .{ class.object, .{session.name} };
    }

    pub fn __getnewargs__(session: *const Session) struct { SessionName } {
        return .{session.name};
    }

    fn awaitable_of(result: bool) lacuna.PythonError!lacuna.Reference {
        var asyncio = try lacuna.import_module("asyncio");
        defer asyncio.release();

        return asyncio.object().?.call_method("sleep", .{ 0, result });
    }
};

pub const Interned = struct {
    key: i64,

    pub const doc = "A value whose __new__ returns one instance per class and key.";
    pub const fields = .{ .key = .read };
    pub const subclassable = true;

    pub fn __new__(
        class: lacuna.TypeObject,
        module_object: lacuna.ModuleObject,
        arguments: struct { key: i64 },
    ) lacuna.PythonError!lacuna.Reference {
        var namespace = try module_object.object.attribute("__dict__");
        defer namespace.release();

        var fresh = try lacuna.DictObject.init();
        defer fresh.release();

        const name: []const u8 = "_interned";

        var table = try namespace.object().?.call_method("setdefault", .{ name, fresh.reference });
        defer table.release();

        var identity = try lacuna.TupleObject.init(2);
        defer identity.release();

        try identity.set(0, class.object);
        try identity.set(1, arguments.key);

        var existing = try table.object().?.call_method("get", .{identity.reference});

        if (!existing.object().?.none()) return existing;

        existing.release();

        var created = try class.instance_new(Interned{ .key = arguments.key });
        defer created.release();

        return table.object().?.call_method("setdefault", .{ identity.reference, created });
    }
};

pub const Impostor = struct {
    marker: u8,

    pub const doc = "A class whose __new__ returns an object of another type.";

    pub fn __new__(module_object: lacuna.ModuleObject) lacuna.PythonError!lacuna.Reference {
        return module_object.object.attribute("__name__");
    }
};

pub const Registry = struct {
    label: SessionName,

    pub const doc = "A dictionary that remembers a label.";
    pub const extends = lacuna.Native.dictionary;
    pub const fields = .{ .label = .read };

    pub fn init(registry: *Registry, arguments: struct { label: SessionName }) void {
        assert(arguments.label.length <= SessionName.capacity_max);

        registry.* = .{ .label = arguments.label };
    }
};

pub const ParseFailure = struct {
    line: u32,

    pub const doc = "An exception that carries the line it failed on.";
    pub const extends = lacuna.Native.exception;
    pub const fields = .{ .line = .read };

    pub fn init(
        failure: *ParseFailure,
        base: lacuna.Object,
        arguments: struct { message: []const u8, line: u32 },
    ) lacuna.PythonError!void {
        var initialized = try base.call(.{arguments.message});
        initialized.release();

        failure.* = .{ .line = arguments.line };
    }
};

pub const Catalog = struct {
    pub const doc = "A metaclass whose classes behave as sequences of their members.";
    pub const extends = lacuna.Native.type;
    pub const subclassable = true;

    pub fn describe(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        return class.object.attribute("__qualname__");
    }

    pub fn __contains__(
        class: lacuna.TypeObject,
        arguments: struct { item: lacuna.Object },
    ) lacuna.PythonError!bool {
        var members = try class.object.attribute("members");
        defer members.release();

        var found = try members.object().?.call_method("__contains__", .{arguments.item});
        defer found.release();

        return found.convert(bool);
    }

    pub fn __getitem__(
        class: lacuna.TypeObject,
        arguments: struct { index: i64 },
    ) lacuna.PythonError!lacuna.Reference {
        var members = try class.object.attribute("members");
        defer members.release();

        return members.object().?.item(arguments.index);
    }

    pub fn __iter__(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        var members = try class.object.attribute("members");
        defer members.release();

        return members.object().?.call_method("__iter__", .{});
    }

    pub fn __len__(class: lacuna.TypeObject) lacuna.PythonError!u64 {
        var members = try class.object.attribute("members");
        defer members.release();

        return members.object().?.length();
    }

    pub fn __repr__(class: lacuna.TypeObject) lacuna.PythonError!lacuna.Reference {
        return class.object.attribute("__qualname__");
    }
};

pub const Palette = struct {
    shade: u8,

    pub const constants = .{ .members = [_][]const u8{ "red", "green", "blue" } };
    pub const doc = "A class whose metaclass is the Zig metaclass Catalog.";
    pub const fields = .{ .shade = .read };
    pub const metaclass = Catalog;
    pub const subclassable = true;

    pub fn init(palette: *Palette, arguments: struct { shade: u8 }) void {
        palette.* = .{ .shade = arguments.shade };

        assert(palette.shade == arguments.shade);
    }
};
