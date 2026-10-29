const lacuna = @import("lacuna");

const Level8 = struct { reference: lacuna.Reference };
const Level7 = struct { inner: Level8 };
const Level6 = struct { inner: Level7 };
const Level5 = struct { inner: Level6 };
const Level4 = struct { inner: Level5 };
const Level3 = struct { inner: Level4 };
const Level2 = struct { inner: Level3 };
const Level1 = struct { inner: Level2 };

const Holder = struct {
    inner: Level1,

    pub fn init(holder: *Holder) void {
        holder.inner.inner.inner.inner.inner.inner.inner.inner.reference = .empty;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
