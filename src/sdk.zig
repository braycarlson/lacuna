const std = @import("std");

const assert = std.debug.assert;

pub const Error = error{
    FileTooLarge,
    OutOfMemory,
    TargetsUnmatched,
    TargetsUnterminated,
    Usage,
} || std.Io.Dir.CreateDirPathError || std.Io.Dir.ReadFileError || std.Io.Dir.WriteFileError;

const Bounds = struct {
    close: usize,
    open: usize,
};

pub const Directories = struct {
    include: []const u8,
    root: []const u8,
};

const Placement = struct {
    data: []const u8,
    directory: []const u8,
    name: []const u8,
};

const create_flags: std.Io.Dir.CreateFileOptions = .{
    .read = false,
    .truncate = true,
    .exclusive = false,
    .lock = .none,
    .lock_nonblocking = false,
    .permissions = .default_file,
    .resolve_beneath = false,
};
const device_target = "arm64-ios";
const list_count_max: u32 = 1 << 12;
const settings_bytes_max: u32 = 1 << 16;
const stub_bytes_max: u32 = 1 << 24;
const targets_key = "targets:";

pub fn main(init: std.process.Init) Error!void {
    assert(init.minimal.args.vector.len > 0);
    assert(stub_bytes_max > settings_bytes_max);

    const arguments = init.minimal.args.toSlice(init.arena.allocator()) catch return error.Usage;
    if (arguments.len != 5) return error.Usage;

    const arena = init.arena.allocator();
    const cwd = std.Io.Dir.cwd();
    const output = arguments[1];
    const stub = try file_read(init.io, arena, arguments[2], stub_bytes_max);
    const settings = try file_read(init.io, arena, arguments[3], settings_bytes_max);
    const retargeted = try retarget(arena, stub);
    const library = try std.Io.Dir.path.join(arena, &.{ output, "usr", "lib" });

    const libc = try libc_text(arena, .{ .include = arguments[4], .root = output });

    const placements = [_]Placement{
        .{ .data = settings, .directory = output, .name = "SDKSettings.json" },
        .{ .data = retargeted, .directory = library, .name = "libSystem.tbd" },
        .{ .data = libc, .directory = output, .name = "libc.txt" },
    };

    try cwd.createDirPath(init.io, library);

    for (placements) |placement| try file_place(init.io, arena, placement);
}

fn file_read(io: std.Io, arena: std.mem.Allocator, path: []const u8, bytes_max: u32) Error![]u8 {
    assert(path.len > 0);
    assert(bytes_max > 0);

    const buffer = try arena.alloc(u8, bytes_max + 1);
    const bytes = try std.Io.Dir.cwd().readFile(io, path, buffer);
    if (bytes.len > bytes_max) return error.FileTooLarge;

    return bytes;
}

fn file_place(io: std.Io, arena: std.mem.Allocator, placement: Placement) Error!void {
    assert(placement.directory.len > 0);
    assert(std.mem.findScalar(u8, placement.name, '/') == null);
    assert(placement.data.len <= stub_bytes_max);

    const destination: std.Io.Dir.WriteFileOptions = .{
        .sub_path = try std.Io.Dir.path.join(arena, &.{ placement.directory, placement.name }),
        .data = placement.data,
        .flags = create_flags,
    };

    try std.Io.Dir.cwd().writeFile(io, destination);
}

pub fn libc_text(arena: std.mem.Allocator, directories: Directories) Error![]u8 {
    assert(directories.root.len > 0);
    assert(directories.include.len > 0);

    const library = try std.Io.Dir.path.join(arena, &.{ directories.root, "usr", "lib" });

    return arena.print(
        "include_dir={s}\nsys_include_dir={s}\ncrt_dir={s}\nmsvc_lib_dir=\n" ++
            "kernel32_lib_dir=\ncc_dir=\ndarwin_sdk_dir={s}\n",
        .{ directories.include, directories.include, library, directories.root },
    );
}

pub fn retarget(allocator: std.mem.Allocator, stub: []const u8) Error![]u8 {
    assert(stub.len <= stub_bytes_max);
    assert(targets_key.len > 0);

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var rest = stub;
    var matched: u32 = 0;

    for (0..list_count_max) |_| {
        const key = std.mem.find(u8, rest, targets_key) orelse {
            if (matched == 0) return error.TargetsUnmatched;

            try result.appendSlice(allocator, rest);

            return result.toOwnedSlice(allocator);
        };

        const bounds = try list_bounds(rest, key);
        const list = std.mem.trimEnd(u8, rest[bounds.open + 1 .. bounds.close], " \n");
        const list_end = bounds.open + 1 + list.len;

        try result.appendSlice(allocator, rest[0..list_end]);

        if (list_device(list)) {
            try result.appendSlice(allocator, ", " ++ device_target);
            matched += 1;
        }

        try result.appendSlice(allocator, rest[list_end..bounds.close]);
        rest = rest[bounds.close..];
    }

    return error.TargetsUnterminated;
}

fn list_bounds(text: []const u8, key: usize) Error!Bounds {
    assert(key + targets_key.len <= text.len);
    assert(std.mem.startsWith(u8, text[key..], targets_key));

    const unterminated = error.TargetsUnterminated;
    const open = std.mem.findScalarPos(u8, text, key, '[') orelse return unterminated;
    const gap = text[key + targets_key.len .. open];
    if (std.mem.trim(u8, gap, " \n").len > 0) return unterminated;

    const close = std.mem.findScalarPos(u8, text, open, ']') orelse return unterminated;

    assert(close > open);

    return .{ .close = close, .open = open };
}

fn list_device(list: []const u8) bool {
    assert(std.mem.findScalar(u8, list, ']') == null);
    assert(list.len <= stub_bytes_max);

    var entries = std.mem.tokenizeAny(u8, list, ", \n");
    var apple_silicon = false;

    for (0..list_count_max) |_| {
        const entry = entries.next() orelse return apple_silicon;

        if (std.mem.eql(u8, entry, device_target)) return false;
        if (!std.mem.startsWith(u8, entry, "arm64")) continue;
        if (std.mem.endsWith(u8, entry, "-macos")) apple_silicon = true;
    }

    return false;
}

test retarget {
    const allocator = std.testing.allocator;

    const stub =
        \\--- !tapi-tbd
        \\targets:         [ x86_64-macos, arm64e-macos,
        \\                   arm64e.x1-macos ]
        \\install-name:    '/usr/lib/libSystem.B.dylib'
        \\exports:
        \\  - targets: [ x86_64-macos ]
        \\    symbols: [ _a ]
        \\  - targets: [ arm64-macos, arm64e-macos ]
        \\    symbols: [ _b ]
        \\  - targets: [ arm64-ios, arm64e-macos ]
        \\    symbols: [ _c ]
        \\...
        \\
    ;

    const expected =
        \\--- !tapi-tbd
        \\targets:         [ x86_64-macos, arm64e-macos,
        \\                   arm64e.x1-macos, arm64-ios ]
        \\install-name:    '/usr/lib/libSystem.B.dylib'
        \\exports:
        \\  - targets: [ x86_64-macos ]
        \\    symbols: [ _a ]
        \\  - targets: [ arm64-macos, arm64e-macos, arm64-ios ]
        \\    symbols: [ _b ]
        \\  - targets: [ arm64-ios, arm64e-macos ]
        \\    symbols: [ _c ]
        \\...
        \\
    ;

    const result = try retarget(allocator, stub);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expected, result);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, result, device_target));

    const unmatched = retarget(allocator, "targets: [ x86_64-macos ]");
    const unterminated = retarget(allocator, "targets: [ arm64-macos");
    const misplaced = retarget(allocator, "targets: x [ arm64-macos ]");

    try std.testing.expectError(error.TargetsUnmatched, unmatched);
    try std.testing.expectError(error.TargetsUnterminated, unterminated);
    try std.testing.expectError(error.TargetsUnterminated, misplaced);
}

test libc_text {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();

    const include = "/zig/lib/libc/include/any-darwin-any";
    const text = try libc_text(arena_state.allocator(), .{
        .include = include,
        .root = ".zig-cache/o/sdk",
    });

    const separator = std.Io.Dir.path.sep_str;
    const crt_line = "crt_dir=.zig-cache/o/sdk" ++ separator ++ "usr" ++ separator ++ "lib\n";

    try std.testing.expect(std.mem.find(u8, text, crt_line) != null);
    try std.testing.expect(std.mem.find(u8, text, "darwin_sdk_dir=.zig-cache/o/sdk\n") != null);
    try std.testing.expect(std.mem.startsWith(u8, text, "include_dir=" ++ include ++ "\n"));
    try std.testing.expect(std.mem.endsWith(u8, text, "\n"));
    try std.testing.expectEqual(@as(usize, 7), std.mem.count(u8, text, "="));
}
