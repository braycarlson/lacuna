const std = @import("std");

const assert = std.debug.assert;
const elf = std.elf;

pub const Error = error{
    DynamicMissing,
    ElfInvalid,
    FileTooLarge,
    OutOfMemory,
    StringTableMissing,
    Usage,
} || std.Io.Dir.ReadFileError || std.Io.Dir.WriteFileError;

pub const Image = struct {
    bytes: []u8,
    endian: std.lang.Endian,
    layout: *const Layout,

    const ProgramHeader = struct {
        kind: u32,
        offset: u64,
        size_file: u64,
        vaddr: u64,
    };

    pub fn init(bytes: []u8) Error!Image {
        assert(bytes.len <= file_bytes_max);
        assert(@sizeOf(elf.Elf64_Ehdr) == 64);

        if (bytes.len < @sizeOf(elf.Elf64_Ehdr)) return error.ElfInvalid;
        if (!std.mem.eql(u8, bytes[0..4], elf.MAGIC)) return error.ElfInvalid;
        const endian: std.lang.Endian = switch (bytes[elf.EI.DATA]) {
            @backingInt(elf.DATA.@"2LSB") => .little,
            @backingInt(elf.DATA.@"2MSB") => .big,
            else => return error.ElfInvalid,
        };

        const layout: *const Layout = switch (bytes[elf.EI.CLASS]) {
            @backingInt(elf.CLASS.@"32") => &layout_32,
            @backingInt(elf.CLASS.@"64") => &layout_64,
            else => return error.ElfInvalid,
        };

        const kind = std.mem.readInt(u16, bytes[16..18], endian);
        if (kind != @backingInt(elf.ET.DYN)) return error.ElfInvalid;
        return .{ .bytes = bytes, .endian = endian, .layout = layout };
    }

    pub fn needed_remove(image: *const Image, name: []const u8) Error!u32 {
        assert(name.len > 0);
        assert(image.bytes.len >= @sizeOf(elf.Elf64_Ehdr));

        const dynamic = try image.dynamic_find();
        const strings = try image.strings_offset(dynamic);
        const count: u32 = @intCast(@divFloor(dynamic.len, image.layout.dynamic_entry_bytes));

        var kept: u32 = 0;
        var removed: u32 = 0;

        for (0..count) |index| {
            const entry = image.entry_read(dynamic, @intCast(index));
            if (entry.tag == elf.DT_NULL) break;

            if (entry.tag == elf.DT_NEEDED) {
                if (image.string_matches(strings + entry.value, name)) {
                    removed += 1;

                    continue;
                }
            }

            image.entry_write(dynamic, kept, entry);
            kept += 1;
        }

        for (kept..kept + removed) |index| {
            image.entry_write(dynamic, @intCast(index), .{ .tag = elf.DT_NULL, .value = 0 });
        }

        assert(kept + removed <= count);

        return removed;
    }

    fn program_header(image: *const Image, index: u32) Error!ProgramHeader {
        assert(index < image.program_header_count());
        assert(image.bytes.len >= @sizeOf(elf.Elf64_Ehdr));

        const layout = image.layout;
        const at = layout.header_offset_offset;
        const table = image.word_read(image.bytes, at);
        const start = table + @as(u64, index) * layout.program_header_bytes;
        if (start + layout.program_header_bytes > image.bytes.len) return error.ElfInvalid;

        const header = image.bytes[@intCast(start)..][0..layout.program_header_bytes];

        return .{
            .kind = std.mem.readInt(u32, header[0..4], image.endian),
            .offset = image.word_read(header, layout.segment_offset_offset),
            .size_file = image.word_read(header, layout.segment_size_offset),
            .vaddr = image.word_read(header, layout.segment_vaddr_offset),
        };
    }

    fn word_read(image: *const Image, bytes: []const u8, at: u32) u64 {
        assert(bytes.len <= image.bytes.len);

        const image_start = @intFromPtr(image.bytes.ptr);
        const image_end = image_start + image.bytes.len;

        assert(@intFromPtr(bytes.ptr) >= image_start);
        assert(@intFromPtr(bytes.ptr) + bytes.len <= image_end);
        assert(at + @as(u32, if (image.layout.wide) 8 else 4) <= bytes.len);
        assert(at % 4 == 0);

        if (image.layout.wide) return std.mem.readInt(u64, bytes[at..][0..8], image.endian);
        return std.mem.readInt(u32, bytes[at..][0..4], image.endian);
    }

    fn program_header_count(image: *const Image) u32 {
        assert(image.bytes.len >= @sizeOf(elf.Elf64_Ehdr));

        const at = image.layout.header_count_offset;
        const count = std.mem.readInt(u16, image.bytes[at..][0..2], image.endian);

        assert(count <= std.math.maxInt(u16));

        return count;
    }

    fn dynamic_find(image: *const Image) Error![]u8 {
        assert(image.bytes.len >= @sizeOf(elf.Elf64_Ehdr));
        assert(image.bytes.len <= file_bytes_max);

        for (0..image.program_header_count()) |index| {
            const header = try image.program_header(@intCast(index));

            if (header.kind == @backingInt(elf.PT.DYNAMIC)) {
                if (header.offset + header.size_file > image.bytes.len) return error.ElfInvalid;
                return image.bytes[@intCast(header.offset)..][0..@intCast(header.size_file)];
            }
        }

        return error.DynamicMissing;
    }

    fn strings_offset(image: *const Image, dynamic: []const u8) Error!u64 {
        assert(dynamic.len % image.layout.dynamic_entry_bytes == 0);
        assert(dynamic.len <= image.bytes.len);

        const count: u32 = @intCast(@divExact(dynamic.len, image.layout.dynamic_entry_bytes));

        for (0..count) |index| {
            const entry = image.entry_read(dynamic, @intCast(index));
            if (entry.tag == elf.DT_STRTAB) return image.file_offset_of(entry.value);
        }

        return error.StringTableMissing;
    }

    fn file_offset_of(image: *const Image, address: u64) Error!u64 {
        assert(image.bytes.len >= @sizeOf(elf.Elf64_Ehdr));
        assert(address <= std.math.maxInt(u64));

        for (0..image.program_header_count()) |index| {
            const header = try image.program_header(@intCast(index));
            if (header.kind != @backingInt(elf.PT.LOAD)) continue;
            if (address < header.vaddr) continue;
            if (address >= header.vaddr + header.size_file) continue;

            const result = address - header.vaddr + header.offset;

            assert(result < image.bytes.len);

            return result;
        }

        return error.ElfInvalid;
    }

    fn string_matches(image: *const Image, start: u64, name: []const u8) bool {
        assert(name.len > 0);
        assert(start <= std.math.maxInt(u64) - @as(u64, name.len));

        if (start + name.len >= image.bytes.len) return false;

        const candidate = image.bytes[@intCast(start)..][0 .. name.len + 1];
        if (candidate[name.len] != 0) return false;
        return std.mem.eql(u8, candidate[0..name.len], name);
    }

    fn entry_read(image: *const Image, dynamic: []const u8, index: u32) Dynamic {
        const size = image.layout.dynamic_entry_bytes;

        assert(index < entry_count_max);
        assert((@as(usize, index) + 1) * size <= dynamic.len);

        const start = @as(usize, index) * size;
        const half = @divExact(size, 2);

        if (image.layout.wide) {
            return .{
                .tag = std.mem.readInt(i64, dynamic[start..][0..8], image.endian),
                .value = std.mem.readInt(u64, dynamic[start + half ..][0..8], image.endian),
            };
        }

        return .{
            .tag = std.mem.readInt(i32, dynamic[start..][0..4], image.endian),
            .value = std.mem.readInt(u32, dynamic[start + half ..][0..4], image.endian),
        };
    }

    fn entry_write(image: *const Image, dynamic: []u8, index: u32, entry: Dynamic) void {
        const size = image.layout.dynamic_entry_bytes;

        assert(index < entry_count_max);
        assert((@as(usize, index) + 1) * size <= dynamic.len);
        assert(entry.tag >= 0);

        const start = @as(usize, index) * size;
        const half = @divExact(size, 2);

        if (image.layout.wide) {
            std.mem.writeInt(i64, dynamic[start..][0..8], entry.tag, image.endian);
            std.mem.writeInt(u64, dynamic[start + half ..][0..8], entry.value, image.endian);
        } else {
            std.mem.writeInt(i32, dynamic[start..][0..4], @intCast(entry.tag), image.endian);
            const value: u32 = @intCast(entry.value);

            std.mem.writeInt(u32, dynamic[start + half ..][0..4], value, image.endian);
        }

        assert(image.entry_read(dynamic, index).tag == entry.tag);
    }
};

pub const Dynamic = struct {
    tag: i64,
    value: u64,
};

pub const Layout = struct {
    dynamic_entry_bytes: u32,
    header_count_offset: u32,
    header_offset_offset: u32,
    program_header_bytes: u32,
    segment_offset_offset: u32,
    segment_size_offset: u32,
    segment_vaddr_offset: u32,
    wide: bool,
};

pub const entry_count_max: u32 = 4096;
pub const file_bytes_max: u32 = 256 * 1024 * 1024;

const layout_32: Layout = .{
    .dynamic_entry_bytes = 8,
    .header_count_offset = 44,
    .header_offset_offset = 28,
    .program_header_bytes = 32,
    .segment_offset_offset = 4,
    .segment_size_offset = 16,
    .segment_vaddr_offset = 8,
    .wide = false,
};

const layout_64: Layout = .{
    .dynamic_entry_bytes = 16,
    .header_count_offset = 56,
    .header_offset_offset = 32,
    .program_header_bytes = 56,
    .segment_offset_offset = 8,
    .segment_size_offset = 32,
    .segment_vaddr_offset = 16,
    .wide = true,
};

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .executable_file,
    .resolve_beneath = false,
};

comptime {
    assert(@sizeOf(elf.Elf64_Dyn) == layout_64.dynamic_entry_bytes);
    assert(@sizeOf(elf.Elf32_Dyn) == layout_32.dynamic_entry_bytes);
    assert(@sizeOf(elf.Elf64.Phdr) == layout_64.program_header_bytes);
    assert(@sizeOf(elf.Elf32.Phdr) == layout_32.program_header_bytes);
}

pub fn main(init: std.process.Init) Error!void {
    assert(file_bytes_max > layout_64.program_header_bytes);
    assert(init.minimal.args.vector.len > 0);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len != 4) return error.Usage;

    const buffer = try init.gpa.alloc(u8, file_bytes_max + 1);
    defer init.gpa.free(buffer);

    const cwd = std.Io.Dir.cwd();
    const bytes = try cwd.readFile(init.io, arguments[1], buffer);
    if (bytes.len > file_bytes_max) return error.FileTooLarge;

    const image: Image = try .init(bytes);
    const removed = try image.needed_remove(arguments[3]);

    assert(removed <= entry_count_max);

    try cwd.writeFile(init.io, .{ .sub_path = arguments[2], .data = bytes, .flags = create_flags });
}

const TestHeader = struct {
    index: u32,
    kind: u32,
    offset: u64,
    size: u64,
};

const TestImage = struct {
    bytes: [0x400]u8,
    endian: std.lang.Endian,
    layout: *const Layout,

    fn header_write(image: *TestImage, header: TestHeader) void {
        assert(header.kind != 0);
        assert(header.index < 4);

        const layout = image.layout;
        const start = 0x40 + header.index * layout.program_header_bytes;
        const slot = image.bytes[start..][0..layout.program_header_bytes];

        const word: TestWord = .{ .endian = image.endian, .wide = layout.wide };

        std.mem.writeInt(u32, slot[0..4], header.kind, image.endian);
        test_word_write(slot, layout.segment_offset_offset, word, header.offset);
        test_word_write(slot, layout.segment_vaddr_offset, word, header.offset);
        test_word_write(slot, layout.segment_size_offset, word, header.size);
    }
};

const TestWord = struct {
    endian: std.lang.Endian,
    wide: bool,
};

fn test_word_write(bytes: []u8, at: u32, word: TestWord, value: u64) void {
    assert(word.wide or value <= std.math.maxInt(u32));
    assert(at % 4 == 0);
    assert(at + @as(u32, if (word.wide) 8 else 4) <= bytes.len);

    if (word.wide) {
        std.mem.writeInt(u64, bytes[at..][0..8], value, word.endian);
    } else {
        std.mem.writeInt(u32, bytes[at..][0..4], @intCast(value), word.endian);
    }
}

fn test_image_build(image: *TestImage, class: elf.CLASS) void {
    const layout = image.layout;

    assert(class != .NONE);
    assert(layout.program_header_bytes > 0);

    image.bytes = @splat(0);

    @memcpy(image.bytes[0..4], elf.MAGIC);
    image.bytes[elf.EI.CLASS] = @backingInt(class);
    image.bytes[elf.EI.DATA] = switch (image.endian) {
        .little => @backingInt(elf.DATA.@"2LSB"),
        .big => @backingInt(elf.DATA.@"2MSB"),
    };

    const word: TestWord = .{ .endian = image.endian, .wide = layout.wide };
    const count_bytes = image.bytes[layout.header_count_offset..][0..2];

    std.mem.writeInt(u16, image.bytes[16..18], @backingInt(elf.ET.DYN), image.endian);
    test_word_write(&image.bytes, layout.header_offset_offset, word, 0x40);
    std.mem.writeInt(u16, count_bytes, 2, image.endian);

    image.header_write(.{ .index = 0, .kind = 1, .offset = 0, .size = 0x400 });

    image.header_write(.{
        .index = 1,
        .kind = 2,
        .offset = 0x200,
        .size = 5 * layout.dynamic_entry_bytes,
    });

    @memcpy(image.bytes[0x300..][0..17], "\x00libc.so\x00libm.so\x00");
}

test Image {
    const Case = struct { class: elf.CLASS, endian: std.lang.Endian, layout: *const Layout };

    const cases = [_]Case{
        .{ .class = .@"32", .endian = .little, .layout = &layout_32 },
        .{ .class = .@"64", .endian = .little, .layout = &layout_64 },
        .{ .class = .@"32", .endian = .big, .layout = &layout_32 },
        .{ .class = .@"64", .endian = .big, .layout = &layout_64 },
    };

    for (cases) |case| {
        var built: TestImage = .{
            .bytes = undefined,
            .endian = case.endian,
            .layout = case.layout,
        };

        test_image_build(&built, case.class);

        const size = case.layout.dynamic_entry_bytes;
        const dynamic = built.bytes[0x200..][0 .. 5 * size];
        const image: Image = try .init(&built.bytes);

        image.entry_write(dynamic, 0, .{ .tag = elf.DT_NEEDED, .value = 1 });
        image.entry_write(dynamic, 1, .{ .tag = elf.DT_NEEDED, .value = 9 });
        image.entry_write(dynamic, 2, .{ .tag = elf.DT_STRTAB, .value = 0x300 });
        image.entry_write(dynamic, 3, .{ .tag = elf.DT_NULL, .value = 0 });

        try std.testing.expectEqual(@as(u32, 1), try image.needed_remove("libc.so"));
        try std.testing.expectEqual(@as(u64, 9), image.entry_read(dynamic, 0).value);
        try std.testing.expectEqual(elf.DT_STRTAB, image.entry_read(dynamic, 1).tag);
        try std.testing.expectEqual(elf.DT_NULL, image.entry_read(dynamic, 2).tag);
        try std.testing.expectEqual(@as(u32, 0), try image.needed_remove("libc.so"));
        try std.testing.expectError(error.ElfInvalid, Image.init(built.bytes[0..16]));
    }
}
