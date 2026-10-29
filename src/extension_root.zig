const std = @import("std");

const lacuna = @import("lacuna");
const extension = @import("extension");
const options = @import("options");

pub const std_options: std.Options = if (@hasDecl(extension, "std_options"))
    extension.std_options
else
    .{};

pub const lacuna_stable_minor: u8 = options.stable_minor;

pub const lacuna_abi: lacuna.c.ABI = .select(.{
    .free_threaded_minor = options.free_threaded_minor,
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
