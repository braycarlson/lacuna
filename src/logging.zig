const std = @import("std");

const c = @import("c.zig");
const exception = @import("exception.zig");
const text_module = @import("text.zig");
const thread = @import("thread.zig");

const assert = std.debug.assert;

pub const log_bytes_max: u32 = 4096;

const Message = text_module.TextType(log_bytes_max);
const truncation = "...";

pub fn log_function(
    comptime level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    arguments: anytype,
) void {
    comptime assert(format.len > 0);
    comptime assert(@tagName(scope).len > 0);
    comptime assert(level_of(level) >= 10);
    comptime assert(@typeInfo(@TypeOf(arguments)) == .@"struct");

    if (c.Py_IsInitialized() == 0) return std.log.defaultLog(level, scope, format, arguments);

    var message: Message = .empty;
    var writer: std.Io.Writer = .fixed(message.bytes[0 .. Message.capacity_max - truncation.len]);

    const truncated = if (writer.print(format, arguments)) false else |err| switch (err) {
        error.WriteFailed => true,
    };

    message.length = @intCast(writer.buffered().len);

    if (truncated) {
        @memcpy(message.bytes[message.length..][0..truncation.len], truncation);
        message.length += truncation.len;
    }

    const attached = thread.Interpreter.attached();
    const ensured = if (attached) null else thread.ensure();
    defer if (ensured) |held| held.release();

    const saved = exception.pending_save();
    defer exception.pending_resume(&saved);

    const record: Record = .{
        .level = level_of(level),
        .scope = @tagName(scope),
        .text = message.slice(),
    };

    record_emit(record) catch {
        c.PyErr_Clear();

        std.log.defaultLog(level, scope, format, arguments);
    };
}

const Record = struct {
    level: c_long,
    scope: [:0]const u8,
    text: []const u8,
};

fn level_of(comptime level: std.log.Level) c_long {
    comptime assert(@tagName(level).len > 0);
    comptime assert(std.enums.values(std.log.Level).len == 4);

    return switch (level) {
        .err => 40,
        .warn => 30,
        .info => 20,
        .debug => 10,
    };
}

fn record_emit(record: Record) error{Raised}!void {
    assert(record.level >= 10);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const logging = c.PyImport_ImportModule("logging") orelse return error.Raised;
    defer c.Py_DecRef(logging);

    const logger = c.PyObject_CallMethod(logging, "getLogger", "s", record.scope.ptr) orelse {
        return error.Raised;
    };

    defer c.Py_DecRef(logger);

    const size: c.Py_ssize_t = @intCast(record.text.len);
    const text = c.PyUnicode_DecodeUTF8(record.text.ptr, size, "replace") orelse {
        return error.Raised;
    };

    defer c.Py_DecRef(text);

    const result = c.PyObject_CallMethod(logger, "log", "lO", record.level, text) orelse {
        return error.Raised;
    };

    c.Py_DecRef(result);
}
