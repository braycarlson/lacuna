const std = @import("std");

const c = @import("c.zig");
const critical = @import("critical.zig");
const kind_module = @import("kind.zig");

const assert = std.debug.assert;

const kind_of = kind_module.kind_of;

pub const holder_count_max: u32 = 1024;
pub const limb_count_max: u32 = kind_module.big_integer_count_max *
    kind_module.big_integer_limb_count_max;
pub const lock_count_max: u32 = 2;
pub const view_count_max: u32 = 64;

pub const Scope = struct {
    limbs: []std.math.big.Limb,
    limb_count: u32,
    objects: []*c.PyObject,
    object_count: u32,
    locked: [lock_count_max]*c.PyObject,
    lock_count: u32,
    pair: critical.Pair,
    acquired: bool,
    views: []c.Py_buffer,
    view_count: u32,

    pub const Mark = struct {
        limb_count: u32,
        lock_count: u32,
    };

    pub const Storage = struct {
        limbs: []std.math.big.Limb = &.{},
        objects: []*c.PyObject,
        views: []c.Py_buffer,
    };

    pub fn init(storage: Storage) Scope {
        assert(storage.objects.len <= holder_count_max);
        assert(storage.views.len <= view_count_max);
        assert(storage.limbs.len <= limb_count_max);

        return .{
            .limbs = storage.limbs,
            .limb_count = 0,
            .objects = storage.objects,
            .object_count = 0,
            .locked = undefined,
            .lock_count = 0,
            .pair = critical.pair_empty,
            .acquired = false,
            .views = storage.views,
            .view_count = 0,
        };
    }

    pub fn limbs_take(scope: *Scope, count: u32) []std.math.big.Limb {
        assert(count > 0);
        assert(count <= kind_module.big_integer_limb_count_max);
        assert(scope.limb_count + count <= scope.limbs.len);

        const taken = scope.limbs[scope.limb_count..][0..count];

        scope.limb_count += count;

        return taken;
    }

    pub fn lock_add(scope: *Scope, object: *c.PyObject) void {
        assert(scope.lock_count < lock_count_max);
        assert(!scope.acquired);
        assert(@intFromPtr(object) % c.object_alignment == 0);

        scope.locked[scope.lock_count] = object;
        scope.lock_count += 1;
    }

    pub fn lock_acquire(scope: *Scope) void {
        assert(!scope.acquired);
        assert(scope.lock_count <= lock_count_max);

        if (scope.lock_count == 0) return;

        critical.pair_begin(&scope.pair, .{ scope.locked[0], scope.locked[scope.lock_count - 1] });
        scope.acquired = true;
    }

    pub fn mark(scope: *const Scope) Mark {
        assert(!scope.acquired);
        assert(scope.lock_count <= lock_count_max);
        assert(scope.limb_count <= scope.limbs.len);

        return .{ .limb_count = scope.limb_count, .lock_count = scope.lock_count };
    }

    pub fn rewind(scope: *Scope, marked: Mark) void {
        assert(!scope.acquired);
        assert(marked.limb_count <= scope.limb_count);
        assert(marked.lock_count <= scope.lock_count);

        scope.limb_count = marked.limb_count;
        scope.lock_count = marked.lock_count;
    }

    pub fn hold(scope: *Scope, object: *c.PyObject) void {
        assert(scope.object_count < scope.objects.len);
        assert(scope.object_count <= holder_count_max);

        scope.objects[scope.object_count] = object;
        scope.object_count += 1;
    }

    pub fn view_next(scope: *Scope) *c.Py_buffer {
        assert(scope.view_count < scope.views.len);
        assert(scope.view_count <= view_count_max);

        return &scope.views[scope.view_count];
    }

    pub fn view_commit(scope: *Scope) void {
        assert(scope.view_count < scope.views.len);
        assert(scope.views[scope.view_count].obj != null);

        scope.view_count += 1;
    }

    pub fn release(scope: *Scope) void {
        assert(scope.object_count <= scope.objects.len);
        assert(scope.view_count <= scope.views.len);
        if (scope.acquired) assert(scope.lock_count > 0);

        if (scope.acquired) {
            critical.pair_end(&scope.pair);

            scope.pair = critical.pair_empty;
            scope.acquired = false;
        }

        scope.lock_count = 0;

        while (scope.view_count > 0) {
            scope.view_count -= 1;

            c.PyBuffer_Release(&scope.views[scope.view_count]);
        }

        while (scope.object_count > 0) {
            scope.object_count -= 1;

            c.Py_DecRef(scope.objects[scope.object_count]);
        }
    }
};

pub fn big_integer_count(
    comptime T: type,
    comptime classes: []const type,
    comptime nested: bool,
) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);

    switch (comptime kind_of(T, classes)) {
        .big_integer => {
            if (nested) {
                @compileError("lacuna: the big integer type '" ++ @typeName(T) ++
                    "' is allowed only as an argument or an optional argument");
            }

            return 1;
        },
        .optional => return big_integer_count(@typeInfo(T).optional.child, classes, nested),
        .array => return big_integer_count(@typeInfo(T).array.child, classes, true),
        .list, .set => return big_integer_count(T.Item, classes, true),
        .map => {
            _ = big_integer_count(T.Key, classes, true);
            _ = big_integer_count(T.Value, classes, true);

            return 0;
        },
        .record, .tuple => {
            inline for (@typeInfo(T).@"struct".field_types) |Field| {
                _ = big_integer_count(Field, classes, true);
            }

            return 0;
        },
        .variant => {
            var result: u32 = 0;

            inline for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) {
                    result = @max(result, big_integer_count(Payload, classes, nested));
                }
            }

            return result;
        },
        else => return 0,
    }
}

pub fn holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (depth == kind_module.depth_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' nests too deeply");
    }

    const result: u32 = switch (comptime kind_of(T, classes)) {
        .array => 1 + @typeInfo(T).array.len * holder_count(
            @typeInfo(T).array.child,
            classes,
            depth + 1,
        ),
        .list => 1 + T.capacity_max * holder_count(T.Item, classes, depth + 1),
        .map => 1 + T.capacity_max * (holder_count(T.Key, classes, depth + 1) +
            holder_count(T.Value, classes, depth + 1)),
        .optional => holder_count(@typeInfo(T).optional.child, classes, depth + 1),
        .path => 2,
        .record, .tuple => fields_holder_count(T, classes, depth),
        .set => 1 + T.capacity_max * (1 + holder_count(T.Item, classes, depth + 1)),
        .variant => variant_holder_count(T, classes, depth),
        else => 0,
    };

    if (result > holder_count_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' holds too many objects");
    }

    comptime assert(result <= holder_count_max);

    return result;
}

pub fn lock_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(depth <= kind_module.depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (depth == kind_module.depth_max) return 0;

    const result: u32 = switch (comptime kind_of(T, classes)) {
        .class_pointer, .class_pointer_mutable => @intFromBool(
            !@import("instance.zig").InstanceType(@typeInfo(T).pointer.child).frozen,
        ),
        .array => @typeInfo(T).array.len * lock_count(
            @typeInfo(T).array.child,
            classes,
            depth + 1,
        ),
        .list, .set => T.capacity_max * lock_count(T.Item, classes, depth + 1),
        .map => T.capacity_max * (lock_count(T.Key, classes, depth + 1) +
            lock_count(T.Value, classes, depth + 1)),
        .optional => lock_count(@typeInfo(T).optional.child, classes, depth + 1),
        .record, .tuple => fields: {
            var result: u32 = 0;

            for (@typeInfo(T).@"struct".field_types) |Field| {
                result += lock_count(Field, classes, depth + 1);
            }

            break :fields result;
        },
        .variant => payloads: {
            var result: u32 = 0;

            for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) result = @max(result, lock_count(Payload, classes, depth + 1));
            }

            break :payloads result;
        },
        else => 0,
    };

    if (result > holder_count_max) {
        @compileError("lacuna: the type '" ++ @typeName(T) ++ "' locks too many instances");
    }

    comptime assert(result <= holder_count_max);

    return result;
}

pub fn locks_check(comptime label: []const u8, comptime count: u32) void {
    comptime assert(label.len > 0);
    comptime assert(count <= std.math.maxInt(u32));

    if (count > lock_count_max) {
        @compileError(std.fmt.comptimePrint(
            "lacuna: '{s}' locks {d} instances for its call, but a critical section locks " ++
                "at most {d}; take the others by value",
            .{ label, count, lock_count_max },
        ));
    }

    comptime assert(count <= lock_count_max);
}

pub fn view_count(comptime T: type, comptime classes: []const type, comptime nested: bool) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);

    const kind = comptime kind_of(T, classes);

    switch (kind) {
        .buffer, .buffer_mutable, .buffer_strided, .bytes => {
            if (nested) {
                @compileError("lacuna: the buffer type '" ++ @typeName(T) ++
                    "' is allowed only as an argument or an optional argument");
            }

            return 1;
        },
        .optional => return view_count(@typeInfo(T).optional.child, classes, nested),
        .array => {
            _ = view_count(@typeInfo(T).array.child, classes, true);

            return 0;
        },
        .list, .set => {
            _ = view_count(T.Item, classes, true);

            return 0;
        },
        .map => {
            _ = view_count(T.Key, classes, true);
            _ = view_count(T.Value, classes, true);

            return 0;
        },
        .variant => {
            var result: u32 = 0;

            inline for (@typeInfo(T).@"union".field_types) |Payload| {
                if (Payload != void) result += view_count(Payload, classes, nested);
            }

            return result;
        },
        .record, .tuple => {
            inline for (@typeInfo(T).@"struct".field_types) |Field| {
                _ = view_count(Field, classes, true);
            }

            return 0;
        },
        else => return 0,
    }
}

pub fn record_holder_count(comptime T: type, comptime classes: []const type) u32 {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(classes.len <= std.math.maxInt(u32));

    const result = fields_holder_count(T, classes, 0);

    if (result > holder_count_max) {
        @compileError("lacuna: the record '" ++ @typeName(T) ++ "' holds too many objects");
    }

    return result;
}

fn variant_holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(depth < kind_module.depth_max);

    var result: u32 = 0;

    inline for (@typeInfo(T).@"union".field_types) |Payload| {
        if (Payload != void) result += holder_count(Payload, classes, depth + 1);
    }

    return result;
}

fn fields_holder_count(comptime T: type, comptime classes: []const type, comptime depth: u32) u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < kind_module.depth_max);

    var result: u32 = 1;

    inline for (@typeInfo(T).@"struct".field_types) |Field| {
        result += 1 + holder_count(Field, classes, depth + 1);
    }

    return result;
}

test "a rewind gives back the locks and limbs that a rejected conversion took" {
    var limbs: [8]std.math.big.Limb = undefined;
    var handles: [2]usize = .{ 0, 0 };

    var scope: Scope = .init(.{ .limbs = &limbs, .objects = &.{}, .views = &.{} });

    const kept = scope.limbs_take(2);
    const marked = scope.mark();

    scope.lock_add(@ptrCast(&handles[0]));
    _ = scope.limbs_take(4);
    scope.rewind(marked);

    try std.testing.expectEqual(kept.ptr + kept.len, scope.limbs_take(6).ptr);
    try std.testing.expectEqual(@as(u32, limbs.len), scope.limb_count);
    try std.testing.expectEqual(@as(u32, 0), scope.lock_count);

    scope.lock_add(@ptrCast(&handles[0]));
    scope.lock_add(@ptrCast(&handles[1]));

    try std.testing.expectEqual(@as(u32, lock_count_max), scope.lock_count);
}

test "owned kinds take no buffer views and no limbs, so setters and restores need none" {
    const list = @import("list.zig");
    const text = @import("text.zig");
    const ListType = list.ListType;
    const TextType = text.TextType;
    const Blob = text.BlobType(8);
    const Name = TextType(8);
    const Record = struct { data: Blob, name: ?Name, tags: list.SetType(Blob, 2) };
    const Choice = union(enum) { data: Blob, items: ListType(Blob, 2), none: void };

    comptime {
        @setEvalBranchQuota(100_000);

        const value = @import("value.zig");
        const owned_types = .{ Blob, ?Blob, Record, Choice, list.MapType(Name, Blob, 2), [2]Blob };
        const borrowed_types = .{ []const f64, []u8, value.Bytes, std.math.big.int.Const };

        for (owned_types) |Owned| {
            assert(kind_module.owned(Owned, &.{}, 0));
            assert(view_count(Owned, &.{}, false) == 0);
            assert(big_integer_count(Owned, &.{}, false) == 0);
        }

        for (borrowed_types) |Borrowed| {
            assert(!kind_module.owned(Borrowed, &.{}, 0));
        }
    }
}

test big_integer_count {
    const Big = std.math.big.int.Const;
    const Wide = union(enum) { big: Big, word: []const u8 };
    const Either = union(enum) { big: Big, maybe: ?Big };

    comptime {
        assert(big_integer_count(Wide, &.{}, false) == 1);
        assert(big_integer_count(Either, &.{}, false) == 1);
        assert(big_integer_count(?Wide, &.{}, false) == 1);
        assert(lock_count(Wide, &.{}, 0) == 0);
    }
}

test holder_count {
    const Pair = struct { []const u8, u32 };
    const Settings = struct { name: []const u8, level: u8 };

    comptime {
        assert(holder_count(u32, &.{}, 0) == 0);
        assert(holder_count([3]u8, &.{}, 0) == 1);
        assert(holder_count([2][3]u8, &.{}, 0) == 3);
        assert(holder_count(Pair, &.{}, 0) == 3);
        assert(holder_count(Settings, &.{}, 0) == 3);
        assert(holder_count(?[2]u8, &.{}, 0) == 1);
        assert(view_count([]const f64, &.{}, false) == 1);
        assert(view_count(?[]const f64, &.{}, false) == 1);
        assert(view_count([4]u8, &.{}, false) == 0);
    }
}

test "the scope counters raise their own branch quota for a wide type" {
    const list = @import("list.zig");
    const ListType = list.ListType;
    const TextType = @import("text.zig").TextType;

    const Leaf = struct {
        codes: list.SetType(u32, 4),
        flags: ?[3]bool,
        label: TextType(8),
        names: list.MapType([]const u8, ListType(u16, 4), 4),
    };
    const Wide = struct {
        first: Leaf,
        second: Leaf,
        third: Leaf,
        fourth: Leaf,
        pair: [2]Leaf,
        spare: ?Leaf,
    };

    comptime {
        assert(lock_count(Wide, &.{}, 0) == 0);
        assert(holder_count(Wide, &.{}, 0) > 0);
        assert(view_count(Wide, &.{}, false) == 0);
        assert(big_integer_count(Wide, &.{}, false) == 0);
    }
}
