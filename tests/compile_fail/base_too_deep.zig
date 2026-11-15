const lacuna = @import("lacuna");

const Bases = struct {
    pub const Level1 = error.Level0;
    pub const Level2 = error.Level1;
    pub const Level3 = error.Level2;
    pub const Level4 = error.Level3;
    pub const Level5 = error.Level4;
    pub const Level6 = error.Level5;
    pub const Level7 = error.Level6;
    pub const Level8 = error.Level7;
    pub const Level9 = error.Level8;
};

const Functions = struct {
    pub fn fail() error{
        Level0,
        Level1,
        Level2,
        Level3,
        Level4,
        Level5,
        Level6,
        Level7,
        Level8,
        Level9,
    }!void {
        return error.Level9;
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .bases = Bases, .functions = Functions });
}
