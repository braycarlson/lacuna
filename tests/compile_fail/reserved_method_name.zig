const lacuna = @import("lacuna");

const Table = struct {
    count: u8,

    pub fn fields(table: *const Table) u8 {
        return table.count;
    }
};

const Functions = struct {
    pub fn nothing() void {}
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Table}, .functions = Functions });
}
