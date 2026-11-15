const lacuna = @import("lacuna");

const Holder = struct {
    items: lacuna.ListType(lacuna.Reference, 4),

    pub fn init(holder: *Holder) void {
        holder.items = .empty;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
