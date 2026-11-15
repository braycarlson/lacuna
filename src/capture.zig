const std = @import("std");

const assert = std.debug.assert;

pub const Error = error{
    ChildFailed,
    Usage,
} || std.Io.File.OpenError || std.process.SpawnError || std.process.Child.WaitError;

pub const argument_count_max: u32 = 32;

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};

pub fn main(init: std.process.Init) Error!void {
    assert(argument_count_max > 2);
    assert(init.minimal.args.vector.len > 0);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len < 3) return error.Usage;
    if (arguments.len > argument_count_max) return error.Usage;

    var command: [argument_count_max][]const u8 = undefined;
    const count = command_copy(&command, arguments[2..]);

    const file = try std.Io.Dir.cwd().createFile(init.io, arguments[1], create_flags);
    defer file.close(init.io);

    var child = try std.process.spawn(init.io, .{
        .argv = command[0..count],
        .stdin = .ignore,
        .stdout = .{ .file = file },
        .stderr = .inherit,
    });

    const term = try child.wait(init.io);
    if (!term.success()) return error.ChildFailed;
}

fn command_copy(command: *[argument_count_max][]const u8, arguments: []const [:0]const u8) u32 {
    assert(arguments.len > 0);
    assert(arguments.len <= command.len);

    for (arguments, 0..) |argument, index| {
        command[index] = argument;
    }

    const count: u32 = @intCast(arguments.len);
    assert(count <= argument_count_max);

    return count;
}

test "capture: the command is copied argument for argument" {
    var command: [argument_count_max][]const u8 = undefined;
    const arguments = [_][:0]const u8{ "zig", "translate-c", "-lc", "limited.h" };
    const count = command_copy(&command, &arguments);

    try std.testing.expectEqual(arguments.len, count);

    for (arguments, command[0..count]) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }
}
