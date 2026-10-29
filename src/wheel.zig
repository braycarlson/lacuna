const std = @import("std");

const zip = @import("zip.zig");

const assert = std.debug.assert;

const Error = error{
    FileTooLarge,
    NameTooLong,
    OutOfMemory,
    Usage,
} || zip.Error || std.Io.File.OpenError || std.Io.Dir.ReadFileError || std.Io.Writer.Error;

const metadata_flag = "--metadata";

const Description = struct {
    metadata_path: []const u8,
    readme_path: []const u8,
};

const Generated = enum {
    metadata,
    record,
};

const Entry = struct {
    name: []const u8,
    path: []const u8,
};

const Name = struct {
    bytes: [zip.name_bytes_max]u8,
    length: u32,

    fn slice(name: *const Name) []const u8 {
        assert(name.length <= zip.name_bytes_max);
        assert(name.length > 0);

        return name.bytes[0..name.length];
    }
};

const Request = struct {
    description: Description,
    metadata_directory: []const u8,
    output_path: []const u8,
    pairs: []const [:0]const u8,
};

const Sinks = struct {
    output: *std.Io.Writer,
    record: *std.Io.Writer,
};

const Wheel = struct {
    archive: zip.Archive,
    metadata: [metadata_bytes_max + 1]u8,
    names: [zip.entry_count_max]Name,
    output_buffer: [zip.chunk_bytes]u8,
    record: [record_bytes_max]u8,
    walker_memory: [walker_bytes_max]u8,
};

const walker_bytes_max: u32 = 256 * 1024;
const argument_count_max: u32 = 5 + 2 * (zip.entry_count_max - 2);
const metadata_bytes_max: u32 = 4 * 1024 * 1024;
const walker_entry_count_max: u32 = 64 * 1024;
const record_bytes_max: u32 = zip.entry_count_max * (zip.name_bytes_max + 96);

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};

const open_flags: std.Io.Dir.OpenFileOptions = .{
    .mode = .read_only,
    .allow_directory = false,
    .lock = .none,
    .lock_nonblocking = false,
    .allow_ctty = false,
    .path_only = false,
    .follow_symlinks = true,
    .resolve_beneath = false,
};

comptime {
    assert(argument_count_max > 5);
    assert(record_bytes_max > zip.name_bytes_max);
}

pub fn main(init: std.process.Init) Error!void {
    assert(zip.entry_count_max >= 4);
    assert(init.minimal.args.vector.len > 0);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len < 5) return error.Usage;
    if (arguments.len > argument_count_max) return error.Usage;
    if (arguments.len % 2 == 0) return error.Usage;

    assert(arguments[5..].len % 2 == 0);

    const wheel = try init.gpa.create(Wheel);
    defer init.gpa.destroy(wheel);

    if (std.mem.eql(u8, arguments[1], metadata_flag)) {
        if (arguments.len != 5) return error.Usage;

        const description: Description = .{
            .metadata_path = arguments[3],
            .readme_path = arguments[4],
        };

        return metadata_write(wheel, init.io, arguments[2], description);
    }

    try build(wheel, init.io, &.{
        .description = .{ .metadata_path = arguments[3], .readme_path = arguments[4] },
        .metadata_directory = arguments[2],
        .output_path = arguments[1],
        .pairs = arguments[5..],
    });
}

fn build(wheel: *Wheel, io: std.Io, request: *const Request) Error!void {
    assert(request.pairs.len % 2 == 0);
    assert(request.metadata_directory.len > 0);
    assert(request.output_path.len > 0);

    const output_file = try std.Io.Dir.cwd().createFile(io, request.output_path, create_flags);
    defer output_file.close(io);

    var file_writer = output_file.writer(io, &wheel.output_buffer);
    var record: std.Io.Writer = .fixed(&wheel.record);

    const sinks: Sinks = .{ .output = &file_writer.interface, .record = &record };

    wheel.archive.init();

    for (0..@divExact(request.pairs.len, 2)) |index| {
        const entry: Entry = .{
            .name = request.pairs[2 * index],
            .path = request.pairs[2 * index + 1],
        };

        if (std.mem.endsWith(u8, entry.name, "/")) {
            try entry_add_directory(wheel, io, sinks, entry);
        } else {
            try entry_add_file(wheel, io, sinks, entry);
        }
    }

    const metadata = try metadata_compose(wheel, io, request.description);
    const metadata_name = try name_join(request.metadata_directory, .metadata);

    const metadata_entry = try wheel.archive.add(io, sinks.output, metadata_name.slice(), .{
        .memory = metadata,
    });

    try record_line(&record, metadata_entry);
    try record.print("{s}/RECORD,,\n", .{request.metadata_directory});

    const record_name = try name_join(request.metadata_directory, .record);

    _ = try wheel.archive.add(io, sinks.output, record_name.slice(), .{
        .memory = record.buffered(),
    });

    try wheel.archive.finish(sinks.output);
}

fn entry_add_file(wheel: *Wheel, io: std.Io, sinks: Sinks, entry: Entry) Error!void {
    assert(entry.name.len > 0);
    assert(entry.path.len > 0);
    assert(sinks.output != sinks.record);

    const file = try std.Io.Dir.cwd().openFile(io, entry.path, open_flags);
    defer file.close(io);

    const added = try wheel.archive.add(io, sinks.output, entry.name, .{ .file = file });

    try record_line(sinks.record, added);
}

fn entry_add_directory(wheel: *Wheel, io: std.Io, sinks: Sinks, entry: Entry) Error!void {
    assert(sinks.output != sinks.record);
    assert(std.mem.endsWith(u8, entry.name, "/"));
    assert(entry.path.len > 0);

    const directory = try std.Io.Dir.cwd().openDir(io, entry.path, .{
        .access_sub_paths = true,
        .follow_symlinks = true,
        .iterate = true,
    });

    defer directory.close(io);

    const prefix = if (std.mem.eql(u8, entry.name, "./")) "" else entry.name;
    const count = try directory_list(wheel, io, &directory, prefix);
    const names = wheel.names[0..count];

    std.mem.sortUnstable(Name, names, {}, name_less);

    for (names) |*name| {
        const relative = name.slice()[prefix.len..];
        const file = try directory.openFile(io, relative, open_flags);
        defer file.close(io);

        const added = try wheel.archive.add(io, sinks.output, name.slice(), .{ .file = file });

        try record_line(sinks.record, added);
    }
}

fn directory_list(
    wheel: *Wheel,
    io: std.Io,
    directory: *const std.Io.Dir,
    prefix: []const u8,
) Error!u32 {
    assert(prefix.len == 0 or std.mem.endsWith(u8, prefix, "/"));
    assert(wheel.names.len == zip.entry_count_max);

    var memory: std.heap.FixedBufferAllocator = .init(&wheel.walker_memory);
    var walker = try directory.walk(memory.allocator());
    defer walker.deinit();

    var count: u32 = 0;

    for (0..walker_entry_count_max) |_| {
        const item = try walker.next(io) orelse break;
        if (item.kind != .file) continue;
        if (!entry_included(item.path)) continue;
        if (count == wheel.names.len) return error.FileTooLarge;

        const name = &wheel.names[count];

        const joined = std.mem.print(&name.bytes, "{s}{s}", .{ prefix, item.path }) catch {
            return error.NameTooLong;
        };

        std.mem.replaceScalar(u8, name.bytes[0..joined.len], std.Io.Dir.path.sep, '/');
        name.length = @intCast(joined.len);
        count += 1;
    } else return error.FileTooLarge;

    assert(count <= zip.entry_count_max);

    return count;
}

fn entry_included(path: []const u8) bool {
    assert(path.len > 0);
    assert(path.len < 1 << 16);

    if (std.mem.find(u8, path, "__pycache__") != null) return false;
    return !std.mem.endsWith(u8, path, ".pyc");
}

fn name_less(context: void, left: Name, right: Name) bool {
    assert(left.length > 0);
    assert(right.length > 0);

    _ = context;

    return std.mem.lessThan(u8, left.slice(), right.slice());
}

fn record_line(record: *std.Io.Writer, entry: *const zip.Entry) std.Io.Writer.Error!void {
    assert(entry.name_length > 0);
    assert(record.buffer.len == record_bytes_max);

    const encoder = std.base64.url_safe_no_pad.Encoder;

    var digest: [encoder.calcSize(entry.digest.len)]u8 = undefined;

    _ = encoder.encode(&digest, &entry.digest);

    try record.print("{s},sha256={s},{d}\n", .{ entry.name_slice(), &digest, entry.size });
}

fn name_join(directory: []const u8, comptime file: Generated) Error!Name {
    assert(directory.len > 0);
    comptime assert(@tagName(file).len > 0);

    const file_name = switch (file) {
        .metadata => "METADATA",
        .record => "RECORD",
    };

    var result: Name = .{ .bytes = undefined, .length = 0 };

    const joined = std.mem.print(&result.bytes, "{s}/" ++ file_name, .{directory}) catch {
        return error.NameTooLong;
    };

    result.length = @intCast(joined.len);

    return result;
}

fn metadata_write(
    wheel: *Wheel,
    io: std.Io,
    output_path: []const u8,
    description: Description,
) Error!void {
    assert(output_path.len > 0);
    assert(description.metadata_path.len > 0);

    const metadata = try metadata_compose(wheel, io, description);
    const output_file = try std.Io.Dir.cwd().createFile(io, output_path, create_flags);
    defer output_file.close(io);

    var file_writer = output_file.writer(io, &wheel.output_buffer);

    try file_writer.interface.writeAll(metadata);
    try file_writer.interface.flush();
}

fn metadata_compose(wheel: *Wheel, io: std.Io, description: Description) Error![]const u8 {
    assert(description.metadata_path.len > 0);
    assert(description.readme_path.len > 0);

    const cwd = std.Io.Dir.cwd();
    const header = try cwd.readFile(io, description.metadata_path, &wheel.metadata);
    if (header.len > metadata_bytes_max) return error.FileTooLarge;
    if (std.mem.eql(u8, description.readme_path, "-")) return header;

    const remaining = wheel.metadata[header.len..];
    if (remaining.len < 2) return error.FileTooLarge;

    remaining[0] = '\n';

    const readme = try cwd.readFile(io, description.readme_path, remaining[1..]);
    const total = header.len + 1 + readme.len;
    if (total > metadata_bytes_max) return error.FileTooLarge;
    return wheel.metadata[0..total];
}

test name_join {
    const name = try name_join("faker-0.1.0.dist-info", .record);

    try std.testing.expectEqualStrings("faker-0.1.0.dist-info/RECORD", name.slice());

    const long: [zip.name_bytes_max]u8 = @splat('a');

    try std.testing.expectError(error.NameTooLong, name_join(&long, .record));
}
