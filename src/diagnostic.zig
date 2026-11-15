const std = @import("std");

const assert = std.debug.assert;

pub const message_bytes_max: u32 = 1024;
const ellipsis = "...";
const ellipsis_length: u32 = ellipsis.len;

comptime {
    assert(message_bytes_max > ellipsis.len);
}

pub fn DiagnosticType(comptime Details_: type) type {
    comptime assert(@typeInfo(Details_) == .@"struct");
    comptime assert(!@typeInfo(Details_).@"struct".is_tuple);

    return struct {
        details: ?Details_,
        message_bytes: [message_bytes_max]u8,
        message_length: u32,

        const Diagnostic = @This();

        pub const Details = Details_;

        pub const empty: Diagnostic = .{
            .details = null,
            .message_bytes = undefined,
            .message_length = 0,
        };

        pub fn print(
            diagnostic: *Diagnostic,
            comptime format: []const u8,
            arguments: anytype,
        ) void {
            comptime assert(@typeInfo(@TypeOf(arguments)) == .@"struct");
            comptime assert(format.len > 0);
            assert(diagnostic.message_length <= message_bytes_max);

            var writer: std.Io.Writer = .fixed(&diagnostic.message_bytes);

            writer.print(format, arguments) catch |err| switch (err) {
                error.WriteFailed => {
                    diagnostic.message_length = truncated(&diagnostic.message_bytes);

                    return;
                },
            };

            diagnostic.message_length = @intCast(writer.buffered().len);

            assert(diagnostic.message_length <= message_bytes_max);
        }

        pub fn message(diagnostic: *const Diagnostic) ?[]const u8 {
            assert(diagnostic.message_length <= message_bytes_max);

            if (diagnostic.message_length == 0) return null;

            const result = diagnostic.message_bytes[0..diagnostic.message_length];

            assert(std.unicode.utf8ValidateSlice(result));

            return result;
        }
    };
}

pub fn is_diagnostic(comptime T: type) bool {
    comptime assert(T != type);

    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "Details")) return false;
    if (@TypeOf(T.Details) != type) return false;
    return T == DiagnosticType(T.Details);
}

fn truncated(bytes: *[message_bytes_max]u8) u32 {
    assert(bytes.len == message_bytes_max);

    var length: u32 = message_bytes_max - ellipsis_length;

    for (0..4) |_| {
        if (std.unicode.utf8ValidateSlice(bytes[0..length])) break;

        length -= 1;
    }

    assert(std.unicode.utf8ValidateSlice(bytes[0..length]));

    @memcpy(bytes[length..][0..ellipsis.len], ellipsis);

    const result = length + ellipsis_length;

    assert(result <= message_bytes_max);

    return result;
}

test DiagnosticType {
    const Diagnostic = DiagnosticType(struct { line: u32, column: u32 });

    var diagnostic: Diagnostic = .empty;

    try std.testing.expectEqual(@as(?[]const u8, null), diagnostic.message());

    diagnostic.print("{d}:{d}: {s}", .{ 1, 13, "the minimum is greater than the maximum" });
    diagnostic.details = .{ .line = 1, .column = 13 };

    try std.testing.expectEqualStrings(
        "1:13: the minimum is greater than the maximum",
        diagnostic.message().?,
    );

    try std.testing.expect(is_diagnostic(Diagnostic));
    try std.testing.expect(!is_diagnostic(struct { line: u32 }));
}

test "a message too long for the buffer ends on a character boundary" {
    const Diagnostic = DiagnosticType(struct {});
    const snowman = "\u{2603}";
    const repeat_count = @divFloor(message_bytes_max, snowman.len) + 1;

    const long = comptime long: {
        var result: []const u8 = "";

        @setEvalBranchQuota(repeat_count * 16);

        for (0..repeat_count) |_| result = result ++ snowman;

        break :long result;
    };

    var diagnostic: Diagnostic = .empty;

    diagnostic.print("{s}", .{long});

    const text = diagnostic.message().?;

    try std.testing.expect(std.unicode.utf8ValidateSlice(text));
    try std.testing.expect(std.mem.endsWith(u8, text, ellipsis));
    try std.testing.expect(text.len <= message_bytes_max);
    try std.testing.expectEqual(@as(usize, 0), (text.len - ellipsis.len) % snowman.len);
}
