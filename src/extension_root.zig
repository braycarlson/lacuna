const std = @import("std");

const lacuna = @import("lacuna");
const extension = @import("extension");
const options = @import("options");

const debug_io = @import("debug_io.zig");

pub const std_options: std.Options = if (@hasDecl(extension, "std_options"))
    extension.std_options
else
    .{};

pub const std_options_debug_io: std.Io = debug_io.io;

pub const lacuna_stable_minor: u8 = options.stable_minor;
pub const panic = if (@hasDecl(extension, "panic"))
    extension.panic
else
    std.debug.FullPanic(lacuna.panic_report);
pub const lacuna_module = extension.module;

pub const lacuna_abi: lacuna.c.ABI = .select(.{
    .abi3t = options.abi3t,
    .free_threaded_minor = options.free_threaded_minor,
    .graalpy_minor = options.graalpy_minor,
    .pypy_minor = options.pypy_minor,
    .versioned_minor = options.versioned_minor,
});

comptime {
    if (!std.mem.eql(u8, options.name, extension.module.name)) {
        @compileError("lacuna: the build names the module '" ++ options.name ++
            "' but its definition names it '" ++ extension.module.name ++ "'");
    }

    if (options.export_name.len == 0) {
        lacuna.module_export(extension.module);
    } else {
        lacuna.module_export_named(extension.module, options.export_name);
    }
}
