const std = @import("std");
const builtin = @import("builtin");

const assert = std.debug.assert;

const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

pub const bytes_max: u32 = 1 << 30;

pub const child_default: Allocator = if (!builtin.single_threaded)
    std.heap.smp_allocator
else if (builtin.link_libc)
    std.heap.c_allocator
else
    std.heap.page_allocator;

const reserve_attempt_max: u32 = 1 << 16;

pub const Budget = struct {
    child: Allocator,
    limit: u32,
    used: std.atomic.Value(u32),

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn init(child: Allocator, limit: u32) Budget {
        assert(limit > 0);
        assert(limit <= bytes_max);

        return .{ .child = child, .limit = limit, .used = .init(0) };
    }

    pub fn allocator(budget: *Budget) Allocator {
        assert(budget.used.load(.monotonic) <= budget.limit);
        assert(budget.limit > 0);

        return .{ .ptr = budget, .vtable = &vtable };
    }

    fn reserve(budget: *Budget, count: u64) bool {
        assert(budget.limit > 0);
        assert(budget.used.load(.monotonic) <= budget.limit);

        if (count > budget.limit) return false;

        const amount: u32 = @intCast(count);

        var current = budget.used.load(.monotonic);

        for (0..reserve_attempt_max) |_| {
            if (amount > budget.limit - current) return false;

            const replaced = current + amount;

            current = budget.used.cmpxchgWeak(current, replaced, .monotonic, .monotonic) orelse {
                return true;
            };
        }

        return false;
    }

    fn release(budget: *Budget, count: u64) void {
        assert(budget.limit > 0);
        assert(count <= budget.used.load(.monotonic));

        _ = budget.used.fetchSub(@intCast(count), .monotonic);
    }

    fn alloc(context: *anyopaque, length: usize, alignment: Alignment, address: usize) ?[*]u8 {
        const budget: *Budget = @ptrCast(@alignCast(context));

        assert(length > 0);
        assert(budget.limit > 0);
        assert(alignment.toByteUnits() <= std.heap.page_size_max);
        assert(address_valid(address));

        if (!budget.reserve(length)) return null;

        return budget.child.rawAlloc(length, alignment, address) orelse {
            budget.release(length);

            return null;
        };
    }

    fn resize(
        context: *anyopaque,
        memory: []u8,
        alignment: Alignment,
        length: usize,
        address: usize,
    ) bool {
        const budget: *Budget = @ptrCast(@alignCast(context));

        assert(length > 0);
        assert(memory.len > 0);
        assert(alignment.check(@intFromPtr(memory.ptr)));
        assert(address_valid(address));

        if (length <= memory.len) {
            if (!budget.child.rawResize(memory, alignment, length, address)) return false;

            budget.release(memory.len - length);

            return true;
        }

        if (!budget.reserve(length - memory.len)) return false;

        if (budget.child.rawResize(memory, alignment, length, address)) return true;

        budget.release(length - memory.len);

        return false;
    }

    fn remap(
        context: *anyopaque,
        memory: []u8,
        alignment: Alignment,
        length: usize,
        address: usize,
    ) ?[*]u8 {
        const budget: *Budget = @ptrCast(@alignCast(context));

        assert(length > 0);
        assert(memory.len > 0);
        assert(alignment.check(@intFromPtr(memory.ptr)));
        assert(address_valid(address));

        if (length <= memory.len) {
            const shrunk = budget.child.rawRemap(memory, alignment, length, address) orelse {
                return null;
            };

            budget.release(memory.len - length);

            return shrunk;
        }

        if (!budget.reserve(length - memory.len)) return null;

        return budget.child.rawRemap(memory, alignment, length, address) orelse {
            budget.release(length - memory.len);

            return null;
        };
    }

    fn free(context: *anyopaque, memory: []u8, alignment: Alignment, address: usize) void {
        const budget: *Budget = @ptrCast(@alignCast(context));

        assert(memory.len > 0);
        assert(memory.len <= budget.used.load(.monotonic));
        assert(alignment.check(@intFromPtr(memory.ptr)));
        assert(address_valid(address));

        budget.child.rawFree(memory, alignment, address);
        budget.release(memory.len);
    }
};

fn address_valid(address: u64) bool {
    comptime assert(std.heap.page_size_min > 0);

    if (address == 0) return true;
    return address >= std.heap.page_size_min;
}

pub const Scratch = struct {
    budget: Budget,
    arena: std.heap.ArenaAllocator,

    pub fn start(scratch: *Scratch) void {
        assert(@intFromPtr(scratch) % @alignOf(Scratch) == 0);

        scratch.budget = .init(child_default, bytes_max);
        scratch.arena = .init(scratch.budget.allocator());

        assert(scratch.budget.used.load(.monotonic) == 0);
    }

    pub fn allocator(scratch: *Scratch) Allocator {
        assert(scratch.budget.limit == bytes_max);

        return scratch.arena.allocator();
    }

    pub fn finish(scratch: *Scratch) void {
        assert(scratch.budget.limit == bytes_max);

        scratch.arena.deinit();

        assert(scratch.budget.used.load(.monotonic) == 0);
    }
};

test Budget {
    var budget: Budget = .init(std.testing.allocator, 64);
    const budgeted = budget.allocator();

    const first = try budgeted.alloc(u8, 40);

    try std.testing.expectEqual(40, budget.used.load(.monotonic));
    try std.testing.expectError(error.OutOfMemory, budgeted.alloc(u8, 25));

    const second = try budgeted.alloc(u8, 24);

    try std.testing.expectEqual(64, budget.used.load(.monotonic));

    budgeted.free(second);

    const resized = budgeted.resize(first, 65);

    try std.testing.expect(!resized);
    try std.testing.expectEqual(40, budget.used.load(.monotonic));

    budgeted.free(first);

    try std.testing.expectEqual(0, budget.used.load(.monotonic));
}

test "an arena over a budget frees everything it took" {
    var budget: Budget = .init(std.testing.allocator, 1 << 16);
    var arena: std.heap.ArenaAllocator = .init(budget.allocator());

    for (0..64) |index| _ = try arena.allocator().alloc(u64, index + 1);

    try std.testing.expect(budget.used.load(.monotonic) > 0);
    try std.testing.expectError(error.OutOfMemory, arena.allocator().alloc(u8, 1 << 17));

    arena.deinit();

    try std.testing.expectEqual(0, budget.used.load(.monotonic));
}
