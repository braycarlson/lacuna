const std = @import("std");

const lacuna = @import("lacuna");
const extension = @import("extension");
const options = @import("options");

const assert = std.debug.assert;

pub const lacuna_stable_minor: u8 = options.stable_minor;

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};

const files = lacuna.stub_files(extension.module);

pub fn main(init: std.process.Init) !void {
    comptime assert(files.len > 0);
    assert(init.minimal.args.vector.len > 0);

    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 2) return error.Usage;

    const open: std.Io.Dir.CreateDirPathOpenOptions = .{
        .open_options = .{ .access_sub_paths = true, .follow_symlinks = true, .iterate = false },
        .permissions = .default_dir,
    };

    var directory = try std.Io.Dir.cwd().createDirPathOpen(init.io, arguments[1], open);
    defer directory.close(init.io);

    inline for (files) |file| {
        comptime assert(file.text[file.text.len - 1] == '\n');

        if (std.Io.Dir.path.dirname(file.path)) |parent| {
            try directory.createDirPath(init.io, parent);
        }

        try directory.writeFile(init.io, .{
            .sub_path = file.path,
            .data = file.text,
            .flags = create_flags,
        });
    }
}
