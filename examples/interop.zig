const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const std_options: std.Options = .{ .logFn = lacuna.log_function, .log_level = .debug };

pub const module: lacuna.Module = .{
    .name = "interop",
    .bases = Bases,
    .doc = "Python objects, signatures, and value types that lacuna converts.",
    .classes = &.{ Node, Shape, Tally },
    .diagnostic = Diagnostic,
    .functions = Functions,
    .messages = Messages,
    .thread_safe = true,
};

pub const Diagnostic = lacuna.DiagnosticType(struct { line: u32, column: u32 });
pub const Error = error{ CallbackFailed, ParseError, RangeInverted, SyntaxInvalid };
const Label = lacuna.TextType(32);
const Name = lacuna.TextType(16);
const Letters = lacuna.SetType(u8, 64);
const Words = lacuna.SetType([]const u8, 16);
const Scores = lacuna.MapType([]const u8, i64, 8);
const Inverted = lacuna.MapType(i64, []const u8, 8);
const Options = lacuna.MapType([]const u8, i64, 4);
const Rest = lacuna.ListType(i64, 8);
const Frozen = lacuna.FrozenSetType(i64, 8);
const Complex = std.math.Complex(f64);

const capsule_name = "interop.counter";
const worker_count_max: u32 = 8;
const worker_stack_bytes: u32 = 1 << 20;

const Worker = struct {
    function: lacuna.Reference,
    failure: lacuna.Reference,
    index: u32,
    interpreter: lacuna.Interpreter,
    result: i64,

    fn run(worker: *Worker) void {
        assert(worker.function.pointer != null);
        assert(worker.failure.pointer == null);

        const attached = worker.interpreter.attach();
        defer attached.release();

        var outcome = worker.function.object().?.call(.{worker.index}) catch {
            worker.failure = lacuna.exception.take();

            return;
        };

        defer outcome.release();

        worker.result = outcome.convert(i64) catch {
            worker.failure = lacuna.exception.take();

            return;
        };
    }

    fn total(workers: []Worker) lacuna.PythonError!i64 {
        assert(workers.len <= worker_count_max);

        var sum: i64 = 0;
        var failure: lacuna.Reference = .empty;

        for (workers) |*worker| {
            worker.function.release();

            if (worker.failure.pointer != null) {
                if (failure.pointer == null) failure = worker.failure else worker.failure.release();
            }

            sum +%= worker.result;
        }

        if (failure.pointer != null) return lacuna.exception.restore(&failure);
        return sum;
    }
};

const Probe = struct {
    fn count(rounds: u32) u32 {
        assert(rounds > 0);

        var seen: u32 = 0;

        for (0..rounds) |_| seen += @intFromBool(lacuna.Interpreter.attached());

        assert(seen <= rounds);

        return seen;
    }

    fn run(rounds: u32, seen: *u32) void {
        assert(rounds > 0);
        assert(seen.* == 0);

        seen.* = count(rounds);
    }
};

const Ranges = struct {
    fn init(count: u32) lacuna.PythonError!lacuna.ListObject {
        var list = try lacuna.ListObject.init(count);
        errdefer list.release();

        for (0..count) |index| try list.append(@as(u64, index));

        assert(list.length() == count);

        return list;
    }
};

const Bases = struct {
    pub const ParseError: lacuna.BuiltinError = .value_error;
    pub const RangeInverted = error.ParseError;
    pub const SyntaxInvalid = error.ParseError;
};

const Messages = struct {
    pub fn message(err: Error) []const u8 {
        return switch (err) {
            error.CallbackFailed => "the callback raised",
            error.ParseError => "the range could not be parsed",
            error.RangeInverted => "the minimum is greater than the maximum",
            error.SyntaxInvalid => "the range is not two integers joined by '..'",
        };
    }
};

const Functions = struct {
    pub const docs = .{
        .apply = "Call a Python function with an integer and return its integer result.",
        .parse = "Parse 'low..high' and return the width of the range.",
    };

    pub const deprecated = .{ .subtract = "use difference instead" };
    pub const names = .{ .zig_doubled = "python_doubled" };

    pub fn parse(arguments: struct { text: []const u8 }, diagnostic: *Diagnostic) Error!i64 {
        assert(std.unicode.utf8ValidateSlice(arguments.text));

        const separator = std.mem.find(u8, arguments.text, "..") orelse {
            diagnostic.print("1:1: no '..' in {s}", .{arguments.text});
            diagnostic.details = .{ .line = 1, .column = 1 };

            return error.SyntaxInvalid;
        };

        const low_text = arguments.text[0..separator];
        const high_text = arguments.text[separator + 2 ..];
        const low = std.fmt.parseInt(i64, low_text, 10) catch return error.SyntaxInvalid;
        const high = std.fmt.parseInt(i64, high_text, 10) catch return error.SyntaxInvalid;

        if (low > high) {
            const column: u32 = @intCast(separator + 3);

            diagnostic.print("1:{d}: the minimum {d} is greater than the maximum {d}", .{
                column,
                low,
                high,
            });

            diagnostic.details = .{ .line = 1, .column = column };

            return error.RangeInverted;
        }

        const result = std.math.sub(i64, high, low) catch return error.RangeInverted;

        assert(result >= 0);

        return result;
    }

    pub fn apply(arguments: struct { function: lacuna.Object, value: i64 }) lacuna.PythonError!i64 {
        var result = try arguments.function.call(.{arguments.value});
        defer result.release();

        return result.convert(i64);
    }

    pub fn shout(
        arguments: struct { item: lacuna.Object },
    ) (lacuna.PythonError || lacuna.TextError)!Label {
        var upper = try arguments.item.call_method("upper", .{});
        defer upper.release();

        var result: Label = .empty;

        try result.extend(try upper.convert([]const u8));

        return result;
    }

    pub fn forward(
        arguments: struct { function: lacuna.Object },
    ) lacuna.PythonError!lacuna.Reference {
        return arguments.function.call(.{});
    }

    pub fn forward_counted(arguments: struct {
        function: lacuna.Object,
    }) lacuna.PythonError!struct { lacuna.Reference, i64 } {
        var result = try arguments.function.call(.{});
        errdefer result.release();

        var length = try result.object().?.call_method("__len__", .{});
        defer length.release();

        return .{ result, try length.convert(i64) };
    }

    pub fn lookup(
        arguments: struct { mapping: lacuna.Object, key: []const u8 },
    ) lacuna.PythonError!i64 {
        var found = arguments.mapping.item(arguments.key) catch |err| {
            if (!lacuna.exception.matches_builtin(.key_error)) return err;

            lacuna.exception.clear();

            return -1;
        };

        defer found.release();

        return found.convert(i64);
    }

    pub fn guarded(arguments: struct { function: lacuna.Object }) error{CallbackFailed}!i64 {
        var result = arguments.function.call(.{}) catch return error.CallbackFailed;
        defer result.release();

        return result.convert(i64) catch error.CallbackFailed;
    }

    pub fn captured(
        arguments: struct { function: lacuna.Object },
    ) lacuna.PythonError!lacuna.Reference {
        var result = arguments.function.call(.{}) catch {
            return lacuna.exception.take();
        };

        defer result.release();

        return lacuna.exception.raise_builtin(.runtime_error, "the callback returned");
    }

    pub fn rethrown(arguments: struct { function: lacuna.Object }) lacuna.PythonError!void {
        var result = arguments.function.call(.{}) catch {
            var raised = lacuna.exception.take();

            return lacuna.exception.restore(&raised);
        };

        result.release();
    }

    pub fn fan_out(
        arguments: struct { function: lacuna.Object, count: u8 },
    ) lacuna.PythonError!i64 {
        if (arguments.count > worker_count_max) {
            return lacuna.exception.raise_builtin(.value_error, "at most 8 workers");
        }

        var workers: [worker_count_max]Worker = undefined;
        var threads: [worker_count_max]std.Thread = undefined;
        const active = workers[0..arguments.count];
        const interpreter = lacuna.Interpreter.current();

        for (active, 0..) |*worker, index| {
            worker.* = .{
                .function = .acquire(arguments.function),
                .failure = .empty,
                .index = @intCast(index),
                .interpreter = interpreter,
                .result = 0,
            };
        }

        var spawned: u32 = 0;
        const detached = lacuna.detach();

        for (active, 0..) |*worker, index| {
            const options: std.Thread.SpawnConfig = .{ .stack_size = worker_stack_bytes };

            threads[index] = std.Thread.spawn(options, Worker.run, .{worker}) catch break;
            spawned += 1;
        }

        for (threads[0..spawned]) |thread| thread.join();

        detached.reattach();

        for (active[spawned..]) |*worker| worker.function.release();

        const sum = try Worker.total(active[0..spawned]);

        if (spawned < active.len) {
            return lacuna.exception.raise_builtin(.runtime_error, "a worker failed to start");
        }

        return sum;
    }

    pub fn configure(arguments: struct { target: lacuna.Object }) lacuna.PythonError!void {
        try arguments.target.attribute_set("enabled", true);
        try arguments.target.attribute_set("label", "configured");
        try arguments.target.attribute_delete("legacy");
    }

    pub fn store(
        arguments: struct { mapping: lacuna.Object, key: []const u8, value: i64 },
    ) lacuna.PythonError!void {
        try arguments.mapping.item_set(.{ .key = arguments.key, .value = arguments.value });
        try arguments.mapping.item_delete("stale");
    }

    pub fn summed(arguments: struct { items: lacuna.Object }) lacuna.PythonError!i64 {
        var iterator = try arguments.items.iterate();
        defer iterator.release();

        var total: i64 = 0;

        for (0..1 << 20) |_| {
            var item = try iterator.next() orelse return total;
            defer item.release();

            total +%= try item.convert(i64);
        }

        return lacuna.exception.raise_builtin(.value_error, "the items number more than 2**20");
    }

    pub fn split_count(arguments: struct { text: lacuna.Object }) lacuna.PythonError!u64 {
        var parts = try arguments.text.call_method_keywords("split", .{
            .arguments = .{},
            .keywords = .{ .sep = ",", .maxsplit = 1 },
        });

        defer parts.release();

        return parts.object().?.length();
    }

    pub fn describe(
        arguments: struct { item: lacuna.Object },
    ) (lacuna.PythonError || lacuna.TextError)!Label {
        var text = try arguments.item.representation();
        defer text.release();

        var result: Label = .empty;

        try result.extend(try text.convert([]const u8));

        return result;
    }

    pub fn inspect(arguments: struct {
        item: lacuna.Object,
        kind: lacuna.Object,
        other: lacuna.Object,
    }) lacuna.PythonError!struct { bool, bool, bool, bool, bool, i64 } {
        const kind = try lacuna.TypeObject.of(arguments.kind);
        const instance = try arguments.item.instance_of(kind);
        const truthy = try arguments.item.truthy();
        const equal = try arguments.item.equal(.{ .other = arguments.other });
        const less = try arguments.item.compare(.{ .other = arguments.other, .comparison = .less });

        var class = arguments.item.class();
        defer class.release();

        const exact = class.object().?.identical(.{ .other = arguments.kind });

        if (exact) assert(instance);

        return .{ instance, exact, truthy, equal, less, try arguments.item.hash() };
    }

    pub fn dumps(arguments: struct { item: lacuna.Object }) lacuna.PythonError!lacuna.Reference {
        var json = try lacuna.import_module("json");
        defer json.release();

        return json.object().?.call_method_keywords("dumps", .{
            .arguments = .{arguments.item},
            .keywords = .{ .sort_keys = true },
        });
    }

    pub fn item_length(arguments: struct { item: lacuna.Object }) lacuna.PythonError!u64 {
        var method = try arguments.item.attribute("__len__");
        defer method.release();

        var length = try method.object().?.call(.{});
        defer length.release();

        return length.convert(u64);
    }

    pub fn combine(arguments: struct {
        first: i64,
        rest: Rest,
        scale: i64 = 1,
        options: Options,

        pub const positional_only = .{.first};
        pub const variadic = .rest;
        pub const keywords = .options;
    }) error{OverflowError}!i64 {
        assert(arguments.rest.count <= Rest.capacity_max);

        var total = arguments.first;

        for (arguments.rest.slice()) |item| {
            total = std.math.add(i64, total, item) catch return error.OverflowError;
        }

        total = std.math.mul(i64, total, arguments.scale) catch return error.OverflowError;

        for (arguments.options.slice()) |entry| {
            total = std.math.add(i64, total, entry.value) catch return error.OverflowError;
        }

        return total;
    }

    pub fn clamp(arguments: struct {
        value: f64,
        low: f64 = 0,
        high: f64 = 1,

        pub const keyword_only = .{ .low, .high };
    }) error{ValueError}!f64 {
        if (arguments.low > arguments.high) return error.ValueError;

        const result = std.math.clamp(arguments.value, arguments.low, arguments.high);

        assert(std.math.isNan(result) or result >= arguments.low);

        return result;
    }

    pub fn difference(arguments: struct {
        left: i64,
        right: i64,

        pub const positional_only = .{ .left, .right };
    }) error{OverflowError}!i64 {
        return std.math.sub(i64, arguments.left, arguments.right) catch error.OverflowError;
    }

    pub fn subtract(arguments: struct { left: i64, right: i64 }) error{OverflowError}!i64 {
        return difference(.{ .left = arguments.left, .right = arguments.right });
    }

    pub fn zig_doubled(arguments: struct {
        zig_value: i64,

        pub const names = .{ .zig_value = "python_value" };
    }) error{OverflowError}!i64 {
        return std.math.mul(i64, arguments.zig_value, 2) catch error.OverflowError;
    }

    pub fn evaluated(arguments: struct { left: i64, right: i64 }) lacuna.PythonError!i64 {
        var namespace = try lacuna.DictObject.init();
        defer namespace.release();

        try namespace.set(.{ .key = "left", .value = arguments.left });
        try namespace.set(.{ .key = "right", .value = arguments.right });

        var result = try lacuna.eval("left + right", namespace.reference.object().?, null);
        defer result.release();

        return result.convert(i64);
    }

    pub fn executed(
        arguments: struct { source: [:0]const u8 },
    ) lacuna.PythonError!lacuna.DictObject {
        var namespace = try lacuna.DictObject.init();
        errdefer namespace.release();

        try lacuna.run(arguments.source, namespace.reference.object().?, null);

        return namespace;
    }

    pub fn fraction_echo(arguments: struct { value: lacuna.Fraction }) lacuna.Fraction {
        assert(arguments.value.denominator > 0);

        return arguments.value;
    }

    pub fn address_echo(arguments: struct { value: lacuna.IPAddress }) lacuna.IPAddress {
        return arguments.value;
    }

    pub fn capsule_made(arguments: struct { value: i64 }) lacuna.PythonError!lacuna.Reference {
        const Counter = struct {
            var stored: i64 = 0;
        };

        Counter.stored = arguments.value;

        return lacuna.capsule_new(&Counter.stored, capsule_name);
    }

    pub fn capsule_read(arguments: struct { capsule: lacuna.Object }) lacuna.PythonError!i64 {
        const counter = try arguments.capsule.capsule_pointer(i64, capsule_name);

        return counter.*;
    }

    pub fn weak_reference(
        arguments: struct { item: lacuna.Object },
    ) lacuna.PythonError!lacuna.Reference {
        return arguments.item.weakref();
    }

    pub fn weak_target(
        arguments: struct { reference: lacuna.Object },
    ) lacuna.PythonError!lacuna.Reference {
        const target = try arguments.reference.weakref_target();

        return target orelse lacuna.Reference.acquire(lacuna.none());
    }

    pub fn singletons() struct { lacuna.Object, lacuna.Object, lacuna.Object } {
        return .{ lacuna.none(), lacuna.ellipsis(), lacuna.not_implemented() };
    }

    pub fn python_version() struct { u8, u8 } {
        const version = lacuna.Interpreter.version();

        assert(version.major == 3);

        return .{ version.major, version.minor };
    }

    pub fn logged(arguments: struct { text: []const u8 }) void {
        assert(std.unicode.utf8ValidateSlice(arguments.text));

        std.log.scoped(.interop_zig).warn("logged {s}", .{arguments.text});
        std.log.scoped(.interop_zig).debug("detail {d}", .{arguments.text.len});

        const detached = lacuna.detach();

        assert(!lacuna.Interpreter.attached());

        std.log.scoped(.interop_zig).info("detached {d}", .{arguments.text.len});
        detached.reattach();
    }

    pub fn caution(arguments: struct { text: []const u8 }) lacuna.PythonError!u64 {
        try lacuna.exception.warn(.user_warning, arguments.text, 1);

        return arguments.text.len;
    }

    pub fn interruptible(arguments: struct { rounds: u32 }) lacuna.PythonError!u32 {
        assert(lacuna.Interpreter.attached());

        for (0..arguments.rounds) |_| {
            const detached = lacuna.detach();

            assert(!lacuna.Interpreter.attached());

            detached.reattach();

            try lacuna.exception.signals_check();
        }

        return arguments.rounds;
    }

    pub fn attachment_seen(
        arguments: struct { rounds: u32 },
    ) lacuna.PythonError!struct { u32, u32 } {
        assert(lacuna.Interpreter.attached());

        if (arguments.rounds == 0) return lacuna.exception.raise_builtin(.value_error, "no rounds");

        var foreign: u32 = 0;
        const options: std.Thread.SpawnConfig = .{ .stack_size = worker_stack_bytes };
        const detached = lacuna.detach();
        const own = Probe.count(arguments.rounds);

        const probe: ?std.Thread = std.Thread.spawn(
            options,
            Probe.run,
            .{ arguments.rounds, &foreign },
        ) catch null;

        if (probe) |thread| thread.join();

        detached.reattach();

        assert(lacuna.Interpreter.attached());

        if (probe == null) {
            return lacuna.exception.raise_builtin(.runtime_error, "the probe failed to start");
        }

        return .{ own, foreign };
    }

    pub fn range_list(arguments: struct { count: u32 }) lacuna.PythonError!lacuna.ListObject {
        return Ranges.init(arguments.count);
    }

    pub fn list_total(arguments: struct { values: lacuna.ListObject }) lacuna.PythonError!i64 {
        var total: i64 = 0;

        for (0..@as(usize, @intCast(arguments.values.length()))) |index| {
            var held: lacuna.Reference = .acquire(try arguments.values.item(index));
            defer held.release();

            total +%= try held.convert(i64);
        }

        return total;
    }

    pub fn squares(arguments: struct { count: u32 }) lacuna.PythonError!lacuna.DictObject {
        var dictionary = try lacuna.DictObject.init();
        errdefer dictionary.release();

        for (0..arguments.count) |index| {
            const number: u64 = index;

            try dictionary.set(.{ .key = number, .value = number * number });
        }

        assert(dictionary.length() == arguments.count);

        return dictionary;
    }

    pub fn dictionary_probe(arguments: struct {
        mapping: lacuna.DictObject,
        key: []const u8,
    }) lacuna.PythonError!struct { bool, u64 } {
        const found = try arguments.mapping.get(arguments.key);

        if (found != null) try arguments.mapping.delete(arguments.key);

        var entries = arguments.mapping.entries();
        var count: u64 = 0;

        for (0..@as(usize, @intCast(arguments.mapping.length())) + 1) |_| {
            _ = entries.next() orelse break;
            count += 1;
        }

        return .{ found != null, count };
    }

    pub fn characters(
        arguments: struct { text: []const u8 },
    ) lacuna.PythonError!lacuna.TupleObject {
        var tuple = try lacuna.TupleObject.init(arguments.text.len);
        errdefer tuple.release();

        for (arguments.text, 0..) |_, index| {
            try tuple.set(index, arguments.text[index .. index + 1]);
        }

        assert(tuple.length() == arguments.text.len);

        return tuple;
    }

    pub fn distinct(arguments: struct {
        values: lacuna.ListObject,
    }) lacuna.PythonError!struct { lacuna.SetObject, lacuna.FrozenSetObject } {
        var set = try lacuna.SetObject.init();
        errdefer set.release();

        var frozen_set = try lacuna.FrozenSetObject.init();
        errdefer frozen_set.release();

        for (0..@as(usize, @intCast(arguments.values.length()))) |index| {
            const element = try arguments.values.item(index);

            try set.add(element);
            try frozen_set.add(element);
        }

        assert(set.length() == frozen_set.length());
        if (arguments.values.length() > 0) assert(try set.contains(try arguments.values.item(0)));

        return .{ set, frozen_set };
    }

    pub fn spelled(arguments: struct { count: u32 }) lacuna.PythonError!lacuna.Reference {
        var array = try lacuna.ByteArrayObject.init(0);
        defer array.release();

        var buffer: [4096]u8 = undefined;
        var writer = array.writer(&buffer);

        for (0..arguments.count) |_| {
            writer.interface.writeAll("ab") catch {
                assert(lacuna.exception.occurred());

                return error.PythonError;
            };
        }

        writer.interface.flush() catch {
            assert(lacuna.exception.occurred());

            return error.PythonError;
        };

        assert(array.length() == 2 * @as(u64, arguments.count));

        return array.to_text();
    }

    pub fn bytearray_grow(arguments: struct {
        data: lacuna.ByteArrayObject,
        extra: u32,
    }) lacuna.PythonError!lacuna.ByteArrayObject {
        const start: usize = @intCast(arguments.data.length());

        try arguments.data.resize(start + arguments.extra);
        @memset(arguments.data.slice()[start..], '!');

        return arguments.data;
    }

    pub fn wrapped_lengths(arguments: struct {
        list: lacuna.Object,
        tuple: lacuna.Object,
        mapping: lacuna.Object,
        set: lacuna.Object,
        array: lacuna.Object,
    }) lacuna.PythonError!struct { u64, u64, u64, u64, u64 } {
        const array = try arguments.array.as_bytearray();
        var bytes = try array.to_bytes();
        defer bytes.release();

        return .{
            (try arguments.list.as_list()).length(),
            (try arguments.tuple.as_tuple()).length(),
            (try arguments.mapping.as_dict()).length(),
            (try arguments.set.as_set()).length(),
            try bytes.object().?.length(),
        };
    }

    pub fn keyword_count(arguments: struct {
        extra: lacuna.Object,

        pub const keywords = .extra;
    }) lacuna.PythonError!u64 {
        return item_length(.{ .item = arguments.extra });
    }

    pub fn measure(arguments: struct {
        item: union(enum) { number: i64, word: []const u8, nothing: void },
    }) i64 {
        return switch (arguments.item) {
            .number => |number| number,
            .word => |word| @intCast(word.len),
            .nothing => -1,
        };
    }

    pub fn parity(arguments: struct { value: i64 }) union(enum) { even: i64, odd: []const u8 } {
        if (@mod(arguments.value, 2) == 0) return .{ .even = @divExact(arguments.value, 2) };
        return .{ .odd = "odd" };
    }

    pub fn moments(arguments: struct {
        day: lacuna.Date,
        clock: lacuna.Time,
        moment: lacuna.DateTime,
        span: lacuna.Duration,
    }) struct { lacuna.Date, lacuna.Time, lacuna.DateTime, lacuna.Duration } {
        return .{ arguments.day, arguments.clock, arguments.moment, arguments.span };
    }

    pub fn doubled_span(
        arguments: struct { span: lacuna.Duration },
    ) error{OverflowError}!lacuna.Duration {
        const microseconds = std.math.mul(i64, arguments.span.microseconds, 2) catch {
            return error.OverflowError;
        };

        return .{ .microseconds = microseconds };
    }

    pub fn path_echo(arguments: struct { path: lacuna.Path }) lacuna.Path {
        assert(std.mem.findScalar(u8, arguments.path.bytes, 0) == null);

        return arguments.path;
    }

    pub fn extension(arguments: struct { path: lacuna.Path }) []const u8 {
        assert(std.mem.findScalar(u8, arguments.path.bytes, 0) == null);

        const dot = std.mem.findScalarLast(u8, arguments.path.bytes, '.') orelse return "";
        const result = arguments.path.bytes[dot..];
        if (!std.unicode.utf8ValidateSlice(result)) return "";
        return result;
    }

    pub fn word_count(arguments: struct { words: Words }) u32 {
        const result: u32 = @intCast(arguments.words.slice().len);

        assert(result <= Words.capacity_max);

        return result;
    }

    pub fn letters(arguments: struct { text: []const u8 }) lacuna.ListError!Letters {
        var result: Letters = .empty;

        for (arguments.text) |byte| try result.include(byte);

        assert(result.slice().len <= arguments.text.len);

        return result;
    }

    pub fn invert(arguments: struct { scores: Scores }) lacuna.ListError!Inverted {
        var result: Inverted = .empty;

        for (arguments.scores.slice()) |entry| {
            try result.assign(.{ .key = entry.value, .value = entry.key });
        }

        assert(result.slice().len <= arguments.scores.slice().len);

        return result;
    }

    pub fn rotate(arguments: struct { value: Complex }) Complex {
        return .{ .re = -arguments.value.im, .im = arguments.value.re };
    }

    pub fn narrow_complex(
        arguments: struct { value: std.math.Complex(f32) },
    ) std.math.Complex(f32) {
        return arguments.value;
    }

    pub fn decimal_scale(
        arguments: struct { value: lacuna.Decimal, shift: i32 },
    ) error{OverflowError}!lacuna.Decimal {
        const exponent = std.math.add(i32, arguments.value.exponent, arguments.shift) catch {
            return error.OverflowError;
        };

        return .{ .coefficient = arguments.value.coefficient, .exponent = exponent };
    }

    pub fn uuid_reverse(arguments: struct { value: lacuna.UUID }) lacuna.UUID {
        var result = arguments.value;

        std.mem.reverse(u8, &result.bytes);

        return result;
    }

    pub fn frozen(arguments: struct { values: Frozen }) Frozen {
        assert(arguments.values.slice().len <= Frozen.capacity_max);

        return arguments.values;
    }

    pub fn wide_add(arguments: struct { left: i256, right: i256 }) error{OverflowError}!i256 {
        return std.math.add(i256, arguments.left, arguments.right) catch error.OverflowError;
    }

    pub fn unsigned_echo(arguments: struct { value: u128 }) u128 {
        return arguments.value;
    }

    pub fn repeat(arguments: struct { text: Label, times: u8 }) lacuna.TextError!Label {
        var result: Label = .empty;

        for (0..arguments.times) |_| try result.extend(arguments.text.slice());

        assert(result.length == arguments.text.length * arguments.times);

        return result;
    }
};

pub const Node = struct {
    label: Label,
    payload: lacuna.Reference,
    children: [2]lacuna.Reference,

    pub const doc = "A tree node that owns Python objects, collected with its cycles.";
    pub const fields = .{ .label = .read_write, .payload = .read_write };

    pub fn init(
        node: *Node,
        arguments: struct { label: Label, payload: ?lacuna.Object = null },
    ) void {
        node.* = .{
            .label = arguments.label,
            .payload = if (arguments.payload) |payload| .acquire(payload) else .empty,
            .children = .{ .empty, .empty },
        };

        assert(node.payload.pointer == if (arguments.payload) |payload| payload.pointer else null);
    }

    pub fn attach(node: *Node, arguments: struct { index: u1, child: ?lacuna.Object }) void {
        const slot = &node.children[arguments.index];

        if (arguments.child) |present| slot.assign(present) else slot.release();
    }

    pub fn child(node: *const Node, arguments: struct { index: u1 }) ?lacuna.Object {
        return node.children[arguments.index].object();
    }
};

pub const Shape = struct {
    width: f64,
    height: f64,
    name: Name,

    pub const doc = "A rectangle that Python code may subclass and pickle.";

    pub const constants = .{
        .sides = 4,
        .unit = Shape{ .width = 1, .height = 1, .name = name_of("unit") },
    };

    pub const deprecated = .{ .surface = "use area instead" };
    pub const docs = .{ .area = "The area of the rectangle." };
    pub const fields = .{ .width = .read_write, .height = .read_write, .name = .read };
    pub const pickle = true;
    pub const properties = .{.area};
    pub const static_methods = .{.square};
    pub const subclassable = true;

    pub fn init(shape: *Shape, arguments: struct {
        width: f64,
        height: f64,
        name: Name = name_of("shape"),
    }) void {
        shape.* = .{ .width = arguments.width, .height = arguments.height, .name = arguments.name };

        assert(std.mem.eql(u8, shape.name.slice(), arguments.name.slice()));
    }

    pub fn area(shape: *const Shape) f64 {
        return shape.width * shape.height;
    }

    pub fn surface(shape: *const Shape) f64 {
        return shape.area();
    }

    pub fn square(arguments: struct { side: f64 }) Shape {
        return .{ .width = arguments.side, .height = arguments.side, .name = name_of("square") };
    }

    pub fn __eq__(shape: *const Shape, arguments: struct { other: *const Shape }) bool {
        if (shape.width != arguments.other.width) return false;
        return shape.height == arguments.other.height;
    }

    fn name_of(comptime text: []const u8) Name {
        comptime assert(text.len <= Name.capacity_max);

        var result: Name = .empty;

        @memcpy(result.bytes[0..text.len], text);
        result.length = text.len;

        return result;
    }
};

pub const Tally = struct {
    zig_total: i64,

    pub const doc = "A running total whose Python names differ from its Zig names.";
    pub const fields = .{ .zig_total = .read };
    pub const names = .{ .zig_total = "total", .zig_add = "add" };
    pub const python_name = "Ledger";

    pub fn init(tally: *Tally, arguments: struct { start: i64 = 0 }) void {
        tally.* = .{ .zig_total = arguments.start };
    }

    pub fn zig_add(tally: *Tally, arguments: struct { amount: i64 }) error{OverflowError}!void {
        tally.zig_total = std.math.add(i64, tally.zig_total, arguments.amount) catch {
            return error.OverflowError;
        };
    }
};
