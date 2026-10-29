const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "sample",
    .doc = "Every conversion and protocol that lacuna supports.",
    .classes = &.{ Vector, Counter, Table, Grid, Row, Pair },
    .constants = Constants,
    .enums = &.{Mode},
    .functions = Functions,
    .messages = Messages,
    .thread_safe = true,
    .unions = &.{Shape},
};

pub const Error = error{ Empty, Negative };
pub const Mode = enum {
    fast,
    exact,

    pub const doc = "How carefully to compute.";
};

pub const Shape = union(enum) {
    circle: struct { radius: f64 },
    square: struct { side: f64 },
    empty: void,

    pub const doc = "A shape that Python matches on by variant.";
};

pub const Point = struct {
    horizontal: f64,
    vertical: f64 = 0,
};

pub const Stats = struct {
    count: u32,
    mean: f64,
    label: ?[]const u8,
};

const Numbers = lacuna.ListType(i64, 8);
const Representation = lacuna.TextType(96);
const Reversed = lacuna.BlobType(64);
const Shouted = lacuna.TextType(256);

var deinit_total: std.atomic.Value(u32) = .init(0);

const Constants = struct {
    pub const count_max = 8;
    pub const ratio = 0.5;
    pub const version = "0.1.0";
    pub const enabled: bool = true;
};

const Messages = struct {
    pub fn message(err: Error) []const u8 {
        return switch (err) {
            error.Empty => "the input holds no items",
            error.Negative => "the value is negative",
        };
    }
};

const Functions = struct {
    pub const docs = .{
        .add = "Add two integers.",
        .checksum = "Sum the bytes of a buffer without the GIL.",
        .tally = "Sum the bytes of a non-empty buffer on a worker thread, as a coroutine.",
    };

    pub const coroutines = .{ .tally, .tally_legacy };
    pub const deprecated = .{ .tally_legacy = "use tally instead" };
    pub const parallel = .{.checksum};

    pub fn add(arguments: struct { left: i64, right: i64 = 1 }) error{OverflowError}!i64 {
        const result = std.math.add(i64, arguments.left, arguments.right) catch {
            return error.OverflowError;
        };

        assert(result - arguments.right == arguments.left);

        return result;
    }

    pub fn sum_strided(arguments: struct { values: lacuna.BufferType(f64) }) f64 {
        const values = arguments.values;
        const count = values.dimension_count;

        var indices: [lacuna.limits.buffer_dimensions_max]u64 = @splat(0);
        var sum: f64 = 0;

        for (0..@as(usize, @intCast(values.len()))) |_| {
            sum += values.at(indices[0..count]);

            for (0..count) |position| {
                const dimension = count - 1 - position;

                indices[dimension] += 1;
                if (indices[dimension] < values.shape[dimension]) break;

                indices[dimension] = 0;
            }
        }

        assert(std.mem.allEqual(u64, indices[0..count], 0));

        return sum;
    }

    pub fn shape_area(arguments: struct { shape: Shape }) f64 {
        const result: f64 = switch (arguments.shape) {
            .circle => |circle| std.math.pi * circle.radius * circle.radius,
            .square => |square| square.side * square.side,
            .empty => 0,
        };

        assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn shape_echo(arguments: struct { shape: Shape }) Shape {
        return arguments.shape;
    }

    pub fn shape_scaled(arguments: struct { shape: Shape, factor: f64 }) Shape {
        return switch (arguments.shape) {
            .circle => |circle| .{ .circle = .{ .radius = circle.radius * arguments.factor } },
            .square => |square| .{ .square = .{ .side = square.side * arguments.factor } },
            .empty => .empty,
        };
    }

    pub fn narrow(arguments: struct { value: u8 }) u8 {
        return arguments.value;
    }

    pub fn wide(arguments: struct { value: u64 }) u64 {
        return arguments.value;
    }

    pub fn negate(arguments: struct { value: i32 }) error{OverflowError}!i32 {
        const result = std.math.negate(arguments.value) catch return error.OverflowError;

        assert(result + arguments.value == 0);

        return result;
    }

    pub fn half(arguments: struct { value: f32 }) f32 {
        const result = arguments.value * 0.5;
        const negative = std.math.signbit(arguments.value);

        if (!std.math.isNan(result)) assert(std.math.signbit(result) == negative);

        return result;
    }

    pub fn invert(arguments: struct { flag: bool }) bool {
        return !arguments.flag;
    }

    pub fn shout(arguments: struct { text: []const u8, times: u8 = 1 }) Error!Shouted {
        assert(std.unicode.utf8ValidateSlice(arguments.text));

        if (arguments.times == 0) return error.Empty;
        if (arguments.text.len * arguments.times > Shouted.capacity_max) return error.Negative;

        var result: Shouted = .empty;

        for (0..arguments.times) |_| {
            for (arguments.text) |character| {
                result.bytes[result.length] = std.ascii.toUpper(character);
                result.length += 1;
            }
        }

        assert(result.length == arguments.text.len * arguments.times);
        assert(std.unicode.utf8ValidateSlice(result.slice()));

        return result;
    }

    pub fn terminated(arguments: struct { text: [:0]const u8 }) u64 {
        assert(arguments.text[arguments.text.len] == 0);
        assert(std.mem.len(arguments.text.ptr) == arguments.text.len);

        return arguments.text.len;
    }

    pub fn mode_flip(arguments: struct { mode: Mode = .fast }) Mode {
        return switch (arguments.mode) {
            .fast => .exact,
            .exact => .fast,
        };
    }

    pub fn maybe(arguments: struct { value: ?i32 = null }) ?i64 {
        const value = arguments.value orelse return null;
        const result = @as(i64, value) * 2;

        assert(@divExact(result, 2) == value);

        return result;
    }

    pub fn reverse(arguments: struct { data: lacuna.Bytes }) Reversed {
        const count: u32 = @intCast(@min(arguments.data.bytes.len, Reversed.blob_capacity_max));

        var result: Reversed = .{ .bytes = undefined, .length = count };

        for (0..count) |index| {
            result.bytes[index] = arguments.data.bytes[count - 1 - index];
        }

        if (count > 0) assert(result.bytes[count - 1] == arguments.data.bytes[0]);

        return result;
    }

    pub fn total(arguments: struct { values: []const f64 }) f64 {
        var sum: f64 = 0;

        for (arguments.values) |value| sum += value;

        return sum;
    }

    pub fn scale(arguments: struct { values: []f64, factor: f64 }) void {
        for (arguments.values) |*value| value.* *= arguments.factor;
    }

    pub fn checksum(arguments: struct { data: lacuna.Bytes }) u64 {
        var sum: u64 = 0;

        for (arguments.data.bytes) |byte| sum += byte;

        assert(sum <= std.math.maxInt(u8) * @as(u128, arguments.data.bytes.len));

        return sum;
    }

    pub fn tally(arguments: struct { data: lacuna.Bytes }) Error!u64 {
        if (arguments.data.bytes.len == 0) return error.Empty;

        const result = checksum(.{ .data = arguments.data });

        assert(result <= std.math.maxInt(u8) * @as(u128, arguments.data.bytes.len));

        return result;
    }

    pub fn tally_legacy(arguments: struct { data: lacuna.Bytes }) Error!u64 {
        return tally(.{ .data = arguments.data });
    }

    pub fn swap(arguments: struct { pair: [2]i64 }) [2]i64 {
        return .{ arguments.pair[1], arguments.pair[0] };
    }

    pub fn doubled(
        arguments: struct { numbers: Numbers },
    ) (lacuna.ListError || error{OverflowError})!Numbers {
        assert(arguments.numbers.count <= Numbers.capacity_max);

        var result: Numbers = .empty;

        for (arguments.numbers.slice()) |number| {
            const twice = std.math.mul(i64, number, 2) catch return error.OverflowError;

            (try result.push_slot()).* = twice;
        }

        assert(result.count == arguments.numbers.count);

        return result;
    }

    pub fn divide(
        arguments: struct { left: i64, right: i64 },
    ) error{ OverflowError, ZeroDivisionError }!struct { i64, i64 } {
        if (arguments.right == 0) return error.ZeroDivisionError;

        const quotient = std.math.divFloor(i64, arguments.left, arguments.right) catch {
            return error.OverflowError;
        };

        const remainder = @mod(arguments.left, arguments.right);

        assert(@as(i128, quotient) * arguments.right + remainder == arguments.left);
        assert(remainder == 0 or (remainder < 0) == (arguments.right < 0));

        return .{ quotient, remainder };
    }

    pub fn summarize(
        arguments: struct { values: []const f64, label: ?[]const u8 = null },
    ) Error!Stats {
        if (arguments.label) |label| assert(std.unicode.utf8ValidateSlice(label));

        if (arguments.values.len == 0) return error.Empty;

        const count: u32 = @intCast(arguments.values.len);
        const mean = total(.{ .values = arguments.values }) / @as(f64, @floatFromInt(count));

        return .{ .count = count, .mean = mean, .label = arguments.label };
    }

    pub fn norm(arguments: struct { point: Point }) f64 {
        const point = arguments.point;
        const result = std.math.hypot(point.horizontal, point.vertical);

        assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn identity(arguments: struct { item: lacuna.Object }) lacuna.Object {
        return arguments.item;
    }

    pub fn nothing() void {}

    pub fn deinit_count() u32 {
        return deinit_total.load(.monotonic);
    }

    pub fn midpoint(arguments: struct { left: *const Vector, right: *const Vector }) Vector {
        return .{
            .horizontal = (arguments.left.horizontal + arguments.right.horizontal) * 0.5,
            .vertical = (arguments.left.vertical + arguments.right.vertical) * 0.5,
        };
    }
};

pub const Vector = struct {
    horizontal: f64,
    vertical: f64,

    const Factor = struct { factor: f64 };
    const Other = struct { other: *const Vector };
    pub const doc = "A two-dimensional vector.";

    pub const docs = .{
        .horizontal = "The horizontal component.",
        .length = "The Euclidean length.",
    };

    pub const fields = .{ .horizontal = .read_write, .vertical = .read_write };
    pub const properties = .{.length};
    pub const sequence = true;

    pub fn init(
        vector: *Vector,
        arguments: struct { horizontal: f64 = 0, vertical: f64 = 0 },
    ) void {
        vector.* = .{ .horizontal = arguments.horizontal, .vertical = arguments.vertical };
    }

    pub fn length(vector: *const Vector) f64 {
        const result = std.math.hypot(vector.horizontal, vector.vertical);

        assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn dot(vector: *const Vector, arguments: Other) f64 {
        const result = vector.horizontal * arguments.other.horizontal +
            vector.vertical * arguments.other.vertical;

        if (arguments.other == vector) assert(std.math.isNan(result) or result >= 0);

        return result;
    }

    pub fn scale(vector: *Vector, arguments: Factor) *Vector {
        vector.horizontal *= arguments.factor;
        vector.vertical *= arguments.factor;

        return vector;
    }

    pub fn origin() Vector {
        return .{ .horizontal = 0, .vertical = 0 };
    }

    pub fn __add__(vector: *const Vector, arguments: Other) Vector {
        return .{
            .horizontal = vector.horizontal + arguments.other.horizontal,
            .vertical = vector.vertical + arguments.other.vertical,
        };
    }

    pub fn __sub__(vector: *const Vector, arguments: Other) Vector {
        return .{
            .horizontal = vector.horizontal - arguments.other.horizontal,
            .vertical = vector.vertical - arguments.other.vertical,
        };
    }

    pub fn __mul__(vector: *const Vector, arguments: Factor) Vector {
        return .{
            .horizontal = vector.horizontal * arguments.factor,
            .vertical = vector.vertical * arguments.factor,
        };
    }

    pub fn __rmul__(vector: *const Vector, arguments: Factor) Vector {
        return vector.__mul__(arguments);
    }

    pub fn __neg__(vector: *const Vector) Vector {
        return .{ .horizontal = -vector.horizontal, .vertical = -vector.vertical };
    }

    pub fn __abs__(vector: *const Vector) f64 {
        return vector.length();
    }

    pub fn __bool__(vector: *const Vector) bool {
        if (vector.horizontal != 0) return true;
        return vector.vertical != 0;
    }

    pub fn __eq__(vector: *const Vector, arguments: Other) bool {
        if (vector.horizontal != arguments.other.horizontal) return false;
        return vector.vertical == arguments.other.vertical;
    }

    pub fn __lt__(vector: *const Vector, arguments: Other) bool {
        return vector.length() < arguments.other.length();
    }

    pub fn __le__(vector: *const Vector, arguments: Other) bool {
        return vector.length() <= arguments.other.length();
    }

    pub fn __len__(_: *const Vector) u32 {
        return 2;
    }

    pub fn __getitem__(
        vector: *const Vector,
        arguments: struct { index: i64 },
    ) error{IndexError}!f64 {
        return switch (arguments.index) {
            0, -2 => vector.horizontal,
            1, -1 => vector.vertical,
            else => error.IndexError,
        };
    }

    pub fn __repr__(vector: *const Vector) lacuna.TextError!Representation {
        var result: Representation = .empty;

        try result.print("Vector({d}, {d})", .{ vector.horizontal, vector.vertical });

        assert(std.mem.startsWith(u8, result.slice(), "Vector("));

        return result;
    }
};

pub const Counter = struct {
    current: i64,
    stop: i64,

    pub const doc = "Counts from start up to but not including stop.";
    pub const fields = .{ .current = .read };

    pub fn init(counter: *Counter, arguments: struct { stop: i64, start: i64 = 0 }) Error!void {
        if (arguments.stop < arguments.start) return error.Negative;

        counter.* = .{ .current = arguments.start, .stop = arguments.stop };

        assert(counter.current <= counter.stop);
    }

    pub fn deinit(counter: *Counter) void {
        assert(counter.current <= counter.stop);
        const previous = deinit_total.fetchAdd(1, .monotonic);

        assert(previous < std.math.maxInt(u32));
    }

    pub fn __iter__(counter: *Counter) *Counter {
        assert(counter.current <= counter.stop);

        return counter;
    }

    pub fn __next__(counter: *Counter) ?i64 {
        assert(counter.current <= counter.stop);

        if (counter.current == counter.stop) return null;

        const result = counter.current;

        counter.current += 1;

        assert(counter.current <= counter.stop);

        return result;
    }

    pub fn __contains__(counter: *const Counter, arguments: struct { value: i64 }) bool {
        assert(counter.current <= counter.stop);

        if (arguments.value < counter.current) return false;
        return arguments.value < counter.stop;
    }

    pub fn __call__(counter: *Counter, arguments: struct { step: i64 = 1 }) i64 {
        assert(counter.current <= counter.stop);

        counter.current = @min(counter.current +| arguments.step, counter.stop);

        assert(counter.current <= counter.stop);

        return counter.current;
    }
};

pub const Table = struct {
    present: [8]bool,
    values: [8]i64,

    const Key = struct { key: u3 };

    pub const mapping = true;

    pub fn init(table: *Table) void {
        table.* = .{ .present = @splat(false), .values = @splat(0) };

        assert(table.__len__() == 0);
    }

    pub fn __len__(table: *const Table) u32 {
        var count: u32 = 0;

        for (table.present) |present| count += @intFromBool(present);

        return count;
    }

    pub fn __getitem__(table: *const Table, arguments: Key) error{KeyError}!i64 {
        if (!table.present[arguments.key]) return error.KeyError;
        return table.values[arguments.key];
    }

    pub fn __setitem__(table: *Table, arguments: struct { key: u3, value: i64 }) void {
        const before = table.__len__();

        table.present[arguments.key] = true;
        table.values[arguments.key] = arguments.value;

        assert(table.__len__() >= before);
        assert(table.__len__() <= before + 1);
    }

    pub fn get(table: *const Table, arguments: struct {
        key: i64,
        default: ?lacuna.Object = null,
    }) union(enum) { found: i64, missing: ?lacuna.Object } {
        if (arguments.key < 0) return .{ .missing = arguments.default };
        if (arguments.key >= table.present.len) return .{ .missing = arguments.default };

        const key: u3 = @intCast(arguments.key);

        if (!table.present[key]) return .{ .missing = arguments.default };
        return .{ .found = table.values[key] };
    }

    pub fn __delitem__(table: *Table, arguments: Key) error{KeyError}!void {
        if (!table.present[arguments.key]) return error.KeyError;

        const before = table.__len__();

        table.present[arguments.key] = false;

        assert(table.__len__() + 1 == before);
    }
};

pub const Grid = struct {
    cells: [2][3]f64,

    pub const doc = "A two-by-three grid exported as a two-dimensional buffer.";

    pub fn init(grid: *Grid, arguments: struct { start: f64 = 0 }) void {
        for (&grid.cells, 0..) |*row, row_index| {
            for (row, 0..) |*cell, column_index| {
                const offset: f64 = @floatFromInt(row_index * 3 + column_index);

                cell.* = arguments.start + offset;
            }
        }

        const first = grid.cells[0][0];

        if (std.math.isNan(arguments.start)) {
            assert(std.math.isNan(first));
        } else {
            assert(first == arguments.start);
        }
    }

    pub fn __buffer__(grid: *Grid) lacuna.BufferMutableType(f64) {
        const row_bytes: i64 = @sizeOf([3]f64);

        return .{
            .data = @ptrCast(&grid.cells),
            .dimension_count = 2,
            .shape = .{ 2, 3, 0, 0, 0, 0, 0, 0 },
            .strides = .{ row_bytes, @sizeOf(f64), 0, 0, 0, 0, 0, 0 },
            .read_only = false,
        };
    }
};

pub const Row = struct {
    values: Numbers,

    pub const doc = "A row of integers that indexes and slices like a list.";
    pub const sequence = true;

    pub fn init(row: *Row, arguments: struct { values: Numbers }) void {
        row.* = .{ .values = arguments.values };

        assert(row.values.count <= Numbers.capacity_max);
    }

    pub fn __len__(row: *const Row) u32 {
        assert(row.values.count <= Numbers.capacity_max);

        return row.values.count;
    }

    pub fn __getitem__(row: *const Row, arguments: struct {
        key: union(enum) { index: i64, range: lacuna.Slice },
    }) (lacuna.ListError || error{IndexError})!union(enum) { item: i64, items: Numbers } {
        const values = row.values.slice();

        switch (arguments.key) {
            .index => |index| {
                if (index < 0) return error.IndexError;
                if (index >= values.len) return error.IndexError;

                return .{ .item = values[@intCast(index)] };
            },
            .range => |range| {
                var window = range;
                const count = window.adjust(values.len);

                var result: Numbers = .empty;
                var position = window.start;

                for (0..@as(usize, @intCast(count))) |_| {
                    (try result.push_slot()).* = values[@intCast(position)];
                    position += window.step;
                }

                return .{ .items = result };
            },
        }
    }

    pub fn __setitem__(
        row: *Row,
        arguments: struct { index: i64, value: i64 },
    ) error{IndexError}!void {
        if (arguments.index < 0) return error.IndexError;
        if (arguments.index >= row.values.count) return error.IndexError;

        row.values.slice_mutable()[@intCast(arguments.index)] = arguments.value;
    }
};

pub const Pair = struct {
    left: i64,
    right: i64,

    pub const derive = .{ .eq, .ord, .hash, .repr };
    pub const doc = "Two integers whose comparisons, hash, and repr are derived from the fields.";
    pub const fields = .{ .left = .read, .right = .read };

    pub fn init(pair: *Pair, arguments: struct { left: i64, right: i64 }) void {
        pair.* = .{ .left = arguments.left, .right = arguments.right };
    }
};
