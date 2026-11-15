const lacuna = @import("lacuna");

const Level16 = struct { reference: lacuna.Reference };
const Level15 = struct { inner: Level16 };
const Level14 = struct { inner: Level15 };
const Level13 = struct { inner: Level14 };
const Level12 = struct { inner: Level13 };
const Level11 = struct { inner: Level12 };
const Level10 = struct { inner: Level11 };
const Level9 = struct { inner: Level10 };
const Level8 = struct { inner: Level9 };
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
        const middle = &holder.inner.inner.inner.inner.inner.inner.inner.inner;
        middle.inner.inner.inner.inner.inner.inner.inner.inner.reference = .empty;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Holder} });
}
