const std = @import("std");

const needed = @import("needed.zig");

const assert = std.debug.assert;
const macho = std.macho;

pub const Error = error{
    BinaryInvalid,
    DependenciesTooMany,
    PolicyInvalid,
    PolicyUnknown,
} || needed.Error;

pub const Check = struct {
    allowed: []const []const u8,
    dependencies: []const []const u8,
    policy: []const []const u8,
    rule: Rule,
};

pub const Dependencies = struct {
    names: [dependency_count_max][]const u8,
    count: u32,

    pub const empty: Dependencies = .{ .names = undefined, .count = 0 };

    pub fn slice(dependencies: *const Dependencies) []const []const u8 {
        assert(dependencies.count <= dependency_count_max);
        assert(dependencies.names.len == dependency_count_max);

        return dependencies.names[0..dependencies.count];
    }

    fn add(dependencies: *Dependencies, name: []const u8) Error!void {
        assert(dependencies.count <= dependency_count_max);
        assert(name.len <= file_bytes_max);

        if (name.len == 0) return error.BinaryInvalid;
        if (dependencies.count == dependency_count_max) return error.DependenciesTooMany;

        dependencies.names[dependencies.count] = name;
        dependencies.count += 1;
    }
};

pub const Libraries = struct {
    names: [library_count_max][]const u8,
    count: u32,

    pub const empty: Libraries = .{ .names = undefined, .count = 0 };

    pub fn slice(libraries: *const Libraries) []const []const u8 {
        assert(libraries.count <= library_count_max);
        assert(libraries.names.len == library_count_max);

        return libraries.names[0..libraries.count];
    }
};

pub const Rule = union(enum) {
    android: u32,
    macos,
    manylinux: Version,
    musllinux: Version,
    windows,
};

pub const Version = struct {
    major: u32,
    minor: u32,

    fn at_most(version: Version, bound: struct { limit: Version }) bool {
        assert(version.major <= version_part_max);
        assert(bound.limit.major <= version_part_max);

        if (version.major != bound.limit.major) return version.major < bound.limit.major;
        return version.minor <= bound.limit.minor;
    }
};

const Directory = struct {
    address: u32,
    size: u32,
};

const Portable = struct {
    base: u64,
    bytes: []const u8,
    delayed: Directory,
    imports: Directory,
    sections: []const u8,

    fn init(bytes: []const u8) Error!Portable {
        assert(bytes.len <= file_bytes_max);
        assert(section_bytes == 40);

        if (bytes.len < 0x40) return error.BinaryInvalid;

        const header = std.mem.readInt(u32, bytes[0x3c..0x40], .little);
        if (header > bytes.len - 24) return error.BinaryInvalid;
        if (!std.mem.eql(u8, bytes[header..][0..4], "PE\x00\x00")) return error.BinaryInvalid;

        const coff = bytes[header + 4 ..][0..20];
        const section_count = std.mem.readInt(u16, coff[2..4], .little);
        const optional_size = std.mem.readInt(u16, coff[16..18], .little);
        const optional_start = header + 24;
        if (optional_size > bytes.len - optional_start) return error.BinaryInvalid;
        if (section_count > section_count_max) return error.BinaryInvalid;

        const optional = bytes[optional_start..][0..optional_size];
        const sections_start = optional_start + optional_size;
        const sections_size = @as(u32, section_count) * section_bytes;
        if (sections_size > bytes.len - sections_start) return error.BinaryInvalid;

        const layout = try layout_of(optional);

        return .{
            .base = layout.image_base,
            .bytes = bytes,
            .delayed = directory_of(optional, layout, directory_delayed),
            .imports = directory_of(optional, layout, directory_imports),
            .sections = bytes[sections_start..][0..sections_size],
        };
    }

    fn offset_of(image: *const Portable, address: u32) Error!u32 {
        assert(address != 0);
        assert(image.sections.len % section_bytes == 0);
        assert(image.bytes.len <= file_bytes_max);

        for (0..@divExact(image.sections.len, section_bytes)) |index| {
            const section = image.sections[index * section_bytes ..][0..section_bytes];
            const virtual_size = std.mem.readInt(u32, section[8..12], .little);
            const virtual_address = std.mem.readInt(u32, section[12..16], .little);
            const raw_size = std.mem.readInt(u32, section[16..20], .little);
            const raw_offset = std.mem.readInt(u32, section[20..24], .little);

            if (address < virtual_address) continue;
            if (address - virtual_address >= @max(virtual_size, raw_size)) continue;

            const delta = address - virtual_address;
            if (delta >= raw_size) return error.BinaryInvalid;

            const result = std.math.add(u32, raw_offset, delta) catch return error.BinaryInvalid;
            if (result >= image.bytes.len) return error.BinaryInvalid;
            return result;
        }

        return error.BinaryInvalid;
    }

    fn string_at(image: *const Portable, address: u32) Error![]const u8 {
        assert(address != 0);
        assert(image.bytes.len <= file_bytes_max);
        assert(image.sections.len % section_bytes == 0);

        const start = try image.offset_of(address);
        const rest = image.bytes[start..];
        const length = std.mem.findScalar(u8, rest, 0) orelse return error.BinaryInvalid;

        return rest[0..length];
    }

    fn imports_collect(image: *const Portable, dependencies: *Dependencies) Error!void {
        assert(image.bytes.len <= file_bytes_max);
        assert(dependencies.count <= dependency_count_max);

        if (image.imports.address == 0) return;

        const start = try image.offset_of(image.imports.address);

        for (0..dependency_count_max + 1) |index| {
            const at = start + index * 20;
            if (at + 20 > image.bytes.len) return error.BinaryInvalid;

            const descriptor = image.bytes[at..][0..20];
            if (std.mem.allEqual(u8, descriptor, 0)) return;

            const name = std.mem.readInt(u32, descriptor[12..16], .little);
            if (name == 0) return error.BinaryInvalid;

            try dependencies.add(try image.string_at(name));
        }

        return error.DependenciesTooMany;
    }

    fn delayed_collect(image: *const Portable, dependencies: *Dependencies) Error!void {
        assert(image.bytes.len <= file_bytes_max);
        assert(dependencies.count <= dependency_count_max);

        if (image.delayed.address == 0) return;

        const start = try image.offset_of(image.delayed.address);

        for (0..dependency_count_max + 1) |index| {
            const at = start + index * 32;
            if (at + 32 > image.bytes.len) return error.BinaryInvalid;

            const descriptor = image.bytes[at..][0..32];
            if (std.mem.allEqual(u8, descriptor, 0)) return;

            try dependencies.add(try image.string_at(try image.relative_of(descriptor)));
        }

        return error.DependenciesTooMany;
    }

    fn relative_of(image: *const Portable, descriptor: *const [32]u8) Error!u32 {
        assert(image.bytes.len <= file_bytes_max);
        assert(image.sections.len % section_bytes == 0);

        const attributes = std.mem.readInt(u32, descriptor[0..4], .little);
        const name = std.mem.readInt(u32, descriptor[4..8], .little);
        if (name == 0) return error.BinaryInvalid;
        if (attributes & 1 != 0) return name;
        if (name < image.base) return error.BinaryInvalid;

        const relative = std.math.cast(u32, name - image.base) orelse {
            return error.BinaryInvalid;
        };

        if (relative == 0) return error.BinaryInvalid;

        assert(relative <= name);

        return relative;
    }
};

const Layout = struct {
    directories_offset: u32,
    directory_count_offset: u32,
    image_base: u64,
};

pub const dependency_count_max: u32 = 256;
pub const file_bytes_max: u32 = needed.file_bytes_max;

const allowed_count_max: u32 = 64;
const library_count_max: u32 = 64;
const command_count_max: u32 = 4096;
const directory_delayed: u32 = 13;
const directory_imports: u32 = 1;
const policies_text = @embedFile("policy.json");
const section_bytes: u32 = 40;
const section_count_max: u32 = 96;
const slice_count_max: u32 = 4;
const version_part_max: u32 = 1 << 16;

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .executable_file,
    .resolve_beneath = false,
};

const windows_system = [_][]const u8{
    "advapi32.dll",
    "bcrypt.dll",
    "bcryptprimitives.dll",
    "cfgmgr32.dll",
    "comctl32.dll",
    "comdlg32.dll",
    "crypt32.dll",
    "d2d1.dll",
    "d3d11.dll",
    "d3d12.dll",
    "dbghelp.dll",
    "dnsapi.dll",
    "dwmapi.dll",
    "dwrite.dll",
    "dxgi.dll",
    "gdi32.dll",
    "gdiplus.dll",
    "hid.dll",
    "imm32.dll",
    "iphlpapi.dll",
    "kernel32.dll",
    "kernelbase.dll",
    "mpr.dll",
    "msimg32.dll",
    "msvcrt.dll",
    "mswsock.dll",
    "ncrypt.dll",
    "netapi32.dll",
    "normaliz.dll",
    "ntdll.dll",
    "ole32.dll",
    "oleaut32.dll",
    "opengl32.dll",
    "powrprof.dll",
    "psapi.dll",
    "rpcrt4.dll",
    "secur32.dll",
    "setupapi.dll",
    "shell32.dll",
    "shlwapi.dll",
    "ucrtbase.dll",
    "user32.dll",
    "userenv.dll",
    "uxtheme.dll",
    "vcruntime140.dll",
    "vcruntime140_1.dll",
    "version.dll",
    "winhttp.dll",
    "wininet.dll",
    "winmm.dll",
    "wintrust.dll",
    "ws2_32.dll",
    "wsock32.dll",
};

comptime {
    assert(@backingInt(macho.LC.LOAD_DYLIB) == 0xc);
    assert(@sizeOf(macho.mach_header_64) == 32);
    assert(@sizeOf(macho.dylib_command) == 24);
    assert(@sizeOf(macho.fat_arch) == 20);
    assert(windows_system.len < allowed_count_max);
}

pub fn main(init: std.process.Init) Error!void {
    assert(init.minimal.args.vector.len > 0);
    assert(dependency_count_max > 0);

    const arena = init.arena.allocator();
    const arguments = init.minimal.args.toSlice(arena) catch return error.Usage;
    if (arguments.len < 5) return error.Usage;
    if (arguments.len - 5 > allowed_count_max) return error.Usage;

    const rule = rule_of(arguments[4]) orelse return error.PolicyUnknown;

    var libraries: Libraries = .empty;

    try policy_libraries(arena, rule, &libraries);
    const buffer = try arena.alloc(u8, file_bytes_max + 1);
    const cwd = std.Io.Dir.cwd();
    const bytes = try cwd.readFile(init.io, arguments[1], buffer);
    if (bytes.len > file_bytes_max) return error.FileTooLarge;

    var dependencies: Dependencies = .empty;
    var allowed: [allowed_count_max][]const u8 = undefined;

    try dependencies_read(bytes, &dependencies);

    for (arguments[5..], 0..) |name, index| {
        allowed[index] = name;
    }

    const check: Check = .{
        .allowed = allowed[0 .. arguments.len - 5],
        .dependencies = dependencies.slice(),
        .policy = libraries.slice(),
        .rule = rule,
    };

    if (refused_first(&check)) |library| {
        std.debug.print(
            "lacuna: {s} for {s} needs {s}, which that platform does not guarantee; link it " ++
                "statically, or name it in libraries_allowed if each target machine provides it\n",
            .{ arguments[3], arguments[4], library },
        );

        std.process.exit(1);
    }

    const destination: std.Io.Dir.WriteFileOptions = .{
        .sub_path = arguments[2],
        .data = bytes,
        .flags = create_flags,
    };

    try cwd.writeFile(init.io, destination);
}

pub fn rule_of(tag: []const u8) ?Rule {
    assert(tag.len > 0);
    assert(tag.len <= file_bytes_max);

    const first = tag[0 .. std.mem.findScalar(u8, tag, '.') orelse tag.len];

    if (std.mem.eql(u8, first, "win32")) return .windows;
    if (std.mem.startsWith(u8, first, "win_")) return .windows;
    if (std.mem.startsWith(u8, first, "macosx_")) return .macos;

    if (std.mem.startsWith(u8, first, "android_")) {
        const version = version_parse(first["android_".len..]) orelse return null;
        return .{ .android = version.major };
    }

    if (std.mem.startsWith(u8, first, "manylinux_")) {
        return .{ .manylinux = version_parse(first["manylinux_".len..]) orelse return null };
    }

    if (std.mem.startsWith(u8, first, "musllinux_")) {
        return .{ .musllinux = version_parse(first["musllinux_".len..]) orelse return null };
    }

    return null;
}

fn version_parse(text: []const u8) ?Version {
    assert(text.len <= file_bytes_max);
    assert(version_part_max > 0);

    var parts = std.mem.splitScalar(u8, text, '_');

    const major = std.fmt.parseUnsigned(u32, parts.first(), 10) catch return null;
    const minor_text = parts.next() orelse "0";
    const minor = std.fmt.parseUnsigned(u32, minor_text, 10) catch 0;
    if (major > version_part_max) return null;
    return .{ .major = major, .minor = @min(minor, version_part_max) };
}

pub fn policy_libraries(arena: std.mem.Allocator, rule: Rule, libraries: *Libraries) Error!void {
    assert(policies_text.len > 0);
    assert(libraries.count == 0);
    if (rule == .android) assert(rule.android <= version_part_max);

    const prefix, const limit = switch (rule) {
        .android => |level| .{ "android_", Version{ .major = level, .minor = 0 } },
        .manylinux => |version| .{ "manylinux_", version },
        .musllinux => |version| .{ "musllinux_", version },
        .macos, .windows => return,
    };

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, policies_text, .{
        .allocate = .alloc_if_needed,
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .max_value_len = policies_text.len,
        .parse_numbers = false,
    }) catch return error.PolicyInvalid;

    if (parsed != .object) return error.PolicyInvalid;

    var best: ?Version = null;
    var chosen: ?std.json.Value = null;

    for (parsed.object.keys(), parsed.object.values()) |name, entries| {
        if (!std.mem.startsWith(u8, name, prefix)) continue;

        const version = version_parse(name[prefix.len..]) orelse return error.PolicyInvalid;
        if (!version.at_most(.{ .limit = limit })) continue;

        if (best) |known| {
            if (version.at_most(.{ .limit = known })) continue;
        }

        best = version;
        chosen = entries;
    }

    const listed = chosen orelse return error.PolicyUnknown;
    if (listed != .array) return error.PolicyInvalid;

    try policy_names(listed.array.items, libraries);
}

fn policy_names(items: []const std.json.Value, libraries: *Libraries) Error!void {
    assert(policies_text.len > 0);
    assert(libraries.count == 0);

    if (items.len > library_count_max) return error.PolicyInvalid;

    for (items, libraries.names[0..items.len]) |item, *name| {
        if (item != .string) return error.PolicyInvalid;
        if (item.string.len == 0) return error.PolicyInvalid;

        name.* = item.string;
    }

    libraries.count = @intCast(items.len);
}

pub fn dependencies_read(bytes: []u8, dependencies: *Dependencies) Error!void {
    assert(bytes.len <= file_bytes_max);
    assert(dependencies.count == 0);

    if (bytes.len < 4) return error.BinaryInvalid;

    if (std.mem.eql(u8, bytes[0..4], std.elf.MAGIC)) {
        const image: needed.Image = try .init(bytes);

        dependencies.count = image.needed_collect(&dependencies.names) catch |err| switch (err) {
            error.DynamicMissing => 0,
            else => return err,
        };

        return;
    }

    if (std.mem.eql(u8, bytes[0..2], "MZ")) {
        const image: Portable = try .init(bytes);

        try image.imports_collect(dependencies);
        try image.delayed_collect(dependencies);

        return;
    }

    const magic_big = std.mem.readInt(u32, bytes[0..4], .big);
    const magic_little = std.mem.readInt(u32, bytes[0..4], .little);

    if (magic_big == macho.FAT_MAGIC) return fat_read(bytes, dependencies);
    if (magic_little == macho.MH_MAGIC_64) return macho_read(bytes, dependencies);
    return error.BinaryInvalid;
}

fn fat_read(bytes: []const u8, dependencies: *Dependencies) Error!void {
    assert(bytes.len >= 4);
    assert(std.mem.readInt(u32, bytes[0..4], .big) == macho.FAT_MAGIC);

    if (bytes.len < 8) return error.BinaryInvalid;

    const count = std.mem.readInt(u32, bytes[4..8], .big);
    if (count == 0) return error.BinaryInvalid;
    if (count > slice_count_max) return error.BinaryInvalid;
    if (bytes.len < 8 + count * 20) return error.BinaryInvalid;

    for (0..count) |index| {
        const entry = bytes[8 + index * 20 ..][0..20];
        const offset = std.mem.readInt(u32, entry[8..12], .big);
        const size = std.mem.readInt(u32, entry[12..16], .big);
        if (offset > bytes.len) return error.BinaryInvalid;
        if (size > bytes.len - offset) return error.BinaryInvalid;

        const slice = bytes[offset..][0..size];
        if (slice.len < 4) return error.BinaryInvalid;
        if (std.mem.readInt(u32, slice[0..4], .little) != macho.MH_MAGIC_64) {
            return error.BinaryInvalid;
        }

        try macho_read(slice, dependencies);
    }
}

fn macho_read(bytes: []const u8, dependencies: *Dependencies) Error!void {
    assert(bytes.len >= 4);
    assert(std.mem.readInt(u32, bytes[0..4], .little) == macho.MH_MAGIC_64);

    const start = @sizeOf(macho.mach_header_64);
    if (bytes.len < start) return error.BinaryInvalid;

    const count = std.mem.readInt(u32, bytes[16..20], .little);
    const size = std.mem.readInt(u32, bytes[20..24], .little);
    if (count > command_count_max) return error.BinaryInvalid;
    if (size > bytes.len - start) return error.BinaryInvalid;

    const commands = bytes[start..][0..size];

    var offset: u32 = 0;

    for (0..count) |_| {
        if (commands.len - offset < 8) return error.BinaryInvalid;

        const command_size = std.mem.readInt(u32, commands[offset + 4 ..][0..4], .little);
        if (command_size < 8) return error.BinaryInvalid;
        if (command_size > commands.len - offset) return error.BinaryInvalid;

        const loaded = commands[offset..][0..command_size];

        if (dylib_loaded(loaded)) try dependencies.add(try dylib_name(loaded));

        offset += command_size;
    }

    assert(offset <= commands.len);
}

fn dylib_loaded(command: []const u8) bool {
    assert(command.len >= 8);
    assert(command.len <= file_bytes_max);

    const kind = std.mem.readInt(u32, command[0..4], .little);

    const loads = [_]macho.LC{
        .LAZY_LOAD_DYLIB,
        .LOAD_DYLIB,
        .LOAD_UPWARD_DYLIB,
        .LOAD_WEAK_DYLIB,
        .REEXPORT_DYLIB,
    };

    for (loads) |load| {
        if (kind == @backingInt(load)) return true;
    }

    return false;
}

fn dylib_name(command: []const u8) Error![]const u8 {
    assert(command.len >= 8);
    assert(command.len <= file_bytes_max);

    if (command.len < @sizeOf(macho.dylib_command)) return error.BinaryInvalid;

    const offset = std.mem.readInt(u32, command[8..12], .little);
    if (offset < @sizeOf(macho.dylib_command)) return error.BinaryInvalid;
    if (offset >= command.len) return error.BinaryInvalid;

    const rest = command[offset..];
    const length = std.mem.findScalar(u8, rest, 0) orelse return error.BinaryInvalid;

    return rest[0..length];
}

fn layout_of(optional: []const u8) Error!Layout {
    assert(optional.len <= file_bytes_max);
    assert(directory_delayed > directory_imports);

    if (optional.len < 2) return error.BinaryInvalid;

    const wide = switch (std.mem.readInt(u16, optional[0..2], .little)) {
        0x10b => false,
        0x20b => true,
        else => return error.BinaryInvalid,
    };

    const directories_offset: u32 = if (wide) 112 else 96;
    if (optional.len < directories_offset) return error.BinaryInvalid;

    const image_base: u64 = if (wide)
        std.mem.readInt(u64, optional[24..32], .little)
    else
        std.mem.readInt(u32, optional[28..32], .little);

    return .{
        .directories_offset = directories_offset,
        .directory_count_offset = directories_offset - 4,
        .image_base = image_base,
    };
}

fn directory_of(optional: []const u8, layout: Layout, index: u32) Directory {
    assert(optional.len >= layout.directories_offset);
    assert(index <= directory_delayed);

    const count = std.mem.readInt(u32, optional[layout.directory_count_offset..][0..4], .little);
    const at = layout.directories_offset + index * 8;
    if (index >= count) return .{ .address = 0, .size = 0 };
    if (at + 8 > optional.len) return .{ .address = 0, .size = 0 };

    return .{
        .address = std.mem.readInt(u32, optional[at..][0..4], .little),
        .size = std.mem.readInt(u32, optional[at + 4 ..][0..4], .little),
    };
}

pub fn refused_first(check: *const Check) ?[]const u8 {
    assert(check.dependencies.len <= dependency_count_max);
    assert(check.allowed.len <= allowed_count_max);

    for (check.dependencies) |name| {
        if (allowed_contains(check, name)) continue;
        if (!admitted(check.rule, check.policy, name)) return name;
    }

    return null;
}

fn allowed_contains(check: *const Check, name: []const u8) bool {
    assert(name.len > 0);
    assert(check.allowed.len <= allowed_count_max);

    for (check.allowed) |allowed| {
        if (check.rule == .windows) {
            if (std.ascii.eqlIgnoreCase(allowed, name)) return true;
        } else {
            if (std.mem.eql(u8, allowed, name)) return true;
        }
    }

    return false;
}

pub fn admitted(rule: Rule, policy: []const []const u8, name: []const u8) bool {
    assert(name.len > 0);
    assert(policy.len <= dependency_count_max);

    if (rule == .macos) assert(policy.len == 0);
    if (rule == .windows) assert(policy.len == 0);

    const special = switch (rule) {
        .android => python_library(name),
        .macos => return macos_system(name),
        .manylinux => glibc_loader(name),
        .musllinux => std.mem.startsWith(u8, name, "ld-musl-"),
        .windows => return windows_admitted(name),
    };

    if (special) return true;
    return names_contain(policy, name);
}

fn glibc_loader(name: []const u8) bool {
    assert(name.len > 0);
    assert(name.len <= file_bytes_max);

    if (std.mem.find(u8, name, "ld-linux") != null) return true;
    if (std.mem.eql(u8, name, "ld64.so.1")) return true;
    return std.mem.eql(u8, name, "ld64.so.2");
}

fn python_library(name: []const u8) bool {
    assert(name.len > 0);
    assert(name.len <= file_bytes_max);

    if (std.mem.eql(u8, name, "libpython3.so")) return true;
    if (!std.mem.startsWith(u8, name, "libpython3.")) return false;

    const rest = name["libpython3.".len..];
    const dot = std.mem.findScalar(u8, rest, '.') orelse return false;
    if (dot == 0) return false;

    for (rest[0..dot]) |character| {
        if (!std.ascii.isDigit(character)) return false;
    }

    return std.mem.startsWith(u8, rest[dot..], ".so");
}

fn macos_system(name: []const u8) bool {
    assert(name.len > 0);
    assert(name.len <= file_bytes_max);

    if (std.mem.startsWith(u8, name, "/usr/lib/")) return true;
    return std.mem.startsWith(u8, name, "/System/");
}

fn windows_admitted(name: []const u8) bool {
    assert(name.len > 0);
    assert(windows_system.len > 0);

    var buffer: [256]u8 = undefined;
    if (name.len > buffer.len) return false;

    const lower = std.ascii.lowerString(&buffer, name);

    if (std.mem.startsWith(u8, lower, "api-ms-win-")) return true;
    if (std.mem.startsWith(u8, lower, "ext-ms-")) return true;
    if (python_dll(lower)) return true;
    if (pypy_dll(lower)) return true;
    return names_contain(&windows_system, lower);
}

fn pypy_dll(lower: []const u8) bool {
    assert(lower.len > 0);
    assert(lower.len <= 256);

    if (lower.len < "libpypy3-c.dll".len) return false;
    if (!std.mem.startsWith(u8, lower, "libpypy3")) return false;
    if (!std.mem.endsWith(u8, lower, "-c.dll")) return false;

    const middle = lower["libpypy3".len .. lower.len - "-c.dll".len];
    if (middle.len == 0) return true;
    if (middle[0] != '.') return false;
    if (middle.len < 2) return false;
    if (middle.len > 3) return false;

    for (middle[1..]) |character| {
        if (!std.ascii.isDigit(character)) return false;
    }

    return true;
}

fn python_dll(lower: []const u8) bool {
    assert(lower.len > 0);
    assert(lower.len <= 256);

    if (lower.len < "python3.dll".len) return false;
    if (!std.mem.startsWith(u8, lower, "python3")) return false;
    if (!std.mem.endsWith(u8, lower, ".dll")) return false;

    const middle = lower["python3".len .. lower.len - ".dll".len];
    const digits = if (std.mem.endsWith(u8, middle, "t")) middle[0 .. middle.len - 1] else middle;
    if (digits.len > 2) return false;

    for (digits) |character| {
        if (!std.ascii.isDigit(character)) return false;
    }

    return true;
}

fn names_contain(names: []const []const u8, name: []const u8) bool {
    assert(name.len > 0);
    assert(names.len <= dependency_count_max);

    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) return true;
    }

    return false;
}

test rule_of {
    const glibc = rule_of("manylinux_2_17_x86_64.manylinux2014_x86_64").?.manylinux;
    const musl = rule_of("musllinux_1_2_i686").?.musllinux;
    const api_level = rule_of("android_24_arm64_v8a").?.android;

    try std.testing.expectEqual(Version{ .major = 2, .minor = 17 }, glibc);
    try std.testing.expectEqual(Version{ .major = 1, .minor = 2 }, musl);
    try std.testing.expectEqual(@as(u32, 24), api_level);
    try std.testing.expectEqual(Rule.macos, rule_of("macosx_11_0_universal2").?);
    try std.testing.expectEqual(Rule.windows, rule_of("win_arm64").?);
    try std.testing.expectEqual(Rule.windows, rule_of("win32").?);
    try std.testing.expectEqual(@as(?Rule, null), rule_of("linux_x86_64"));
    try std.testing.expectEqual(@as(?Rule, null), rule_of("freebsd_14_0_release_amd64"));
    try std.testing.expectEqual(@as(?Rule, null), rule_of("manylinux_x_17_x86_64"));
}

test policy_libraries {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    var older: Libraries = .empty;
    var newer: Libraries = .empty;

    try policy_libraries(arena, rule_of("manylinux_2_19_ppc64le").?, &older);
    try policy_libraries(arena, rule_of("manylinux_2_31_armv7l").?, &newer);
    try std.testing.expect(names_contain(older.slice(), "libexpat.so.1"));
    try std.testing.expect(!names_contain(older.slice(), "libmvec.so.1"));
    try std.testing.expect(names_contain(newer.slice(), "libmvec.so.1"));

    var musl: Libraries = .empty;
    var android: Libraries = .empty;
    var none: Libraries = .empty;

    try policy_libraries(arena, rule_of("musllinux_1_2_x86_64").?, &musl);
    try policy_libraries(arena, rule_of("android_29_x86_64").?, &android);
    try policy_libraries(arena, .windows, &none);
    try std.testing.expect(names_contain(musl.slice(), "libc.so"));
    try std.testing.expect(!names_contain(musl.slice(), "libc.so.6"));
    try std.testing.expect(names_contain(android.slice(), "libneuralnetworks.so"));
    try std.testing.expectEqual(@as(u32, 0), none.count);

    const early: Rule = .{ .manylinux = .{ .major = 2, .minor = 4 } };

    var ancient: Libraries = .empty;

    try std.testing.expectError(error.PolicyUnknown, policy_libraries(arena, early, &ancient));
}

test admitted {
    const policy = [_][]const u8{ "libc.so.6", "libm.so.6" };
    const manylinux: Rule = .{ .manylinux = .{ .major = 2, .minor = 17 } };
    const android: Rule = .{ .android = 24 };

    try std.testing.expect(admitted(manylinux, &policy, "libc.so.6"));
    try std.testing.expect(admitted(manylinux, &policy, "ld-linux-x86-64.so.2"));
    try std.testing.expect(admitted(manylinux, &policy, "ld64.so.2"));
    try std.testing.expect(!admitted(manylinux, &policy, "libssl.so.3"));
    try std.testing.expect(!admitted(manylinux, &policy, "libpython3.12.so.1.0"));
    try std.testing.expect(admitted(android, &policy, "libpython3.so"));
    try std.testing.expect(admitted(android, &policy, "libpython3.13.so"));
    try std.testing.expect(!admitted(android, &policy, "libpython3.x.so"));
    try std.testing.expect(admitted(.macos, &.{}, "/usr/lib/libSystem.B.dylib"));
    try std.testing.expect(admitted(.macos, &.{}, "/System/Library/Frameworks/Security"));
    try std.testing.expect(!admitted(.macos, &.{}, "@rpath/libwitness.dylib"));
    try std.testing.expect(!admitted(.macos, &.{}, "/opt/homebrew/lib/libssl.3.dylib"));
    try std.testing.expect(admitted(.windows, &.{}, "KERNEL32.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "python314t.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "python3.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "python3t.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "api-ms-win-crt-runtime-l1-1-0.dll"));
    try std.testing.expect(!admitted(.windows, &.{}, "python31415.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "libpypy3.12-c.dll"));
    try std.testing.expect(admitted(.windows, &.{}, "libpypy3-c.dll"));
    try std.testing.expect(!admitted(.windows, &.{}, "libpypy3.x-c.dll"));
    try std.testing.expect(!admitted(.windows, &.{}, "libpypy3.123-c.dll"));
    try std.testing.expect(!admitted(.windows, &.{}, "libssl-3-x64.dll"));
}

test refused_first {
    const dependencies = [_][]const u8{ "KERNEL32.dll", "witness.dll", "zlib1.dll" };
    const allowed = [_][]const u8{"WITNESS.DLL"};

    const strict: Check = .{
        .allowed = &.{},
        .dependencies = &dependencies,
        .policy = &.{},
        .rule = .windows,
    };

    const relaxed: Check = .{
        .allowed = &allowed,
        .dependencies = &dependencies,
        .policy = &.{},
        .rule = .windows,
    };

    try std.testing.expectEqualStrings("witness.dll", refused_first(&strict).?);
    try std.testing.expectEqualStrings("zlib1.dll", refused_first(&relaxed).?);
}

test dependencies_read {
    var dependencies: Dependencies = .empty;
    var garbage: [64]u8 = @splat(0x5a);

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&garbage, &dependencies));

    var portable: [0x40]u8 = @splat(0);

    @memcpy(portable[0..2], "MZ");
    std.mem.writeInt(u32, portable[0x3c..0x40], 0xffff_fff0, .little);

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&portable, &dependencies));

    var fat: [8]u8 = .{ 0xca, 0xfe, 0xba, 0xbe, 0, 0, 0, 9 };

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&fat, &dependencies));

    var thin: [32]u8 = @splat(0);

    std.mem.writeInt(u32, thin[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, thin[16..20], 1, .little);

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&thin, &dependencies));
    try std.testing.expectEqual(@as(u32, 0), dependencies.count);
}

const TestPortable = struct {
    bytes: [0x400]u8,

    fn build(portable: *TestPortable, delayed_attributes: u32) void {
        assert(delayed_attributes <= 1);
        assert(portable.bytes.len == 0x400);

        const bytes = &portable.bytes;
        const image_base: u64 = 0x1000_0000;

        bytes.* = @splat(0);
        @memcpy(bytes[0..2], "MZ");
        std.mem.writeInt(u32, bytes[0x3c..0x40], 0x40, .little);
        @memcpy(bytes[0x40..0x44], "PE\x00\x00");
        std.mem.writeInt(u16, bytes[0x44..0x46], 0x8664, .little);
        std.mem.writeInt(u16, bytes[0x46..0x48], 1, .little);
        std.mem.writeInt(u16, bytes[0x54..0x56], 240, .little);

        const optional = bytes[0x58..][0..240];

        std.mem.writeInt(u16, optional[0..2], 0x20b, .little);
        std.mem.writeInt(u64, optional[24..32], image_base, .little);
        std.mem.writeInt(u32, optional[108..112], 16, .little);
        std.mem.writeInt(u32, optional[112 + 8 ..][0..4], 0x1040, .little);
        std.mem.writeInt(u32, optional[112 + 13 * 8 ..][0..4], 0x1000, .little);

        const section = bytes[0x58 + 240 ..][0..section_bytes];

        std.mem.writeInt(u32, section[8..12], 0x200, .little);
        std.mem.writeInt(u32, section[12..16], 0x1000, .little);
        std.mem.writeInt(u32, section[16..20], 0x200, .little);
        std.mem.writeInt(u32, section[20..24], 0x200, .little);

        const delayed_name: u64 = if (delayed_attributes == 1) 0x1100 else image_base + 0x1100;

        std.mem.writeInt(u32, bytes[0x200..0x204], delayed_attributes, .little);
        std.mem.writeInt(u32, bytes[0x204..0x208], @intCast(delayed_name), .little);
        std.mem.writeInt(u32, bytes[0x240 + 12 ..][0..4], 0x1110, .little);
        @memcpy(bytes[0x300..][0..12], "delayed.dll\x00");
        @memcpy(bytes[0x310..][0..13], "imported.dll\x00");
    }
};

test "a portable executable lists its imports and its delayed imports" {
    var portable: TestPortable = .{ .bytes = undefined };
    var dependencies: Dependencies = .empty;

    portable.build(1);

    try dependencies_read(&portable.bytes, &dependencies);
    try std.testing.expectEqual(@as(u32, 2), dependencies.count);
    try std.testing.expectEqualStrings("imported.dll", dependencies.names[0]);
    try std.testing.expectEqualStrings("delayed.dll", dependencies.names[1]);

    portable.build(0);

    var addressed: Dependencies = .empty;

    try dependencies_read(&portable.bytes, &addressed);
    try std.testing.expectEqualStrings("delayed.dll", addressed.names[1]);

    std.mem.writeInt(u32, portable.bytes[0x240 + 12 ..][0..4], 0x9000, .little);

    var stray: Dependencies = .empty;

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&portable.bytes, &stray));
}

test "a mach-o image lists what it loads and not its own name" {
    var bytes: [0x100]u8 = @splat(0);

    std.mem.writeInt(u32, bytes[0..4], macho.MH_MAGIC_64, .little);
    std.mem.writeInt(u32, bytes[16..20], 2, .little);
    std.mem.writeInt(u32, bytes[20..24], 96, .little);

    const own = bytes[32..][0..48];
    const load = bytes[80..][0..48];

    std.mem.writeInt(u32, own[0..4], @backingInt(macho.LC.ID_DYLIB), .little);
    std.mem.writeInt(u32, own[4..8], 48, .little);
    std.mem.writeInt(u32, own[8..12], 24, .little);
    @memcpy(own[24..][0..18], "@rpath/libown.so\x00\x00");
    std.mem.writeInt(u32, load[0..4], @backingInt(macho.LC.LOAD_WEAK_DYLIB), .little);
    std.mem.writeInt(u32, load[4..8], 48, .little);
    std.mem.writeInt(u32, load[8..12], 24, .little);
    @memcpy(load[24..][0..17], "/usr/lib/libz.1\x00\x00");

    var dependencies: Dependencies = .empty;

    try dependencies_read(&bytes, &dependencies);
    try std.testing.expectEqual(@as(u32, 1), dependencies.count);
    try std.testing.expectEqualStrings("/usr/lib/libz.1", dependencies.names[0]);

    std.mem.writeInt(u32, load[8..12], 60, .little);

    var stray: Dependencies = .empty;

    try std.testing.expectError(error.BinaryInvalid, dependencies_read(&bytes, &stray));
}
