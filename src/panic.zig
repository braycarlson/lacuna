const std = @import("std");

const c = @import("c.zig");
const thread = @import("thread.zig");

const assert = std.debug.assert;

pub threadlocal var call: ?[:0]const u8 = null;

pub fn report(message: []const u8, address: ?usize) noreturn {
    const label = call orelse "no lacuna call";

    std.debug.print("lacuna: panic in {s}: {s}\n", .{ label, message });

    if (thread.Interpreter.attached()) traceback_dump();

    std.debug.defaultPanic(message, address);
}

fn traceback_dump() void {
    assert(thread.Interpreter.attached());

    const saved = @import("exception.zig").pending_save();
    defer @import("exception.zig").pending_resume(&saved);

    assert(c.PyErr_Occurred() == null);

    const module = c.PyImport_ImportModule("faulthandler") orelse return clear();
    defer c.Py_DecRef(module);

    assert(@intFromPtr(module) % c.object_alignment == 0);

    const dump = @import("python.zig").attribute_get(module, "dump_traceback") orelse {
        return clear();
    };

    defer c.Py_DecRef(dump);

    assert(@intFromPtr(dump) % c.object_alignment == 0);

    const result = c.PyObject_CallObject(dump, null) orelse return clear();

    c.Py_DecRef(result);
}

fn clear() void {
    assert(thread.Interpreter.attached());

    if (c.PyErr_Occurred() != null) c.PyErr_Clear();

    assert(c.PyErr_Occurred() == null);
}
