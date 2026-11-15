const std = @import("std");

const assert = std.debug.assert;

const Error = error{ ArgumentsTooMany, Usage } || std.Io.Writer.Error;

const argument_count_max: u32 = 64;

pub fn main(init: std.process.Init) Error!void {
    assert(init.minimal.args.vector.len > 0);
    assert(argument_count_max > 1);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len > argument_count_max) return error.ArgumentsTooMany;

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(init.io, &buffer);
    const output = &writer.interface;

    for (arguments[1..], 0..) |argument, index| {
        if (index > 0) try output.writeByte(' ');

        for (argument) |character| {
            try output.writeByte(std.ascii.toUpper(character));
        }
    }

    try output.writeByte('\n');
    try output.flush();
}
