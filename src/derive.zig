const std = @import("std");

const c = @import("c.zig");
const text_module = @import("text.zig");

const assert = std.debug.assert;

pub const Member = enum {
    equality,
    ordering,
    hash,
    representation,
};

const spellings = [_][]const u8{ "eq", "ord", "hash", "repr" };

comptime {
    assert(spellings.len == @typeInfo(Member).@"enum".field_names.len);
}

fn member_of_tag(comptime tag: []const u8) Member {
    comptime assert(tag.len > 0);
    comptime assert(spellings.len == 4);

    for (spellings, 0..) |spelling, index| {
        if (std.mem.eql(u8, spelling, tag)) return @fromBackingInt(index);
    }

    @compileError("lacuna: 'derive' lists '" ++ tag ++ "', which is not eq, ord, hash, or repr");
}

pub fn spelling_of(comptime member: Member) []const u8 {
    comptime assert(@backingInt(member) < spellings.len);
    comptime assert(spellings.len == 4);

    return spellings[@backingInt(member)];
}

pub const repr_bytes_max: u32 = 4096;

const FieldClass = enum {
    float,
    ordinal,
    sliced,
    unsupported,
};

pub fn derived(comptime Class: type, comptime member: Member) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(@tagName(member).len > 0);

    if (!@hasDecl(Class, "derive")) return false;

    for (Class.derive) |listed| {
        if (member_of_tag(@tagName(listed)) == member) return true;
    }

    return false;
}

pub fn member_of_dunder(comptime name: []const u8) ?Member {
    comptime assert(name.len > 4);
    comptime assert(std.mem.startsWith(u8, name, "__"));

    @setEvalBranchQuota(100_000);

    for (std.enums.values(Member)) |member| {
        for (dunders_of(member)) |dunder| {
            if (std.mem.eql(u8, dunder, name)) return member;
        }
    }

    return null;
}

pub fn derived_dunder(comptime Class: type, comptime name: []const u8) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 4);

    if (!@hasDecl(Class, "derive")) return false;

    const member = member_of_dunder(name) orelse return false;
    return derived(Class, member);
}

fn dunders_of(comptime member: Member) []const []const u8 {
    comptime assert(@tagName(member).len > 0);
    comptime assert(std.enums.values(Member).len == 4);

    return switch (member) {
        .equality => &.{ "__eq__", "__ne__" },
        .ordering => &.{ "__lt__", "__le__", "__gt__", "__ge__" },
        .hash => &.{"__hash__"},
        .representation => &.{"__repr__"},
    };
}

pub fn derive_check(comptime Class: type, comptime name: []const u8) void {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(name.len > 0);

    if (!@hasDecl(Class, "derive")) return;

    for (Class.derive) |listed| {
        const member = member_of_tag(@tagName(listed));

        for (dunders_of(member)) |dunder| {
            if (@hasDecl(Class, dunder)) {
                @compileError("lacuna: the class '" ++ name ++ "' derives " ++
                    spelling_of(member) ++ " and also defines " ++ dunder);
            }
        }
    }

    if (derived(Class, .hash)) {
        if (!derived(Class, .equality)) {
            @compileError("lacuna: the class '" ++ name ++ "' derives hash without eq");
        }
    }

    const compared = derived(Class, .equality) or derived(Class, .ordering) or
        derived(Class, .hash);
    if (!compared) return;

    for (@typeInfo(Class).@"struct".field_names) |field| {
        const Field = @FieldType(Class, field);

        switch (field_class(Field)) {
            .ordinal, .sliced => {},
            .float => if (derived(Class, .hash)) {
                @compileError("lacuna: the class '" ++ name ++ "' derives hash, but its field '" ++
                    field ++ "' is a float, and -0.0 and 0.0 compare equal");
            },
            .unsupported => @compileError("lacuna: the class '" ++ name ++ "' derives a " ++
                "comparison, but its field '" ++ field ++ "' of type '" ++ @typeName(Field) ++
                "' has none"),
        }
    }
}

fn field_class(comptime Field: type) FieldClass {
    comptime assert(Field != type);
    comptime assert(@typeInfo(Field) != .@"opaque");

    return switch (@typeInfo(Field)) {
        .bool, .@"enum", .int => .ordinal,
        .float => .float,
        .@"struct" => if (text_module.is_text(Field) or text_module.is_blob(Field))
            .sliced
        else
            .unsupported,
        else => .unsupported,
    };
}

pub fn OperandsType(comptime T: type) type {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    return struct {
        left: *const T,
        right: *const T,
    };
}

pub fn fields_compare(
    comptime Class: type,
    operands: OperandsType(Class),
    operation: c_int,
) bool {
    comptime assert(@typeInfo(Class) == .@"struct");
    assert(@intFromPtr(operands.left) % @alignOf(Class) == 0);
    assert(operation >= c.Py_LT);
    assert(operation <= c.Py_GE);

    inline for (@typeInfo(Class).@"struct".field_names) |field| {
        const Field = @FieldType(Class, field);
        const before = &@field(operands.left, field);
        const after = &@field(operands.right, field);
        const forward: OperandsType(Field) = .{ .left = before, .right = after };

        if (!field_equal(Field, forward)) {
            return switch (operation) {
                c.Py_EQ => false,
                c.Py_NE => true,
                c.Py_LT, c.Py_LE => field_less(Field, forward),
                c.Py_GT, c.Py_GE => field_less(Field, .{ .left = after, .right = before }),
                else => unreachable,
            };
        }
    }

    return switch (operation) {
        c.Py_EQ, c.Py_LE, c.Py_GE => true,
        c.Py_NE, c.Py_LT, c.Py_GT => false,
        else => unreachable,
    };
}

fn field_equal(comptime Field: type, operands: OperandsType(Field)) bool {
    comptime assert(field_class(Field) != .unsupported);
    assert(@intFromPtr(operands.left) % @alignOf(Field) == 0);

    const left = operands.left;
    const right = operands.right;

    return switch (comptime field_class(Field)) {
        .float => left.* == right.*,
        .ordinal => ordinal_of(Field, left.*) == ordinal_of(Field, right.*),
        .sliced => std.mem.eql(u8, left.slice(), right.slice()),
        .unsupported => unreachable,
    };
}

fn field_less(comptime Field: type, operands: OperandsType(Field)) bool {
    comptime assert(field_class(Field) != .unsupported);
    assert(@intFromPtr(operands.right) % @alignOf(Field) == 0);

    const left = operands.left;
    const right = operands.right;

    return switch (comptime field_class(Field)) {
        .float => left.* < right.*,
        .ordinal => ordinal_of(Field, left.*) < ordinal_of(Field, right.*),
        .sliced => std.mem.lessThan(u8, left.slice(), right.slice()),
        .unsupported => unreachable,
    };
}

fn ordinal_of(comptime Field: type, value: Field) i256 {
    comptime assert(field_class(Field) == .ordinal);
    comptime assert(@bitSizeOf(Field) <= 255);
    if (@typeInfo(Field) == .@"enum") assert(std.enums.tagName(Field, value) != null);

    return switch (@typeInfo(Field)) {
        .bool => @intFromBool(value),
        .@"enum" => @backingInt(value),
        .int => value,
        else => unreachable,
    };
}

pub fn fields_hash(comptime Class: type, value: *const Class) u64 {
    comptime assert(@typeInfo(Class) == .@"struct");
    comptime assert(derived(Class, .hash));

    var hasher = std.hash.Wyhash.init(0);

    inline for (@typeInfo(Class).@"struct".field_names) |field| {
        const Field = @FieldType(Class, field);
        const item = &@field(value, field);

        switch (comptime field_class(Field)) {
            .ordinal => {
                const wide = ordinal_of(Field, item.*);

                hasher.update(std.mem.asBytes(&wide));
            },
            .sliced => hasher.update(item.slice()),
            .float, .unsupported => unreachable,
        }
    }

    return hasher.final();
}

test fields_compare {
    const Pair = struct {
        left: i64,
        right: f64,
        flag: bool,
    };

    const small: Pair = .{ .left = 1, .right = 2.5, .flag = false };
    const large: Pair = .{ .left = 1, .right = 3.5, .flag = false };
    const nan: Pair = .{ .left = 1, .right = std.math.nan(f64), .flag = false };

    try std.testing.expect(fields_compare(Pair, .{ .left = &small, .right = &large }, c.Py_LT));
    try std.testing.expect(fields_compare(Pair, .{ .left = &small, .right = &small }, c.Py_LE));
    try std.testing.expect(!fields_compare(Pair, .{ .left = &small, .right = &large }, c.Py_EQ));
    try std.testing.expect(fields_compare(Pair, .{ .left = &large, .right = &small }, c.Py_GT));
    try std.testing.expect(!fields_compare(Pair, .{ .left = &nan, .right = &nan }, c.Py_EQ));
    try std.testing.expect(!fields_compare(Pair, .{ .left = &nan, .right = &small }, c.Py_LT));
}

test fields_hash {
    const Pair = struct {
        left: i64,
        right: u3,

        pub const derive = .{ .eq, .hash };
    };

    const first: Pair = .{ .left = 7, .right = 2 };
    const second: Pair = .{ .left = 7, .right = 2 };
    const third: Pair = .{ .left = 7, .right = 3 };

    try std.testing.expectEqual(fields_hash(Pair, &first), fields_hash(Pair, &second));
    try std.testing.expect(fields_hash(Pair, &first) != fields_hash(Pair, &third));
    try std.testing.expect(comptime derived(Pair, .hash));
    try std.testing.expect(comptime !derived(Pair, .ordering));
}
