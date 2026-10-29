const std = @import("std");

const assert = std.debug.assert;

pub const Error = error{ListFull};
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

    if (T == []const u8) return std.mem.eql(u8, pair[0], pair[1]);
    return std.meta.eql(pair[0], pair[1]);
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
