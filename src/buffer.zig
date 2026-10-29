const std = @import("std");

const kind_module = @import("kind.zig");

const assert = std.debug.assert;

pub const dimensions_max: u8 = 8;

pub fn BufferType(comptime T: type) type {
    comptime assert(kind_module.buffer_element(T));

    return StridedType(T, false);
}

pub fn BufferMutableType(comptime T: type) type {
    comptime assert(kind_module.buffer_element(T));

    return StridedType(T, true);
}

fn StridedType(comptime T: type, comptime mutable: bool) type {
    comptime assert(@sizeOf(T) > 0);

    if (!kind_module.buffer_element(T)) {
        @compileError("lacuna: '" ++ @typeName(T) ++ "' is not a buffer element type");
    }

    return struct {
        data: [*]T,
        dimension_count: u8,
        shape: [dimensions_max]u64,
        strides: [dimensions_max]i64,
        read_only: bool,

        const Buffer = @This();

        pub const Element = T;
        pub const writable = mutable;

        pub fn len(buffer: *const Buffer) u64 {
            assert(buffer.dimension_count <= dimensions_max);

            var result: u64 = 1;

            for (buffer.shape[0..buffer.dimension_count]) |extent| result *= extent;

            assert(buffer.dimension_count > 0 or result == 1);

            return result;
        }

        pub fn at(buffer: *const Buffer, indices: []const u64) T {
            assert(indices.len == buffer.dimension_count);
            assert(buffer.dimension_count <= dimensions_max);

            return buffer.pointer_at(indices).*;
        }

        pub fn set(buffer: *const Buffer, indices: []const u64, element: T) void {
            comptime assert(mutable);
            assert(indices.len == buffer.dimension_count);
            assert(!buffer.read_only);

            buffer.pointer_at(indices).* = element;
        }

        pub fn contiguous(buffer: *const Buffer) bool {
            assert(buffer.dimension_count <= dimensions_max);

            var expected: i64 = @sizeOf(T);
            var index: u8 = buffer.dimension_count;

            for (0..buffer.dimension_count) |_| {
                index -= 1;

                if (buffer.shape[index] > 1) {
                    if (buffer.strides[index] != expected) return false;
                }

                expected *= @intCast(buffer.shape[index]);
            }

            assert(index == 0);

            return true;
        }

        fn pointer_at(buffer: *const Buffer, indices: []const u64) *align(1) T {
            assert(indices.len == buffer.dimension_count);
            assert(buffer.dimension_count <= dimensions_max);

            var offset: i64 = 0;

            for (indices, 0..) |index, dimension| {
                assert(index < buffer.shape[dimension]);

                offset += @as(i64, @intCast(index)) * buffer.strides[dimension];
            }

            const base: i64 = @intCast(@intFromPtr(buffer.data));

            return @ptrFromInt(@as(usize, @intCast(base + offset)));
        }
    };
}

pub fn is_buffer(comptime T: type) bool {
    comptime assert(T != type);
    comptime assert(@typeInfo(T) != .@"opaque");

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "Element")) return false;
    if (!@hasDecl(T, "writable")) return false;
    if (@TypeOf(T.Element) != type) return false;
    if (!kind_module.buffer_element(T.Element)) return false;
    return T == StridedType(T.Element, T.writable);
}

test BufferType {
    var values = [_]f64{ 1, 2, 3, 4, 5, 6 };

    const grid: BufferType(f64) = .{
        .data = &values,
        .dimension_count = 2,
        .shape = .{ 2, 3, 0, 0, 0, 0, 0, 0 },
        .strides = .{ 24, 8, 0, 0, 0, 0, 0, 0 },
        .read_only = true,
    };

    const column: BufferType(f64) = .{
        .data = &values,
        .dimension_count = 1,
        .shape = .{ 3, 0, 0, 0, 0, 0, 0, 0 },
        .strides = .{ 16, 0, 0, 0, 0, 0, 0, 0 },
        .read_only = true,
    };

    try std.testing.expectEqual(6, grid.len());
    try std.testing.expect(grid.contiguous());
    try std.testing.expectEqual(6, grid.at(&.{ 1, 2 }));
    try std.testing.expect(!column.contiguous());
    try std.testing.expectEqual(5, column.at(&.{2}));
    try std.testing.expect(comptime is_buffer(BufferType(u8)));
    try std.testing.expect(comptime !is_buffer(struct { data: u8 }));
}
