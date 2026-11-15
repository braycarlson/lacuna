const lacuna = @import("lacuna");

const Registry = struct {
    label: u32,

    pub const extends = lacuna.Native.dictionary;

    pub fn init(registry: *Registry, base: lacuna.Object) void {
        _ = base;

        registry.* = .{ .label = 0 };
    }
};

const Functions = struct {
    pub fn build(arguments: struct { kind: lacuna.Object }) lacuna.PythonError!lacuna.Reference {
        const class: lacuna.TypeObject = .{ .object = arguments.kind };

        return class.instance_new(Registry{ .label = 1 });
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Registry}, .functions = Functions });
}
