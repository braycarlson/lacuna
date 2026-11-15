const std = @import("std");

const lacuna = @import("lacuna");

const Buffer = struct {
    items: []u8,

    pub fn init(buffer: *Buffer) void {
        buffer.* = .{ .items = &.{} };
    }

    pub fn grow(buffer: *Buffer, allocator: std.mem.Allocator) error{OutOfMemory}!void {
        buffer.items = try allocator.alloc(u8, 16);
    }
};

comptime {
    lacuna.module_export(.{ .name = "fixture", .classes = &.{Buffer} });
}
