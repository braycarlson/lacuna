const lacuna = @import("lacuna");

const Holder = struct {
    value: i64,

    pub const setters = .{ .value = .value_set };

    pub fn init(holder: *Holder) void {
        holder.* = .{ .value = 0 };
    }

    pub fn value_set(holder: *Holder, arguments: struct { value: i64 }) void {
        holder.value = arguments.value;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
