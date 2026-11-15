const std = @import("std");

const buffer_module = @import("buffer.zig");
const calendar = @import("calendar.zig");
const list = @import("list.zig");
const text = @import("text.zig");
const value = @import("value.zig");

const assert = std.debug.assert;

const BufferMutableType = buffer_module.BufferMutableType;
const BufferType = buffer_module.BufferType;
const ListType = list.ListType;
const TextType = text.TextType;

pub const Kind = enum {
    array,
    big_integer,
    boolean,
    buffer,
    buffer_mutable,
    buffer_strided,
    bytes,
    bytes_owned,
    class_pointer,
    class_extended,
    class_pointer_mutable,
    class_value,
    complex,
    container,
    custom,
    date,
    datetime,
    decimal,
    duration,
    enumeration,
    float,
    fraction,
    integer,
    ip_address,
    items,
    list,
    loop_object,
    map,
    none,
    object,
    optional,
    path,
    record,
    reference,
    set,
    slice,
    text,
    text_owned,
    text_terminated,
    time,
    tuple,
    union_class,
    uuid,
    variant,
};

pub const depth_max: u32 = 8;
pub const eval_branch_quota: u32 = 1_000_000;
pub const integer_bits_max: u16 = 1024;
pub const big_integer_bits_max: u32 = 1 << 14;
pub const big_integer_count_max: u32 = 8;
pub const big_integer_limb_count_max: u32 = @divExact(
    big_integer_bits_max,
    @bitSizeOf(std.math.big.Limb),
);

pub fn kind_of(comptime T: type, comptime classes: []const type) Kind {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);

    @setEvalBranchQuota(eval_branch_quota);

    if (custom_is(T)) return .custom;

    return switch (@typeInfo(T)) {
        .array => .array,
        .bool => .boolean,
        .comptime_float, .float => .float,
        .comptime_int => .integer,
        .@"enum" => enum_kind(T),
        .int => integer_kind(T),
        .optional => |optional| optional_kind(T, optional.child),
        .pointer => |pointer| pointer_kind(T, pointer, classes),
        .@"struct" => struct_kind(T, classes),
        .@"union" => union_kind(T, classes),
        .void => .none,
        else => @compileError(unsupported(T)),
    };
}

pub fn custom_is(comptime T: type) bool {
    comptime assert(T != type);

    switch (@typeInfo(T)) {
        .@"enum", .@"struct", .@"union" => {},
        else => return false,
    }

    if (!@hasDecl(T, "python")) return false;

    custom_check(T);

    return true;
}

fn custom_check(comptime T: type) void {
    comptime assert(@hasDecl(T, "python"));

    const label = "lacuna: the Python conversion of '" ++ @typeName(T) ++ "'";

    if (@TypeOf(T.python) != type) @compileError(label ++ " must be a struct of functions");

    const Python = T.python;

    if (!@hasDecl(Python, "annotation")) @compileError(label ++ " declares no annotation");

    const from = @hasDecl(Python, "from");
    const to = @hasDecl(Python, "to");

    if (!from) {
        if (!to) @compileError(label ++ " declares neither from nor to");
    }

    if (from) {
        if (@TypeOf(Python.from) != fn (value.Object) error{PythonError}!T) {
            @compileError(label ++ " has from, which must be fn (lacuna.Object) " ++
                "lacuna.PythonError!" ++ @typeName(T));
        }
    }

    if (to) {
        if (@TypeOf(Python.to) != fn (*const T) error{PythonError}!value.Reference) {
            @compileError(label ++ " has to, which must be fn (*const " ++ @typeName(T) ++
                ") lacuna.PythonError!lacuna.Reference");
        }
    }
}

pub fn class_index(comptime T: type, comptime classes: []const type) ?u32 {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(T != type);

    inline for (classes, 0..) |class, index| {
        if (class == T) return index;
    }

    return null;
}

pub fn enum_index(comptime T: type, comptime enums: []const type) u32 {
    comptime assert(@typeInfo(T) == .@"enum");
    comptime assert(enums.len <= std.math.maxInt(u32));

    return class_index(T, enums) orelse @compileError("lacuna: the enum '" ++ @typeName(T) ++
        "' is converted, so the module must list it in .enums");
}

pub fn unsupported(comptime T: type) []const u8 {
    comptime assert(@typeName(T).len > 0);
    comptime assert(T != type);

    return "lacuna: the Zig type '" ++ @typeName(T) ++ "' has no Python equivalent";
}

pub fn buffer_element(comptime T: type) bool {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    return switch (@typeInfo(T)) {
        .float => |float| float.bits == 16 or float.bits == 32 or float.bits == 64,
        .int => |int| int.bits == 8 or int.bits == 16 or int.bits == 32 or int.bits == 64,
        else => false,
    };
}

pub fn owned(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(depth < depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    return switch (comptime kind_of(T, classes)) {
        .array => owned(@typeInfo(T).array.child, classes, depth + 1),
        .boolean, .class_value, .enumeration, .float, .integer => true,
        .complex, .custom, .decimal, .fraction, .ip_address, .slice, .union_class, .uuid => true,
        .class_extended => false,
        .bytes_owned, .date, .datetime, .duration, .text_owned, .time => true,
        .map => owned(T.Key, classes, depth + 1) and owned(T.Value, classes, depth + 1),
        .set => owned(T.Item, classes, depth + 1),
        .variant => variants_owned(T, classes, depth),
        .list => owned(T.Item, classes, depth + 1),
        .optional => owned(@typeInfo(T).optional.child, classes, depth + 1),
        .record, .tuple => fields_owned(T, classes, depth),
        else => false,
    };
}

fn variants_owned(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(depth < depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    inline for (@typeInfo(T).@"union".field_types) |Payload| {
        if (Payload != void) {
            if (!owned(Payload, classes, depth + 1)) return false;
        }
    }

    return true;
}

pub fn fields_owned(comptime T: type, comptime classes: []const type, comptime depth: u32) bool {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(depth < depth_max);
    comptime assert(classes.len <= std.math.maxInt(u32));

    inline for (@typeInfo(T).@"struct".field_types) |Field| {
        if (!owned(Field, classes, depth + 1)) return false;
    }

    return true;
}

fn enum_kind(comptime T: type) Kind {
    comptime assert(@typeInfo(T) == .@"enum");

    const enumeration = @typeInfo(T).@"enum";

    if (enumeration.mode != .exhaustive) {
        @compileError("lacuna: the enum '" ++ @typeName(T) ++ "' must be exhaustive");
    }

    comptime assert(enumeration.field_names.len > 0);

    return .enumeration;
}

fn integer_kind(comptime T: type) Kind {
    comptime assert(@typeInfo(T) == .int);

    if (@typeInfo(T).int.bits > integer_bits_max) {
        @compileError("lacuna: the integer type '" ++ @typeName(T) ++ "' is wider than 1024 bits");
    }

    comptime assert(@typeInfo(T).int.bits <= integer_bits_max);

    return .integer;
}

fn optional_kind(comptime T: type, comptime Child: type) Kind {
    comptime assert(@typeInfo(T) == .optional);

    switch (@typeInfo(Child)) {
        .optional, .void => @compileError("lacuna: the optional '" ++ @typeName(T) ++
            "' cannot tell its own null from its child's"),
        else => {},
    }

    layout_check(T);

    comptime assert(@typeInfo(Child) != .optional);

    return .optional;
}

fn pointer_kind(
    comptime T: type,
    comptime pointer: std.lang.Type.Pointer,
    comptime classes: []const type,
) Kind {
    comptime assert(classes.len <= std.math.maxInt(u32));
    comptime assert(@typeInfo(T) == .pointer);
    comptime assert(pointer.child != void);

    switch (pointer.size) {
        .one => {
            if (@typeInfo(pointer.child) != .@"struct") @compileError(unsupported(T));
            if (class_index(pointer.child, classes) == null) @compileError(unsupported(T));

            return if (pointer.attrs.@"const") .class_pointer else .class_pointer_mutable;
        },
        .slice => return slice_kind(T, pointer),
        .c, .many => @compileError(unsupported(T)),
    }
}

fn slice_kind(comptime T: type, comptime pointer: std.lang.Type.Pointer) Kind {
    comptime assert(pointer.size == .slice);
    comptime assert(@typeInfo(T) == .pointer);

    const sentinel = pointer.sentinel();

    if (pointer.child == u8) {
        if (!pointer.attrs.@"const") {
            if (sentinel != null) @compileError(unsupported(T));

            return .buffer_mutable;
        }

        if (sentinel) |terminator| {
            if (terminator != 0) @compileError(unsupported(T));

            return .text_terminated;
        }

        return .text;
    }

    if (sentinel != null) @compileError(unsupported(T));
    if (!buffer_element(pointer.child)) return .items;

    return if (pointer.attrs.@"const") .buffer else .buffer_mutable;
}

fn struct_kind(comptime T: type, comptime classes: []const type) Kind {
    comptime assert(@typeInfo(T) == .@"struct");
    comptime assert(classes.len <= std.math.maxInt(u32));

    if (value.container_is(T)) return .container;
    if (buffer_module.is_buffer(T)) return .buffer_strided;
    if (T == value.Bytes) return .bytes;
    if (T == value.Decimal) return .decimal;
    if (T == value.UUID) return .uuid;
    if (T == std.math.Complex(f64)) return .complex;
    if (T == std.math.Complex(f32)) return .complex;
    if (T == value.Object) return .object;
    if (T == value.Path) return .path;
    if (T == value.Reference) return .reference;
    if (T == value.Slice) return .slice;
    if (T == value.Fraction) return .fraction;
    if (T == std.math.big.int.Const) return .big_integer;
    if (T == @import("cancellation.zig").LoopObject) return .loop_object;

    const limbs_owned = "lacuna: '" ++ @typeName(T) ++ "' owns or reuses its limbs; take and " ++
        "return std.math.big.int.Const, built in the per-call arena";

    if (T == std.math.big.int.Managed) @compileError(limbs_owned);
    if (T == std.math.big.int.Mutable) @compileError(limbs_owned);

    const contexts = .{
        value.ModuleObject,
        value.TypeObject,
        std.mem.Allocator,
        @import("cancellation.zig").Cancellation,
        @import("cancellation.zig").Loop,
    };

    inline for (contexts) |Context| {
        if (T == Context) {
            @compileError("lacuna: '" ++ @typeName(T) ++ "' is a context parameter that " ++
                "follows the receiver, not an argument or a result");
        }
    }

    if (value.state_is(T)) {
        @compileError("lacuna: '" ++ @typeName(T) ++ "' is a context parameter that " ++
            "follows the receiver, not an argument or a result");
    }

    if (T == calendar.Date) return .date;
    if (T == calendar.DateTime) return .datetime;
    if (T == calendar.Duration) return .duration;
    if (T == calendar.Time) return .time;
    if (list.is_list(T)) return .list;
    if (list.is_map(T)) return .map;
    if (list.is_set(T)) return .set;
    if (text.is_text(T)) return .text_owned;
    if (text.is_blob(T)) return .bytes_owned;
    if (class_index(T, classes) != null) return .class_value;

    if (@hasDecl(T, "extended_class")) {
        if (class_index(T.extended_class, classes) == null) @compileError(unsupported(T));

        return .class_extended;
    }

    if (@typeInfo(T).@"struct".is_tuple) return .tuple;
    return .record;
}

fn union_kind(comptime T: type, comptime classes: []const type) Kind {
    comptime assert(@typeInfo(T) == .@"union");
    comptime assert(classes.len <= std.math.maxInt(u32));

    const structure = @typeInfo(T).@"union";

    if (structure.tag_type == null) {
        @compileError("lacuna: the union '" ++ @typeName(T) ++ "' must be tagged");
    }

    if (structure.field_names.len == 0) {
        @compileError("lacuna: the union '" ++ @typeName(T) ++ "' has no variants");
    }

    comptime assert(structure.field_names.len > 0);

    layout_check(T);

    if (T == value.IPAddress) return .ip_address;
    if (class_index(T, classes) != null) return .union_class;

    for (structure.field_types, 0..) |Left, index| {
        for (structure.field_types[index + 1 ..]) |Right| {
            if (Left == Right) {
                @compileError("lacuna: the union '" ++ @typeName(T) ++ "' has two variants " ++
                    "of type '" ++ @typeName(Left) ++ "', so a Python value cannot choose " ++
                    "between them");
            }
        }
    }

    return .variant;
}

pub fn layout_check(comptime T: type) void {
    comptime assert(T != type);
    comptime assert(T != noreturn);

    const size_lowered = layout_size_lowered(T) orelse return;
    if (size_lowered == @sizeOf(T)) return;

    @compileError("lacuna: '" ++ @typeName(T) ++ "' takes " ++
        std.fmt.comptimePrint("{d}", .{@sizeOf(T)}) ++ " bytes in Zig but " ++
        std.fmt.comptimePrint("{d}", .{size_lowered}) ++ " in Zig 0.17's LLVM backend, " ++
        "which drops the padding of an optional whose child is zero-size and of a union " ++
        "whose variants all are, so copying it overruns memory; give the zero-size child " ++
        "or variants an alignment of 1, as [0]u8 and struct {} have");
}

fn layout_size_lowered(comptime T: type) ?usize {
    comptime assert(T != type);
    comptime assert(T != noreturn);

    switch (@typeInfo(T)) {
        .optional => |optional| {
            if (@sizeOf(optional.child) > 0) return null;

            comptime assert(@sizeOf(T) >= 1);

            return 1;
        },
        .@"union" => |structure| {
            const Tag = structure.tag_type orelse return null;

            for (structure.field_types) |Field| {
                if (@sizeOf(Field) > 0) return null;
            }

            comptime assert(@sizeOf(Tag) <= @sizeOf(T));

            return @sizeOf(Tag);
        },
        else => return null,
    }
}

test kind_of {
    const Point = struct { horizontal: f64, vertical: f64 };
    const Color = enum { red, green };
    const Shape = union(enum) { circle: f64, empty: void };

    comptime {
        @setEvalBranchQuota(10_000);

        const classes = [_]type{Point};

        assert(kind_of(void, &classes) == .none);
        assert(kind_of(u8, &classes) == .integer);
        assert(kind_of(f32, &classes) == .float);
        assert(kind_of([]const u8, &classes) == .text);
        assert(kind_of([:0]const u8, &classes) == .text_terminated);
        assert(kind_of([]u8, &classes) == .buffer_mutable);
        assert(kind_of([]const f64, &classes) == .buffer);
        assert(kind_of([]i32, &classes) == .buffer_mutable);
        assert(kind_of(*const Point, &classes) == .class_pointer);
        assert(kind_of(*Point, &classes) == .class_pointer_mutable);
        assert(kind_of(Point, &classes) == .class_value);
        assert(kind_of(Point, &.{}) == .record);
        assert(kind_of(struct { u8, bool }, &classes) == .tuple);
        assert(kind_of(?u8, &classes) == .optional);
        assert(kind_of(?[0]u8, &classes) == .optional);
        assert(kind_of(union(enum) { empty: [0]u8, none: void }, &classes) == .variant);
        assert(kind_of(Color, &classes) == .enumeration);
        assert(kind_of([3]u8, &classes) == .array);
        assert(kind_of(value.Bytes, &classes) == .bytes);
        assert(kind_of(value.Object, &classes) == .object);
        assert(kind_of(ListType(u8, 4), &classes) == .list);
        assert(kind_of(list.SetType(u8, 4), &classes) == .set);
        assert(kind_of(list.MapType([]const u8, u8, 4), &classes) == .map);
        assert(kind_of(TextType(4), &classes) == .text_owned);
        assert(kind_of(text.BlobType(4), &classes) == .bytes_owned);
        assert(kind_of(value.Path, &classes) == .path);
        assert(kind_of(value.ListObject, &classes) == .container);
        assert(kind_of(value.Slice, &classes) == .slice);
        assert(kind_of(value.Fraction, &classes) == .fraction);
        assert(kind_of(value.IPAddress, &classes) == .ip_address);
        assert(kind_of(BufferType(f64), &classes) == .buffer_strided);
        assert(kind_of(BufferMutableType(u8), &classes) == .buffer_strided);
        assert(kind_of(value.FrozenSetObject, &classes) == .container);
        assert(kind_of(value.Reference, &classes) == .reference);
        assert(kind_of(calendar.Date, &classes) == .date);
        assert(kind_of(calendar.DateTime, &classes) == .datetime);
        assert(kind_of(calendar.Duration, &classes) == .duration);
        assert(kind_of(calendar.Time, &classes) == .time);
        assert(kind_of(union(enum) { number: i64, word: []const u8 }, &classes) == .variant);
        assert(kind_of(Shape, &.{ Point, Shape }) == .union_class);
        assert(kind_of(u128, &classes) == .integer);
        assert(kind_of(i1024, &classes) == .integer);
        assert(!buffer_element(bool));
        assert(buffer_element(u16));
        assert(class_index(Point, &classes).? == 0);
        assert(class_index(Color, &classes) == null);
    }
}

test layout_size_lowered {
    const Wide = union(enum) { wide: [0]u128, none: void };
    const Mixed = union(enum) { wide: [0]u128, byte: u8 };
    const Narrow = union(enum) { empty: [0]u8, none: void };

    comptime {
        assert(@sizeOf(?[0]f128) == @alignOf(f128));
        assert(layout_size_lowered(?[0]f128).? == 1);
        assert(@sizeOf(?[0]u64) == @alignOf(u64));
        assert(layout_size_lowered(?[0]u64).? == 1);
        assert(layout_size_lowered(?[0]u8).? == @sizeOf(?[0]u8));
        assert(layout_size_lowered(?u64) == null);
        assert(layout_size_lowered(?*const u8) == null);
        assert(@sizeOf(Wide) == @alignOf(u128));
        assert(layout_size_lowered(Wide).? == 1);
        assert(layout_size_lowered(Narrow).? == @sizeOf(Narrow));
        assert(layout_size_lowered(Mixed) == null);
        assert(layout_size_lowered(u8) == null);
    }
}
