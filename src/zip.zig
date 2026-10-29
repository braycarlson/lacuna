const std = @import("std");

const assert = std.debug.assert;
const flate = std.compress.flate;

pub const Error = error{
    ArchiveFull,
    ArchiveTooLarge,
    NameDuplicate,
    NameTooLong,
} || std.Io.Reader.ShortError || std.Io.Writer.Error;

pub const Entry = struct {
    checksum: u32,
    digest: [SHA256.digest_length]u8,
    name: [name_bytes_max]u8,
    name_length: u16,
    offset: u32,
    size: u32,
    size_compressed: u32,

    pub fn name_slice(entry: *const Entry) []const u8 {
        assert(entry.name_length <= name_bytes_max);
        assert(entry.name_length > 0);

        return entry.name[0..entry.name_length];
    }
};

pub const Source = union(enum) {
    file: std.Io.File,
    memory: []const u8,
};

const Input = union(enum) {
    file: std.Io.File.Reader,
    memory: std.Io.Reader,

    fn reader(input: *Input) *std.Io.Reader {
        return switch (input.*) {
            .file => |*file| &file.interface,
            .memory => |*memory| memory,
        };
    }
};

pub const chunk_bytes: u32 = 64 * 1024;
pub const entry_count_max: u32 = 256;
pub const name_bytes_max: u32 = 512;
pub const pass_count_max: u32 = 1 << 16;

const SHA256 = std.crypto.hash.sha2.Sha256;

const sha256_options: SHA256.Options = .{};
const date_dos: u16 = (0 << 9) | (1 << 5) | 1;
const external_attributes: u32 = 0o100644 << 16;
const flag_utf8: u16 = 1 << 11;
const method_deflate: u16 = 8;
const signature_central: u32 = 0x02014b50;
const signature_end: u32 = 0x06054b50;
const signature_local: u32 = 0x04034b50;
const time_dos: u16 = 0;
const version_made_by: u16 = (3 << 8) | 20;
const version_needed: u16 = 20;

comptime {
    assert(chunk_bytes >= flate.max_window_len);
    assert(name_bytes_max < std.math.maxInt(u16));
    assert(date_dos == 0x21);
}

pub const Archive = struct {
    chunk: [chunk_bytes]u8,
    compress: flate.Compress,
    compress_output: [chunk_bytes]u8,
    entries: [entry_count_max]Entry,
    entry_count: u32,
    input_buffer: [chunk_bytes]u8,
    offset: u64,
    window: [flate.max_window_len]u8,

    pub fn init(archive: *Archive) void {
        assert(@intFromPtr(archive) != 0);
        assert(entry_count_max > 0);

        archive.entry_count = 0;
        archive.offset = 0;
    }

    pub fn add(
        archive: *Archive,
        io: std.Io,
        output: *std.Io.Writer,
        name: []const u8,
        source: Source,
    ) Error!*const Entry {
        assert(archive.entry_count <= entry_count_max);
        assert(name.len > 0);

        assert(switch (source) {
            .file => true,
            .memory => |bytes| bytes.len <= std.math.maxInt(u32),
        });

        if (archive.entry_count == entry_count_max) return error.ArchiveFull;
        if (name.len > name_bytes_max) return error.NameTooLong;
        if (archive.contains(name)) return error.NameDuplicate;

        const entry = &archive.entries[archive.entry_count];

        @memcpy(entry.name[0..name.len], name);
        entry.name_length = @intCast(name.len);

        var measured = archive.input_of(io, source);

        try archive.measure(entry, measured.reader());

        entry.offset = try archive.offset_checked();

        try local_header_write(output, entry);

        var deflated = archive.input_of(io, source);

        const compressed = try archive.deflate(deflated.reader(), output);

        assert(compressed == entry.size_compressed);

        archive.offset += 30 + name.len + compressed;
        archive.entry_count += 1;

        return entry;
    }

    pub fn contains(archive: *const Archive, name: []const u8) bool {
        assert(archive.entry_count <= entry_count_max);
        assert(name.len > 0);

        for (archive.entries[0..archive.entry_count]) |*entry| {
            if (std.mem.eql(u8, entry.name_slice(), name)) return true;
        }

        return false;
    }

    pub fn finish(archive: *Archive, output: *std.Io.Writer) Error!void {
        assert(archive.entry_count > 0);
        assert(archive.entry_count <= entry_count_max);

        var directory_size: u64 = 0;

        for (archive.entries[0..archive.entry_count]) |*entry| {
            try central_header_write(output, entry);
            directory_size += 46 + entry.name_length;
        }

        if (directory_size > std.math.maxInt(u32)) return error.ArchiveTooLarge;

        try end_record_write(output, .{
            .entry_count = @intCast(archive.entry_count),
            .directory_offset = try archive.offset_checked(),
            .directory_size = @intCast(directory_size),
        });

        try output.flush();
    }

    fn input_of(archive: *Archive, io: std.Io, source: Source) Input {
        assert(archive.entry_count < entry_count_max);
        assert(archive.input_buffer.len == chunk_bytes);

        assert(switch (source) {
            .file => true,
            .memory => |bytes| bytes.len <= std.math.maxInt(u32),
        });

        return switch (source) {
            .file => |file| .{ .file = file.reader(io, &archive.input_buffer) },
            .memory => |bytes| .{ .memory = .fixed(bytes) },
        };
    }

    fn offset_checked(archive: *const Archive) Error!u32 {
        assert(archive.entry_count <= entry_count_max);

        if (archive.offset > std.math.maxInt(u32)) return error.ArchiveTooLarge;

        const result: u32 = @intCast(archive.offset);

        assert(result == archive.offset);

        return result;
    }

    fn measure(archive: *Archive, entry: *Entry, reader: *std.Io.Reader) Error!void {
        assert(entry.name_length > 0);
        assert(archive.entry_count < entry_count_max);

        var checksum: std.hash.Crc32 = .init();
        var digest: SHA256 = .init(sha256_options);
        var discarding: std.Io.Writer.Discarding = .init(&archive.compress_output);
        var size: u64 = 0;

        archive.compress = try .init(&discarding.writer, &archive.window, .raw, .level_6);

        for (0..pass_count_max) |_| {
            const count = try reader.readSliceShort(&archive.chunk);
            if (count == 0) break;

            const bytes = archive.chunk[0..count];

            checksum.update(bytes);
            digest.update(bytes);
            size += count;

            try archive.compress.writer.writeAll(bytes);
        } else return error.ArchiveTooLarge;

        try archive.compress.finish();

        const compressed = discarding.fullCount();

        if (size > std.math.maxInt(u32)) return error.ArchiveTooLarge;
        if (compressed > std.math.maxInt(u32)) return error.ArchiveTooLarge;

        entry.checksum = checksum.final();
        entry.digest = digest.finalResult();
        entry.size = @intCast(size);
        entry.size_compressed = @intCast(compressed);
    }

    fn deflate(archive: *Archive, reader: *std.Io.Reader, output: *std.Io.Writer) Error!u64 {
        assert(archive.entry_count < entry_count_max);
        assert(output.buffer.len > 8);

        var counting: Counting = .{ .count = 0, .inner = output, .writer = .{
            .vtable = &.{ .drain = Counting.drain },
            .buffer = &archive.compress_output,
        } };

        archive.compress = try .init(&counting.writer, &archive.window, .raw, .level_6);

        for (0..pass_count_max) |_| {
            const count = try reader.readSliceShort(&archive.chunk);
            if (count == 0) break;

            try archive.compress.writer.writeAll(archive.chunk[0..count]);
        } else return error.ArchiveTooLarge;

        try archive.compress.finish();
        try counting.writer.flush();

        return counting.count;
    }
};

const Counting = struct {
    count: u64,
    inner: *std.Io.Writer,
    writer: std.Io.Writer,

    fn drain(
        writer: *std.Io.Writer,
        data: []const []const u8,
        splat: usize,
    ) std.Io.Writer.Error!usize {
        assert(data.len > 0);
        assert(writer.buffer.len > 0);
        assert(splat <= std.math.maxInt(u32));

        const counting: *Counting = @alignCast(@fieldParentPtr("writer", writer));

        try counting.inner.writeAll(writer.buffered());
        counting.count += writer.end;
        writer.end = 0;

        var written: u64 = 0;

        for (data[0 .. data.len - 1]) |bytes| {
            try counting.inner.writeAll(bytes);
            written += bytes.len;
        }

        const pattern = data[data.len - 1];

        for (0..splat) |_| {
            try counting.inner.writeAll(pattern);
            written += pattern.len;
        }

        counting.count += written;

        assert(written <= std.math.maxInt(u32));

        return @intCast(written);
    }
};

const EndRecord = struct {
    directory_offset: u32,
    directory_size: u32,
    entry_count: u16,
};

fn end_record_write(output: *std.Io.Writer, record: EndRecord) std.Io.Writer.Error!void {
    assert(record.entry_count > 0);
    assert(record.entry_count <= entry_count_max);
    assert(output.buffer.len > 8);

    try output.writeInt(u32, signature_end, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u16, record.entry_count, .little);
    try output.writeInt(u16, record.entry_count, .little);
    try output.writeInt(u32, record.directory_size, .little);
    try output.writeInt(u32, record.directory_offset, .little);
    try output.writeInt(u16, 0, .little);
}

fn local_header_write(output: *std.Io.Writer, entry: *const Entry) std.Io.Writer.Error!void {
    assert(entry.name_length > 0);
    assert(entry.name_length <= name_bytes_max);

    try output.writeInt(u32, signature_local, .little);
    try output.writeInt(u16, version_needed, .little);
    try output.writeInt(u16, flag_utf8, .little);
    try output.writeInt(u16, method_deflate, .little);
    try output.writeInt(u16, time_dos, .little);
    try output.writeInt(u16, date_dos, .little);
    try output.writeInt(u32, entry.checksum, .little);
    try output.writeInt(u32, entry.size_compressed, .little);
    try output.writeInt(u32, entry.size, .little);
    try output.writeInt(u16, entry.name_length, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeAll(entry.name_slice());
}

fn central_header_write(output: *std.Io.Writer, entry: *const Entry) std.Io.Writer.Error!void {
    assert(entry.name_length > 0);
    assert(entry.name_length <= name_bytes_max);

    try output.writeInt(u32, signature_central, .little);
    try output.writeInt(u16, version_made_by, .little);
    try output.writeInt(u16, version_needed, .little);
    try output.writeInt(u16, flag_utf8, .little);
    try output.writeInt(u16, method_deflate, .little);
    try output.writeInt(u16, time_dos, .little);
    try output.writeInt(u16, date_dos, .little);
    try output.writeInt(u32, entry.checksum, .little);
    try output.writeInt(u32, entry.size_compressed, .little);
    try output.writeInt(u32, entry.size, .little);
    try output.writeInt(u16, entry.name_length, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u16, 0, .little);
    try output.writeInt(u32, external_attributes, .little);
    try output.writeInt(u32, entry.offset, .little);
    try output.writeAll(entry.name_slice());
}

test Archive {
    const archive = try std.testing.allocator.create(Archive);
    defer std.testing.allocator.destroy(archive);

    var buffer: [4096]u8 = undefined;
    var output: std.Io.Writer = .fixed(&buffer);
    const first = "hello hello hello hello\n";

    archive.init();

    const entry = try archive.add(std.testing.io, &output, "a/hello.txt", .{ .memory = first });

    _ = try archive.add(std.testing.io, &output, "empty", .{ .memory = "" });

    try archive.finish(&output);

    const written = output.buffered();

    try std.testing.expectEqual(@as(u32, 24), entry.size);
    try std.testing.expectEqual(std.hash.Crc32.hash(first), entry.checksum);
    try std.testing.expectEqualSlices(u8, "PK\x03\x04", written[0..4]);
    try std.testing.expectEqualSlices(u8, "PK\x05\x06", written[written.len - 22 ..][0..4]);

    const end = written[written.len - 22 ..];
    const directory_size = std.mem.readInt(u32, end[12..16], .little);
    const directory_offset = std.mem.readInt(u32, end[16..20], .little);

    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, end[10..12], .little));
    try std.testing.expectEqual(written.len - 22, directory_offset + directory_size);
    try std.testing.expectEqualSlices(u8, "PK\x01\x02", written[directory_offset..][0..4]);

    var round_trip: [64]u8 = undefined;
    var input: std.Io.Reader = .fixed(written[30 + "a/hello.txt".len ..][0..entry.size_compressed]);
    var window: [flate.max_window_len]u8 = undefined;
    var decompress: flate.Decompress = .init(&input, .raw, &window);
    const count = try decompress.reader.readSliceShort(&round_trip);

    try std.testing.expectEqualStrings(first, round_trip[0..count]);
}
