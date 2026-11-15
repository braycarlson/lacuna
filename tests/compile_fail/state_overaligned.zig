const lacuna = @import("lacuna");

const Counter = struct {
    count: u64 align(16),

    pub const empty: Counter = .{ .count = 0 };
};

const Functions = struct {
    pub fn bump(counter: lacuna.StateOf(Counter)) u64 {
        counter.data.count += 1;

        return counter.data.count;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .functions = Functions, .state = Counter });
}
