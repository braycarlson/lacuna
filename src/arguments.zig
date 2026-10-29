const std = @import("std");

const c = @import("c.zig");
const from_python_module = @import("from_python.zig");
const list_module = @import("list.zig");
const python = @import("python.zig");
const scope_module = @import("scope.zig");
const signature_module = @import("signature.zig");
const state_module = @import("state.zig");
const value_module = @import("value.zig");

const assert = std.debug.assert;

const Builtins = state_module.Builtins;
const Scope = scope_module.Scope;
const from_python = from_python_module.from_python;

pub const Error = error{Raised};

pub const Call = struct {
    keywords: Keywords,
    positional: Positional,

    pub const Keywords = union(enum) {
        dictionary: ?*c.PyObject,
        vector: Vector,
    };

    pub const Positional = union(enum) {
        tuple: *c.PyObject,
        vector: []const *c.PyObject,
    };

    pub const Vector = struct {
        names: ?*c.PyObject,
        values: []const *c.PyObject,
    };

    pub fn fast(vector: []const *c.PyObject, count: c.Py_ssize_t, names: ?*c.PyObject) Call {
        assert(count >= 0);
        assert(count <= vector.len);
        assert(python.flagged_or_null(names, c.Py_TPFLAGS_TUPLE_SUBCLASS));

        const positional_total: u32 = count_of(count);

        return .{
            .keywords = .{ .vector = .{
                .names = names,
                .values = vector[positional_total..],
            } },
            .positional = .{ .vector = vector[0..positional_total] },
        };
    }

    pub fn tuple(arguments: *c.PyObject, keywords: ?*c.PyObject) Call {
        assert(python.has_flag(arguments, c.Py_TPFLAGS_TUPLE_SUBCLASS));
        assert(python.flagged_or_null(keywords, c.Py_TPFLAGS_DICT_SUBCLASS));

        return .{ .keywords = .{ .dictionary = keywords }, .positional = .{ .tuple = arguments } };
    }

    pub fn positional_count(call: *const Call) u32 {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(call.keyword_count() <= std.math.maxInt(u32));

        return switch (call.positional) {
            .tuple => |arguments| count_of(c.PyTuple_Size(arguments)),
            .vector => |vector| count_of(@intCast(vector.len)),
        };
    }

    pub fn positional_get(call: *const Call, index: u32) *c.PyObject {
        assert(index < call.positional_count());
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

        const object = switch (call.positional) {
            .tuple => |arguments| c.PyTuple_GetItem(arguments, @intCast(index)),
            .vector => |vector| vector[index],
        };

        assert(object != null);

        return object.?;
    }

    pub fn keyword_count(call: *const Call) u32 {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(@sizeOf(Call) > 0);

        return switch (call.keywords) {
            .dictionary => |dictionary| if (dictionary) |live| count_of(c.PyDict_Size(live)) else 0,
            .vector => |vector| count_of(@intCast(vector.values.len)),
        };
    }
};

const KeywordCursor = struct {
    call: *const Call,
    index: u32,
    position: c.Py_ssize_t,
    remaining: u32,

    const Entry = struct {
        name: *c.PyObject,
        value: *c.PyObject,
    };

    fn init(call: *const Call) KeywordCursor {
        if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
        assert(call.keyword_count() <= std.math.maxInt(u32));

        return .{ .call = call, .index = 0, .position = 0, .remaining = call.keyword_count() };
    }

    fn next(cursor: *KeywordCursor) Entry {
        assert(cursor.remaining > 0);
        assert(cursor.remaining <= cursor.call.keyword_count());

        cursor.remaining -= 1;

        switch (cursor.call.keywords) {
            .dictionary => |dictionary| {
                var name: ?*c.PyObject = null;
                var value: ?*c.PyObject = null;

                const found = c.PyDict_Next(dictionary.?, &cursor.position, &name, &value);

                assert(found != 0);

                return .{ .name = name.?, .value = value.? };
            },
            .vector => |vector| {
                const name = c.PyTuple_GetItem(vector.names.?, @intCast(cursor.index));

                assert(name != null);
                defer cursor.index += 1;

                return .{ .name = name.?, .value = vector.values[cursor.index] };
            },
        }
    }
};

fn count_of(size: c.Py_ssize_t) u32 {
    assert(size >= 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    return std.math.cast(u32, size) orelse std.math.maxInt(u32);
}

pub fn bind(
    comptime Binding: type,
    comptime Arguments: type,
    comptime name: [:0]const u8,
    state: *const Binding.State,
    call: *const Call,
    scope: *Scope,
) Error!Arguments {
    comptime assert(name.len > 0);
    comptime assert(!@typeInfo(Arguments).@"struct".is_tuple);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const structure = @typeInfo(Arguments).@"struct";
    const layout = comptime signature_module.layout_of(Arguments, name);

    var slots: [structure.field_names.len]?*c.PyObject = @splat(null);
    var extras: ExtrasType(Arguments, layout) = .{ .count = 0, .entries = undefined };
    var result: Arguments = undefined;

    const source: Source = .{ .call = call, .scope = scope };

    try collected_initialize(Binding, Arguments, layout, &result, scope);
    try positional_fill(Arguments, name, &state.builtins, call, &slots);
    try keywords_fill(Arguments, name, &state.builtins, call, &slots, &extras, &result);
    try rest_convert(Binding, Arguments, name, state, source, &result);
    try extras_convert(Binding, Arguments, name, state, source, &extras, &result);

    inline for (structure.field_names, structure.field_attrs, 0..) |field, attributes, index| {
        if (comptime layout.slotted(index)) {
            const Field = @FieldType(Arguments, field);

            if (slots[index]) |object| {
                const spelled = comptime signature_module.python_name_of(Arguments, field);
                const label = name ++ "() argument '" ++ spelled ++ "'";
                const item = try from_python(Binding, Field, label, state, object, scope);

                @field(result, field) = item;
            } else {
                @field(result, field) = attributes.defaultValue(Field) orelse {
                    const spelled = comptime signature_module.python_name_of(Arguments, field);
                    const message = name ++ "() missing required argument '" ++ spelled ++ "'";

                    c.PyErr_SetString(state.builtins.get(.type_error), message);

                    return error.Raised;
                };
            }
        }
    }

    return result;
}

const Source = struct {
    call: *const Call,
    scope: *Scope,
};

const Found = union(enum) {
    extra,
    field: u32,
};

fn ExtrasType(comptime Arguments: type, comptime layout: signature_module.Layout) type {
    comptime assert(@typeInfo(Arguments) == .@"struct");
    comptime assert(layout.positional_end <= @typeInfo(Arguments).@"struct".field_names.len);

    const capacity: u32 = capacity: {
        const index = layout.keywords orelse break :capacity 0;
        const Extra = @FieldType(Arguments, @typeInfo(Arguments).@"struct".field_names[index]);

        if (Extra == value_module.Object) break :capacity 0;
        break :capacity Extra.capacity_max;
    };

    return struct {
        count: u32,
        entries: [capacity]KeywordCursor.Entry,
    };
}

fn collected_initialize(
    comptime Binding: type,
    comptime Arguments: type,
    comptime layout: signature_module.Layout,
    result: *Arguments,
    scope: *Scope,
) Error!void {
    comptime assert(layout.positional_end <= @typeInfo(Arguments).@"struct".field_names.len);
    comptime assert(Binding.classes.len <= std.math.maxInt(u32));
    assert(scope.object_count <= scope.objects.len);

    const names = @typeInfo(Arguments).@"struct".field_names;

    if (layout.variadic) |index| {
        const Rest = @FieldType(Arguments, names[index]);

        comptime assert(list_module.is_list(Rest));

        @field(result, names[index]) = .empty;
    }

    if (layout.keywords) |index| {
        const Extra = @FieldType(Arguments, names[index]);

        if (Extra == value_module.Object) {
            const dictionary = c.PyDict_New() orelse return error.Raised;

            scope.hold(dictionary);
            @field(result, names[index]) = .{ .pointer = dictionary };
        } else {
            comptime assert(list_module.is_map(Extra));

            @field(result, names[index]) = .empty;
        }
    }
}

fn positional_fill(
    comptime Arguments: type,
    comptime name: [:0]const u8,
    builtins: *const Builtins,
    call: *const Call,
    slots: *[@typeInfo(Arguments).@"struct".field_names.len]?*c.PyObject,
) Error!void {
    comptime assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const layout = comptime signature_module.layout_of(Arguments, name);
    const names = @typeInfo(Arguments).@"struct".field_names;
    const positional_count = call.positional_count();
    const bound_count = @min(positional_count, layout.positional_end);

    for (0..bound_count) |index| slots[index] = call.positional_get(@intCast(index));

    if (positional_count == bound_count) return;

    const index = layout.variadic orelse {
        const format = std.fmt.comptimePrint(
            "{s}() takes at most {d} positional arguments (%zd given)",
            .{ name, layout.positional_end },
        );

        return positional_excess(format, builtins, positional_count);
    };

    const Rest = @FieldType(Arguments, names[index]);

    if (positional_count - bound_count > Rest.capacity_max) {
        const format = std.fmt.comptimePrint(
            "{s}() takes at most {d} extra positional arguments (%zd given)",
            .{ name, Rest.capacity_max },
        );

        return positional_excess(format, builtins, positional_count - bound_count);
    }
}

fn rest_convert(
    comptime Binding: type,
    comptime Arguments: type,
    comptime name: [:0]const u8,
    state: *const Binding.State,
    source: Source,
    result: *Arguments,
) Error!void {
    comptime assert(name.len > 0);
    assert(source.scope.object_count <= source.scope.objects.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const layout = comptime signature_module.layout_of(Arguments, name);
    const index = layout.variadic orelse return;
    const names = @typeInfo(Arguments).@"struct".field_names;
    const Rest = @FieldType(Arguments, names[index]);
    const rest = &@field(result, names[index]);
    const label = name ++ "() argument '*" ++ names[index] ++ "' item";
    const positional_count = source.call.positional_count();
    const bound_count = @min(positional_count, layout.positional_end);

    assert(rest.count == 0);
    assert(positional_count - bound_count <= Rest.capacity_max);

    for (bound_count..positional_count) |position| {
        const object = source.call.positional_get(@intCast(position));
        const item = try from_python(Binding, Rest.Item, label, state, object, source.scope);

        rest.items[rest.count] = item;
        rest.count += 1;
    }

    assert(rest.count == positional_count - bound_count);
}

fn positional_excess(comptime format: [:0]const u8, builtins: *const Builtins, given: u32) Error {
    comptime assert(std.mem.find(u8, format, "%zd") != null);
    assert(given > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const count: c.Py_ssize_t = @intCast(given);

    _ = c.PyErr_Format(builtins.get(.type_error), format, count);

    return error.Raised;
}

fn keywords_fill(
    comptime Arguments: type,
    comptime name: [:0]const u8,
    builtins: *const Builtins,
    call: *const Call,
    slots: *[@typeInfo(Arguments).@"struct".field_names.len]?*c.PyObject,
    extras: *ExtrasType(Arguments, signature_module.layout_of(Arguments, name)),
    result: *Arguments,
) Error!void {
    comptime assert(name.len > 0);
    assert(extras.count == 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const layout = comptime signature_module.layout_of(Arguments, name);
    const names = @typeInfo(Arguments).@"struct".field_names;

    var cursor: KeywordCursor = .init(call);
    var extra_count: u32 = 0;

    for (0..cursor.remaining) |_| {
        const entry = cursor.next();
        const found = try field_find(Arguments, layout, name, builtins, entry.name);

        switch (found) {
            .field => |index| {
                if (slots[index] != null) {
                    _ = c.PyErr_Format(
                        builtins.get(.type_error),
                        name ++ "() got multiple values for argument %R",
                        entry.name,
                    );

                    return error.Raised;
                }

                slots[index] = entry.value;
            },
            .extra => {
                const index = layout.keywords orelse unreachable;
                const extra = &@field(result, names[index]);

                if (@TypeOf(extra.*) == value_module.Object) {
                    if (c.PyDict_SetItem(extra.pointer, entry.name, entry.value) != 0) {
                        return error.Raised;
                    }
                } else {
                    if (extra_count < extras.entries.len) extras.entries[extra_count] = entry;

                    extra_count += 1;
                }
            },
        }
    }

    assert(cursor.remaining == 0);

    if (extra_count > extras.entries.len) {
        const format = std.fmt.comptimePrint(
            "{s}() takes at most {d} extra keyword arguments (%zd given)",
            .{ name, extras.entries.len },
        );

        return positional_excess(format, builtins, extra_count);
    }

    extras.count = extra_count;
}

fn extras_convert(
    comptime Binding: type,
    comptime Arguments: type,
    comptime name: [:0]const u8,
    state: *const Binding.State,
    source: Source,
    extras: *const ExtrasType(Arguments, signature_module.layout_of(Arguments, name)),
    result: *Arguments,
) Error!void {
    comptime assert(name.len > 0);
    assert(extras.count <= extras.entries.len);
    assert(source.scope.object_count <= source.scope.objects.len);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

    const layout = comptime signature_module.layout_of(Arguments, name);
    const index = layout.keywords orelse return;
    const names = @typeInfo(Arguments).@"struct".field_names;
    const Extra = @FieldType(Arguments, names[index]);

    if (Extra == value_module.Object) return;

    const extra = &@field(result, names[index]);
    const label = name ++ "() keyword argument";

    for (extras.entries[0..extras.count]) |entry| {
        const key = try from_python(Binding, Extra.Key, label, state, entry.name, source.scope);
        const item = try from_python(Binding, Extra.Value, label, state, entry.value, source.scope);

        extra.assign(.{ .key = key, .value = item }) catch {
            const message = std.fmt.comptimePrint(
                "{s}() takes at most {d} extra keyword arguments",
                .{ name, Extra.capacity_max },
            );

            c.PyErr_SetString(state.builtins.get(.type_error), message);

            return error.Raised;
        };
    }

    assert(extra.slice().len <= extras.count);
}

fn field_find(
    comptime Arguments: type,
    comptime layout: signature_module.Layout,
    comptime name: [:0]const u8,
    builtins: *const Builtins,
    keyword: *c.PyObject,
) Error!Found {
    comptime assert(layout.positional_only_count <= layout.positional_end);
    comptime assert(name.len > 0);
    assert(python.has_flag(keyword, c.Py_TPFLAGS_UNICODE_SUBCLASS));

    const names = @typeInfo(Arguments).@"struct".field_names;
    const text = python.text_of(keyword) orelse return error.Raised;

    inline for (names, 0..) |field, index| {
        if (comptime layout.nameable(index)) {
            const spelled = comptime signature_module.python_name_of(Arguments, field);

            if (std.mem.eql(u8, text, spelled)) return .{ .field = index };
        }
    }

    if (layout.keywords != null) return .extra;

    inline for (names, 0..) |field, index| {
        if (index < layout.positional_only_count) {
            const spelled = comptime signature_module.python_name_of(Arguments, field);

            if (std.mem.eql(u8, text, spelled)) {
                _ = c.PyErr_Format(
                    builtins.get(.type_error),
                    name ++ "() got a positional-only argument passed as a keyword: %R",
                    keyword,
                );

                return error.Raised;
            }
        }
    }

    _ = c.PyErr_Format(
        builtins.get(.type_error),
        name ++ "() got an unexpected keyword argument %R",
        keyword,
    );

    return error.Raised;
}

pub fn bind_none(
    comptime name: [:0]const u8,
    builtins: *const Builtins,
    call: *const Call,
) Error!void {
    comptime assert(name.len > 0);
    if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
    assert(call.positional_count() <= std.math.maxInt(u32));

    const count: u64 = @as(u64, call.positional_count()) + call.keyword_count();
    if (count == 0) return;

    _ = c.PyErr_Format(
        builtins.get(.type_error),
        name ++ "() takes no arguments (%zd given)",
        @as(c.Py_ssize_t, @intCast(count)),
    );

    return error.Raised;
}
