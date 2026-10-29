const lacuna = @import("lacuna");

const Holder = struct {
    payload: lacuna.Reference,

    pub fn init(holder: *Holder) void {
        holder.payload = .empty;
    }
};

const Functions = struct {
    pub fn make() Holder {
        return .{ .payload = .empty };
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder}, .functions = Functions });
}
