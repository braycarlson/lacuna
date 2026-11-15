const std = @import("std");

const c = @import("c.zig");
const kind_module = @import("kind.zig");
const list_module = @import("list.zig");
const python = @import("python.zig");

const assert = std.debug.assert;

const Limb = std.math.big.Limb;
const ListType = list_module.ListType;
const kind_of = kind_module.kind_of;

pub const alignment_max: u32 = 64;
pub const size_max: u64 = python.memory_size_max - alignment_max;

pub const Region = struct {
    bytes: []align(alignment_max) u8,
    copying: bool,
    used: u64,

    pub const measuring: Region = .{ .bytes = &.{}, .copying = false, .used = 0 };

    pub fn over(bytes: []align(alignment_max) u8) Region {
        assert(bytes.len <= size_max);
        assert(std.mem.isAligned(@intFromPtr(bytes.ptr), alignment_max));

        return .{ .bytes = bytes, .copying = true, .used = 0 };
    }

    fn take(region: *Region, comptime T: type, count: u64) ?[]T {
        comptime assert(@alignOf(T) <= alignment_max);
        comptime assert(@sizeOf(T) > 0);
        assert(count <= @divFloor(size_max, @sizeOf(T)));

        const start = std.mem.alignForward(u64, region.used, @alignOf(T));
        const end = start + count * @sizeOf(T);

        region.used = end;

        if (!region.copying) return null;

        assert(end <= region.bytes.len);

        const taken = region.bytes[@intCast(start)..@intCast(end)];

        return @alignCast(std.mem.bytesAsSlice(T, taken));
    }
};

pub const Buffer = struct {
    allocation: []u8,
    region: Region,

    pub fn acquire(size: u64) ?Buffer {
        assert(size <= size_max);
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const allocation = python.memory_take(size + alignment_max) orelse return null;
        const offset = std.mem.alignPointerOffset(allocation.ptr, alignment_max).?;
        const window = allocation[offset..][0..@intCast(size)];
        const aligned: []align(alignment_max) u8 = @alignCast(window);

        return .{ .allocation = allocation, .region = .over(aligned) };
    }

    pub fn release(buffer: *Buffer) void {
        assert(buffer.region.copying);
        assert(buffer.region.used <= buffer.region.bytes.len);

        python.memory_give(buffer.allocation);
    }
};

pub fn borrowed(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (kind_module.owned(T, classes, depth)) return false;

    return switch (kind_of(T, classes)) {
        .big_integer, .buffer, .buffer_mutable, .bytes, .items, .path => true,
        .text, .text_terminated => true,
        .array => borrowed(@typeInfo(T).array.child, classes, depth + 1),
        .list, .set => borrowed(T.Item, classes, depth + 1),
        .map => borrowed(T.Key, classes, depth + 1) or borrowed(T.Value, classes, depth + 1),
        .optional => borrowed(@typeInfo(T).optional.child, classes, depth + 1),
        .record, .tuple => fields_borrowed(T, classes, depth),
        .variant => variants_borrowed(T, classes, depth),
        .buffer_strided, .class_extended, .class_pointer, .class_pointer_mutable => false,
        .container, .loop_object, .none, .object, .reference => false,
        .boolean, .bytes_owned, .class_value, .complex, .custom, .date => comptime unreachable,
        .datetime, .decimal, .duration, .enumeration, .float, .fraction => comptime unreachable,
        .integer, .ip_address, .slice, .text_owned, .time, .union_class => comptime unreachable,
        .uuid => comptime unreachable,
    };
}

fn fields_borrowed(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    inline for (@typeInfo(T).@"struct".field_types) |Field| {
        if (borrowed(Field, classes, depth + 1)) return true;
    }

    return false;
}

fn variants_borrowed(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    inline for (@typeInfo(T).@"union".field_types) |Payload| {
        if (borrowed(Payload, classes, depth + 1)) return true;
    }

    return false;
}

pub fn size_of(comptime T: type, comptime classes: []const type, source: *const T) u64 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(borrowed(T, classes, 0));
    assert(std.mem.isAligned(@intFromPtr(source), @alignOf(T)));

    var region: Region = .measuring;

    _ = snapshot(T, classes, 0, &region, source);

    assert(region.used <= size_max);

    return region.used;
}

pub fn snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));
    assert(std.mem.isAligned(@intFromPtr(source), @alignOf(T)));

    if (comptime !borrowed(T, classes, depth)) return source.*;

    return switch (comptime kind_of(T, classes)) {
        .array => array_snapshot(T, classes, depth, region, source),
        .big_integer => big_integer_snapshot(region, source),
        .buffer, .buffer_mutable, .text => slice_snapshot(T, region, source.*),
        .bytes, .path => .{ .bytes = slice_snapshot([]const u8, region, source.bytes) },
        .items => items_snapshot(T, classes, depth, region, source.*),
        .list => list_snapshot(T, classes, depth, region, source),
        .map, .set => wrapped_snapshot(T, classes, depth, region, source),
        .optional => optional_snapshot(T, classes, depth, region, source),
        .record, .tuple => fields_snapshot(T, classes, depth, region, source),
        .text_terminated => terminated_snapshot(region, source.*),
        .variant => variant_snapshot(T, classes, depth, region, source),
        else => comptime unreachable,
    };
}

fn slice_snapshot(comptime T: type, region: *Region, source: T) T {
    comptime assert(@typeInfo(T).pointer.size == .slice);
    assert(source.len <= size_max);

    const Child = @typeInfo(T).pointer.child;

    if (comptime @sizeOf(Child) == 0) return source;

    const copied = region.take(Child, source.len) orelse return source;

    @memcpy(copied, source);

    return copied;
}

fn terminated_snapshot(region: *Region, source: [:0]const u8) [:0]const u8 {
    assert(source[source.len] == 0);
    assert(source.len < size_max);

    const copied = region.take(u8, source.len + 1) orelse return source;

    @memcpy(copied[0..source.len], source);
    copied[source.len] = 0;

    return copied[0..source.len :0];
}

fn big_integer_snapshot(
    region: *Region,
    source: *const std.math.big.int.Const,
) std.math.big.int.Const {
    assert(source.limbs.len > 0);
    assert(source.limbs.len <= kind_module.big_integer_limb_count_max);

    const limbs = region.take(Limb, source.limbs.len) orelse return source.*;

    @memcpy(limbs, source.limbs);

    return .{ .limbs = limbs, .positive = source.positive };
}

fn array_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(@typeInfo(T) == .array);
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    const Child = @typeInfo(T).array.child;

    var result: T = undefined;

    for (source, &result) |*item, *target| {
        target.* = snapshot(Child, classes, depth + 1, region, item);
    }

    return result;
}

fn items_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: T,
) T {
    comptime assert(@typeInfo(T).pointer.size == .slice);
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));
    assert(source.len <= size_max);

    const Child = @typeInfo(T).pointer.child;

    if (comptime @sizeOf(Child) == 0) return source;

    const copied = region.take(Child, source.len);

    for (source, 0..) |*item, index| {
        const item_copied = snapshot(Child, classes, depth + 1, region, item);

        if (copied) |target| target[index] = item_copied;
    }

    return copied orelse source;
}

fn list_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(list_module.is_list(T));
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));
    assert(source.count <= T.capacity_max);

    var result = source.*;

    for (result.slice_mutable()) |*item| {
        const copied = snapshot(T.Item, classes, depth + 1, region, item);

        item.* = copied;
    }

    assert(result.count == source.count);

    return result;
}

fn wrapped_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(@hasField(T, "list"));
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    const List = @FieldType(T, "list");

    return .{ .list = list_snapshot(List, classes, depth, region, &source.list) };
}

fn optional_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(@typeInfo(T) == .optional);
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    const present = if (source.*) |*inner| inner else return null;

    return snapshot(@typeInfo(T).optional.child, classes, depth + 1, region, present);
}

fn fields_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    const structure = @typeInfo(T).@"struct";

    var result: T = undefined;

    inline for (structure.field_names, structure.field_types) |name, Field| {
        const field = &@field(source.*, name);

        @field(result, name) = snapshot(Field, classes, depth + 1, region, field);
    }

    return result;
}

fn variant_snapshot(
    comptime T: type,
    comptime classes: []const type,
    comptime depth: u32,
    region: *Region,
    source: *const T,
) T {
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(depth < kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    switch (source.*) {
        inline else => |*payload, tag| {
            const Payload = @TypeOf(payload.*);
            const copied = snapshot(Payload, classes, depth + 1, region, payload);

            return @unionInit(T, @tagName(tag), copied);
        },
    }
}

test borrowed {
    const Mode = enum { fast, exact };
    const Labelled = union(enum) { text: []const u8, count: u32 };

    comptime {
        @setEvalBranchQuota(10_000);

        assert(!borrowed(u32, &.{}, 0));
        assert(!borrowed(ListType(Mode, 4), &.{}, 0));
        assert(borrowed([]const u8, &.{}, 0));
        assert(borrowed([:0]const u8, &.{}, 0));
        assert(borrowed([]const Mode, &.{}, 0));
        assert(borrowed([]const f64, &.{}, 0));
        assert(borrowed(?[]const u8, &.{}, 0));
        assert(borrowed(struct { count: u32, name: []const u8 }, &.{}, 0));
        assert(borrowed(Labelled, &.{}, 0));
        assert(borrowed(ListType([]const u8, 2), &.{}, 0));
        assert(borrowed(list_module.MapType(u8, []const u8, 2), &.{}, 0));
        assert(borrowed(std.math.big.int.Const, &.{}, 0));
        assert(!borrowed(void, &.{}, 0));
    }
}

test "a snapshot keeps its contents when the source memory is overwritten" {
    const Mode = enum { fast, exact };
    const Labelled = union(enum) { text: []const u8, count: u32 };
    const Names = ListType([]const u8, 2);
    const Scores = list_module.MapType([]const u8, []const u8, 2);
    const Record = struct {
        count: u32,
        label: Labelled,
        modes: []const Mode,
        name: []const u8,
        names: Names,
        nested: ?[]const u8,
        scores: Scores,
        terminated: [:0]const u8,
    };

    var storage: [6:0]u8 = "alphas".*;
    var modes = [_]Mode{ .fast, .fast, .fast };
    var names: Names = .empty;
    var scores: Scores = .empty;

    (try names.push_slot()).* = storage[0..2];
    try scores.assign(.{ .key = storage[1..3], .value = storage[3..6] });

    const source: Record = .{
        .count = 7,
        .label = .{ .text = storage[2..5] },
        .modes = &modes,
        .name = storage[0..5],
        .names = names,
        .nested = storage[4..6],
        .scores = scores,
        .terminated = &storage,
    };
    const size = size_of(Record, &.{}, &source);

    var bytes: [256]u8 align(alignment_max) = undefined;
    var region: Region = .over(bytes[0..@intCast(size)]);

    const copied = snapshot(Record, &.{}, 0, &region, &source);

    try std.testing.expectEqual(size, region.used);

    @memcpy(&storage, "omegas");
    @memset(&modes, .exact);

    try std.testing.expectEqual(7, copied.count);
    try std.testing.expectEqualStrings("pha", copied.label.text);
    try std.testing.expectEqualSlices(Mode, &.{ .fast, .fast, .fast }, copied.modes);
    try std.testing.expectEqualStrings("alpha", copied.name);
    try std.testing.expectEqualStrings("al", copied.names.slice()[0]);
    try std.testing.expectEqualStrings("as", copied.nested.?);
    try std.testing.expectEqualStrings("lp", copied.scores.slice()[0].key);
    try std.testing.expectEqualStrings("has", copied.scores.slice()[0].value);
    try std.testing.expectEqualStrings("alphas", copied.terminated);
    try std.testing.expectEqual(0, copied.terminated[copied.terminated.len]);
    try std.testing.expectEqualStrings("omegas", source.terminated);
    try std.testing.expectEqual(.exact, source.modes[0]);
}

test "a big integer snapshot owns its limbs" {
    var limbs = [_]Limb{ 5, 7 };

    const source: std.math.big.int.Const = .{ .limbs = &limbs, .positive = false };
    const size = size_of(std.math.big.int.Const, &.{}, &source);

    var bytes: [64]u8 align(alignment_max) = undefined;
    var region: Region = .over(bytes[0..@intCast(size)]);

    const copied = snapshot(std.math.big.int.Const, &.{}, 0, &region, &source);

    limbs = .{ 1, 1 };

    try std.testing.expectEqual(2 * @sizeOf(Limb), size);
    try std.testing.expectEqualSlices(Limb, &.{ 5, 7 }, copied.limbs);
    try std.testing.expect(!copied.positive);
}

test "a measured size covers every alignment the copy needs" {
    const Mixed = struct { label: []const u8, numbers: []const u64, wide: []const u128 };

    const numbers = [_]u64{ 1, 2, 3 };
    const wide = [_]u128{ 4, 5 };
    const source: Mixed = .{ .label = "abc", .numbers = &numbers, .wide = &wide };
    const size = size_of(Mixed, &.{}, &source);

    var bytes: [256]u8 align(alignment_max) = undefined;
    var region: Region = .over(bytes[0..@intCast(size)]);

    const copied = snapshot(Mixed, &.{}, 0, &region, &source);

    try std.testing.expectEqual(64, size);
    try std.testing.expectEqual(size, region.used);
    try std.testing.expectEqualStrings("abc", copied.label);
    try std.testing.expectEqualSlices(u64, &numbers, copied.numbers);
    try std.testing.expectEqualSlices(u128, &wide, copied.wide);
    try std.testing.expect(@intFromPtr(copied.wide.ptr) % @alignOf(u128) == 0);
}
