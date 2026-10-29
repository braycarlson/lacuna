const std = @import("std");

const assert = std.debug.assert;

pub const Error = error{TextFull};
pub const text_capacity_max: u32 = 1 << 20;

pub fn TextType(comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= text_capacity_max);

    return struct {
        bytes: [capacity]u8,
        length: u32,

        const Text = @This();

        pub const capacity_max: u32 = capacity;
        pub const empty: Text = .{ .bytes = undefined, .length = 0 };

        pub fn extend(text: *Text, piece: []const u8) Error!void {
            assert(std.unicode.utf8ValidateSlice(piece));
            assert(text.length <= capacity);

            if (piece.len > capacity - text.length) return error.TextFull;

            @memcpy(text.bytes[text.length..][0..piece.len], piece);
            text.length += @intCast(piece.len);

            assert(text.length <= capacity);
        }

        pub fn print(text: *Text, comptime format: []const u8, arguments: anytype) Error!void {
            comptime assert(@typeInfo(@TypeOf(arguments)) == .@"struct");
            comptime assert(format.len > 0);
            assert(text.length <= capacity);

            var writer: std.Io.Writer = .fixed(text.bytes[text.length..]);

            writer.print(format, arguments) catch |err| switch (err) {
                error.WriteFailed => return error.TextFull,
            };

            const written = writer.buffered();

            assert(std.unicode.utf8ValidateSlice(written));

            text.length += @intCast(written.len);
        }

        pub fn slice(text: *const Text) []const u8 {
            assert(text.length <= capacity);
            assert(text.bytes.len == capacity);

            return text.bytes[0..text.length];
        }
    };
}

pub fn BlobType(comptime capacity: u32) type {
    comptime assert(capacity > 0);
    comptime assert(capacity <= text_capacity_max);

    return struct {
        bytes: [capacity]u8,
        length: u32,

        const Bytes = @This();

        pub const blob_capacity_max: u32 = capacity;
        pub const empty: Bytes = .{ .bytes = undefined, .length = 0 };

        pub fn extend(bytes: *Bytes, piece: []const u8) Error!void {
            assert(piece.len <= std.math.maxInt(u32));
            assert(bytes.length <= capacity);

            if (piece.len > capacity - bytes.length) return error.TextFull;

            @memcpy(bytes.bytes[bytes.length..][0..piece.len], piece);
            bytes.length += @intCast(piece.len);

            assert(bytes.length <= capacity);
        }

        pub fn slice(bytes: *const Bytes) []const u8 {
            assert(bytes.length <= capacity);
            assert(bytes.bytes.len == capacity);

            return bytes.bytes[0..bytes.length];
        }
    };
}

pub fn is_blob(comptime T: type) bool {
    comptime assert(T != type);
    comptime assert(text_capacity_max > 0);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "blob_capacity_max")) return false;
    return T == BlobType(T.blob_capacity_max);
}

pub fn is_text(comptime T: type) bool {
    comptime assert(T != type);
    comptime assert(text_capacity_max > 0);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "capacity_max")) return false;
    if (@TypeOf(T.capacity_max) != u32) return false;
    return T == TextType(T.capacity_max);
}

test TextType {
    const Line = TextType(8);

    var line: Line = .empty;

    try line.extend("ab");
    try line.print("{d}", .{345});

    const printed = line.print("{s}", .{"wxyz"});

    try std.testing.expectEqualStrings("ab345", line.slice());
    try std.testing.expectError(error.TextFull, printed);

    const extended = line.extend("wxyz");

    try std.testing.expectEqualStrings("ab345", line.slice());
    try std.testing.expectError(error.TextFull, extended);
    try std.testing.expect(is_text(Line));
    try std.testing.expect(!is_text(struct { capacity_max: u32 }));
}

test BlobType {
    const Packet = BlobType(4);

    var packet: Packet = .empty;

    try packet.extend(&.{ 0, 255 });

    const refused = packet.extend(&.{ 1, 2, 3 });

    try std.testing.expectEqualSlices(u8, &.{ 0, 255 }, packet.slice());
    try std.testing.expectError(error.TextFull, refused);
    try std.testing.expect(is_blob(Packet));
    try std.testing.expect(!is_text(Packet));
}
