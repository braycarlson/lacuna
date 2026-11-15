const std = @import("std");

const assert = std.debug.assert;
const macho = std.macho;

pub const Error = error{
    ArchitectureRepeated,
    FileTooLarge,
    MachInvalid,
    OutOfMemory,
    Usage,
} || std.Io.Dir.ReadFileError || std.Io.Dir.WriteFileError;

pub const Slice = struct {
    bytes: []const u8,
    cpu_type: macho.cpu_type_t,
    cpu_subtype: macho.cpu_subtype_t,

    pub fn init(bytes: []const u8) Error!Slice {
        assert(bytes.len <= file_bytes_max);
        assert(@sizeOf(macho.mach_header_64) == 32);

        if (bytes.len < @sizeOf(macho.mach_header_64)) return error.MachInvalid;

        const magic = std.mem.readInt(u32, bytes[0..4], .little);
        if (magic != macho.MH_MAGIC_64) return error.MachInvalid;

        const result: Slice = .{
            .bytes = bytes,
            .cpu_type = std.mem.readInt(i32, bytes[4..8], .little),
            .cpu_subtype = std.mem.readInt(i32, bytes[8..12], .little),
        };

        assert(result.bytes.len >= @sizeOf(macho.mach_header_64));

        return result;
    }
};

const alignment_log2: u5 = 14;
const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};
const file_bytes_max: u32 = 1 << 28;
const slice_count_max: u32 = 4;

comptime {
    assert(@sizeOf(macho.fat_header) == 8);
    assert(@sizeOf(macho.fat_arch) == 20);
    assert(slice_count_max * (file_bytes_max + (1 << alignment_log2)) < std.math.maxInt(u32));
}

pub fn main(init: std.process.Init) Error!void {
    assert(init.minimal.args.vector.len > 0);
    assert(slice_count_max >= 2);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len < 4) return error.Usage;
    if (arguments.len > 2 + slice_count_max) return error.Usage;

    const cwd = std.Io.Dir.cwd();
    const inputs = arguments[2..];
    const arena = init.arena.allocator();

    var slices: [slice_count_max]Slice = undefined;

    for (inputs, 0..) |path, index| {
        const buffer = try arena.alloc(u8, file_bytes_max + 1);
        const bytes = try cwd.readFile(init.io, path, buffer);
        if (bytes.len > file_bytes_max) return error.FileTooLarge;

        slices[index] = try .init(bytes);
    }

    const output = try arena.alloc(u8, fat_size(slices[0..inputs.len]));

    try fat_write(output, slices[0..inputs.len]);
    const destination: std.Io.Dir.WriteFileOptions = .{
        .sub_path = arguments[1],
        .data = output,
        .flags = create_flags,
    };

    try cwd.writeFile(init.io, destination);
}

pub fn fat_size(slices: []const Slice) u32 {
    assert(slices.len >= 2);
    assert(slices.len <= slice_count_max);

    const header: u32 = header_bytes(@intCast(slices.len));

    var offset: u32 = header;

    for (slices) |slice| {
        offset = std.mem.alignForward(u32, offset, 1 << alignment_log2);
        offset += @intCast(slice.bytes.len);
    }

    assert(offset >= header);

    return offset;
}

fn header_bytes(count: u32) u32 {
    assert(count >= 2);
    assert(count <= slice_count_max);

    return @sizeOf(macho.fat_header) + count * @sizeOf(macho.fat_arch);
}

pub fn fat_write(output: []u8, slices: []const Slice) Error!void {
    assert(output.len == fat_size(slices));
    assert(slices.len >= 2);

    for (slices, 0..) |slice, index| {
        for (slices[index + 1 ..]) |other| {
            if (other.cpu_type == slice.cpu_type) return error.ArchitectureRepeated;
        }
    }

    @memset(output, 0);

    const count: u32 = @intCast(slices.len);

    std.mem.writeInt(u32, output[0..4], macho.FAT_MAGIC, .big);
    std.mem.writeInt(u32, output[4..8], count, .big);

    var offset: u32 = header_bytes(count);

    for (slices, 0..) |slice, index| {
        offset = std.mem.alignForward(u32, offset, 1 << alignment_log2);

        const entry = output[@sizeOf(macho.fat_header) + index * @sizeOf(macho.fat_arch) ..];
        const size: u32 = @intCast(slice.bytes.len);

        std.mem.writeInt(i32, entry[0..4], slice.cpu_type, .big);
        std.mem.writeInt(i32, entry[4..8], slice.cpu_subtype, .big);
        std.mem.writeInt(u32, entry[8..12], offset, .big);
        std.mem.writeInt(u32, entry[12..16], size, .big);
        std.mem.writeInt(u32, entry[16..20], alignment_log2, .big);

        @memcpy(output[offset..][0..size], slice.bytes);
        offset += size;
    }

    assert(offset == output.len);
}

fn test_slice_build(buffer: []u8, cpu_type: macho.cpu_type_t) Error!Slice {
    assert(buffer.len >= @sizeOf(macho.mach_header_64));
    assert(cpu_type != 0);

    @memset(buffer, 0xab);

    std.mem.writeInt(u32, buffer[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(i32, buffer[4..8], cpu_type, .little);
    std.mem.writeInt(i32, buffer[8..12], 3, .little);

    return Slice.init(buffer);
}

test fat_write {
    var arm: [40]u8 = undefined;
    var intel: [72]u8 = undefined;

    const slices = [_]Slice{
        try test_slice_build(&arm, macho.CPU_TYPE_ARM64),
        try test_slice_build(&intel, macho.CPU_TYPE_X86_64),
    };

    var output: [2 * (1 << alignment_log2) + 72]u8 = undefined;

    try std.testing.expectEqual(@as(u32, output.len), fat_size(&slices));

    try fat_write(&output, &slices);

    try std.testing.expectEqual(macho.FAT_MAGIC, std.mem.readInt(u32, output[0..4], .big));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, output[4..8], .big));

    for (slices, 0..) |slice, index| {
        const entry = output[8 + index * 20 ..];
        const offset = std.mem.readInt(u32, entry[8..12], .big);
        const size = std.mem.readInt(u32, entry[12..16], .big);

        try std.testing.expectEqual(slice.cpu_type, std.mem.readInt(i32, entry[0..4], .big));
        try std.testing.expectEqual(@as(u32, 0), offset % (1 << alignment_log2));
        try std.testing.expectEqualSlices(u8, slice.bytes, output[offset..][0..size]);

        const round = try Slice.init(output[offset..][0..size]);

        try std.testing.expectEqual(slice.cpu_subtype, round.cpu_subtype);
    }

    const repeated = [_]Slice{ slices[0], slices[0] };

    var repeated_output: [2 * (1 << alignment_log2) + 40]u8 = undefined;

    try std.testing.expectEqual(@as(u32, repeated_output.len), fat_size(&repeated));

    const outcome = fat_write(&repeated_output, &repeated);

    try std.testing.expectError(error.ArchitectureRepeated, outcome);
    try std.testing.expectError(error.MachInvalid, Slice.init(intel[4..]));
}
