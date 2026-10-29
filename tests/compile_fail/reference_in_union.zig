const lacuna = @import("lacuna");

const Slot = union(enum) {
    held: lacuna.Reference,
    vacant: void,
};

const Holder = struct {
    slot: Slot,

    pub fn init(holder: *Holder) void {
        holder.slot = .vacant;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
