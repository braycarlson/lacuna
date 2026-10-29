const lacuna = @import("lacuna");

const Holder = struct {
    held: lacuna.Reference,

    pub fn init(holder: *Holder) void {
        holder.* = .{ .held = .{ .pointer = null } };
    }
};

const Functions = struct {
    pub fn build(arguments: struct { kind: lacuna.Object }) lacuna.PythonError!lacuna.Reference {
        const class: lacuna.TypeObject = .{ .object = arguments.kind };

        return class.instance_new(Holder{ .held = .{ .pointer = null } });
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder}, .functions = Functions });
}
