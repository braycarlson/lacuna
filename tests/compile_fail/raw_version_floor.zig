const lacuna = @import("lacuna");

comptime {
    _ = lacuna.c.raw.PyObject_Vectorcall;
}
