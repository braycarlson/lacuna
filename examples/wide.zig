const std = @import("std");

const lacuna = @import("lacuna");

const assert = std.debug.assert;

pub const module: lacuna.Module = .{
    .name = "wide",
    .doc = doc,
    .classes = &.{Panel},
    .functions = Functions,
    .messages = Messages,
    .thread_safe = true,
};

pub const Fault = error{
    NorthAlpha,
    NorthBravo,
    NorthCharlie,
    NorthDelta,
    NorthEcho,
    NorthFoxtrot,
    NorthGolf,
    NorthHotel,
    NorthIndia,
    NorthJuliett,
    NorthKilo,
    NorthLima,
    NorthMike,
    NorthNovember,
    NorthOscar,
    NorthPapa,
    SouthAlpha,
    SouthBravo,
    SouthCharlie,
    SouthDelta,
    SouthEcho,
    SouthFoxtrot,
    SouthGolf,
    SouthHotel,
    SouthIndia,
    SouthJuliett,
    SouthKilo,
    SouthLima,
    SouthMike,
    SouthNovember,
    SouthOscar,
    SouthPapa,
    EastAlpha,
    EastBravo,
    EastCharlie,
    EastDelta,
    EastEcho,
    EastFoxtrot,
    EastGolf,
    EastHotel,
    EastIndia,
    EastJuliett,
    EastKilo,
    EastLima,
    EastMike,
    EastNovember,
    EastOscar,
    EastPapa,
    WestAlpha,
    WestBravo,
    WestCharlie,
    WestDelta,
    WestEcho,
    WestFoxtrot,
    WestGolf,
    WestHotel,
    WestIndia,
    WestJuliett,
    WestKilo,
    WestLima,
    WestMike,
    WestNovember,
    WestOscar,
    WestPapa,
};

const doc =
    \\The wide fixture holds sixty-four errors and sixteen documented fields so that
    \\every comptime table of the binding grows past the default branch quota. The
    \\wide fixture holds sixty-four errors and sixteen documented fields so that every
    \\comptime table of the binding grows past the default branch quota. The wide
    \\fixture holds sixty-four errors and sixteen documented fields so that every
    \\comptime table of the binding grows past the default branch quota. The wide
    \\fixture holds sixty-four errors and sixteen documented fields so that every
    \\comptime table of the binding grows past the default branch quota.
;

const Messages = struct {
    pub fn message(err: Fault) []const u8 {
        const result: []const u8 = switch (err) {
            inline else => |known| "the " ++ @errorName(known) ++ " fault stopped the wide module",
        };

        assert(std.mem.startsWith(u8, result, "the "));
        assert(std.mem.endsWith(u8, result, " fault stopped the wide module"));

        return result;
    }
};

const Functions = struct {
    pub const docs = .{ .fail = doc };

    pub fn fail(arguments: struct { index: u8 }) (Fault || error{IndexError})!void {
        const names = @typeInfo(Fault).error_set.error_names.?;

        comptime assert(names.len == 64);

        inline for (names, 0..) |name, index| {
            if (arguments.index == index) return @field(Fault, name);
        }

        assert(arguments.index >= names.len);

        return error.IndexError;
    }
};

pub const Panel = struct {
    alpha: i64,
    bravo: i64,
    charlie: i64,
    delta: i64,
    echo: i64,
    foxtrot: i64,
    golf: i64,
    hotel: i64,
    india: i64,
    juliett: i64,
    kilo: i64,
    lima: i64,
    mike: i64,
    november: i64,
    oscar: i64,
    papa: i64,

    pub const doc = "A panel of sixteen documented slots.";

    pub const docs = .{
        .alpha = "The alpha slot, documented so that the docstring table of the class grows.",
        .bravo = "The bravo slot, documented so that the docstring table of the class grows.",
        .charlie = "The charlie slot, documented so that the docstring table of the class grows.",
        .delta = "The delta slot, documented so that the docstring table of the class grows.",
        .echo = "The echo slot, documented so that the docstring table of the class grows.",
        .foxtrot = "The foxtrot slot, documented so that the docstring table of the class grows.",
        .golf = "The golf slot, documented so that the docstring table of the class grows.",
        .hotel = "The hotel slot, documented so that the docstring table of the class grows.",
        .india = "The india slot, documented so that the docstring table of the class grows.",
        .juliett = "The juliett slot, documented so that the docstring table of the class grows.",
        .kilo = "The kilo slot, documented so that the docstring table of the class grows.",
        .lima = "The lima slot, documented so that the docstring table of the class grows.",
        .mike = "The mike slot, documented so that the docstring table of the class grows.",
        .november = "The november slot, documented so that the docstring table of the class grows.",
        .oscar = "The oscar slot, documented so that the docstring table of the class grows.",
        .papa = "The papa slot, documented so that the docstring table of the class grows.",
        .alpha_doubled = "Twice the alpha slot, saturated at the bounds of an i64.",
        .bravo_doubled = "Twice the bravo slot, saturated at the bounds of an i64.",
        .charlie_doubled = "Twice the charlie slot, saturated at the bounds of an i64.",
        .delta_doubled = "Twice the delta slot, saturated at the bounds of an i64.",
        .echo_doubled = "Twice the echo slot, saturated at the bounds of an i64.",
        .foxtrot_doubled = "Twice the foxtrot slot, saturated at the bounds of an i64.",
        .golf_doubled = "Twice the golf slot, saturated at the bounds of an i64.",
        .hotel_doubled = "Twice the hotel slot, saturated at the bounds of an i64.",
        .india_doubled = "Twice the india slot, saturated at the bounds of an i64.",
        .juliett_doubled = "Twice the juliett slot, saturated at the bounds of an i64.",
        .kilo_doubled = "Twice the kilo slot, saturated at the bounds of an i64.",
        .lima_doubled = "Twice the lima slot, saturated at the bounds of an i64.",
        .mike_doubled = "Twice the mike slot, saturated at the bounds of an i64.",
        .november_doubled = "Twice the november slot, saturated at the bounds of an i64.",
        .oscar_doubled = "Twice the oscar slot, saturated at the bounds of an i64.",
        .papa_doubled = "Twice the papa slot, saturated at the bounds of an i64.",
    };

    pub const fields = .{
        .alpha = .read_write,
        .bravo = .read_write,
        .charlie = .read_write,
        .delta = .read_write,
        .echo = .read_write,
        .foxtrot = .read_write,
        .golf = .read_write,
        .hotel = .read_write,
        .india = .read_write,
        .juliett = .read_write,
        .kilo = .read_write,
        .lima = .read_write,
        .mike = .read_write,
        .november = .read_write,
        .oscar = .read_write,
        .papa = .read_write,
    };

    pub const properties = .{
        .alpha_doubled,
        .bravo_doubled,
        .charlie_doubled,
        .delta_doubled,
        .echo_doubled,
        .foxtrot_doubled,
        .golf_doubled,
        .hotel_doubled,
        .india_doubled,
        .juliett_doubled,
        .kilo_doubled,
        .lima_doubled,
        .mike_doubled,
        .november_doubled,
        .oscar_doubled,
        .papa_doubled,
    };

    pub fn init(panel: *Panel) void {
        panel.* = std.mem.zeroes(Panel);

        assert(std.mem.allEqual(u8, std.mem.asBytes(panel), 0));
        assert(panel.papa_doubled() == 0);
    }

    pub fn alpha_doubled(panel: *const Panel) i64 {
        const result = panel.alpha *| 2;

        assert(@abs(result) >= @abs(panel.alpha));
        assert((result < 0) == (panel.alpha < 0));

        return result;
    }

    pub fn bravo_doubled(panel: *const Panel) i64 {
        const result = panel.bravo *| 2;

        assert(@abs(result) >= @abs(panel.bravo));
        assert((result < 0) == (panel.bravo < 0));

        return result;
    }

    pub fn charlie_doubled(panel: *const Panel) i64 {
        const result = panel.charlie *| 2;

        assert(@abs(result) >= @abs(panel.charlie));
        assert((result < 0) == (panel.charlie < 0));

        return result;
    }

    pub fn delta_doubled(panel: *const Panel) i64 {
        const result = panel.delta *| 2;

        assert(@abs(result) >= @abs(panel.delta));
        assert((result < 0) == (panel.delta < 0));

        return result;
    }

    pub fn echo_doubled(panel: *const Panel) i64 {
        const result = panel.echo *| 2;

        assert(@abs(result) >= @abs(panel.echo));
        assert((result < 0) == (panel.echo < 0));

        return result;
    }

    pub fn foxtrot_doubled(panel: *const Panel) i64 {
        const result = panel.foxtrot *| 2;

        assert(@abs(result) >= @abs(panel.foxtrot));
        assert((result < 0) == (panel.foxtrot < 0));

        return result;
    }

    pub fn golf_doubled(panel: *const Panel) i64 {
        const result = panel.golf *| 2;

        assert(@abs(result) >= @abs(panel.golf));
        assert((result < 0) == (panel.golf < 0));

        return result;
    }

    pub fn hotel_doubled(panel: *const Panel) i64 {
        const result = panel.hotel *| 2;

        assert(@abs(result) >= @abs(panel.hotel));
        assert((result < 0) == (panel.hotel < 0));

        return result;
    }

    pub fn india_doubled(panel: *const Panel) i64 {
        const result = panel.india *| 2;

        assert(@abs(result) >= @abs(panel.india));
        assert((result < 0) == (panel.india < 0));

        return result;
    }

    pub fn juliett_doubled(panel: *const Panel) i64 {
        const result = panel.juliett *| 2;

        assert(@abs(result) >= @abs(panel.juliett));
        assert((result < 0) == (panel.juliett < 0));

        return result;
    }

    pub fn kilo_doubled(panel: *const Panel) i64 {
        const result = panel.kilo *| 2;

        assert(@abs(result) >= @abs(panel.kilo));
        assert((result < 0) == (panel.kilo < 0));

        return result;
    }

    pub fn lima_doubled(panel: *const Panel) i64 {
        const result = panel.lima *| 2;

        assert(@abs(result) >= @abs(panel.lima));
        assert((result < 0) == (panel.lima < 0));

        return result;
    }

    pub fn mike_doubled(panel: *const Panel) i64 {
        const result = panel.mike *| 2;

        assert(@abs(result) >= @abs(panel.mike));
        assert((result < 0) == (panel.mike < 0));

        return result;
    }

    pub fn november_doubled(panel: *const Panel) i64 {
        const result = panel.november *| 2;

        assert(@abs(result) >= @abs(panel.november));
        assert((result < 0) == (panel.november < 0));

        return result;
    }

    pub fn oscar_doubled(panel: *const Panel) i64 {
        const result = panel.oscar *| 2;

        assert(@abs(result) >= @abs(panel.oscar));
        assert((result < 0) == (panel.oscar < 0));

        return result;
    }

    pub fn papa_doubled(panel: *const Panel) i64 {
        const result = panel.papa *| 2;

        assert(@abs(result) >= @abs(panel.papa));
        assert((result < 0) == (panel.papa < 0));

        return result;
    }
};
