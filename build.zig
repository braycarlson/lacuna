const std = @import("std");

const c_api = @import("src/c.zig");
const dispatch_module = @import("src/dispatch.zig");
const package_module = @import("src/package.zig");
const version_module = @import("src/version.zig");

const assert = std.debug.assert;

const CopyFilter = std.Build.Step.WriteFile.CopyDirectoryOptions;

pub const Author = package_module.Author;
pub const EntryGroup = package_module.EntryGroup;
pub const EntryPoint = package_module.EntryPoint;
pub const Extra = package_module.Extra;
pub const Link = package_module.Link;
pub const Version = c_api.ABI.Minor;

pub const DataFile = struct {
    name: []const u8,
    path: std.Build.LazyPath,
    scheme: DataScheme,
};

pub const DataScheme = enum {
    data,
    headers,
    platlib,
    purelib,
    scripts,
};

pub const Description = struct {
    content_type: ?[]const u8 = null,
    path: std.Build.LazyPath,
};

pub const Extension = struct {
    check: *std.Build.Step,
    develop: *std.Build.Step,
    free_threaded: []const Version,
    installer: std.Build.LazyPath,
    package: std.Build.LazyPath,
    packages_free_threaded: [free_threaded_count_max]std.Build.LazyPath,
    packages_pypy: [pypy_count_max]std.Build.LazyPath,
    package_tsan: ?std.Build.LazyPath,
    platforms: []const Platform,
    pypy: []const PyPyVersion,
    wheel: *std.Build.Step,
    versioned: []const Version,
    packages_versioned: [versioned_count_max]std.Build.LazyPath,
    wheels: [platform_count_max]Built,
    wheels_free_threaded: [platform_count_max][free_threaded_count_max]?Built,
    wheels_pypy: [platform_count_max][pypy_count_max]?Built,
    wheels_versioned: [platform_count_max][versioned_count_max]?Built,
};

pub const ExtensionOptions = struct {
    dispatch: bool = false,
    free_threaded: []const Version = &free_threaded_default,
    module: *std.Build.Module,
    name: []const u8,
    optimize: std.lang.Optimize,
    package: Package,
    platforms: []const Platform,
    python_exclude_extensions: []const []const u8 = &python_exclude_default,
    python_include_extensions: ?[]const []const u8 = null,
    python_source: ?std.Build.LazyPath = null,
    pypy: []const PyPyVersion = &.{},
    python_version_min: Version = python_version_floor,
    release_optimize: std.lang.Optimize = .safe,
    strip: bool,
    target: std.Build.ResolvedTarget,
    versioned: []const Version = &.{},
};

pub const License = struct {
    expression: []const u8,
    files: []const LicenseFile,
};

pub const LicenseFile = struct {
    name: []const u8,
    path: std.Build.LazyPath,
};

pub const Package = struct {
    authors: []const Author = &.{},
    classifiers: []const []const u8 = &.{},
    data: []const DataFile = &.{},
    dependencies: []const []const u8 = &.{},
    description: ?Description = null,
    dynamic: []const []const u8 = &.{},
    entry_points: []const EntryGroup = &.{},
    extras: []const Extra = &.{},
    gui_scripts: []const EntryPoint = &.{},
    keywords: []const []const u8 = &.{},
    license: ?License = null,
    links: []const Link = &.{},
    maintainers: []const Author = &.{},
    name: []const u8,
    obsoletes: []const []const u8 = &.{},
    provides: []const []const u8 = &.{},
    requires_python: ?[]const u8 = null,
    scripts: []const EntryPoint = &.{},
    summary: ?[]const u8 = null,
    version: []const u8,
};

pub const Platform = struct {
    free_threaded: bool,
    multiarch: []const u8,
    needed_removed: []const []const u8,
    python_linked: bool = false,
    pypy: bool = false,
    query: std.Target.Query,
    tag: []const u8,
    universal: ?std.Target.Query = null,
};

pub const PyPyVersion = struct {
    abi: []const u8,
    version: Version,
};

pub const PythonTestOptions = struct {
    conftest: ?std.Build.LazyPath = null,
    free_threaded: ?Version = null,
    pypy: ?PyPyVersion = null,
    python: []const []const u8,
    script: std.Build.LazyPath,
    tsan: bool = false,
    versioned: ?Version = null,
};

pub const StubTestOptions = struct {
    name: []const u8,
    python: []const []const u8,
};

const Artifacts = struct {
    binary: std.Build.LazyPath,
    stub: std.Build.LazyPath,
};

const Built = struct {
    path: std.Build.LazyPath,
    step: *std.Build.Step,
};

const Context = struct {
    builder: *std.Build,
    filters: []const []const u8,
    module: *std.Build.Module,
    optimize: std.lang.Optimize,
    python: []const []const u8,
    python_free_threaded: ?Version,
    python_pypy: ?Version,
    python_include: ?[]const u8,
    python_tsan: ?[]const []const u8,
    python_versioned: ?Version,
    steps: Steps,
    target: std.Build.ResolvedTarget,
};

const Example = struct {
    leak_script: ?[]const u8 = null,
    name: []const u8,
    property_script: ?[]const u8 = null,
    python_source: ?[]const u8,
    root: []const u8,
    script: []const u8,
    wheel_script: ?[]const u8 = null,
};

const Layout = struct {
    binary_stem: []const u8,
    typed: []const u8,
};

const Owner = struct {
    builder: *std.Build,
    module: *std.Build.Module,
};

const Steps = struct {
    backend: *std.Build.Step,
    check: *std.Build.Step,
    continuous_integration: *std.Build.Step,
    example: *std.Build.Step,
    test_abi: *std.Build.Step,
    test_all: *std.Build.Step,
    test_audit: *std.Build.Step,
    test_backend: *std.Build.Step,
    test_compile_fail: *std.Build.Step,
    test_debug: *std.Build.Step,
    test_format: *std.Build.Step,
    test_free_threaded: *std.Build.Step,
    test_property: *std.Build.Step,
    test_pypy: *std.Build.Step,
    test_python: *std.Build.Step,
    test_stub: *std.Build.Step,
    test_tsan: *std.Build.Step,
    test_unit: *std.Build.Step,
    test_versioned: *std.Build.Step,
    test_wheel: *std.Build.Step,
    wheel: *std.Build.Step,
};

const Translation = struct {
    include: []const u8,
    mode: Mode,

    const Mode = union(enum) {
        free_threaded,
        limited: []const u8,
        pypy,
        versioned,
    };
};

const Tool = struct {
    name: []const u8,
    root: []const u8,
};

const Tools = struct {
    fat: *std.Build.Step.Compile,
    needed: *std.Build.Step.Compile,
    wheel: *std.Build.Step.Compile,
};

const Tree = struct {
    layout: Layout,
    library: *std.Build.Step.Compile,
    python_filter: CopyFilter,
    python_source: ?std.Build.LazyPath,
    stub: std.Build.LazyPath,
    suffix: []const u8,
};

const Variant = union(enum) {
    free_threaded: Version,
    pypy: PyPyVersion,
    stable,
    versioned: Version,
};

const VersionRange = struct {
    kind: []const u8,
    minor_max: u8,
    minor_min: u8,
};

const WheelEntries = struct {
    artifacts: Artifacts,
    directory: []const u8,
    options: *const ExtensionOptions,
    platform: Platform,
    variant: Variant,
};

const argument_bytes_max: u32 = 1 << 20;
pub const free_threaded_count_max: u32 = 4;
pub const free_threaded_minor_max: u8 = 15;
pub const free_threaded_minor_min: u8 = 13;
pub const python_version_floor: Version = .{
    .major = version_module.floor.major,
    .minor = version_module.floor.minor,
};

pub const platform_count_max: u32 = 32;
pub const pypy_count_max: u32 = 4;
pub const pypy_minor_max: u8 = 12;
pub const pypy_minor_min: u8 = 11;
pub const versioned_count_max: u32 = 4;
pub const versioned_minor_max: u8 = 15;
pub const versioned_minor_min: u8 = 12;

const free_threaded_range: VersionRange = .{
    .kind = "free-threaded",
    .minor_max = free_threaded_minor_max,
    .minor_min = free_threaded_minor_min,
};

const pypy_range: VersionRange = .{
    .kind = "PyPy",
    .minor_max = pypy_minor_max,
    .minor_min = pypy_minor_min,
};

const versioned_range: VersionRange = .{
    .kind = "version-specific",
    .minor_max = versioned_minor_max,
    .minor_min = versioned_minor_min,
};

pub const free_threaded_default = [_]Version{
    .{ .major = 3, .minor = 14 },
    .{ .major = 3, .minor = 15 },
};

pub const pypy_all = [_]PyPyVersion{
    .{ .abi = "pp80", .version = .{ .major = 3, .minor = 11 } },
    .{ .abi = "pp80", .version = .{ .major = 3, .minor = 12 } },
};

pub const versioned_all = [_]Version{
    .{ .major = 3, .minor = 12 },
    .{ .major = 3, .minor = 13 },
    .{ .major = 3, .minor = 14 },
    .{ .major = 3, .minor = 15 },
};

const versioned_examples = [_]Version{.{ .major = 3, .minor = 14 }};

const tsan_version: Version = .{ .major = 3, .minor = 14 };

const tsan_environment = [_][2][]const u8{
    .{ "GLIBC_TUNABLES", "glibc.rtld.optional_static_tls=0x100000" },
    .{ "TSAN_OPTIONS", "halt_on_error=1 exitcode=66 second_deadlock_stack=1" },
};

pub const platforms = [_]Platform{
    .{
        .free_threaded = true,
        .multiarch = "x86_64-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 17, .patch = 0 },
        },
        .pypy = true,
        .tag = "manylinux_2_17_x86_64.manylinux2014_x86_64",
    },
    .{
        .free_threaded = true,
        .multiarch = "aarch64-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 17, .patch = 0 },
        },
        .pypy = true,
        .tag = "manylinux_2_17_aarch64.manylinux2014_aarch64",
    },
    .{
        .free_threaded = false,
        .multiarch = "i386-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 17, .patch = 0 },
        },
        .tag = "manylinux_2_17_i686.manylinux2014_i686",
    },
    .{
        .free_threaded = false,
        .multiarch = "arm-linux-gnueabihf",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .arm,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.generic },
            .cpu_features_add = std.Target.arm.featureSet(&.{ .v7a, .vfp3d16, .thumb2 }),
            .os_tag = .linux,
            .abi = .gnueabihf,
            .glibc_version = .{ .major = 2, .minor = 31, .patch = 0 },
        },
        .tag = "manylinux_2_31_armv7l",
    },
    .{
        .free_threaded = true,
        .multiarch = "powerpc64le-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .powerpc64le,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 19, .patch = 0 },
        },
        .tag = "manylinux_2_19_ppc64le",
    },
    .{
        .free_threaded = true,
        .multiarch = "s390x-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .s390x,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 17, .patch = 0 },
        },
        .tag = "manylinux_2_17_s390x.manylinux2014_s390x",
    },
    .{
        .free_threaded = true,
        .multiarch = "riscv64-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .riscv64,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 31, .patch = 0 },
        },
        .tag = "manylinux_2_31_riscv64",
    },
    .{
        .free_threaded = true,
        .multiarch = "loongarch64-linux-gnu",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .loongarch64,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 36, .patch = 0 },
        },
        .tag = "manylinux_2_36_loongarch64",
    },
    .{
        .free_threaded = true,
        .multiarch = "x86_64-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_x86_64",
    },
    .{
        .free_threaded = true,
        .multiarch = "aarch64-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_aarch64",
    },
    .{
        .free_threaded = false,
        .multiarch = "i386-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_i686",
    },
    .{
        .free_threaded = false,
        .multiarch = "arm-linux-musleabihf",
        .needed_removed = &.{"libc.so"},
        .query = .{
            .cpu_arch = .arm,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.generic },
            .cpu_features_add = std.Target.arm.featureSet(&.{ .v7a, .vfp3d16, .thumb2 }),
            .os_tag = .linux,
            .abi = .musleabihf,
        },
        .tag = "musllinux_1_2_armv7l",
    },
    .{
        .free_threaded = true,
        .multiarch = "powerpc64le-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_ppc64le",
    },
    .{
        .free_threaded = true,
        .multiarch = "s390x-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .s390x, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_s390x",
    },
    .{
        .free_threaded = true,
        .multiarch = "riscv64-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_riscv64",
    },
    .{
        .free_threaded = true,
        .multiarch = "loongarch64-linux-musl",
        .needed_removed = &.{"libc.so"},
        .query = .{ .cpu_arch = .loongarch64, .os_tag = .linux, .abi = .musl },
        .tag = "musllinux_1_2_loongarch64",
    },
    .{
        .free_threaded = true,
        .multiarch = "win_amd64",
        .needed_removed = &.{},
        .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
        .pypy = true,
        .tag = "win_amd64",
    },
    .{
        .free_threaded = true,
        .multiarch = "win_arm64",
        .needed_removed = &.{},
        .query = .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
        .tag = "win_arm64",
    },
    .{
        .free_threaded = false,
        .multiarch = "win32",
        .needed_removed = &.{},
        .query = .{ .cpu_arch = .x86, .os_tag = .windows, .abi = .gnu },
        .tag = "win32",
    },
    .{
        .free_threaded = false,
        .multiarch = "aarch64-linux-android",
        .needed_removed = &.{},
        .python_linked = true,
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .android,
            .android_api_level = 29,
        },
        .tag = "android_29_arm64_v8a",
    },
    .{
        .free_threaded = false,
        .multiarch = "x86_64-linux-android",
        .needed_removed = &.{},
        .python_linked = true,
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .android,
            .android_api_level = 29,
        },
        .tag = "android_29_x86_64",
    },
    .{
        .free_threaded = true,
        .multiarch = "darwin",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .macos,
            .os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } },
        },
        .pypy = true,
        .tag = "macosx_11_0_x86_64",
    },
    .{
        .free_threaded = true,
        .multiarch = "darwin",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
            .os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } },
        },
        .pypy = true,
        .tag = "macosx_11_0_arm64",
    },
};

pub const platforms_local = [_]Platform{
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .freebsd,
            .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
        },
        .tag = "freebsd_14_0_release_amd64",
    },
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .freebsd,
            .os_version_min = .{ .semver = .{ .major = 14, .minor = 0, .patch = 0 } },
        },
        .tag = "freebsd_14_0_release_arm64",
    },
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .netbsd,
            .os_version_min = .{ .semver = .{ .major = 10, .minor = 1, .patch = 0 } },
        },
        .tag = "netbsd_10_1_amd64",
    },
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .netbsd,
            .os_version_min = .{ .semver = .{ .major = 10, .minor = 1, .patch = 0 } },
        },
        .tag = "netbsd_10_1_evbarm",
    },
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .x86_64,
            .os_tag = .openbsd,
            .os_version_min = .{ .semver = .{ .major = 7, .minor = 8, .patch = 0 } },
        },
        .tag = "openbsd_7_8_amd64",
    },
    .{
        .free_threaded = false,
        .multiarch = "",
        .needed_removed = &.{},
        .query = .{
            .cpu_arch = .aarch64,
            .os_tag = .openbsd,
            .os_version_min = .{ .semver = .{ .major = 7, .minor = 8, .patch = 0 } },
        },
        .tag = "openbsd_7_8_arm64",
    },
};

pub const platform_universal2: Platform = .{
    .free_threaded = true,
    .multiarch = "darwin",
    .needed_removed = &.{},
    .query = .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } },
    },
    .tag = "macosx_11_0_universal2",
    .universal = .{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
        .os_version_min = .{ .semver = .{ .major = 11, .minor = 0, .patch = 0 } },
    },
};

const platforms_universal2 = platforms ++ [_]Platform{platform_universal2};

pub const python_exclude_default = [_][]const u8{ ".pyc", ".pyo" };

pub const python_default = [_][]const u8{
    "uv",
    "run",
    "--no-project",
    "--with",
    "pytest",
    "python",
};

const examples = [_]Example{
    .{
        .name = "hello",
        .python_source = null,
        .root = "examples/hello.zig",
        .script = "tests/test_hello.py",
    },
    .{
        .leak_script = "tests/leak_interop.py",
        .name = "interop",
        .property_script = "tests/property_interop.py",
        .python_source = null,
        .root = "examples/interop.zig",
        .script = "tests/test_interop.py",
    },
    .{
        .name = "mixed._native",
        .python_source = "examples/mixed",
        .root = "examples/mixed.zig",
        .script = "tests/test_mixed.py",
        .wheel_script = "tests/test_mixed_wheel.py",
    },
    .{
        .leak_script = "tests/leak_protocols.py",
        .name = "protocols",
        .property_script = "tests/property_protocols.py",
        .python_source = null,
        .root = "examples/protocols.zig",
        .script = "tests/test_protocols.py",
    },
    .{
        .leak_script = "tests/leak_sample.py",
        .name = "sample",
        .property_script = "tests/property_sample.py",
        .python_source = null,
        .root = "examples/sample.zig",
        .script = "tests/test_sample.py",
    },
    .{
        .name = "wide",
        .python_source = null,
        .root = "examples/wide.zig",
        .script = "tests/test_wide.py",
    },
};

const format_paths = [_][]const u8{
    "build.zig",
    "examples",
    "src",
    "templates",
    "tests/compile_fail",
};

const tool_hosts = [_]std.Target.Query{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf },
    .{ .cpu_arch = .x86, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
};

const CompileFail = struct {
    message: []const u8,
    root: []const u8,
};

const compile_fail_cases = [_]CompileFail{
    .{
        .message = "lacuna: the function 'fail' returns anyerror; name its errors",
        .root = "tests/compile_fail/anyerror_return.zig",
    },
    .{
        .message = "lacuna: the bases of 'fixture' form a cycle through 'First'",
        .root = "tests/compile_fail/base_cycle.zig",
    },
    .{
        .message = "lacuna: the bases of 'fixture' chain 'Level9' deeper than 8 errors",
        .root = "tests/compile_fail/base_too_deep.zig",
    },
    .{
        .message = "lacuna: the base of 'Child' is 'Missing', which no function raises as " ++
            "a module error",
        .root = "tests/compile_fail/base_undeclared_error.zig",
    },
    .{
        .message = "lacuna: the bases of 'fixture' name 'Missing', which no function " ++
            "raises as a module error",
        .root = "tests/compile_fail/base_unraised.zig",
    },
    .{
        .message = "lacuna: the class 'Holder' owns Python references, so it is passed by " ++
            "pointer, not copied",
        .root = "tests/compile_fail/collected_by_value.zig",
    },
    .{
        .message = "lacuna: the class 'collected_returned.Holder' owns Python references, " ++
            "so it is never returned by value",
        .root = "tests/compile_fail/collected_returned.zig",
    },
    .{
        .message = "lacuna: the coroutine function 'inspect' takes a Python object, which it " ++
            "cannot touch without the GIL",
        .root = "tests/compile_fail/coroutine_object.zig",
    },
    .{
        .message = "lacuna: 'total' is listed in both parallel and coroutines; a coroutine " ++
            "already runs without the GIL",
        .root = "tests/compile_fail/coroutine_parallel.zig",
    },
    .{
        .message = "lacuna: the coroutines list names 'missing', which is not a function",
        .root = "tests/compile_fail/coroutine_undeclared.zig",
    },
    .{
        .message = "lacuna: the required argument 'value' of 'scale' follows an argument " ++
            "with a default",
        .root = "tests/compile_fail/default_before_required.zig",
    },
    .{
        .message = "lacuna: the class 'derived_returned.Derived' extends " ++
            "'derived_returned.Base', so it is returned as " ++
            "lacuna.ExtendedType(derived_returned.Derived) with its base",
        .root = "tests/compile_fail/derived_returned.zig",
    },
    .{
        .message = "lacuna: the deprecated list of 'deprecated_undeclared.Functions' names " ++
            "'missing', which is not a function",
        .root = "tests/compile_fail/deprecated_undeclared.zig",
    },
    .{
        .message = "lacuna: the class 'Pair' derives hash and also defines __hash__",
        .root = "tests/compile_fail/derive_duplicate.zig",
    },
    .{
        .message = "lacuna: the class 'Pair' derives a comparison, but its field 'left' of type " ++
            "'[2]i64' has none",
        .root = "tests/compile_fail/derive_field_unsupported.zig",
    },
    .{
        .message = "lacuna: the class 'Pair' derives hash, but its field 'left' is a float, and " ++
            "-0.0 and 0.0 compare equal",
        .root = "tests/compile_fail/derive_hash_float.zig",
    },
    .{
        .message = "lacuna: the class 'Pair' derives hash without eq",
        .root = "tests/compile_fail/derive_hash_without_eq.zig",
    },
    .{
        .message = "lacuna: 'derive' lists 'order', which is not eq, ord, hash, or repr",
        .root = "tests/compile_fail/derive_unknown.zig",
    },
    .{
        .message = "lacuna: the docs of 'docs_undeclared.Functions' name 'missing', " ++
            "which it does not declare",
        .root = "tests/compile_fail/docs_undeclared.zig",
    },
    .{
        .message = "lacuna: the enum 'enum_non_exhaustive.Level' must be exhaustive",
        .root = "tests/compile_fail/enum_non_exhaustive.zig",
    },
    .{
        .message = "lacuna: the enum 'enum_undeclared.Level' is converted, so the " ++
            "module must list it in .enums",
        .root = "tests/compile_fail/enum_undeclared.zig",
    },
    .{
        .message = "lacuna: the class 'extends_final_base.Derived' extends " ++
            "'extends_final_base.Base', which must declare subclassable = true",
        .root = "tests/compile_fail/extends_final_base.zig",
    },
    .{
        .message = "lacuna: 'Derived.init' must take a mutable pointer to each " ++
            "ancestor, starting with *extends_init_without_base.Base, after its receiver to " ++
            "initialize them",
        .root = "tests/compile_fail/extends_init_without_base.zig",
    },
    .{
        .message = "lacuna: the class 'Failure' extends the native 'exception', which needs " ++
            "Python 3.12; this build's floor is Python 3.11",
        .root = "tests/compile_fail/extends_native_floor.zig",
    },
    .{
        .message = "lacuna: 'Registry.merge' takes a lacuna.Object, which only init " ++
            "receives as the native base",
        .root = "tests/compile_fail/extends_native_method.zig",
    },
    .{
        .message = "lacuna: 'init' takes the native base without taking its receiver",
        .root = "tests/compile_fail/extends_native_receiver.zig",
    },
    .{
        .message = "lacuna: the class 'Counted' extends the native 'integer', which is " ++
            "variable-size and has no type data to place fields after",
        .root = "tests/compile_fail/extends_native_varsize.zig",
    },
    .{
        .message = "lacuna: the class 'extends_native_chain.Derived' extends " ++
            "'extends_native_chain.Base', which extends a native base",
        .root = "tests/compile_fail/extends_native_chain.zig",
    },
    .{
        .message = "lacuna: the class 'Derived' extends 'Base', which must come before " ++
            "it in .classes",
        .root = "tests/compile_fail/extends_unordered.zig",
    },
    .{
        .message = "lacuna: the field 'fixture.Holder.name' borrows from Python and " ++
            "cannot be written",
        .root = "tests/compile_fail/field_borrowed_writable.zig",
    },
    .{
        .message = "lacuna: the class 'instance_new_native.Registry' extends a native " ++
            "base, so its instances come from init, not instance_new",
        .root = "tests/compile_fail/instance_new_native.zig",
    },
    .{
        .message = "lacuna: the class 'instance_new_referencing.Holder' owns Python " ++
            "references, so instance_new cannot build it by value",
        .root = "tests/compile_fail/instance_new_referencing.zig",
    },
    .{
        .message = "lacuna: the class 'instance_new_unextended.Child' extends " ++
            "'instance_new_unextended.Base', so instance_new takes " ++
            "lacuna.ExtendedType(instance_new_unextended.Child)",
        .root = "tests/compile_fail/instance_new_unextended.zig",
    },
    .{
        .message = "lacuna: the integer type 'u1025' is wider than 1024 bits",
        .root = "tests/compile_fail/integer_too_wide.zig",
    },
    .{
        .message = "lacuna: the metaclass 'Catalog' has fields; a metaclass carries no Zig " ++
            "state, so keep per-class state in class attributes",
        .root = "tests/compile_fail/metaclass_fields.zig",
    },
    .{
        .message = "lacuna: the class 'metaclass_floor.Plugin' declares a metaclass, which " ++
            "needs Python 3.12; this build's floor is Python 3.11",
        .root = "tests/compile_fail/metaclass_floor.zig",
    },
    .{
        .message = "lacuna: the metaclass 'Catalog' declares pickle, which a metaclass cannot " ++
            "have; its instances are classes that type creates",
        .root = "tests/compile_fail/metaclass_forbidden.zig",
    },
    .{
        .message = "lacuna: the metaclass of 'metaclass_not_type.Plugin' is " ++
            "'metaclass_not_type.Ordinary', which does not extend lacuna.Native.type",
        .root = "tests/compile_fail/metaclass_not_type.zig",
    },
    .{
        .message = "lacuna: the metaclass of 'metaclass_path_invalid.Plugin' is 'Registered'; " ++
            "name a Python metaclass as 'module.Name'",
        .root = "tests/compile_fail/metaclass_path_invalid.zig",
    },
    .{
        .message = "lacuna: a method of the metaclass 'metaclass_pointer_receiver.Catalog' " ++
            "takes the class it is bound to as a lacuna.TypeObject, not a pointer",
        .root = "tests/compile_fail/metaclass_pointer_receiver.zig",
    },
    .{
        .message = "lacuna: the metaclass 'Catalog' extends type, which PyPy cannot extend with " ++
            "type data; list it only where lacuna.native_metaclasses holds",
        .root = "tests/compile_fail/metaclass_pypy.zig",
    },
    .{
        .message = "lacuna: the metaclass of 'metaclass_undeclared.Palette' is " ++
            "'metaclass_undeclared.Catalog', which the module does not declare",
        .root = "tests/compile_fail/metaclass_undeclared.zig",
    },
    .{
        .message = "lacuna: the metaclass 'metaclass_unordered.Catalog' must come before " ++
            "'metaclass_unordered.Palette' in .classes",
        .root = "tests/compile_fail/metaclass_unordered.zig",
    },
    .{
        .message = "lacuna: the Python name 'not valid' of 'names_invalid.Functions.present' " ++
            "is not an identifier",
        .root = "tests/compile_fail/names_invalid.zig",
    },
    .{
        .message = "lacuna: the names of 'names_undeclared.Functions' rename 'missing', " ++
            "which it does not declare",
        .root = "tests/compile_fail/names_undeclared.zig",
    },
    .{
        .message = "lacuna: the type 'nesting_too_deep.Level8' nests deeper than 8 levels",
        .root = "tests/compile_fail/nesting_too_deep.zig",
    },
    .{
        .message = "lacuna: the class 'new_native.Registry' extends a native base, so it is " ++
            "constructed by init and cannot declare __new__",
        .root = "tests/compile_fail/new_native.zig",
    },
    .{
        .message = "lacuna: 'new_receiver.Token.__new__' takes an instance, which does not " ++
            "exist until __new__ returns it",
        .root = "tests/compile_fail/new_receiver.zig",
    },
    .{
        .message = "lacuna: 'new_returns_value.Token.__new__' returns " ++
            "'new_returns_value.Token'; it returns the instance as a lacuna.Reference",
        .root = "tests/compile_fail/new_returns_value.zig",
    },
    .{
        .message = "lacuna: the class 'new_with_init.Token' declares both init and __new__; " ++
            "__new__ builds its instances with lacuna.TypeObject.instance_new",
        .root = "tests/compile_fail/new_with_init.zig",
    },
    .{
        .message = "lacuna: the parallel function 'touch' takes a Python object, which it " ++
            "cannot touch without the GIL",
        .root = "tests/compile_fail/parallel_object.zig",
    },
    .{
        .message = "lacuna: the parallel function 'touch' takes a Python object, which it " ++
            "cannot touch without the GIL",
        .root = "tests/compile_fail/parallel_object_nested.zig",
    },
    .{
        .message = "lacuna: the class 'Holder' holds a field that borrows from Python, so it " ++
            "cannot be pickled",
        .root = "tests/compile_fail/pickle_borrowed.zig",
    },
    .{
        .message = "lacuna: take an lacuna.Object argument and acquire an lacuna.Reference " ++
            "from it, so the function decides what it keeps",
        .root = "tests/compile_fail/reference_argument.zig",
    },
    .{
        .message = "lacuna: the container 'list.ListType(value.Reference,4)' holds an " ++
            "lacuna.Reference, which only a struct, an array, or an optional may hold",
        .root = "tests/compile_fail/reference_in_list.zig",
    },
    .{
        .message = "lacuna: the container 'list.ListType(value.Reference,4)' holds an " ++
            "lacuna.Reference, which only a struct, an array, or an optional may hold",
        .root = "tests/compile_fail/reference_in_returned_list.zig",
    },
    .{
        .message = "lacuna: the union 'reference_in_union.Slot' holds an lacuna.Reference, " ++
            "which only a struct, an array, or an optional may hold",
        .root = "tests/compile_fail/reference_in_union.zig",
    },
    .{
        .message = "lacuna: the class 'Both' declares both sequence and mapping",
        .root = "tests/compile_fail/sequence_and_mapping.zig",
    },
    .{
        .message = "lacuna: the setters of 'setter_unlisted.Holder' name 'value', which " ++
            "is not a property",
        .root = "tests/compile_fail/setter_unlisted.zig",
    },
    .{
        .message = "lacuna: the class 'subclass_hook_final.Plugin' defines __init_subclass__ " ++
            "but is not subclassable, so it never runs",
        .root = "tests/compile_fail/subclass_hook_final.zig",
    },
    .{
        .message = "lacuna: 'subclass_hook_receiver.Plugin.__init_subclass__' takes an " ++
            "instance; it receives the new subclass as a lacuna.TypeObject",
        .root = "tests/compile_fail/subclass_hook_receiver.zig",
    },
    .{
        .message = "lacuna: the submodule 'elsewhere.inner' must be named " ++
            "'fixture.<name>'",
        .root = "tests/compile_fail/submodule_misnamed.zig",
    },
    .{
        .message = "lacuna: the module function 'kind' takes a lacuna.TypeObject, which " ++
            "only a class member receives",
        .root = "tests/compile_fail/type_object_in_function.zig",
    },
    .{
        .message = "lacuna: the variant 'union_nested.Outer.inner' holds the union " ++
            "'union_nested.Inner', which a variant class cannot nest",
        .root = "tests/compile_fail/union_nested.zig",
    },
    .{
        .message = "lacuna: the union 'union_untagged.Number' must be tagged",
        .root = "tests/compile_fail/union_untagged.zig",
    },
    .{
        .message = "lacuna: the union 'variant_ambiguous.Either' has two variants of type " ++
            "'i64', so a Python value cannot choose between them",
        .root = "tests/compile_fail/variant_ambiguous.zig",
    },
};

const backend_tests = [_][]const u8{ "tests/test_backend.py", "tests/test_zon.py" };
const limited_api_version = "0x030b0000";
const limited_api_version_3_12 = "0x030c0000";
const module_root = "src/lacuna.zig";
const tool_roots = [_][]const u8{ "src/fat.zig", "src/needed.zig", "src/wheel.zig" };
const unit_tests_root = "src/unit_tests.zig";
const unit_tests_x86_64_root = "src/unit_tests_x86_64.zig";

const pytest_arguments = [_][]const u8{
    "-B",
    "-X",
    "dev",
    "-W",
    "error",
    "-m",
    "pytest",
    "-p",
    "no:cacheprovider",
    "-q",
};

const exports_text = lines_join(&c_api.exports);
const exports_3_12_text = lines_join(&c_api.exports_3_12);
const exports_3_13_text = lines_join(&c_api.exports_3_13);
const exports_free_threaded_text = lines_join(&c_api.exports_free_threaded);
const exports_versioned_text = lines_join(&c_api.exports_versioned);

const conftest_path = "tests/conftest.py";

const python_debug = [_][]const u8{
    "uv",
    "run",
    "--no-project",
    "--python",
    "3.14+debug",
    "--with",
    "pytest",
    "--with",
    "hypothesis",
    "python",
};

const python_audit = [_][]const u8{
    "uv",
    "run",
    "--quiet",
    "--no-project",
    "--with",
    "auditwheel==6.8.2",
    "--with",
    "pytest",
    "python",
};

const python_property = [_][]const u8{
    "uv",
    "run",
    "--no-project",
    "--with",
    "pytest",
    "--with",
    "hypothesis",
    "python",
};

const stub_python = [_][]const u8{
    "uv",
    "run",
    "--no-project",
    "--with",
    "mypy",
    "python",
};

comptime {
    @setEvalBranchQuota(100_000);

    assert(std.mem.count(u8, exports_text, "\n") > 40);
    assert(platforms.len == 23);
    assert(platforms.len + platforms_local.len <= platform_count_max);

    for (platforms_local) |platform| {
        assert(platform_bsd(platform));
        assert(!platform.free_threaded);
        assert(!platform.pypy);
    }
    assert(platforms.len <= platform_count_max);
    assert(free_threaded_default.len <= free_threaded_count_max);
    assert(free_threaded_minor_min <= free_threaded_minor_max);
    assert(examples.len == 6);

    for (free_threaded_default) |version| {
        assert(version.major == 3);
        assert(version.minor >= free_threaded_minor_min);
        assert(version.minor <= free_threaded_minor_max);
    }

    assert(versioned_all.len <= versioned_count_max);
    assert(versioned_minor_min <= versioned_minor_max);
    assert(versioned_all.len == versioned_minor_max - versioned_minor_min + 1);

    for (versioned_all ++ versioned_examples) |version| {
        assert(version.major == 3);
        assert(version.minor >= versioned_minor_min);
        assert(version.minor <= versioned_minor_max);
    }
}

fn lines_join(comptime names: []const []const u8) []const u8 {
    comptime assert(names.len > 0);
    comptime assert(names.len < 1 << 12);

    var result: []const u8 = "";

    for (names) |name| result = result ++ name ++ "\n";

    return result;
}

pub fn build(builder: *std.Build) void {
    assert(builder.graph.host.result.os.tag != .freestanding);
    assert(examples.len > 0);

    const filters = builder.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const python = builder.option(
        []const []const u8,
        "python",
        "The command that runs Python with pytest available, one argument per option",
    ) orelse &python_default;

    const python_include = builder.option(
        []const u8,
        "python-include",
        "The Python include directory that the ABI check translates",
    );

    const python_tsan = builder.option(
        []const []const u8,
        "python-tsan",
        "The command that runs a ThreadSanitizer free-threaded Python with pytest available",
    );

    const headers = headers_option(builder);

    const context = Context{
        .builder = builder,
        .filters = filters,
        .module = builder.addModule("lacuna", .{ .root_source_file = builder.path(module_root) }),
        .optimize = builder.standardOptimizeOption(.{ .preferred_optimize_mode = null }),
        .python = python,
        .python_free_threaded = headers.free_threaded,
        .python_pypy = headers.pypy,
        .python_include = python_include,
        .python_tsan = python_tsan,
        .python_versioned = headers.versioned,
        .steps = steps_declare(builder),
        .target = builder.standardTargetOptions(.{ .whitelist = null, .default_target = .{} }),
    };

    add_abi(&context);
    add_audit(&context);
    add_backend(&context);
    add_compile_fail_tests(&context);
    add_examples(&context);
    add_format(&context);
    add_tool_check(&context);
    add_unit_tests(&context);

    context.steps.continuous_integration.dependOn(context.steps.check);
    context.steps.continuous_integration.dependOn(context.steps.test_all);
    context.steps.continuous_integration.dependOn(context.steps.test_python);
    context.steps.continuous_integration.dependOn(context.steps.test_property);
    context.steps.continuous_integration.dependOn(context.steps.test_wheel);
    context.steps.continuous_integration.dependOn(context.steps.test_stub);
    context.steps.continuous_integration.dependOn(context.steps.test_free_threaded);
    context.steps.continuous_integration.dependOn(context.steps.test_versioned);
    context.steps.continuous_integration.dependOn(context.steps.test_pypy);
    context.steps.continuous_integration.dependOn(context.steps.test_backend);
    context.steps.continuous_integration.dependOn(context.steps.wheel);
}

const backend_classifiers = [_][]const u8{
    "Programming Language :: Python :: 3",
    "Programming Language :: Zig",
    "Topic :: Software Development :: Build Tools",
};

const backend_scripts = [_]EntryPoint{.{ .name = "lacuna", .target = "lacuna_build.cli:main" }};
const backend_vendored = [_][]const u8{ "LICENSE", "build.zig", "build.zig.zon", "src/", "tools/" };

fn add_audit(context: *const Context) void {
    assert(context.steps.test_audit != context.steps.test_all);
    assert(context.steps.continuous_integration != context.steps.test_audit);

    const builder = context.builder;
    const check = builder.addSystemCommand(&python_audit);

    check.addArgs(&.{
        "-B",
        "-X",
        "dev",
        "-W",
        "error",
        "-m",
        "pytest",
        "-p",
        "no:cacheprovider",
        "-q",
    });
    check.addFileArg(builder.path("tests/test_audit.py"));
    check.has_side_effects = true;

    context.steps.test_audit.dependOn(&check.step);

    if (builder.graph.host.result.os.tag == .linux) {
        context.steps.continuous_integration.dependOn(context.steps.test_audit);
    }
}

fn add_backend(context: *const Context) void {
    assert(context.steps.backend != context.steps.test_backend);
    assert(backend_classifiers.len > 0);

    const license_files = [_]LicenseFile{
        .{ .name = "LICENSE", .path = context.builder.path("LICENSE") },
    };

    const backend_package: Package = .{
        .classifiers = &backend_classifiers,
        .license = .{ .expression = "MIT", .files = &license_files },
        .name = "lacuna-build",
        .scripts = &backend_scripts,
        .summary = "A PEP 517 build backend for Python extensions written in Zig with lacuna",
        .version = "0.1.0",
    };

    const builder = context.builder;
    const owner: Owner = .{ .builder = builder, .module = context.module };
    const tool = tool_create(builder, owner, .{ .name = "wheel", .root = "src/wheel.zig" });
    const filename = "lacuna_build-0.1.0-py3-none-any.whl";
    const run = builder.addRunArtifact(tool);
    const output = run.addOutputFileArg(filename);

    backend_entries_add(builder, run, &backend_package);

    const install = builder.addInstallFileWithDir(output, .{ .custom = "backend" }, filename);

    context.steps.backend.dependOn(&install.step);

    for (backend_tests) |script| {
        const check = builder.addSystemCommand(context.python);

        check.addArgs(&.{ "-B", "-X", "dev", "-W", "error" });
        check.addFileArg(builder.path("tools/backend.py"));
        check.addDirectoryArg(builder.path("."));
        check.addFileArg(output);
        check.addFileArg(builder.path(script));
        check.has_side_effects = true;

        context.steps.test_backend.dependOn(&check.step);
    }
}

fn backend_entries_add(
    builder: *std.Build,
    run: *std.Build.Step.Run,
    package: *const Package,
) void {
    assert(run.step.owner == builder);
    assert(package.name.len > 0);
    assert(package.scripts.len > 0);

    var metadata_buffer: [package_module.metadata_bytes_max]u8 = undefined;
    var wheel_buffer: [package_module.wheel_bytes_max]u8 = undefined;

    const directory = "lacuna_build-0.1.0.dist-info";
    const files = builder.addWriteFiles();

    run.addArg(directory);
    const metadata = metadata_text(&metadata_buffer, package, python_version_floor);

    run.addFileArg(files.add("METADATA", metadata));
    run.addArg("-");

    const wheel = wheel_text(&wheel_buffer, .{
        .interpreter = "py3-none",
        .platform = "any",
        .purelib = true,
    });

    var entry_buffer: [package_module.metadata_bytes_max]u8 = undefined;

    const entry_points = entry_points_text(&entry_buffer, package) orelse unreachable;

    entry_add(run, "lacuna_build/", builder.path("backend/lacuna_build"));
    entry_add(run, "lacuna_build/template/", builder.path("templates/project"));
    entry_add(run, directory ++ "/WHEEL", files.add("WHEEL", wheel));
    entry_add(run, directory ++ "/entry_points.txt", files.add("entry_points.txt", entry_points));
    entry_add(run, directory ++ "/licenses/LICENSE", builder.path("LICENSE"));

    for (backend_vendored) |vendored| {
        const name = builder.fmt("lacuna_build/lacuna/{s}", .{vendored});
        const path = builder.path(std.mem.trimEnd(u8, vendored, "/"));

        entry_add(run, name, path);
    }
}

const Headers = struct {
    free_threaded: ?Version,
    pypy: ?Version,
    versioned: ?Version,
};

fn headers_option(builder: *std.Build) Headers {
    assert(builder.graph.zig_exe.len > 0);
    assert(free_threaded_range.minor_min <= versioned_range.minor_max);

    const free_threaded = builder.option(
        []const u8,
        "python-free-threaded",
        "The free-threaded version of the headers, such as 3.14, for the ABI check",
    );

    const versioned = builder.option(
        []const u8,
        "python-versioned",
        "The version of the full headers, such as 3.14, for the version-specific ABI check",
    );

    const free_threaded_version = if (free_threaded) |text|
        version_option(text, free_threaded_range)
    else
        null;

    const versioned_version = if (versioned) |text| version_option(text, versioned_range) else null;

    const pypy = builder.option(
        []const u8,
        "python-pypy",
        "The PyPy version of the headers, such as 3.11, for the PyPy ABI check",
    );

    const pypy_version = if (pypy) |text| version_option(text, pypy_range) else null;

    const exclusive_count = @intFromBool(free_threaded_version != null) +
        @intFromBool(versioned_version != null) +
        @intFromBool(pypy_version != null);

    if (exclusive_count > 1) {
        std.process.fatal("lacuna: the ABI check takes at most one of -Dpython-free-threaded, " ++
            "-Dpython-versioned, and -Dpython-pypy", .{});
    }

    return .{
        .free_threaded = free_threaded_version,
        .pypy = pypy_version,
        .versioned = versioned_version,
    };
}

fn version_option(text: []const u8, range: VersionRange) Version {
    assert(text.len <= argument_bytes_max);
    assert(range.minor_min <= range.minor_max);

    const message = "lacuna: '{s}' is not a {s} version from 3.{d} to 3.{d}";
    const arguments = .{ text, range.kind, range.minor_min, range.minor_max };
    const dot = std.mem.findScalar(u8, text, '.') orelse std.process.fatal(message, arguments);

    const major = std.fmt.parseInt(u8, text[0..dot], 10) catch {
        std.process.fatal(message, arguments);
    };

    const minor = std.fmt.parseInt(u8, text[dot + 1 ..], 10) catch {
        std.process.fatal(message, arguments);
    };

    assert(text[dot] == '.');

    if (major != 3) std.process.fatal(message, arguments);
    if (minor < range.minor_min) std.process.fatal(message, arguments);
    if (minor > range.minor_max) std.process.fatal(message, arguments);

    return .{ .major = major, .minor = minor };
}

fn steps_declare(builder: *std.Build) Steps {
    assert(builder.graph.zig_exe.len > 0);
    assert(examples.len > 0);

    const result = Steps{
        .backend = builder.step("backend", "Build the lacuna_build wheel into zig-out/backend"),
        .check = builder.step(
            "check",
            "Compile every example for every release and local-only platform",
        ),
        .continuous_integration = builder.step("ci", "Run every check, test, and wheel build"),
        .example = builder.step("example", "Install every example package into zig-out/python"),
        .test_abi = builder.step("test:abi", "Check the extern declarations against Python.h"),
        .test_all = builder.step(
            "test",
            "Run the unit tests, the tidy check, and the format check",
        ),
        .test_audit = builder.step(
            "test:audit",
            "Check every Linux wheel against the auditwheel platform policy",
        ),
        .test_backend = builder.step(
            "test:backend",
            "Build, install, and edit a project through the lacuna_build backend",
        ),
        .test_compile_fail = builder.step(
            "test:compile-fail",
            "Check that every misuse in tests/compile_fail stops the build with its diagnostic",
        ),
        .test_debug = builder.step(
            "test:debug",
            "Test every example under a debug Python and fail any test that leaks references",
        ),
        .test_format = builder.step("test:fmt", "Check that every source file is formatted"),
        .test_free_threaded = builder.step(
            "test:free-threaded",
            "Test every example under each free-threaded Python",
        ),
        .test_property = builder.step(
            "test:property",
            "Check every example against its Hypothesis properties and hostile inputs",
        ),
        .test_pypy = builder.step(
            "test:pypy",
            "Test every example under each PyPy it is built for",
        ),
        .test_python = builder.step("test:python", "Import every example in Python and test it"),
        .test_stub = builder.step("test:stub", "Compare every example stub with its module"),
        .test_tsan = builder.step(
            "test:tsan",
            "Test every example under a ThreadSanitizer free-threaded Python",
        ),
        .test_unit = builder.step("test:unit", "Run the unit tests and the tidy check"),
        .test_versioned = builder.step(
            "test:versioned",
            "Test every example under each Python it has a version-specific build for",
        ),
        .test_wheel = builder.step("test:wheel", "Install every host wheel with pip and test it"),
        .wheel = builder.step("wheel", "Build a wheel of every example for every platform"),
    };

    assert(result.check != result.test_all);
    assert(result.wheel != result.example);

    return result;
}

fn add_tool_check(context: *const Context) void {
    assert(tool_hosts.len > 0);
    assert(context.steps.check != context.steps.test_all);

    const builder = context.builder;

    for (tool_hosts) |query| {
        for (tool_roots) |root| {
            const tool = builder.addExecutable(.{
                .name = std.fs.path.stem(root),
                .root_module = builder.createModule(.{
                    .root_source_file = builder.path(root),
                    .target = builder.resolveTargetQuery(query),
                    .optimize = .safe,
                }),
            });

            context.steps.check.dependOn(&tool.step);
        }
    }
}

fn add_examples(context: *const Context) void {
    assert(examples.len > 0);
    assert(context.steps.example != context.steps.test_python);

    const owner: Owner = .{ .builder = context.builder, .module = context.module };

    const license_files = [_]LicenseFile{
        .{ .name = "LICENSE", .path = context.builder.path("LICENSE") },
    };

    for (examples) |example| {
        const options = example_options(context, example, &license_files);
        const extension = extension_add(context.builder, owner, &options);

        const test_options: PythonTestOptions = .{
            .conftest = context.builder.path(conftest_path),
            .python = context.python,
            .script = context.builder.path(example.script),
        };

        const stub_options: StubTestOptions = .{ .name = example.name, .python = &stub_python };
        const run = add_python_test(context.builder, &extension, test_options);
        const install = add_wheel_test(context.builder, &extension, test_options);
        const stub = add_stub_test(context.builder, &extension, stub_options);

        context.steps.example.dependOn(extension.develop);
        context.steps.test_python.dependOn(&run.step);
        context.steps.test_wheel.dependOn(&install.step);
        context.steps.test_stub.dependOn(&stub.step);
        context.steps.wheel.dependOn(extension.wheel);
        context.steps.check.dependOn(extension.check);

        if (example.wheel_script) |script| {
            const wheel_options: PythonTestOptions = .{
                .conftest = context.builder.path(conftest_path),
                .python = context.python,
                .script = context.builder.path(script),
            };

            const metadata = add_wheel_test(context.builder, &extension, wheel_options);

            context.steps.test_wheel.dependOn(&metadata.step);
        }

        add_audit_tests(context, &extension);
        add_debug_tests(context, &extension, example);
        add_free_threaded_tests(context, &extension, example);
        add_property_test(context, &extension, example);
        add_versioned_tests(context, &extension, example);
        add_pypy_tests(context, &extension, example);
        add_tsan_tests(context, &extension, example);
    }
}

fn add_pypy_tests(context: *const Context, extension: *const Extension, example: Example) void {
    assert(extension.pypy.len <= pypy_count_max);
    assert(example.script.len > 0);

    const builder = context.builder;

    for (extension.pypy) |pypy| {
        const version = pypy.version;
        const interpreter = builder.fmt("pypy@{d}.{d}", .{ version.major, version.minor });

        const python = [_][]const u8{
            "uv",
            "run",
            "--no-project",
            "--python",
            interpreter,
            "--with",
            "pytest",
            "--with",
            "pip",
            "python",
        };

        const options: PythonTestOptions = .{
            .conftest = builder.path(conftest_path),
            .pypy = pypy,
            .python = &python,
            .script = builder.path(example.script),
        };

        const run = add_python_test(builder, extension, options);
        const install = add_wheel_test(builder, extension, options);

        context.steps.test_pypy.dependOn(&run.step);
        context.steps.test_pypy.dependOn(&install.step);
    }
}

fn add_property_test(context: *const Context, extension: *const Extension, example: Example) void {
    assert(example.script.len > 0);
    assert(extension.package == .generated);

    const script = example.property_script orelse return;
    const builder = context.builder;

    const options: PythonTestOptions = .{
        .conftest = builder.path(conftest_path),
        .python = &python_property,
        .script = builder.path(script),
    };

    const run = add_python_test(builder, extension, options);

    context.steps.test_property.dependOn(&run.step);
}

fn add_audit_tests(context: *const Context, extension: *const Extension) void {
    assert(extension.platforms.len <= platform_count_max);
    assert(context.steps.test_audit != context.steps.test_all);

    for (extension.platforms, 0..) |platform, index| {
        if (!audit_applies(platform)) continue;

        audit_add(context, extension.wheels[index], platform);

        for (extension.wheels_free_threaded[index]) |candidate| {
            if (candidate) |built| audit_add(context, built, platform);
        }

        for (extension.wheels_pypy[index]) |candidate| {
            if (candidate) |built| audit_add(context, built, platform);
        }

        for (extension.wheels_versioned[index]) |candidate| {
            if (candidate) |built| audit_add(context, built, platform);
        }
    }
}

fn audit_applies(platform: Platform) bool {
    assert(platform.tag.len > 0);

    if (std.mem.startsWith(u8, platform.tag, "manylinux_")) return true;
    return std.mem.startsWith(u8, platform.tag, "musllinux_");
}

fn audit_add(context: *const Context, built: Built, platform: Platform) void {
    assert(audit_applies(platform));
    assert(platform.query.os_tag == .linux);
    assert(built.step.owner == context.builder);

    const builder = context.builder;
    const run = builder.addSystemCommand(&python_audit);

    run.addArgs(&.{ "-B", "-X", "dev" });
    run.addFileArg(builder.path("tools/audit.py"));
    run.addFileArg(built.path);
    run.addArg(platform.tag);
    run.expectExitCode(0);

    context.steps.test_audit.dependOn(&run.step);
}

fn add_debug_tests(context: *const Context, extension: *const Extension, example: Example) void {
    assert(example.script.len > 0);
    assert(extension.package == .generated);

    const builder = context.builder;
    const scripts = [_]?[]const u8{ example.script, example.leak_script, example.property_script };

    for (scripts) |candidate| {
        const script = candidate orelse continue;

        const options: PythonTestOptions = .{
            .conftest = builder.path(conftest_path),
            .python = &python_debug,
            .script = builder.path(script),
        };

        const run = add_python_test(builder, extension, options);

        context.steps.test_debug.dependOn(&run.step);
    }
}

fn add_tsan_tests(context: *const Context, extension: *const Extension, example: Example) void {
    assert(example.script.len > 0);
    assert(context.steps.test_tsan != context.steps.test_free_threaded);

    const builder = context.builder;

    if (extension.package_tsan == null) return;

    const python = context.python_tsan orelse {
        const message = "lacuna: test:tsan needs -Dpython-tsan=<ThreadSanitizer Python>";

        context.steps.test_tsan.dependOn(&builder.addFail(message).step);

        return;
    };

    if (builder.graph.host.result.os.tag != .linux) {
        const message = "lacuna: test:tsan runs only on a Linux host";

        context.steps.test_tsan.dependOn(&builder.addFail(message).step);

        return;
    }

    const options: PythonTestOptions = .{
        .conftest = builder.path(conftest_path),
        .python = python,
        .script = builder.path(example.script),
        .tsan = true,
    };

    const run = add_python_test(builder, extension, options);

    run.addArg("--capture=sys");

    for (tsan_environment) |variable| run.setEnvironmentVariable(variable[0], variable[1]);

    context.steps.test_tsan.dependOn(&run.step);
}

fn add_free_threaded_tests(
    context: *const Context,
    extension: *const Extension,
    example: Example,
) void {
    assert(extension.free_threaded.len <= free_threaded_count_max);
    assert(example.script.len > 0);

    const builder = context.builder;

    for (extension.free_threaded) |version| {
        const interpreter = builder.fmt("{d}.{d}t", .{ version.major, version.minor });

        const python = [_][]const u8{
            "uv",
            "run",
            "--no-project",
            "--python",
            interpreter,
            "--with",
            "pytest",
            "python",
        };

        const options: PythonTestOptions = .{
            .conftest = builder.path(conftest_path),
            .free_threaded = version,
            .python = &python,
            .script = builder.path(example.script),
        };

        const run = add_python_test(builder, extension, options);
        const install = add_wheel_test(builder, extension, options);

        context.steps.test_free_threaded.dependOn(&run.step);
        context.steps.test_free_threaded.dependOn(&install.step);

        if (example.property_script) |script| {
            const property_python = [_][]const u8{
                "uv",
                "run",
                "--no-project",
                "--python",
                interpreter,
                "--with",
                "pytest",
                "--with",
                "hypothesis",
                "python",
            };

            const property_options: PythonTestOptions = .{
                .conftest = builder.path(conftest_path),
                .free_threaded = version,
                .python = &property_python,
                .script = builder.path(script),
            };

            const property = add_python_test(builder, extension, property_options);

            context.steps.test_free_threaded.dependOn(&property.step);
        }
    }
}

fn add_versioned_tests(
    context: *const Context,
    extension: *const Extension,
    example: Example,
) void {
    assert(extension.versioned.len <= versioned_count_max);
    assert(example.script.len > 0);

    const builder = context.builder;

    for (extension.versioned) |version| {
        const interpreter = builder.fmt("{d}.{d}+gil", .{ version.major, version.minor });

        const python = [_][]const u8{
            "uv",
            "run",
            "--no-project",
            "--python",
            interpreter,
            "--with",
            "pytest",
            "python",
        };

        const options: PythonTestOptions = .{
            .conftest = builder.path(conftest_path),
            .python = &python,
            .script = builder.path(example.script),
            .versioned = version,
        };

        const run = add_python_test(builder, extension, options);
        const install = add_wheel_test(builder, extension, options);

        context.steps.test_versioned.dependOn(&run.step);
        context.steps.test_versioned.dependOn(&install.step);
    }
}

fn example_options(
    context: *const Context,
    example: Example,
    license_files: []const LicenseFile,
) ExtensionOptions {
    assert(example.name.len > 0);
    assert(std.mem.startsWith(u8, example.root, "examples/"));
    assert(license_files.len > 0);

    const builder = context.builder;

    const distribution = example.name[0 .. std.mem.findScalar(u8, example.name, '.') orelse
        example.name.len];

    return .{
        .dispatch = true,
        .module = builder.createModule(.{ .root_source_file = builder.path(example.root) }),
        .name = example.name,
        .optimize = context.optimize,
        .package = .{
            .data = if (example.python_source != null) mixed_data(builder) else &.{},
            .dependencies = if (example.python_source != null) &mixed_dependencies else &.{},
            .description = .{ .content_type = "text/markdown", .path = builder.path("README.md") },
            .extras = if (example.python_source != null) &mixed_extras else &.{},
            .license = .{ .expression = "MIT", .files = license_files },
            .name = distribution,
            .scripts = if (example.python_source != null) &mixed_scripts else &.{},
            .summary = "An lacuna example extension",
            .version = "0.1.0",
        },
        .platforms = if (std.mem.eql(u8, example.name, "hello"))
            &platforms_universal2
        else
            &platforms,
        .python_source = if (example.python_source) |source| builder.path(source) else null,
        .strip = false,
        .target = context.target,
        .pypy = &pypy_all,
        .versioned = &versioned_examples,
    };
}

const mixed_dependencies = [_][]const u8{"typing-extensions>=4.6"};

fn mixed_data(builder: *std.Build) []const DataFile {
    assert(builder.graph.zig_exe.len > 0);
    assert(@typeInfo(DataScheme).@"enum".field_names.len == 5);

    const files = builder.allocator.alloc(DataFile, 2) catch @panic("out of memory");

    files[0] = .{
        .name = "share/mixed/notes.txt",
        .path = builder.path("examples/mixed_data/notes.txt"),
        .scheme = .data,
    };

    files[1] = .{
        .name = "mixed/",
        .path = builder.path("examples/mixed_data/include"),
        .scheme = .headers,
    };

    return files;
}
const mixed_extras = [_]Extra{.{ .dependencies = &.{"pytest>=8"}, .name = "test" }};
const mixed_scripts = [_]EntryPoint{.{ .name = "mixed-greet", .target = "mixed.helpers:main" }};

pub fn add_extension(builder: *std.Build, options: ExtensionOptions) Extension {
    assert(builder.graph.zig_exe.len > 0);
    assert(options.module.owner.graph == builder.graph);

    const arguments: struct {} = .{};
    const dependency = builder.dependencyFromBuildZig(@This(), arguments);
    const owner: Owner = .{ .builder = dependency.builder, .module = dependency.module("lacuna") };

    assert(owner.builder.graph == builder.graph);

    return extension_add(builder, owner, &options);
}

pub fn add_python_test(
    builder: *std.Build,
    extension: *const Extension,
    options: PythonTestOptions,
) *std.Build.Step.Run {
    assert(options.python.len > 0);
    assert(extension.package == .generated);
    assert(options.free_threaded == null or options.versioned == null);
    if (options.tsan) assert(extension.package_tsan != null);

    const package = if (options.tsan) extension.package_tsan.? else package_selected(
        extension,
        &options,
    );

    const files = builder.addWriteFiles();
    const script = files.addCopyFile(options.script, "test_extension.py");

    if (options.conftest) |conftest| _ = files.addCopyFile(conftest, "conftest.py");

    _ = files.addCopyDirectory(package, "", .{
        .exclude_extensions = &.{},
        .include_extensions = null,
    });

    const run = builder.addSystemCommand(options.python);

    run.addArgs(&pytest_arguments);

    run.addFileArg(script);
    run.has_side_effects = true;

    return run;
}

pub fn add_stub_test(
    builder: *std.Build,
    extension: *const Extension,
    options: StubTestOptions,
) *std.Build.Step.Run {
    assert(options.python.len > 0);
    assert(options.name.len > 0);
    assert(extension.package == .generated);

    const null_device = if (builder.graph.host.result.os.tag == .windows) "nul" else "/dev/null";
    const files = builder.addWriteFiles();

    const configuration = files.add(
        "mypy.ini",
        builder.fmt("[mypy]\ncache_dir = {s}\n", .{null_device}),
    );

    const run = builder.addSystemCommand(options.python);

    run.addArgs(&.{ "-B", "-m", "mypy.stubtest", "--concise", "--mypy-config-file" });
    run.addFileArg(configuration);
    run.addArg(options.name);
    run.setCwd(extension.package);
    run.has_side_effects = true;

    return run;
}

pub fn add_wheel_test(
    builder: *std.Build,
    extension: *const Extension,
    options: PythonTestOptions,
) *std.Build.Step.Run {
    assert(options.python.len > 0);
    assert(extension.platforms.len <= platform_count_max);
    assert(options.free_threaded == null or options.versioned == null);

    const host = builder.graph.host.result;
    const run = builder.addSystemCommand(options.python);

    run.addFileArg(extension.installer);
    run.has_side_effects = true;

    const index = platform_hosted_index(extension.platforms, host) orelse {
        run.step.dependOn(&builder.addFail("lacuna: no release platform matches the host").step);

        return run;
    };

    const wheel = wheel_selected(extension, &options, index) orelse {
        const fail = builder.addFail(builder.fmt("lacuna: the host builds no {s} wheel", .{
            wheel_kind(&options),
        }));

        run.step.dependOn(&fail.step);

        return run;
    };

    run.addFileArg(wheel.path);
    run.addFileArg(options.script);

    return run;
}

fn package_selected(
    extension: *const Extension,
    options: *const PythonTestOptions,
) std.Build.LazyPath {
    assert(extension.package == .generated);
    assert(options.free_threaded == null or options.versioned == null);

    if (options.free_threaded) |version| {
        return extension.packages_free_threaded[free_threaded_index(extension, version)];
    }

    if (options.versioned) |version| {
        return extension.packages_versioned[versioned_index(extension, version)];
    }

    if (options.pypy) |pypy| return extension.packages_pypy[pypy_index(extension, pypy)];

    return extension.package;
}

fn wheel_selected(
    extension: *const Extension,
    options: *const PythonTestOptions,
    index: u32,
) ?Built {
    assert(index < platform_count_max);
    assert(options.free_threaded == null or options.versioned == null);

    if (options.free_threaded) |version| {
        return extension.wheels_free_threaded[index][free_threaded_index(extension, version)];
    }

    if (options.versioned) |version| {
        return extension.wheels_versioned[index][versioned_index(extension, version)];
    }

    if (options.pypy) |pypy| return extension.wheels_pypy[index][pypy_index(extension, pypy)];

    return extension.wheels[index];
}

fn wheel_kind(options: *const PythonTestOptions) []const u8 {
    assert(options.python.len > 0);
    assert(options.free_threaded == null or options.versioned == null);

    if (options.free_threaded != null) return "free-threaded";
    if (options.versioned != null) return "version-specific";
    if (options.pypy != null) return "PyPy";
    return "stable";
}

fn free_threaded_index(extension: *const Extension, version: Version) u32 {
    assert(extension.free_threaded.len <= free_threaded_count_max);
    assert(version.major > 0);

    for (extension.free_threaded, 0..) |present, index| {
        if (std.meta.eql(present, version)) {
            const result: u32 = @intCast(index);

            assert(result < free_threaded_count_max);

            return result;
        }
    }

    std.process.fatal("lacuna: the extension builds no free-threaded {d}.{d}", .{
        version.major,
        version.minor,
    });
}

fn pypy_index(extension: *const Extension, pypy: PyPyVersion) u32 {
    assert(extension.pypy.len <= pypy_count_max);
    assert(pypy.abi.len > 0);

    for (extension.pypy, 0..) |present, index| {
        if (std.meta.eql(present.version, pypy.version)) {
            if (std.mem.eql(u8, present.abi, pypy.abi)) {
                const result: u32 = @intCast(index);

                assert(result < pypy_count_max);

                return result;
            }
        }
    }

    std.process.fatal("lacuna: the extension builds no PyPy {d}.{d} {s}", .{
        pypy.version.major,
        pypy.version.minor,
        pypy.abi,
    });
}

fn versioned_index(extension: *const Extension, version: Version) u32 {
    assert(extension.versioned.len <= versioned_count_max);
    assert(version.major > 0);

    for (extension.versioned, 0..) |present, index| {
        if (std.meta.eql(present, version)) {
            const result: u32 = @intCast(index);

            assert(result < versioned_count_max);

            return result;
        }
    }

    std.process.fatal("lacuna: the extension builds no version-specific {d}.{d}", .{
        version.major,
        version.minor,
    });
}

fn platform_hosted_index(candidates: []const Platform, host: std.Target) ?u32 {
    assert(candidates.len <= platform_count_max);
    assert(host.os.tag != .freestanding);

    for (candidates, 0..) |platform, index| {
        if (platform_hosted(platform, host)) {
            const result: u32 = @intCast(index);

            assert(result < platform_count_max);

            return result;
        }
    }

    return null;
}

fn platform_hosted(platform: Platform, host: std.Target) bool {
    assert(platform.tag.len > 0);
    assert(host.os.tag != .freestanding);

    if (platform.query.cpu_arch != host.cpu.arch) return false;
    if (platform.query.os_tag != host.os.tag) return false;
    if (host.os.tag != .linux) return true;
    return platform.query.abi == host.abi;
}

fn extension_add(builder: *std.Build, owner: Owner, options: *const ExtensionOptions) Extension {
    assert(owner.builder.graph == builder.graph);
    assert(options.module.owner.graph == builder.graph);

    options_validate(options);

    assert(options.platforms.len <= platform_count_max);
    assert(options.free_threaded.len <= free_threaded_count_max);
    assert(options.versioned.len <= versioned_count_max);

    options.module.addImport("lacuna", owner.module);

    const layout = layout_of(builder, options.name);
    const stub = stub_generate(builder, owner, options);
    const tools = tools_create(builder, owner);

    const develop = develop_add(builder, owner, options, .{
        .layout = layout,
        .stub = stub,
        .variant = .stable,
    });

    const wheel_step = builder.step(
        builder.fmt("wheel:{s}", .{options.name}),
        builder.fmt("Build every wheel of {s}", .{options.name}),
    );

    const check_step = check_step_add(builder, options.name, wheel_step);

    var result: Extension = .{
        .check = check_step,
        .develop = develop.step,
        .free_threaded = options.free_threaded,
        .installer = owner.builder.path("tools/install.py"),
        .package = develop.tree,
        .packages_free_threaded = undefined,
        .packages_pypy = undefined,
        .package_tsan = null,
        .platforms = options.platforms,
        .pypy = options.pypy,
        .versioned = options.versioned,
        .packages_versioned = undefined,
        .wheel = wheel_step,
        .wheels = undefined,
        .wheels_free_threaded = @splat(@splat(null)),
        .wheels_pypy = @splat(@splat(null)),
        .wheels_versioned = @splat(@splat(null)),
    };

    packages_add(builder, owner, options, .{ .layout = layout, .stub = stub }, &result);

    const common: Common = .{
        .layout = layout,
        .options = options,
        .owner = owner,
        .stub = stub,
        .tools = tools,
    };

    releases_add(builder, common, &result);
    releases_local_add(builder, common, check_step);

    host_steps_add(builder, options, &result);
    metadata_step_add(builder, options, tools.wheel);

    return result;
}

const Located = struct {
    layout: Layout,
    stub: std.Build.LazyPath,
};

fn packages_add(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    located: Located,
    extension: *Extension,
) void {
    assert(owner.builder.graph == builder.graph);
    assert(options.free_threaded.len <= free_threaded_count_max);
    assert(options.versioned.len <= versioned_count_max);
    assert(located.stub == .generated);

    for (options.free_threaded, 0..) |version, index| {
        const free = develop_add(builder, owner, options, .{
            .layout = located.layout,
            .stub = located.stub,
            .variant = .{ .free_threaded = version },
        });

        extension.packages_free_threaded[index] = free.tree;
    }

    for (options.versioned, 0..) |version, index| {
        const versioned = develop_add(builder, owner, options, .{
            .layout = located.layout,
            .stub = located.stub,
            .variant = .{ .versioned = version },
        });

        extension.packages_versioned[index] = versioned.tree;
    }

    for (options.pypy, 0..) |pypy, index| {
        const developed = develop_add(builder, owner, options, .{
            .layout = located.layout,
            .stub = located.stub,
            .variant = .{ .pypy = pypy },
        });

        extension.packages_pypy[index] = developed.tree;
    }

    for (options.free_threaded) |version| {
        if (!std.meta.eql(version, tsan_version)) continue;

        extension.package_tsan = develop_tree(builder, owner, options, .{
            .layout = located.layout,
            .sanitize_thread = true,
            .stub = located.stub,
            .variant = .{ .free_threaded = version },
        });
    }
}

const Common = struct {
    layout: Layout,
    options: *const ExtensionOptions,
    owner: Owner,
    stub: std.Build.LazyPath,
    tools: Tools,

    fn request(common: Common, platform: Platform, variant: Variant) ReleaseRequest {
        assert(variant != .free_threaded or platform.free_threaded);
        assert(variant != .versioned or !platform.python_linked);
        assert(platform.tag.len > 0);
        assert(common.stub == .generated);

        return .{
            .layout = common.layout,
            .options = common.options,
            .owner = common.owner,
            .platform = platform,
            .stub = common.stub,
            .tools = common.tools,
            .variant = variant,
        };
    }
};

fn releases_add(builder: *std.Build, common: Common, extension: *Extension) void {
    assert(common.options.platforms.len <= platform_count_max);
    assert(extension.platforms.len == common.options.platforms.len);

    for (common.options.platforms, 0..) |platform, index| {
        const stable = release_build(builder, common.request(platform, .stable));

        extension.wheel.dependOn(stable.step);
        extension.wheels[index] = stable;

        if (platform.free_threaded) {
            for (common.options.free_threaded, 0..) |version, version_index| {
                const variant: Variant = .{ .free_threaded = version };
                const free = release_build(builder, common.request(platform, variant));

                extension.wheel.dependOn(free.step);
                extension.wheels_free_threaded[index][version_index] = free;
            }
        }

        if (platform.pypy) {
            for (common.options.pypy, 0..) |pypy, pypy_index_value| {
                const variant: Variant = .{ .pypy = pypy };
                const built = release_build(builder, common.request(platform, variant));

                extension.wheel.dependOn(built.step);
                extension.wheels_pypy[index][pypy_index_value] = built;
            }
        }

        if (!platform.python_linked) {
            for (common.options.versioned, 0..) |version, version_index| {
                const variant: Variant = .{ .versioned = version };
                const versioned = release_build(builder, common.request(platform, variant));

                extension.wheel.dependOn(versioned.step);
                extension.wheels_versioned[index][version_index] = versioned;
            }
        }
    }
}

fn check_step_add(builder: *std.Build, name: []const u8, wheel: *std.Build.Step) *std.Build.Step {
    assert(name.len > 0);
    assert(wheel.owner == builder);

    const result = builder.step(
        builder.fmt("check:{s}", .{name}),
        builder.fmt("Build every wheel of {s} and every local-only platform", .{name}),
    );

    result.dependOn(wheel);

    return result;
}

fn releases_local_add(builder: *std.Build, common: Common, check: *std.Build.Step) void {
    assert(common.options.platforms.len <= platform_count_max);
    assert(common.options.versioned.len <= versioned_count_max);

    for (platforms_local) |platform| {
        if (platform_listed(common.options.platforms, platform)) continue;

        const stable = release_build(builder, common.request(platform, .stable));

        check.dependOn(stable.step);

        for (common.options.versioned) |version| {
            const variant: Variant = .{ .versioned = version };
            const versioned = release_build(builder, common.request(platform, variant));

            check.dependOn(versioned.step);
        }
    }
}

fn platform_listed(candidates: []const Platform, platform: Platform) bool {
    assert(candidates.len <= platform_count_max);
    assert(platform.tag.len > 0);

    for (candidates) |candidate| {
        if (std.mem.eql(u8, candidate.tag, platform.tag)) return true;
    }

    return false;
}

fn platform_bsd(platform: Platform) bool {
    assert(platform.tag.len > 0);
    assert(platform.query.os_tag != null);

    return switch (platform.query.os_tag.?) {
        .freebsd, .netbsd, .openbsd => true,
        else => false,
    };
}

const Developed = struct {
    step: *std.Build.Step,
    tree: std.Build.LazyPath,
};

const DevelopRequest = struct {
    layout: Layout,
    sanitize_thread: bool = false,
    stub: std.Build.LazyPath,
    variant: Variant,
};

fn develop_add(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    request: DevelopRequest,
) Developed {
    assert(owner.builder.graph == builder.graph);
    assert(request.stub == .generated);
    assert(!request.sanitize_thread);

    const tree = develop_tree(builder, owner, options, request);

    const directory = switch (request.variant) {
        .stable => "python",
        .free_threaded => |version| builder.fmt("python-{d}.{d}t", .{
            version.major,
            version.minor,
        }),
        .versioned => |version| builder.fmt("python-{d}.{d}", .{
            version.major,
            version.minor,
        }),
        .pypy => |pypy| builder.fmt("python-pypy{d}.{d}", .{
            pypy.version.major,
            pypy.version.minor,
        }),
    };

    const install = builder.addInstallDirectory(.{
        .source_dir = tree,
        .install_dir = .{ .custom = directory },
        .install_subdir = "",
    });

    const step = builder.step(
        builder.fmt("{s}:{s}", .{ develop_name(builder, request.variant), options.name }),
        builder.fmt("Install {s} into zig-out/{s}", .{ options.name, directory }),
    );

    step.dependOn(&install.step);

    return .{ .step = step, .tree = tree };
}

fn develop_tree(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    request: DevelopRequest,
) std.Build.LazyPath {
    assert(owner.builder.graph == builder.graph);
    assert(request.stub == .generated);
    assert(options.name.len > 0);

    const library = library_compile(builder, owner, options, .{
        .export_name = "",
        .optimize = options.optimize,
        .sanitize_thread = request.sanitize_thread,
        .target = options.target,
        .variant = request.variant,
    });

    const windows = options.target.result.os.tag == .windows;

    const suffix = switch (request.variant) {
        .pypy => pypy_host_suffix(builder, options, request.variant.pypy),
        else => if (windows) ".pyd" else switch (request.variant) {
            .stable => ".abi3.so",
            .free_threaded, .pypy, .versioned => ".so",
        },
    };

    return tree_create(builder, .{
        .layout = request.layout,
        .library = library,
        .python_filter = python_filter_of(options),
        .python_source = options.python_source,
        .stub = request.stub,
        .suffix = suffix,
    });
}

fn host_pypy_steps_add(
    builder: *std.Build,
    options: *const ExtensionOptions,
    extension: *Extension,
    index: u32,
) void {
    assert(index < platform_count_max);
    assert(options.pypy.len <= pypy_count_max);

    for (options.pypy, 0..) |pypy, pypy_position| {
        const version = pypy.version;

        const step = builder.step(
            builder.fmt("wheel-host-pypy{d}.{d}:{s}", .{
                version.major,
                version.minor,
                options.name,
            }),
            builder.fmt("Build the PyPy {d}.{d} host wheel of {s}", .{
                version.major,
                version.minor,
                options.name,
            }),
        );

        const wheel = extension.wheels_pypy[index][pypy_position] orelse {
            step.dependOn(&builder.addFail("lacuna: the host builds no PyPy wheel").step);

            continue;
        };

        step.dependOn(wheel.step);
    }
}

fn pypy_host_suffix(
    builder: *std.Build,
    options: *const ExtensionOptions,
    pypy: PyPyVersion,
) []const u8 {
    assert(pypy.abi.len > 0);
    assert(options.platforms.len <= platform_count_max);

    const host = options.target.result;
    const index = platform_hosted_index(options.platforms, host) orelse {
        std.process.fatal("lacuna: no release platform of {s} matches the host for PyPy", .{
            options.name,
        });
    };

    return suffix_of(builder, options.platforms[index], .{ .pypy = pypy });
}

fn develop_name(builder: *std.Build, variant: Variant) []const u8 {
    assert(builder.graph.zig_exe.len > 0);
    assert(variant != .free_threaded or variant.free_threaded.minor >= free_threaded_minor_min);
    assert(variant != .versioned or variant.versioned.minor >= versioned_minor_min);

    return switch (variant) {
        .stable => "develop",
        .free_threaded => |version| builder.fmt("develop-{d}.{d}t", .{
            version.major,
            version.minor,
        }),
        .versioned => |version| builder.fmt("develop-{d}.{d}", .{
            version.major,
            version.minor,
        }),
        .pypy => |pypy| builder.fmt("develop-pypy{d}.{d}", .{
            pypy.version.major,
            pypy.version.minor,
        }),
    };
}

fn host_steps_add(
    builder: *std.Build,
    options: *const ExtensionOptions,
    extension: *Extension,
) void {
    assert(extension.platforms.len <= platform_count_max);
    assert(options.name.len > 0);

    const host = builder.graph.host.result;

    const stable = builder.step(
        builder.fmt("wheel-host:{s}", .{options.name}),
        builder.fmt("Build the host wheel of {s}", .{options.name}),
    );

    const index = platform_hosted_index(extension.platforms, host) orelse {
        stable.dependOn(&builder.addFail("lacuna: no release platform matches the host").step);

        return;
    };

    stable.dependOn(extension.wheels[index].step);

    for (options.free_threaded, 0..) |version, version_index| {
        const step = builder.step(
            builder.fmt("wheel-host-{d}.{d}t:{s}", .{ version.major, version.minor, options.name }),
            builder.fmt("Build the free-threaded {d}.{d} host wheel of {s}", .{
                version.major,
                version.minor,
                options.name,
            }),
        );

        const wheel = extension.wheels_free_threaded[index][version_index] orelse {
            step.dependOn(&builder.addFail("lacuna: the host builds no free-threaded wheel").step);

            continue;
        };

        step.dependOn(wheel.step);
    }

    host_pypy_steps_add(builder, options, extension, index);

    for (options.versioned, 0..) |version, version_index| {
        const step = builder.step(
            builder.fmt("wheel-host-{d}.{d}:{s}", .{ version.major, version.minor, options.name }),
            builder.fmt("Build the version-specific {d}.{d} host wheel of {s}", .{
                version.major,
                version.minor,
                options.name,
            }),
        );

        const wheel = extension.wheels_versioned[index][version_index] orelse {
            const fail = builder.addFail("lacuna: the host builds no version-specific wheel");

            step.dependOn(&fail.step);

            continue;
        };

        step.dependOn(wheel.step);
    }
}

fn metadata_step_add(
    builder: *std.Build,
    options: *const ExtensionOptions,
    tool: *std.Build.Step.Compile,
) void {
    assert(options.name.len > 0);
    assert(options.package.name.len > 0);
    assert(tool.kind == .exe);

    var distribution_buffer: [package_module.distribution_bytes_max]u8 = undefined;
    var metadata_buffer: [package_module.metadata_bytes_max]u8 = undefined;
    var entry_buffer: [package_module.metadata_bytes_max]u8 = undefined;

    const package = &options.package;
    const distribution = package_module.distribution_normalize(package.name, &distribution_buffer);
    const directory = builder.fmt("{s}-{s}.dist-info", .{ distribution, package.version });
    const files = builder.addWriteFiles();
    const headers = builder.addWriteFiles();

    const header = headers.add(
        "METADATA",
        metadata_text(&metadata_buffer, package, options.python_version_min),
    );

    const compose = builder.addRunArtifact(tool);

    compose.addArg("--metadata");

    const metadata = compose.addOutputFileArg("METADATA");

    compose.addFileArg(header);

    if (package.description) |description| {
        compose.addFileArg(description.path);
    } else {
        compose.addArg("-");
    }

    _ = files.addCopyFile(metadata, builder.fmt("{s}/METADATA", .{directory}));

    if (entry_points_text(&entry_buffer, package)) |text| {
        _ = files.add(builder.fmt("{s}/entry_points.txt", .{directory}), text);
    }

    const install = builder.addInstallDirectory(.{
        .source_dir = files.getDirectory(),
        .install_dir = .{ .custom = "metadata" },
        .install_subdir = "",
    });

    const step = builder.step(
        builder.fmt("metadata:{s}", .{options.name}),
        builder.fmt("Install the metadata of {s} into zig-out/metadata", .{options.name}),
    );

    step.dependOn(&install.step);
}

const ReleaseRequest = struct {
    layout: Layout,
    options: *const ExtensionOptions,
    owner: Owner,
    platform: Platform,
    stub: std.Build.LazyPath,
    tools: Tools,
    variant: Variant,
};

fn release_build(builder: *std.Build, request: ReleaseRequest) Built {
    assert(request.platform.tag.len > 0);
    assert(request.stub == .generated);

    const suffix = suffix_of(builder, request.platform, request.variant);
    const primary = release_slice(builder, request, request.platform.query, suffix);

    const binary = if (request.platform.universal) |second| fat: {
        const secondary = release_slice(builder, request, second, suffix);
        const run = builder.addRunArtifact(request.tools.fat);
        const merged = run.addOutputFileArg(builder.fmt("binary{s}", .{suffix}));

        run.addFileArg(primary);
        run.addFileArg(secondary);

        break :fat merged;
    } else primary;

    const artifacts: Artifacts = .{ .binary = binary, .stub = request.stub };

    const entries: WheelEntries = .{
        .artifacts = artifacts,
        .directory = "",
        .options = request.options,
        .platform = request.platform,
        .variant = request.variant,
    };

    return wheel_build(builder, request.tools.wheel, entries, request.layout);
}

fn release_slice(
    builder: *std.Build,
    request: ReleaseRequest,
    query: std.Target.Query,
    suffix: []const u8,
) std.Build.LazyPath {
    assert(suffix.len > 0);
    assert(query.cpu_arch != null);
    assert(request.platform.tag.len > 0);

    const target = builder.resolveTargetQuery(query);
    const release = release_compile(builder, request, target);

    if (request.platform.python_linked) {
        release.root_module.linkLibrary(python_stub(builder, request.owner, target));
        release.link_z_max_page_size = 16 * 1024;
    }

    return binary_patch(builder, .{
        .binary = release.getEmittedBin(),
        .platform = request.platform,
        .suffix = suffix,
        .tool = request.tools.needed,
    });
}

fn release_compile(
    builder: *std.Build,
    request: ReleaseRequest,
    target: std.Build.ResolvedTarget,
) *std.Build.Step.Compile {
    assert(request.platform.tag.len > 0);
    assert(target.result.os.tag == request.platform.query.os_tag.?);

    if (request.platform.universal) |second| {
        if (second.cpu_arch != target.result.cpu.arch) {
            assert(request.platform.query.cpu_arch == target.result.cpu.arch);
        }
    } else {
        assert(request.platform.query.cpu_arch == target.result.cpu.arch);
    }

    assert(request.options.release_optimize != .small);

    const compilation: Compilation = .{
        .export_name = "",
        .optimize = request.options.release_optimize,
        .target = target,
        .variant = request.variant,
    };

    if (!request.options.dispatch) {
        return library_compile(builder, request.owner, request.options, compilation);
    }

    if (target.result.cpu.arch != .x86_64) {
        return library_compile(builder, request.owner, request.options, compilation);
    }

    return dispatched_compile(builder, request.owner, request.options, compilation);
}

fn dispatched_compile(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    compilation: Compilation,
) *std.Build.Step.Compile {
    assert(compilation.target.result.cpu.arch == .x86_64);
    assert(compilation.export_name.len == 0);
    assert(owner.builder.graph == builder.graph);

    const target = compilation.target;
    const configuration = builder.addOptions();
    const dot = std.mem.findScalarLast(u8, options.name, '.');
    const leaf = options.name[if (dot) |index| index + 1 else 0..];

    configuration.addOption([]const u8, "leaf", leaf);

    const root = builder.createModule(.{
        .root_source_file = owner.builder.path("src/dispatch_root.zig"),
        .imports = &.{.{ .name = "options", .module = configuration.createModule() }},
        .target = target,
        .optimize = compilation.optimize,
        .link_libc = libc_linked(target.result),
        .strip = options.strip,
        .pic = true,
        .omit_frame_pointer = false,
    });

    var query = target.query;

    query.cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v3 };

    const targets: Targets = .init(.{
        .baseline = target,
        .x86_64_v3 = builder.resolveTargetQuery(query),
    });

    for (std.enums.values(dispatch_module.Level)) |level| {
        const object = variant_object(builder, owner, options, .{
            .export_name = dispatch_module.variant_names[@backingInt(level)],
            .optimize = compilation.optimize,
            .target = targets.get(level),
            .variant = compilation.variant,
        });

        root.addObject(object);
    }

    if (target.result.os.tag == .windows) {
        root.addObjectFile(import_library(builder, target, .{
            .minimum = options.python_version_min,
            .variant = compilation.variant,
        }));
    }

    return library_add(builder, options, root);
}

fn variant_object(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    compilation: Compilation,
) *std.Build.Step.Compile {
    assert(compilation.export_name.len > 0);
    assert(options.name.len > 0);
    assert(owner.builder.graph == builder.graph);

    const name = builder.fmt("{s}_{s}", .{ options.name, compilation.export_name });

    std.mem.replaceScalar(u8, name, '.', '_');

    return builder.addObject(.{
        .name = name,
        .root_module = root_create(builder, owner, options, compilation),
    });
}

fn layout_of(builder: *std.Build, name: []const u8) Layout {
    assert(name.len > 0);
    assert(name[name.len - 1] != '.');

    const top = name[0 .. std.mem.findScalar(u8, name, '.') orelse name.len];

    if (std.mem.findScalar(u8, name, '.') == null) {
        return .{
            .binary_stem = builder.fmt("{s}/__init__", .{name}),
            .typed = builder.fmt("{s}/py.typed", .{name}),
        };
    }

    const stem = builder.fmt("{s}", .{name});

    std.mem.replaceScalar(u8, stem, '.', '/');

    return .{
        .binary_stem = stem,
        .typed = builder.fmt("{s}/py.typed", .{top}),
    };
}

fn suffix_of(builder: *std.Build, platform: Platform, variant: Variant) []const u8 {
    assert(platform.multiarch.len > 0 or platform_bsd(platform));
    assert(@tagName(variant).len > 0);

    if (platform_bsd(platform)) return suffix_bsd_of(builder, variant);

    const windows = platform.query.os_tag == .windows;

    return switch (variant) {
        .stable => if (windows) ".pyd" else ".abi3.so",
        .free_threaded => |version| if (windows)
            builder.fmt(".cp{d}{d}t-{s}.pyd", .{ version.major, version.minor, platform.multiarch })
        else
            builder.fmt(".cpython-{d}{d}t-{s}.so", .{
                version.major,
                version.minor,
                platform.multiarch,
            }),
        .versioned => |version| if (windows)
            builder.fmt(".cp{d}{d}-{s}.pyd", .{ version.major, version.minor, platform.multiarch })
        else
            builder.fmt(".cpython-{d}{d}-{s}.so", .{
                version.major,
                version.minor,
                platform.multiarch,
            }),
        .pypy => |pypy| builder.fmt(".pypy{d}{d}-{s}-{s}{s}", .{
            pypy.version.major,
            pypy.version.minor,
            pypy.abi,
            platform.multiarch,
            if (windows) ".pyd" else ".so",
        }),
    };
}

fn suffix_bsd_of(builder: *std.Build, variant: Variant) []const u8 {
    assert(variant != .free_threaded);
    assert(variant != .pypy);

    return switch (variant) {
        .stable => ".abi3.so",
        .versioned => |version| builder.fmt(".cpython-{d}{d}.so", .{
            version.major,
            version.minor,
        }),
        .free_threaded, .pypy => unreachable,
    };
}

fn interpreter_tag(builder: *std.Build, variant: Variant, minimum: Version) []const u8 {
    assert(builder.graph.zig_exe.len > 0);
    assert(minimum.minor >= python_version_floor.minor);
    assert(variant != .free_threaded or variant.free_threaded.minor >= free_threaded_minor_min);
    assert(variant != .versioned or variant.versioned.minor >= versioned_minor_min);

    return switch (variant) {
        .stable => builder.fmt("cp{d}{d}-abi3", .{ minimum.major, minimum.minor }),
        .free_threaded => |version| builder.fmt("cp{d}{d}-cp{d}{d}t", .{
            version.major,
            version.minor,
            version.major,
            version.minor,
        }),
        .versioned => |version| builder.fmt("cp{d}{d}-cp{d}{d}", .{
            version.major,
            version.minor,
            version.major,
            version.minor,
        }),
        .pypy => |pypy| builder.fmt("pp{d}{d}-pypy{d}{d}_{s}", .{
            pypy.version.major,
            pypy.version.minor,
            pypy.version.major,
            pypy.version.minor,
            pypy.abi,
        }),
    };
}

const Patch = struct {
    binary: std.Build.LazyPath,
    platform: Platform,
    suffix: []const u8,
    tool: *std.Build.Step.Compile,
};

fn binary_patch(builder: *std.Build, patch: Patch) std.Build.LazyPath {
    assert(patch.platform.needed_removed.len <= 4);
    if (patch.platform.needed_removed.len > 0) assert(patch.platform.query.os_tag == .linux);
    assert(patch.binary == .generated);
    assert(patch.tool.kind == .exe);

    var result = patch.binary;

    for (patch.platform.needed_removed) |name| {
        const run = builder.addRunArtifact(patch.tool);

        run.addFileArg(result);
        result = run.addOutputFileArg(builder.fmt("binary{s}", .{patch.suffix}));

        run.addArg(name);
    }

    return result;
}

const Targets = std.enums.EnumArray(dispatch_module.Level, std.Build.ResolvedTarget);

const Compilation = struct {
    export_name: []const u8,
    optimize: std.lang.Optimize,
    sanitize_thread: bool = false,
    target: std.Build.ResolvedTarget,
    variant: Variant,
};

fn library_compile(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    compilation: Compilation,
) *std.Build.Step.Compile {
    assert(compilation.export_name.len == 0);
    assert(options.name.len > 0);
    assert(owner.builder.graph == builder.graph);

    const target = compilation.target;
    const root = root_create(builder, owner, options, compilation);

    if (target.result.os.tag == .windows) {
        root.addObjectFile(import_library(builder, target, .{
            .minimum = options.python_version_min,
            .variant = compilation.variant,
        }));
    }

    return library_add(builder, options, root);
}

fn root_create(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
    compilation: Compilation,
) *std.Build.Module {
    assert(compilation.optimize != .small);
    assert(options.name.len > 0);
    assert(owner.builder.graph == builder.graph);

    const configuration = builder.addOptions();

    const free_threaded_minor: ?u8 = switch (compilation.variant) {
        .free_threaded => |version| version.minor,
        .pypy, .stable, .versioned => null,
    };

    const versioned_minor: ?u8 = switch (compilation.variant) {
        .versioned => |version| version.minor,
        .free_threaded, .pypy, .stable => null,
    };

    const pypy_minor: ?u8 = switch (compilation.variant) {
        .pypy => |pypy| pypy.version.minor,
        .free_threaded, .stable, .versioned => null,
    };

    configuration.addOption(?u8, "free_threaded_minor", free_threaded_minor);
    configuration.addOption(?u8, "versioned_minor", versioned_minor);
    configuration.addOption(?u8, "pypy_minor", pypy_minor);
    configuration.addOption(u8, "stable_minor", options.python_version_min.minor);
    configuration.addOption([]const u8, "export_name", compilation.export_name);
    configuration.addOption([]const u8, "name", options.name);

    return builder.createModule(.{
        .root_source_file = owner.builder.path("src/extension_root.zig"),
        .imports = &.{
            .{ .name = "lacuna", .module = owner.module },
            .{ .name = "extension", .module = options.module },
            .{ .name = "options", .module = configuration.createModule() },
        },
        .target = compilation.target,
        .optimize = compilation.optimize,
        .link_libc = libc_linked(compilation.target.result),
        .strip = options.strip,
        .pic = true,
        .omit_frame_pointer = false,
        .sanitize_thread = compilation.sanitize_thread,
    });
}

fn library_add(
    builder: *std.Build,
    options: *const ExtensionOptions,
    root: *std.Build.Module,
) *std.Build.Step.Compile {
    assert(options.name.len > 0);
    assert(root.resolved_target != null);

    const target = root.resolved_target.?;
    const library_name = builder.fmt("{s}", .{options.name});

    std.mem.replaceScalar(u8, library_name, '.', '_');

    const library = builder.addLibrary(.{
        .linkage = .dynamic,
        .name = library_name,
        .root_module = root,
        .version = null,
    });

    if (libc_linked(target.result)) library.linker_allow_shlib_undefined = true;

    return library;
}

fn libc_linked(target: std.Target) bool {
    assert(target.ptrBitWidth() >= 32);
    assert(@tagName(target.os.tag).len > 0);

    if (target.os.tag == .windows) return false;
    return !target.abi.isAndroid();
}

fn pypy_exports_text(builder: *std.Build, minor: u8) []const u8 {
    assert(minor >= pypy_minor_min);
    assert(minor <= pypy_minor_max);

    var text: std.ArrayList(u8) = .empty;

    const names: []const []const u8 = if (minor >= 12)
        &(c_api.exports ++ c_api.exports_3_12 ++ c_api.exports_pypy)
    else
        &(c_api.exports ++ c_api.exports_pypy);

    for (names) |name| {
        const symbol = pypy_symbol(builder, name, minor);

        text.print(builder.allocator, "{s}\n", .{symbol}) catch @panic("out of memory");
    }

    return text.items;
}

fn pypy_symbol(builder: *std.Build, name: []const u8, minor: u8) []const u8 {
    assert(name.len > 2);
    assert(minor >= pypy_minor_min);

    const listed: []const []const u8 = if (minor >= 12)
        &c_api.pypy_prefixed_3_12
    else
        &c_api.pypy_unprefixed_3_11;

    const exception = for (listed) |entry| {
        if (std.mem.eql(u8, entry, name)) break true;
    } else false;

    const prefixed = if (minor >= 12) exception else !exception;

    if (!prefixed) return name;
    if (name[0] == '_') return builder.fmt("_PyPy{s}", .{name[3..]});
    return builder.fmt("PyPy{s}", .{name[2..]});
}

fn python_stub(
    builder: *std.Build,
    owner: Owner,
    target: std.Build.ResolvedTarget,
) *std.Build.Step.Compile {
    assert(target.result.abi.isAndroid());
    assert(owner.builder.graph == builder.graph);

    return builder.addLibrary(.{
        .linkage = .dynamic,
        .name = "python3",
        .root_module = builder.createModule(.{
            .root_source_file = owner.builder.path("src/python_stub.zig"),
            .target = target,
            .optimize = .small,
            .pic = true,
        }),
        .version = null,
    });
}

const Linkage = struct {
    minimum: Version,
    variant: Variant,
};

fn import_library(
    builder: *std.Build,
    target: std.Build.ResolvedTarget,
    linkage: Linkage,
) std.Build.LazyPath {
    assert(linkage.minimum.minor >= python_version_floor.minor);

    const variant = linkage.variant;

    assert(variant != .free_threaded or target.result.cpu.arch != .x86);
    assert(target.result.os.tag == .windows);
    assert(builder.graph.zig_exe.len > 0);

    const machine = switch (target.result.cpu.arch) {
        .aarch64 => "arm64",
        .x86 => "i386",
        .x86_64 => "i386:x86-64",
        else => std.process.fatal("lacuna: Windows on {t} is not a release platform", .{
            target.result.cpu.arch,
        }),
    };

    const dll = switch (variant) {
        .stable => "python3.dll",
        .free_threaded => |version| builder.fmt("python{d}{d}t.dll", .{
            version.major,
            version.minor,
        }),
        .versioned => |version| builder.fmt("python{d}{d}.dll", .{
            version.major,
            version.minor,
        }),
        .pypy => |pypy| builder.fmt("libpypy{d}.{d}-c.dll", .{
            pypy.version.major,
            pypy.version.minor,
        }),
    };

    const names = import_names(builder, linkage);
    const files = builder.addWriteFiles();

    const definition = files.add(
        "python.def",
        builder.fmt("LIBRARY {s}\nEXPORTS\n{s}", .{ dll, names }),
    );

    const run = builder.addSystemCommand(&.{
        builder.graph.zig_exe,
        "dlltool",
        "-m",
        machine,
        "-D",
        dll,
        "-d",
    });

    run.addFileArg(definition);
    run.addArg("-l");

    return run.addOutputFileArg("python.lib");
}

fn import_names(builder: *std.Build, linkage: Linkage) []const u8 {
    assert(linkage.variant != .stable or linkage.minimum.minor <= versioned_minor_max);
    assert(linkage.minimum.minor >= python_version_floor.minor);

    return switch (linkage.variant) {
        .free_threaded => exports_text ++ exports_3_12_text ++ exports_3_13_text ++
            exports_free_threaded_text,
        .pypy => |pypy| pypy_exports_text(builder, pypy.version.minor),
        .stable => if (linkage.minimum.minor >= 12)
            exports_text ++ exports_3_12_text
        else
            exports_text,
        .versioned => |version| if (version.minor >= 13)
            exports_text ++ exports_3_12_text ++ exports_3_13_text ++ exports_versioned_text
        else
            exports_text ++ exports_3_12_text ++ exports_versioned_text,
    };
}

fn stub_generate(
    builder: *std.Build,
    owner: Owner,
    options: *const ExtensionOptions,
) std.Build.LazyPath {
    assert(options.name.len > 0);
    assert(owner.builder.graph == builder.graph);

    const configuration = builder.addOptions();

    configuration.addOption(u8, "stable_minor", options.python_version_min.minor);

    const root = builder.createModule(.{
        .root_source_file = owner.builder.path("src/stub_root.zig"),
        .imports = &.{
            .{ .name = "lacuna", .module = owner.module },
            .{ .name = "extension", .module = options.module },
            .{ .name = "options", .module = configuration.createModule() },
        },
        .target = builder.graph.host,
        .optimize = .debug,
    });

    const generator = builder.addExecutable(.{ .name = "stub", .root_module = root });
    const run = builder.addRunArtifact(generator);

    return run.addOutputDirectoryArg("stubs");
}

fn python_filter_of(options: *const ExtensionOptions) CopyFilter {
    assert(options.python_exclude_extensions.len <= package_module.list_count_max);
    assert(options.name.len > 0);

    return .{
        .exclude_extensions = options.python_exclude_extensions,
        .include_extensions = options.python_include_extensions,
    };
}

fn tree_create(builder: *std.Build, tree: Tree) std.Build.LazyPath {
    assert(tree.layout.binary_stem.len > 0);
    assert(tree.suffix.len > 0);
    assert(tree.stub == .generated);

    const files = builder.addWriteFiles();

    if (tree.python_source) |source| _ = files.addCopyDirectory(source, "", tree.python_filter);

    const binary = builder.fmt("{s}{s}", .{ tree.layout.binary_stem, tree.suffix });

    _ = files.addCopyFile(tree.library.getEmittedBin(), binary);
    _ = files.addCopyDirectory(tree.stub, "", .{
        .exclude_extensions = &.{},
        .include_extensions = &.{".pyi"},
    });

    _ = files.add(tree.layout.typed, "");

    return files.getDirectory();
}

fn tools_create(builder: *std.Build, owner: Owner) Tools {
    assert(builder.graph.zig_exe.len > 0);
    assert(owner.builder.graph == builder.graph);

    return .{
        .fat = tool_create(builder, owner, .{ .name = "fat", .root = "src/fat.zig" }),
        .needed = tool_create(builder, owner, .{ .name = "needed", .root = "src/needed.zig" }),
        .wheel = tool_create(builder, owner, .{ .name = "wheel", .root = "src/wheel.zig" }),
    };
}

fn tool_create(builder: *std.Build, owner: Owner, tool: Tool) *std.Build.Step.Compile {
    assert(tool.name.len > 0);
    assert(std.mem.endsWith(u8, tool.root, ".zig"));
    assert(owner.builder.graph == builder.graph);

    return builder.addExecutable(.{
        .name = tool.name,
        .root_module = builder.createModule(.{
            .root_source_file = owner.builder.path(tool.root),
            .target = builder.graph.host,
            .optimize = .safe,
        }),
    });
}

fn wheel_build(
    builder: *std.Build,
    tool: *std.Build.Step.Compile,
    entries: WheelEntries,
    layout: Layout,
) Built {
    assert(layout.binary_stem.len > 0);
    assert(entries.platform.tag.len > 0);
    assert(entries.artifacts.binary == .generated);
    assert(tool.kind == .exe);

    var distribution_buffer: [package_module.distribution_bytes_max]u8 = undefined;

    const package = entries.options.package;
    const distribution = package_module.distribution_normalize(package.name, &distribution_buffer);
    const metadata_directory = builder.fmt("{s}-{s}.dist-info", .{ distribution, package.version });

    const filename = builder.fmt("{s}-{s}-{s}-{s}.whl", .{
        distribution,
        package.version,
        interpreter_tag(builder, entries.variant, entries.options.python_version_min),
        entries.platform.tag,
    });

    const run = builder.addRunArtifact(tool);
    const output = run.addOutputFileArg(filename);

    run.addArg(metadata_directory);

    var located = entries;

    located.directory = metadata_directory;

    wheel_entries_add(builder, run, located, layout);

    const install = builder.addInstallFileWithDir(output, .{ .custom = "dist" }, filename);
    return .{ .path = output, .step = &install.step };
}

fn wheel_entries_add(
    builder: *std.Build,
    run: *std.Build.Step.Run,
    entries: WheelEntries,
    layout: Layout,
) void {
    assert(layout.binary_stem.len > 0);
    assert(std.mem.endsWith(u8, entries.directory, ".dist-info"));
    assert(run.step.owner == builder);

    var metadata_buffer: [package_module.metadata_bytes_max]u8 = undefined;
    var wheel_buffer: [package_module.wheel_bytes_max]u8 = undefined;

    const package = &entries.options.package;
    const minimum = entries.options.python_version_min;
    const files = builder.addWriteFiles();

    run.addFileArg(files.add("METADATA", metadata_text(&metadata_buffer, package, minimum)));

    if (package.description) |description| run.addFileArg(description.path) else run.addArg("-");

    const suffix = suffix_of(builder, entries.platform, entries.variant);
    const binary = builder.fmt("{s}{s}", .{ layout.binary_stem, suffix });

    const wheel = wheel_text(&wheel_buffer, .{
        .interpreter = interpreter_tag(builder, entries.variant, minimum),
        .platform = entries.platform.tag,
        .purelib = false,
    });

    entry_add(run, binary, entries.artifacts.binary);
    entry_add(run, "./", entries.artifacts.stub);
    entry_add(run, layout.typed, files.add("py.typed", ""));
    entry_add(run, builder.fmt("{s}/WHEEL", .{entries.directory}), files.add("WHEEL", wheel));

    var entry_buffer: [package_module.metadata_bytes_max]u8 = undefined;

    if (entry_points_text(&entry_buffer, package)) |text| {
        const name = builder.fmt("{s}/entry_points.txt", .{entries.directory});

        entry_add(run, name, files.add("entry_points.txt", text));
    }

    if (entries.options.python_source) |source| {
        entry_directory_add(run, "./", source, python_filter_of(entries.options));
    }

    const data_directory = builder.fmt("{s}.data", .{
        entries.directory[0 .. entries.directory.len - ".dist-info".len],
    });

    for (package.data) |file| {
        const name = builder.fmt("{s}/{t}/{s}", .{ data_directory, file.scheme, file.name });

        entry_add(run, name, file.path);
    }

    const license = package.license orelse return;

    for (license.files) |file| {
        const license_name = builder.fmt("{s}/licenses/{s}", .{ entries.directory, file.name });

        entry_add(run, license_name, file.path);
    }
}

fn entry_add(run: *std.Build.Step.Run, name: []const u8, path: std.Build.LazyPath) void {
    assert(name.len > 0);
    assert(std.mem.findScalar(u8, name, '\\') == null);
    assert(path != .cwd_relative or std.fs.path.isAbsolute(path.cwd_relative));

    const unfiltered: CopyFilter = .{
        .exclude_extensions = &.{},
        .include_extensions = null,
    };

    if (std.mem.endsWith(u8, name, "/")) {
        entry_directory_add(run, name, path, unfiltered);

        return;
    }

    run.addArg(name);
    run.addFileArg(path);
}

fn entry_directory_add(
    run: *std.Build.Step.Run,
    name: []const u8,
    path: std.Build.LazyPath,
    filter: CopyFilter,
) void {
    assert(std.mem.endsWith(u8, name, "/"));
    if (filter.include_extensions) |extensions| assert(extensions.len > 0);
    assert(std.mem.findScalar(u8, name, '\\') == null);
    assert(path != .cwd_relative or std.fs.path.isAbsolute(path.cwd_relative));

    const files = run.step.owner.addWriteFiles();
    const copied = files.addCopyDirectory(path, "", filter);

    run.addArg(name);
    run.addDirectoryArg(copied);
}

fn metadata_of(
    package: *const Package,
    minimum: Version,
    license_files: *[package_module.list_count_max][]const u8,
) package_module.Metadata {
    assert(package.name.len > 0);
    assert(minimum.major == 3);

    const license_count = if (package.license) |license| license.files.len else 0;

    assert(license_count <= package_module.list_count_max);

    if (package.license) |license| {
        for (license.files, 0..) |file, index| license_files[index] = file.name;
    }

    return .{
        .authors = package.authors,
        .classifiers = package.classifiers,
        .content_type = if (package.description) |description|
            content_type_of(description)
        else
            null,
        .dependencies = package.dependencies,
        .dynamic = package.dynamic,
        .extras = package.extras,
        .keywords = package.keywords,
        .license_expression = if (package.license) |license| license.expression else null,
        .license_files = license_files[0..license_count],
        .links = package.links,
        .maintainers = package.maintainers,
        .name = package.name,
        .obsoletes = package.obsoletes,
        .provides = package.provides,
        .python_version_min = .{ .major = minimum.major, .minor = minimum.minor },
        .requires_python = package.requires_python,
        .summary = package.summary,
        .version = package.version,
    };
}

fn content_type_of(description: Description) []const u8 {
    assert(description.content_type == null or description.content_type.?.len > 0);
    assert(readme_types.len == 3);

    if (description.content_type) |content_type| return content_type;

    const name = switch (description.path) {
        .src_path => |source| source.sub_path,
        .cwd_relative => |path| path,
        else => "",
    };

    for (readme_types) |readme| {
        if (std.ascii.endsWithIgnoreCase(name, readme.suffix)) return readme.content_type;
    }

    std.process.fatal("lacuna: the content type of the readme '{s}' is not known from its " ++
        "suffix; set Description.content_type", .{name});
}

const ReadmeType = struct {
    content_type: []const u8,
    suffix: []const u8,
};

const readme_types = [_]ReadmeType{
    .{ .content_type = "text/markdown", .suffix = ".md" },
    .{ .content_type = "text/x-rst", .suffix = ".rst" },
    .{ .content_type = "text/plain", .suffix = ".txt" },
};

fn metadata_text(
    buffer: *[package_module.metadata_bytes_max]u8,
    package: *const Package,
    minimum: Version,
) []const u8 {
    assert(package.name.len > 0);
    assert(buffer.len == package_module.metadata_bytes_max);
    assert(minimum.minor >= python_version_floor.minor);

    var license_files: [package_module.list_count_max][]const u8 = undefined;
    var writer: std.Io.Writer = .fixed(buffer);

    const metadata = metadata_of(package, minimum, &license_files);

    package_module.metadata_write(&writer, &metadata) catch {
        std.process.fatal("lacuna: the metadata of {s} is too long", .{package.name});
    };

    return writer.buffered();
}

fn entry_groups_of(
    package: *const Package,
    groups: *[package_module.list_count_max]EntryGroup,
) []const EntryGroup {
    assert(package.entry_points.len + 2 <= package_module.list_count_max);
    assert(package.name.len > 0);

    var count: u32 = 0;

    if (package.scripts.len > 0) {
        groups[count] = .{ .entries = package.scripts, .group = "console_scripts" };
        count += 1;
    }

    if (package.gui_scripts.len > 0) {
        groups[count] = .{ .entries = package.gui_scripts, .group = "gui_scripts" };
        count += 1;
    }

    for (package.entry_points) |group| {
        groups[count] = group;
        count += 1;
    }

    return groups[0..count];
}

fn entry_points_text(
    buffer: *[package_module.metadata_bytes_max]u8,
    package: *const Package,
) ?[]const u8 {
    assert(package.name.len > 0);
    assert(buffer.len == package_module.metadata_bytes_max);

    var groups: [package_module.list_count_max]EntryGroup = undefined;
    var writer: std.Io.Writer = .fixed(buffer);

    const listed = entry_groups_of(package, &groups);
    if (listed.len == 0) return null;

    package_module.entry_points_write(&writer, listed) catch {
        std.process.fatal("lacuna: the entry points of {s} are too long", .{package.name});
    };

    return writer.buffered();
}

fn wheel_text(buffer: *[package_module.wheel_bytes_max]u8, tags: package_module.Tags) []const u8 {
    assert(tags.platform.len > 0);
    assert(std.mem.findScalar(u8, tags.platform, '-') == null);

    var writer: std.Io.Writer = .fixed(buffer);

    package_module.wheel_write(&writer, tags) catch {
        std.process.fatal("lacuna: the WHEEL file is too long", .{});
    };

    return writer.buffered();
}

fn options_validate(options: *const ExtensionOptions) void {
    const name = options.name;
    const package = &options.package;

    if (name.len == 0) std.process.fatal("lacuna: an extension needs a module name", .{});
    if (package.name.len == 0) std.process.fatal("lacuna: {s} needs a package name", .{name});
    if (package.version.len == 0) std.process.fatal("lacuna: {s} needs a version", .{name});
    if (options.platforms.len == 0) std.process.fatal("lacuna: {s} lists no platforms", .{name});

    if (options.release_optimize == .small) {
        std.process.fatal("lacuna: {s} cannot release in small mode", .{name});
    }

    if (options.platforms.len > platform_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} platforms", .{
            name,
            platform_count_max,
        });
    }

    if (options.free_threaded.len > free_threaded_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} free-threaded versions", .{
            name,
            free_threaded_count_max,
        });
    }

    pypy_validate(options);
    python_version_min_validate(options);

    if (options.versioned.len > versioned_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} version-specific versions", .{
            name,
            versioned_count_max,
        });
    }

    const license_count = if (package.license) |license| license.files.len else 0;

    if (license_count > package_module.list_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} license files", .{
            name,
            package_module.list_count_max,
        });
    }

    if (package.entry_points.len + 2 > package_module.list_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} entry point groups", .{
            name,
            package_module.list_count_max - 2,
        });
    }

    data_validate(options);
    options_versions_validate(options.name, options.free_threaded, free_threaded_range);
    options_versions_validate(options.name, options.versioned, versioned_range);
    package_validate(options);

    assert(options.platforms.len <= platform_count_max);
    assert(license_count <= package_module.list_count_max);
}

fn options_versions_validate(
    name: []const u8,
    versions: []const Version,
    range: VersionRange,
) void {
    assert(name.len > 0);
    assert(versions.len <= @max(free_threaded_count_max, versioned_count_max));
    assert(range.minor_min <= range.minor_max);

    for (versions, 0..) |version, index| {
        const supported = supported: {
            if (version.major != 3) break :supported false;
            if (version.minor < range.minor_min) break :supported false;

            break :supported version.minor <= range.minor_max;
        };

        if (!supported) {
            std.process.fatal("lacuna: {s} lists {s} {d}.{d}; lacuna builds 3.{d} to 3.{d}", .{
                name,
                range.kind,
                version.major,
                version.minor,
                range.minor_min,
                range.minor_max,
            });
        }

        for (versions[0..index]) |earlier| {
            if (std.meta.eql(earlier, version)) {
                std.process.fatal("lacuna: {s} lists {s} {d}.{d} twice", .{
                    name,
                    range.kind,
                    version.major,
                    version.minor,
                });
            }
        }
    }
}

fn python_version_min_validate(options: *const ExtensionOptions) void {
    const minimum = options.python_version_min;

    assert(options.name.len > 0);
    assert(python_version_floor.minor <= versioned_minor_max);

    const supported = minimum.major == 3 and minimum.minor >= python_version_floor.minor and
        minimum.minor <= versioned_minor_max;

    if (supported) return;

    std.process.fatal("lacuna: {s} sets python_version_min {d}.{d}; lacuna builds 3.{d} to " ++
        "3.{d}", .{
        options.name,
        minimum.major,
        minimum.minor,
        python_version_floor.minor,
        versioned_minor_max,
    });
}

fn pypy_validate(options: *const ExtensionOptions) void {
    const name = options.name;

    assert(name.len > 0);
    assert(pypy_minor_min <= pypy_minor_max);

    if (options.pypy.len > pypy_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} PyPy versions", .{
            name,
            pypy_count_max,
        });
    }

    for (options.pypy) |pypy| {
        const minor = pypy.version.minor;

        const supported = pypy.version.major == 3 and minor >= pypy_minor_min and
            minor <= pypy_minor_max;

        if (!supported) {
            std.process.fatal("lacuna: {s} lists PyPy {d}.{d}; lacuna builds 3.{d} to 3.{d}", .{
                name,
                pypy.version.major,
                minor,
                pypy_minor_min,
                pypy_minor_max,
            });
        }

        if (pypy.abi.len == 0) {
            std.process.fatal("lacuna: {s} lists a PyPy without an ABI", .{name});
        }
    }
}

fn data_validate(options: *const ExtensionOptions) void {
    const name = options.name;
    const data = options.package.data;

    assert(name.len > 0);
    assert(package_module.list_count_max > 0);

    if (data.len > package_module.list_count_max) {
        std.process.fatal("lacuna: {s} lists more than {d} data files", .{
            name,
            package_module.list_count_max,
        });
    }

    for (data) |file| {
        if (!package_module.data_name_valid(file.name)) {
            std.process.fatal("lacuna: the data file '{s}' of {s} must be a relative path " ++
                "without '.' or '..' parts", .{ file.name, name });
        }
    }
}

fn package_validate(options: *const ExtensionOptions) void {
    assert(options.platforms.len > 0);
    assert(options.package.name.len > 0);

    var license_files: [package_module.list_count_max][]const u8 = undefined;
    var groups: [package_module.list_count_max]EntryGroup = undefined;

    const metadata = metadata_of(&options.package, options.python_version_min, &license_files);

    const problem = package_module.problem_of(&metadata, options.name) orelse
        package_module.entry_points_problem(entry_groups_of(&options.package, &groups)) orelse
        return;

    if (problem == .requires_python_below_minimum) {
        std.process.fatal("lacuna: the package '{s}' requires Python '{s}', which admits " ++
            "versions below the {d}.{d} that module '{s}' is built for", .{
            options.package.name,
            options.package.requires_python.?,
            options.python_version_min.major,
            options.python_version_min.minor,
            options.name,
        });
    }

    std.process.fatal("lacuna: the package '{s}' version '{s}' of module '{s}' is invalid: {t}", .{
        options.package.name,
        options.package.version,
        options.name,
        problem,
    });
}

fn add_format(context: *const Context) void {
    assert(format_paths.len > 0);
    assert(context.steps.test_format != context.steps.test_all);

    const format = context.builder.addFmt(.{
        .paths = context.builder.pathList(&format_paths),
        .check = true,
    });

    context.steps.test_format.dependOn(&format.step);
    context.steps.test_all.dependOn(&format.step);
}

fn add_compile_fail_tests(context: *const Context) void {
    assert(compile_fail_cases.len > 0);
    assert(context.steps.test_compile_fail != context.steps.test_all);

    const builder = context.builder;

    for (compile_fail_cases) |case| {
        assert(std.mem.startsWith(u8, case.message, "lacuna: "));
        assert(std.mem.startsWith(u8, case.root, "tests/compile_fail/"));

        const run = builder.addSystemCommand(&.{
            builder.graph.zig_exe,
            "build-obj",
            "-fno-emit-bin",
            "--dep",
            "lacuna",
        });

        run.addPrefixedFileArg("-Mroot=", builder.path(case.root));
        run.addPrefixedFileArg("-Mlacuna=", builder.path(module_root));
        run.expectExitCode(1);
        run.expectStdErrMatch(builder.fmt("error: {s}\n", .{case.message}));
        run.has_side_effects = true;

        context.steps.test_compile_fail.dependOn(&run.step);
        context.steps.test_all.dependOn(&run.step);
    }
}

fn add_unit_tests(context: *const Context) void {
    assert(context.steps.test_unit != context.steps.test_all);
    assert(unit_tests_root.len > 0);

    suite_add(context, unit_tests_root);

    if (context.target.result.cpu.arch == .x86_64) suite_add(context, unit_tests_x86_64_root);

    const exports = context.builder.addObject(.{
        .name = "exports",
        .root_module = context.builder.createModule(.{
            .root_source_file = context.builder.path("src/exports.zig"),
            .target = context.target,
            .optimize = .debug,
        }),
    });

    context.steps.test_unit.dependOn(&exports.step);
    context.steps.test_all.dependOn(&exports.step);
}

fn suite_add(context: *const Context, root: []const u8) void {
    assert(std.mem.startsWith(u8, root, "src/unit_tests"));
    assert(std.mem.endsWith(u8, root, ".zig"));

    const suite = context.builder.addTest(.{
        .name = std.Io.Dir.path.stem(root),
        .root_module = context.builder.createModule(.{
            .root_source_file = context.builder.path(root),
            .target = context.target,
            .optimize = context.optimize,
        }),
        .filters = context.filters,
    });

    const run = context.builder.addRunArtifact(suite);

    run.setCwd(context.builder.path("."));
    run.has_side_effects = true;

    context.steps.test_unit.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
}

fn add_abi(context: *const Context) void {
    assert(context.steps.test_abi != context.steps.test_all);
    assert(limited_api_version.len == 10);

    const builder = context.builder;
    const include = context.python_include orelse "";

    if (include.len == 0) {
        const fail = builder.addFail("test:abi needs -Dpython-include=<Python include directory>");

        context.steps.test_abi.dependOn(&fail.step);

        return;
    }

    const owner: Owner = .{ .builder = builder, .module = context.module };
    const capture = tool_create(builder, owner, .{ .name = "capture", .root = "src/capture.zig" });
    const free_threaded = context.python_free_threaded;
    const pypy = context.python_pypy;
    const versioned = context.python_versioned;

    assert(free_threaded == null or versioned == null);

    const mode = translation_mode_of(context);

    const limited = limited_translate(builder, capture, .{ .include = include, .mode = mode });

    const limited_3_12 = if (mode == .limited) limited_translate(builder, capture, .{
        .include = include,
        .mode = .{ .limited = limited_api_version_3_12 },
    }) else limited;

    const configuration = builder.addOptions();
    const free_threaded_minor: ?u8 = if (free_threaded) |version| version.minor else null;
    const versioned_minor: ?u8 = if (versioned) |version| version.minor else null;

    configuration.addOption(?u8, "free_threaded_minor", free_threaded_minor);
    configuration.addOption(?u8, "pypy_minor", if (pypy) |version| version.minor else null);
    configuration.addOption(?u8, "versioned_minor", versioned_minor);

    const check = builder.addObject(.{
        .name = "abi",
        .root_module = builder.createModule(.{
            .root_source_file = builder.path("src/abi.zig"),
            .imports = &.{
                .{ .name = "limited", .module = limited },
                .{ .name = "limited_3_12", .module = limited_3_12 },
                .{ .name = "options", .module = configuration.createModule() },
            },
            .target = builder.graph.host,
            .optimize = .debug,
        }),
    });

    context.steps.test_abi.dependOn(&check.step);
}

fn translation_mode_of(context: *const Context) Translation.Mode {
    assert(context.python_free_threaded == null or context.python_versioned == null);
    assert(limited_api_version.len == 10);

    if (context.python_free_threaded != null) return .free_threaded;
    if (context.python_pypy != null) return .pypy;
    if (context.python_versioned != null) return .versioned;
    return .{ .limited = limited_api_version };
}

fn limited_translate(
    builder: *std.Build,
    capture: *std.Build.Step.Compile,
    translation: Translation,
) *std.Build.Module {
    assert(translation.include.len > 0);
    assert(translation.mode != .limited or translation.mode.limited.len == 10);

    const files = builder.addWriteFiles();

    const define = switch (translation.mode) {
        .free_threaded => "#define Py_GIL_DISABLED 1\n#define _Py_ALIGNED_DEF(N, T) T\n",
        .limited => |version| builder.fmt("#define Py_LIMITED_API {s}\n", .{version}),
        .pypy => "",
        .versioned => "#define _Py_ALIGNED_DEF(N, T) T\n",
    };

    const internal = switch (translation.mode) {
        .free_threaded, .limited, .pypy => "",
        .versioned => "#define Py_BUILD_CORE 1\n#include <internal/pycore_dict.h>\n",
    };

    const text = builder.fmt("{s}#include <Python.h>\n{s}", .{ define, internal });
    const header = files.add("limited.h", text);

    const translate = builder.addRunArtifact(capture);
    const translated = translate.addOutputFileArg("limited.zig");

    translate.addArgs(&.{
        builder.graph.zig_exe,
        "translate-c",
        "-lc",
        "-I",
        translation.include,
    });

    translate.addFileArg(header);

    return builder.createModule(.{ .root_source_file = translated });
}
