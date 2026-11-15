const std = @import("std");

const text_module = @import("text.zig");

const assert = std.debug.assert;

const TextType = text_module.TextType;

pub const Error = error{ListFull};
pub const equal_depth_max: u32 = 8;
pub const list_capacity_max: u32 = 1 << 16;

pub fn ListType(comptime T: type, comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= list_capacity_max);

    return struct {
        count: u32,
        items: [capacity]T,

        const List = @This();

        pub const Item = T;
        pub const capacity_max: u32 = capacity;
        pub const empty: List = .{ .count = 0, .items = undefined };

        pub fn full(list: *const List) bool {
            assert(list.count <= capacity);
            assert(capacity <= list_capacity_max);

            return list.count == capacity;
        }

        pub fn push_slot(list: *List) Error!*T {
            assert(list.count <= capacity);
            assert(list.items.len == capacity);

            if (list.count == capacity) return error.ListFull;

            list.count += 1;

            assert(list.count <= capacity);

            return &list.items[list.count - 1];
        }

        pub fn slice(list: *const List) []const T {
            assert(list.count <= capacity);
            assert(list.items.len == capacity);

            return list.items[0..list.count];
        }

        pub fn slice_mutable(list: *List) []T {
            assert(list.count <= capacity);
            assert(list.items.len == capacity);

            return list.items[0..list.count];
        }
    };
}

pub fn SetType(comptime T: type, comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= list_capacity_max);

    return SetKindType(T, capacity, false);
}

pub fn FrozenSetType(comptime T: type, comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= list_capacity_max);

    return SetKindType(T, capacity, true);
}

fn SetKindType(comptime T: type, comptime capacity: u32, comptime frozen_set: bool) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= list_capacity_max);

    return struct {
        list: ListType(T, capacity),

        const Set = @This();

        pub const frozen = frozen_set;
        pub const Item = T;
        pub const capacity_max: u32 = capacity;
        pub const empty: Set = .{ .list = .empty };

        pub fn contains(set: *const Set, item: T) bool {
            assert(item_valid(T, &item));
            assert(set.list.count <= capacity);

            for (set.list.slice()) |present| {
                if (equal(T, .{ present, item })) return true;
            }

            return false;
        }

        pub fn include(set: *Set, item: T) Error!void {
            assert(item_valid(T, &item));
            assert(set.list.count <= capacity);

            if (set.contains(item)) return;

            (try set.list.push_slot()).* = item;

            assert(set.contains(item));
        }

        pub fn slice(set: *const Set) []const T {
            assert(set.list.count <= capacity);
            assert(capacity <= list_capacity_max);

            return set.list.slice();
        }
    };
}

pub fn MapType(comptime K: type, comptime V: type, comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= list_capacity_max);

    return struct {
        list: ListType(Entry, capacity),

        const Map = @This();

        pub const Entry = struct {
            key: K,
            value: V,
        };

        pub const Key = K;
        pub const Value = V;
        pub const capacity_max: u32 = capacity;
        pub const empty: Map = .{ .list = .empty };

        pub fn get(map: *const Map, key: K) ?*const V {
            assert(item_valid(K, &key));
            assert(map.list.count <= capacity);

            for (map.list.slice()) |*entry| {
                if (equal(K, .{ entry.key, key })) return &entry.value;
            }

            return null;
        }

        pub fn assign(map: *Map, entry: Entry) Error!void {
            assert(item_valid(K, &entry.key));
            assert(map.list.count <= capacity);

            for (map.list.slice_mutable()) |*present| {
                if (equal(K, .{ present.key, entry.key })) {
                    present.value = entry.value;

                    return;
                }
            }

            (try map.list.push_slot()).* = entry;

            assert(map.get(entry.key) != null);
        }

        pub fn slice(map: *const Map) []const Entry {
            assert(map.list.count <= capacity);
            assert(capacity <= list_capacity_max);

            return map.list.slice();
        }
    };
}

pub fn equal(comptime T: type, pair: [2]T) bool {
    comptime assert(T != type);
    assert(item_valid(T, &pair[0]));

    return equal_at(T, .{ &pair[0], &pair[1] }, 0);
}

fn equal_at(comptime T: type, pair: [2]*const T, comptime depth: u32) bool {
    comptime assert(depth < equal_depth_max);
    comptime assert(T != type);
    assert(item_valid(T, pair[0]));

    const owned = comptime text_module.is_text(T) or text_module.is_blob(T);

    if (T == []const u8) return std.mem.eql(u8, pair[0].*, pair[1].*);
    if (owned) return std.mem.eql(u8, pair[0].slice(), pair[1].slice());

    if (comptime is_list(T)) {
        return items_equal(T.Item, .{ pair[0].slice(), pair[1].slice() }, depth);
    }

    if (comptime is_set(T)) return sets_equal(T, pair);
    if (comptime is_map(T)) return maps_equal(T, pair, depth);

    return switch (@typeInfo(T)) {
        .array => |array| items_equal(array.child, .{ pair[0], pair[1] }, depth),
        .optional => |optional| optionals_equal(optional.child, pair, depth),
        .@"struct" => fields_equal(T, pair, depth),
        .@"union" => payloads_equal(T, pair, depth),
        else => std.meta.eql(pair[0].*, pair[1].*),
    };
}

fn items_equal(comptime Item: type, pair: [2][]const Item, comptime depth: u32) bool {
    comptime assert(depth < equal_depth_max);
    assert(pair[0].len <= list_capacity_max);

    if (pair[0].len != pair[1].len) return false;

    for (pair[0], pair[1]) |*left, *right| {
        if (!equal_at(Item, .{ left, right }, depth + 1)) return false;
    }

    return true;
}

fn optionals_equal(comptime Child: type, pair: [2]*const ?Child, comptime depth: u32) bool {
    comptime assert(depth < equal_depth_max);
    comptime assert(@typeInfo(Child) != .optional);
    assert(@intFromPtr(pair[1]) % @alignOf(?Child) == 0);

    const left = pair[0].* orelse return pair[1].* == null;
    const right = pair[1].* orelse return false;

    return equal_at(Child, .{ &left, &right }, depth + 1);
}

fn fields_equal(comptime T: type, pair: [2]*const T, comptime depth: u32) bool {
    comptime assert(depth < equal_depth_max);
    comptime assert(@typeInfo(T) == .@"struct");
    assert(@intFromPtr(pair[1]) % @alignOf(T) == 0);

    inline for (@typeInfo(T).@"struct".field_names) |name| {
        const fields = .{ &@field(pair[0].*, name), &@field(pair[1].*, name) };

        if (!equal_at(@FieldType(T, name), fields, depth + 1)) return false;
    }

    return true;
}

fn payloads_equal(comptime T: type, pair: [2]*const T, comptime depth: u32) bool {
    comptime assert(depth < equal_depth_max);
    comptime assert(@typeInfo(T).@"union".tag_type != null);

    if (std.meta.activeTag(pair[0].*) != std.meta.activeTag(pair[1].*)) return false;

    switch (pair[0].*) {
        inline else => |*payload, tag| {
            const other = &@field(pair[1].*, @tagName(tag));

            return equal_at(@TypeOf(payload.*), .{ payload, other }, depth + 1);
        },
    }
}

fn sets_equal(comptime T: type, pair: [2]*const T) bool {
    comptime assert(is_set(T));
    assert(pair[0].slice().len <= T.capacity_max);

    if (pair[0].slice().len != pair[1].slice().len) return false;

    for (pair[0].slice()) |item| {
        if (!pair[1].contains(item)) return false;
    }

    return true;
}

fn maps_equal(comptime T: type, pair: [2]*const T, comptime depth: u32) bool {
    comptime assert(is_map(T));
    comptime assert(depth < equal_depth_max);

    if (pair[0].slice().len != pair[1].slice().len) return false;

    for (pair[0].slice()) |*entry| {
        const found = pair[1].get(entry.key) orelse return false;

        if (!equal_at(T.Value, .{ &entry.value, found }, depth + 1)) return false;
    }

    return true;
}

pub fn item_valid(comptime T: type, item: *const T) bool {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    if (T == []const u8) return std.unicode.utf8ValidateSlice(item.*);
    return true;
}

pub fn is_set(comptime T: type) bool {
    comptime assert(T != void);
    comptime assert(list_capacity_max > 0);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "Item")) return false;
    if (!@hasDecl(T, "capacity_max")) return false;
    if (!@hasField(T, "list")) return false;
    if (!@hasDecl(T, "frozen")) return false;
    return T == SetKindType(T.Item, T.capacity_max, T.frozen);
}

pub fn is_map(comptime T: type) bool {
    comptime assert(T != void);
    comptime assert(list_capacity_max > 0);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "Key")) return false;
    if (!@hasDecl(T, "Value")) return false;
    if (!@hasDecl(T, "capacity_max")) return false;
    return T == MapType(T.Key, T.Value, T.capacity_max);
}

pub fn is_list(comptime T: type) bool {
    comptime assert(T != void);
    comptime assert(list_capacity_max > 0);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "Item")) return false;
    if (!@hasDecl(T, "capacity_max")) return false;
    return T == ListType(T.Item, T.capacity_max);
}

test ListType {
    const Numbers = ListType(u32, 2);

    var numbers: Numbers = .empty;

    (try numbers.push_slot()).* = 7;
    (try numbers.push_slot()).* = 9;

    try std.testing.expect(numbers.full());
    try std.testing.expectError(error.ListFull, numbers.push_slot());
    try std.testing.expectEqualSlices(u32, &.{ 7, 9 }, numbers.slice());
    try std.testing.expect(is_list(Numbers));
    try std.testing.expect(!is_list(struct { Item: u32 }));
}

test SetType {
    const Tags = SetType([]const u8, 2);

    var tags: Tags = .empty;

    try tags.include("red");
    try tags.include("red");
    try tags.include("blue");

    const refused = tags.include("green");

    try std.testing.expectEqual(@as(usize, 2), tags.slice().len);
    try std.testing.expect(tags.contains("blue"));
    try std.testing.expect(!tags.contains("green"));
    try std.testing.expectError(error.ListFull, refused);
    try std.testing.expect(is_set(Tags));
    try std.testing.expect(!is_list(Tags));
}

test MapType {
    const Scores = MapType([]const u8, i64, 2);

    var scores: Scores = .empty;

    try scores.assign(.{ .key = "ada", .value = 3 });
    try scores.assign(.{ .key = "ada", .value = 5 });
    try scores.assign(.{ .key = "grace", .value = 7 });

    const refused = scores.assign(.{ .key = "linus", .value = 1 });

    try std.testing.expectEqual(@as(i64, 5), scores.get("ada").?.*);
    try std.testing.expectEqual(@as(?*const i64, null), scores.get("linus"));
    try std.testing.expectError(error.ListFull, refused);
    try std.testing.expect(is_map(Scores));
    try std.testing.expect(!is_set(Scores));
}

test "owned texts compare by content, not by the bytes past their length" {
    const Name = TextType(8);
    const Scores = MapType(Name, i64, 2);

    var stored: Name = .{ .bytes = @splat(0xaa), .length = 0 };
    var probed: Name = .{ .bytes = @splat(0x55), .length = 0 };

    try stored.extend("ada");
    try probed.extend("ada");

    var scores: Scores = .empty;

    try scores.assign(.{ .key = stored, .value = 3 });
    try scores.assign(.{ .key = probed, .value = 5 });

    try std.testing.expect(equal(Name, .{ stored, probed }));
    try std.testing.expectEqual(@as(usize, 1), scores.slice().len);
    try std.testing.expectEqual(@as(i64, 5), scores.get(probed).?.*);
}

test "composite items compare their owned parts by content" {
    const Name = TextType(4);
    const Pair = struct { Name, ?i64 };
    const Pairs = SetType(Pair, 4);
    const Numbers = ListType(i64, 4);
    const Lists = SetType(Numbers, 2);

    var left: Pair = .{ .{ .bytes = @splat(1), .length = 0 }, 7 };
    var right: Pair = .{ .{ .bytes = @splat(2), .length = 0 }, 7 };

    try left[0].extend("x");
    try right[0].extend("x");

    var pairs: Pairs = .empty;

    try pairs.include(left);
    try pairs.include(right);

    var first: Numbers = .{ .count = 0, .items = @splat(11) };
    var second: Numbers = .{ .count = 0, .items = @splat(22) };

    (try first.push_slot()).* = 4;
    (try second.push_slot()).* = 4;

    var lists: Lists = .empty;

    try lists.include(first);
    try lists.include(second);

    try std.testing.expectEqual(@as(usize, 1), pairs.slice().len);
    try std.testing.expectEqual(@as(usize, 1), lists.slice().len);
    try std.testing.expect(!equal(Pair, .{ left, .{ left[0], null } }));
}
