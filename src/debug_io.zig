const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

const Write = std.Io.Operation.FileWriteStreaming;

pub const io: std.Io = if (stderr_only)
    .{ .userdata = null, .vtable = &vtable }
else
    std.Io.Threaded.global_single_threaded.io();

const stderr_only = builtin.target.os.tag.isDarwin() and !@hasField(std.Io.Threaded.NullFile, "fd");
const write_attempt_max = 64;
const write_bytes_max: u32 = std.math.maxInt(u32);

threadlocal var writer: std.Io.File.Writer = .initStreaming(.stderr(), io, &.{});

const vtable: std.Io.VTable = table: {
    var table = std.Io.failing.vtable.*;

    table.lockStderr = stderr_lock;
    table.operate = operate;
    table.swapCancelProtection = protection_swap;
    table.unlockStderr = stderr_unlock;

    break :table table;
};

fn operate(
    userdata: ?*anyopaque,
    operation: std.Io.Operation,
) std.Io.Cancelable!std.Io.Operation.Result {
    assert(userdata == null);
    assert(operation != .device_io_control);

    switch (operation) {
        .file_write_streaming => |write| {
            const written = stream_write(&write) catch |err| {
                return .{ .file_write_streaming = err };
            };

            return .{ .file_write_streaming = written };
        },
        else => return std.Io.failingOperate(userdata, operation),
    }
}

fn stream_write(write: *const Write) Write.Error!u32 {
    assert(write.data.len > 0);
    assert(stderr_only);

    const bytes = stream_next(write);
    if (bytes.len == 0) return 0;

    const chunk = bytes[0..@min(bytes.len, write_bytes_max)];

    for (0..write_attempt_max) |_| {
        const result = std.c.write(write.file.handle, chunk.ptr, chunk.len);

        if (result >= 0) {
            assert(result <= chunk.len);

            return @intCast(result);
        }

        if (std.c.errno(result) != .INTR) return error.InputOutput;
    }

    return error.InputOutput;
}

fn stream_next(write: *const Write) []const u8 {
    assert(write.data.len > 0);
    assert(write.data.len <= std.math.maxInt(u32));

    if (write.header.len > 0) return write.header;

    for (write.data[0 .. write.data.len - 1]) |part| {
        if (part.len > 0) return part;
    }

    if (write.splat == 0) return &.{};
    return write.data[write.data.len - 1];
}

fn stderr_lock(
    userdata: ?*anyopaque,
    terminal_mode: ?std.Io.Terminal.Mode,
) std.Io.Cancelable!std.Io.LockedStderr {
    assert(userdata == null);
    assert(writer.mode == .streaming);
    if (terminal_mode) |mode| assert(mode != .windows_api);

    return .{ .file_writer = &writer, .terminal_mode = terminal_mode orelse .no_color };
}

fn stderr_unlock(userdata: ?*anyopaque) void {
    assert(userdata == null);
    assert(writer.mode == .streaming);

    if (writer.err == null) {
        writer.interface.flush() catch |err| switch (err) {
            error.WriteFailed => assert(writer.err != null),
        };
    }

    writer.err = null;
    writer.interface.end = 0;
    writer.interface.buffer = &.{};
}

fn protection_swap(userdata: ?*anyopaque, _: std.Io.CancelProtection) std.Io.CancelProtection {
    assert(userdata == null);
    assert(stderr_only);

    return .blocked;
}
