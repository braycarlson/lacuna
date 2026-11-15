const lacuna = @import("lacuna");

const Holder = struct {
    name: []const u8,

    pub const fields = .{ .name = .read_write };

    pub fn init(holder: *Holder) void {
        holder.name = "holder";
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
