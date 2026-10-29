const std = @import("std");

const c = @import("c.zig");
const class_module = @import("class.zig");
const exception = @import("exception.zig");
const from_python_module = @import("from_python.zig");
const function_module = @import("function.zig");
const instance_module = @import("instance.zig");
const kind_module = @import("kind.zig");
const native_module = @import("native.zig");
const python = @import("python.zig");
const registry = @import("registry.zig");
const signature_module = @import("signature.zig");
const state_module = @import("state.zig");
const to_python_module = @import("to_python.zig");
const variant_module = @import("variant.zig");
const version_module = @import("version.zig");

const assert = std.debug.assert;

const Module = registry.Module;
const terminated = @import("signature.zig").terminated;

const coroutine_source: [:0]const u8 =
    \\import asyncio
    \\import functools
    \\import warnings
    \\
    \\
    \\def wrap(function, deprecation):
    \\    @functools.wraps(function)
    \\    async def coroutine(*arguments, **keywords):
    \\        if deprecation is not None:
    \\            warnings.warn(deprecation, DeprecationWarning, stacklevel=2)
    \\
    \\        return await asyncio.to_thread(function, *arguments, **keywords)
    \\
    \\    return coroutine
    \\
;

const Created = struct {
    class: *c.PyObject,
    metaclass: *c.PyObject,
};

const Creation = struct {
    bases: ?*c.PyObject,
    specification: *const c.PyType_Spec,
};

const Family = struct {
    base: *c.PyObject,
    member: *c.PyObject,
};

pub fn module_export(comptime module: Module) void {
    comptime assert(module.name.len > 0);
    comptime assert(module.classes.len <= registry.class_count_max);

    const leaf = comptime signature_module.module_leaf(module.name);

    module_export_named(module, "PyInit_" ++ leaf);
}

pub fn module_export_named(comptime module: Module, comptime name: []const u8) void {
    comptime assert(module.name.len > 0);
    comptime assert(name.len > 0);

    const Binding = BindingType(module);

    @export(&Binding.initialize, .{ .name = name });
}

pub fn BindingType(comptime module: Module) type {
    comptime assert(module.classes.len <= registry.class_count_max);
    comptime assert(module.name.len > 0);

    comptime registry.validate(module);

    const pickled = pickled_any(module.classes) or module.unions.len > 0;
    const function_count = registry.function_count(module.functions) + @intFromBool(pickled);

    return struct {
        pub const State = state_module.StateType(.{
            .classes = module.classes.len,
            .enums = module.enums.len,
            .errors = errors.len,
            .variants = variant_module.slot_count(module.unions),
        });

        pub const classes = module.classes;
        pub const declared = module.classes ++ module.unions;
        pub const enums = module.enums;
        pub const errors = registry.errors_of(module);
        pub const messages = module.messages;
        pub const name = module.name;
        pub const unions = module.unions;

        const Binding = @This();

        var definition: c.PyModuleDef = definition_of(&slots);
        var definition_3_11: c.PyModuleDef = definition_of(&slots_3_11);

        const methods: [function_count + 1]c.PyMethodDef = methods: {
            var result: [function_count + 1]c.PyMethodDef = undefined;
            var index: u32 = 0;

            if (module.functions) |Namespace| {
                for (@typeInfo(Namespace).@"struct".decl_names) |member| {
                    if (registry.function_member_of(Namespace, member) == .function) {
                        const Function = function_module.FunctionType(Binding, Namespace, member);

                        result[index] = Function.definition;
                        index += 1;
                    }
                }
            }

            if (pickled) {
                result[index] = restore_definition;
                index += 1;
            }

            result[index] = std.mem.zeroes(c.PyMethodDef);

            break :methods result;
        };

        const restore_definition: c.PyMethodDef = .{
            .ml_name = class_module.restore_name,
            .ml_meth = &restore,
            .ml_flags = c.METH_FASTCALL,
            .ml_doc = class_module.restore_name ++ "($module, class, fields, /)\n--\n\n" ++
                "Rebuild a pickled instance from its fields.",
        };

        const slots = [_]c.PyModuleDef_Slot{
            .{ .slot = c.Py_mod_exec, .value = &exec },
            .{
                .slot = c.api_3_12.Py_mod_multiple_interpreters,
                .value = @ptrFromInt(c.api_3_12.Py_MOD_PER_INTERPRETER_GIL_SUPPORTED),
            },
        } ++ gil_slots ++ [_]c.PyModuleDef_Slot{.{ .slot = 0, .value = null }};

        const gil_slots = if (c.free_threaded)
            [_]c.PyModuleDef_Slot{.{
                .slot = c.api_free_threaded.Py_mod_gil,
                .value = if (module.thread_safe)
                    @ptrFromInt(c.api_free_threaded.Py_MOD_GIL_NOT_USED)
                else
                    null,
            }}
        else
            [_]c.PyModuleDef_Slot{};

        const slots_3_11 = [_]c.PyModuleDef_Slot{
            .{ .slot = c.Py_mod_exec, .value = &exec },
            .{ .slot = 0, .value = null },
        };

        const built_raise = if (c.abi_minor) |built| python.Raise{
            .class_name = "ImportError",
            .message = std.fmt.comptimePrint("{s} was built for the {s}Python {d}.{d} only", .{
                name,
                if (c.free_threaded) "free-threaded " else "GIL ",
                built.major,
                built.minor,
            }),
        } else {};

        const version_raise: python.Raise = .{
            .class_name = "ImportError",
            .message = std.fmt.comptimePrint("{s} needs Python {d}.{d} or later", .{
                name,
                floor_built.major,
                floor_built.minor,
            }),
        };

        const floor_built: version_module.Version = .{
            .major = version_module.floor.major,
            .minor = c.stable_minor,
        };

        fn definition_of(comptime slots_selected: []const c.PyModuleDef_Slot) c.PyModuleDef {
            comptime assert(slots_selected.len >= 2);
            comptime assert(slots_selected[slots_selected.len - 1].slot == 0);

            return .{
                .m_base = .{
                    .ob_base = c.object_head_static,
                    .m_init = null,
                    .m_index = 0,
                    .m_copy = null,
                },
                .m_name = name,
                .m_doc = if (module.doc) |doc| doc.ptr else null,
                .m_size = @sizeOf(State),
                .m_methods = &methods,
                .m_slots = slots_selected.ptr,
                .m_traverse = &traverse,
                .m_clear = &clear,
                .m_free = &free,
            };
        }

        fn restore(
            object: *c.PyObject,
            arguments: ?[*]const *c.PyObject,
            count: c.Py_ssize_t,
        ) callconv(.c) ?*c.PyObject {
            assert(@intFromPtr(arguments) % @alignOf(*c.PyObject) == 0);
            assert(count >= 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const state = State.of_module(object);

            if (count != 2) {
                c.PyErr_SetString(
                    state.builtins.get(.type_error),
                    class_module.restore_name ++ "() takes exactly 2 arguments",
                );

                return null;
            }

            const class = arguments.?[0];

            if (python.has_flag(class, c.Py_TPFLAGS_TYPE_SUBCLASS)) {
                inline for (0..classes.len) |position| {
                    const index = classes.len - 1 - position;
                    const Class = classes[index];

                    if (comptime class_module.picklable(Class)) {
                        const Instance = instance_module.InstanceType(Class);

                        if (Instance.defining_of(class) == state.class_get(index)) {
                            const Definition = class_module.ClassType(Binding, Class);

                            return Definition.restore_into(state, .{
                                .class = class,
                                .fields = arguments.?[1],
                            });
                        }
                    }
                }
            }

            const restoration: class_module.Restoration = .{
                .class = class,
                .fields = arguments.?[1],
            };

            if (variant_restore(state, restoration)) |restored| return restored;
            if (c.PyErr_Occurred() != null) return null;

            c.PyErr_SetString(
                state.builtins.get(.type_error),
                class_module.restore_name ++ "() needs a picklable class of this module",
            );

            return null;
        }

        pub fn state_current() ?*const State {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(name.len > 0);

            const object = c.PyImport_ImportModule(name) orelse return null;
            defer c.Py_DecRef(object);

            if (!definition_known(c.PyModule_GetDef(object))) {
                c.PyErr_Clear();

                python.exception_raise(.{
                    .class_name = "RuntimeError",
                    .message = name ++ " is not the module in sys.modules",
                });

                return null;
            }

            return State.of_module(object);
        }

        fn definition_known(defined: ?*c.PyModuleDef) bool {
            assert(@intFromPtr(defined) % @alignOf(c.PyModuleDef) == 0);

            if (defined == &definition) return true;
            return defined == &definition_3_11;
        }

        pub fn initialize() callconv(.c) ?*c.PyObject {
            const selected = definition_select() orelse return null;

            return c.PyModuleDef_Init(selected);
        }

        pub fn definition_select() ?*c.PyModuleDef {
            assert(definition.m_size == @sizeOf(State));
            assert(definition_3_11.m_size == definition.m_size);

            const text = python.text_bounded(c.Py_GetVersion(), version_module.text_bytes_max);

            const version = version_module.parse(text) orelse {
                python.exception_raise(version_raise);

                return null;
            };

            if (version.rank() < floor_built.rank()) {
                python.exception_raise(version_raise);

                return null;
            }

            if (c.abi_minor) |minor| {
                const built: version_module.Version = .{
                    .major = minor.major,
                    .minor = minor.minor,
                };

                if (version.rank() != built.rank()) {
                    python.exception_raise(built_raise);

                    return null;
                }

                if (version_module.free_threaded_is(text) != c.free_threaded) {
                    python.exception_raise(built_raise);

                    return null;
                }
            }

            if (c.pypy) return &definition_3_11;
            if (version.rank() >= version_module.per_interpreter_gil.rank()) return &definition;
            return &definition_3_11;
        }

        fn exec(object: *c.PyObject) callconv(.c) c_int {
            const state = State.of_module(object);

            assert(state.builtins.objects[0] == null);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            state.builtins.load() catch return -1;
            errors_add(state, object) catch return -1;
            enums_add(state, object) catch return -1;
            classes_add(state, object) catch return -1;
            unions_add(state, object) catch return -1;
            constants_add(state, object) catch return -1;
            coroutines_add(object) catch return -1;
            submodules_add(object) catch return -1;

            return 0;
        }

        fn coroutines_add(object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(registry.coroutine_count(module.functions) <= registry.name_count_max);

            if (comptime registry.coroutine_count(module.functions) == 0) return;

            const Namespace = module.functions.?;
            const wrap = try coroutine_wrap_of();
            defer c.Py_DecRef(wrap);

            inline for (Namespace.coroutines) |entry| {
                const member = @tagName(entry);
                const python_name = comptime signature_module.python_name_of(Namespace, member);
                const message = try deprecation_object(Namespace, member);
                defer c.Py_DecRef(message);

                const function = c.PyObject_GetAttrString(object, python_name) orelse {
                    return error.Raised;
                };

                defer c.Py_DecRef(function);

                const wrapper = c.PyObject_CallFunction(
                    wrap,
                    "OO",
                    function,
                    message,
                ) orelse return error.Raised;

                defer c.Py_DecRef(wrapper);

                if (c.PyModule_AddObjectRef(object, python_name, wrapper) != 0) {
                    return error.Raised;
                }
            }
        }

        fn deprecation_object(
            comptime Namespace: type,
            comptime member: []const u8,
        ) error{Raised}!*c.PyObject {
            comptime assert(@hasDecl(Namespace, member));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const deprecation = comptime class_module.deprecation_of(Namespace, member);
            const text = deprecation orelse return python.builtin_new("None") orelse error.Raised;

            assert(text.len > 0);

            return c.PyUnicode_FromStringAndSize(text.ptr, text.len) orelse error.Raised;
        }

        fn coroutine_wrap_of() error{Raised}!*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(coroutine_source.len > 0);

            const builtins = c.PyImport_ImportModule("builtins") orelse return error.Raised;
            defer c.Py_DecRef(builtins);

            const execute = c.PyObject_GetAttrString(builtins, "exec") orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(execute);

            const namespace = c.PyDict_New() orelse return error.Raised;
            defer c.Py_DecRef(namespace);

            const executed = c.PyObject_CallFunction(
                execute,
                "sO",
                coroutine_source.ptr,
                namespace,
            ) orelse return error.Raised;

            c.Py_DecRef(executed);

            const key = c.PyUnicode_FromStringAndSize("wrap", "wrap".len) orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(key);

            const wrap = c.PyObject_GetItem(namespace, key) orelse return error.Raised;

            assert(c.PyCallable_Check(wrap) == 1);

            return wrap;
        }

        fn submodules_add(object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(module.submodules.len <= registry.submodule_count_max);

            if (module.submodules.len == 0) return;

            const machinery = c.PyImport_ImportModule("importlib.machinery") orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(machinery);

            const specification_class = c.PyObject_GetAttrString(machinery, "ModuleSpec") orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(specification_class);

            const modules = c.PyImport_GetModuleDict() orelse return error.Raised;
            const none = python.builtin_new("None") orelse return error.Raised;
            defer c.Py_DecRef(none);

            inline for (module.submodules) |submodule| {
                const Submodule = BindingType(submodule);
                const leaf = comptime terminated(signature_module.module_leaf(submodule.name));
                const selected = Submodule.definition_select() orelse return error.Raised;

                const specification = c.PyObject_CallFunction(
                    specification_class,
                    "sO",
                    submodule.name.ptr,
                    none,
                ) orelse return error.Raised;

                defer c.Py_DecRef(specification);

                const created = c.PyModule_FromDefAndSpec2(
                    selected,
                    specification,
                    c.PYTHON_ABI_VERSION,
                ) orelse return error.Raised;

                defer c.Py_DecRef(created);

                if (c.PyModule_ExecDef(created, selected) != 0) return error.Raised;
                if (c.PyModule_AddObjectRef(object, leaf, created) != 0) return error.Raised;

                const registered = c.PyDict_SetItemString(modules, submodule.name, created);
                if (registered != 0) return error.Raised;
            }
        }

        fn errors_add(state: *State, object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(state.objects[0] == null);

            @setEvalBranchQuota(errors.len * errors.len * 256 + 10_000);

            const base_doc = "The base of every exception that " ++ name ++ " raises.";

            const base = c.PyErr_NewExceptionWithDoc(
                name ++ ".Error",
                base_doc,
                null,
                null,
            ) orelse {
                return error.Raised;
            };

            state.error_base_set(base);

            if (c.PyModule_AddObjectRef(object, "Error", base) != 0) return error.Raised;

            if (module.diagnostic) |Diagnostic| {
                inline for (@typeInfo(Diagnostic.Details).@"struct".field_names) |field| {
                    const none = state.builtins.get(.none);
                    if (c.PyObject_SetAttrString(base, field, none) != 0) return error.Raised;
                }
            }

            inline for (comptime registry.errors_ordered(module)) |index| {
                const error_name = errors[index];
                const doc = comptime exception.message_of(messages, error_name);
                const parent = comptime registry.base_of(module, error_name);
                const bases = try error_bases_of(state, base, parent);
                defer c.Py_DecRef(bases);

                const class = c.PyErr_NewExceptionWithDoc(
                    name ++ "." ++ error_name,
                    if (doc) |text| text.ptr else null,
                    bases,
                    null,
                ) orelse return error.Raised;

                state.error_class_set(index, class);

                if (c.PyModule_AddObjectRef(object, error_name, class) != 0) return error.Raised;
            }
        }

        fn enums_add(state: *State, object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(enums.len <= registry.enum_count_max);

            if (enums.len == 0) return;

            const base = try state.library_get(.enumeration);

            inline for (enums, 0..) |Enum, index| {
                const class = try enum_create(Enum, base);

                state.enum_set(index, class);

                const enum_name = comptime from_python_module.class_name(Enum);
                if (c.PyModule_AddObjectRef(object, enum_name, class) != 0) return error.Raised;
            }
        }

        fn enum_create(comptime Enum: type, base: *c.PyObject) error{Raised}!*c.PyObject {
            comptime assert(@typeInfo(Enum) == .@"enum");
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const enum_name = comptime from_python_module.class_name(Enum);
            const fields = @typeInfo(Enum).@"enum".field_names;
            const members = c.PyList_New(fields.len) orelse return error.Raised;
            defer c.Py_DecRef(members);

            inline for (fields, 0..) |field, position| {
                const number: c_longlong = @backingInt(@field(Enum, field));
                const member = comptime signature_module.python_name_of(Enum, field);
                const pair = c.Py_BuildValue("(sL)", member.ptr, number) orelse return error.Raised;
                const status = c.PyList_SetItem(members, position, pair);

                assert(status == 0);
            }

            const arguments = c.Py_BuildValue("(sO)", enum_name.ptr, members) orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(arguments);

            const keywords = c.Py_BuildValue(
                "{s:s,s:s}",
                "module",
                name.ptr,
                "qualname",
                enum_name.ptr,
            ) orelse return error.Raised;

            defer c.Py_DecRef(keywords);

            const class = c.PyObject_Call(base, arguments, keywords) orelse return error.Raised;
            errdefer c.Py_DecRef(class);

            if (@hasDecl(Enum, "doc")) {
                const size: c.Py_ssize_t = @intCast(Enum.doc.len);

                const text = c.PyUnicode_FromStringAndSize(Enum.doc.ptr, size) orelse {
                    return error.Raised;
                };

                defer c.Py_DecRef(text);

                if (c.PyObject_SetAttrString(class, "__doc__", text) != 0) return error.Raised;
            }

            return class;
        }

        fn error_bases_of(
            state: *const State,
            base: *c.PyObject,
            comptime parent: ?registry.ErrorBase,
        ) error{Raised}!*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(python.class_is(base));
            comptime assert(parent == null or parent.? != .module or parent.?.module < errors.len);

            const first = if (parent) |known| switch (known) {
                .builtin => base,
                .module => |index| state.error_class(index),
            } else base;

            const count: c.Py_ssize_t = if (parent) |known| switch (known) {
                .builtin => 2,
                .module => 1,
            } else 1;

            const result = c.PyTuple_New(count) orelse return error.Raised;
            const status = c.PyTuple_SetItem(result, 0, python.reference_new(first));

            assert(status == 0);

            if (parent) |known| {
                switch (known) {
                    .builtin => |kind| {
                        const extra = state.builtins.get(exception.builtin_of_error(kind));
                        const second = c.PyTuple_SetItem(result, 1, python.reference_new(extra));

                        assert(second == 0);
                    },
                    .module => {},
                }
            }

            return result;
        }

        fn classes_add(state: *State, object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(classes.len <= registry.class_count_max);

            inline for (classes, 0..) |Class, index| {
                const Definition = class_module.ClassType(Binding, Class);
                const bases = if (comptime base_index_of(Class)) |known|
                    try bases_single(state.class_get(known))
                else if (comptime native_module.native_of(Class)) |native|
                    try native_bases_of(native)
                else
                    null;

                defer c.Py_DecRef(bases);

                const metaclass = comptime if (native_module.available)
                    class_module.metaclass_of(Class)
                else
                    null;

                const class = if (metaclass) |source|
                    try class_from_metaclass(source, state, object, .{
                        .bases = bases,
                        .specification = &Definition.specification,
                    })
                else
                    c.PyType_FromModuleAndSpec(
                        object,
                        &Definition.specification,
                        bases,
                    ) orelse return error.Raised;

                state.class_set(index, class);

                const status = c.PyModule_AddObjectRef(object, Definition.python_name, class);
                if (status != 0) return error.Raised;
            }

            inline for (classes) |Class| {
                if (@hasDecl(Class, "constants")) try class_constants_add(Class, state);
            }
        }

        fn variant_restore(
            state: *const State,
            restoration: class_module.Restoration,
        ) ?*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(@intFromPtr(restoration.class) % @alignOf(c.PyObject_Header) == 0);
            comptime assert(unions.len <= registry.union_count_max);

            const class = restoration.class;

            inline for (unions, 0..) |Union, index| {
                const Variant = variant_module.VariantType(Binding, Union);
                const first = comptime variant_module.slot_first(unions, index);

                inline for (0..Variant.count) |tag_index| {
                    if (class == state.variant_get(first + 1 + tag_index)) {
                        return Variant.MemberType(tag_index).restore(state, restoration);
                    }
                }
            }

            return null;
        }

        fn unions_add(state: *State, object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(unions.len <= registry.union_count_max);

            inline for (unions, 0..) |Union, index| {
                const Variant = variant_module.VariantType(Binding, Union);
                const first = comptime variant_module.slot_first(unions, index);

                const base = c.PyType_FromModuleAndSpec(
                    object,
                    &Variant.base_specification,
                    null,
                ) orelse return error.Raised;

                state.variant_set(first, base);

                const status = c.PyModule_AddObjectRef(object, Variant.python_name, base);
                if (status != 0) return error.Raised;

                const bases = try bases_single(base);
                defer c.Py_DecRef(bases);

                inline for (0..Variant.count) |tag_index| {
                    const Member = Variant.MemberType(tag_index);

                    const member = c.PyType_FromModuleAndSpec(
                        object,
                        &Member.specification,
                        bases,
                    ) orelse return error.Raised;

                    state.variant_set(first + 1 + tag_index, member);

                    try member_describe(Member, .{ .base = base, .member = member });
                }
            }
        }

        fn member_describe(comptime Member: type, family: Family) error{Raised}!void {
            assert(python.class_is(family.base));
            assert(python.class_is(family.member));

            const size: c.Py_ssize_t = @intCast(Member.qualified.len);
            const qualified = c.PyUnicode_FromStringAndSize(Member.qualified.ptr, size) orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(qualified);

            if (c.PyObject_SetAttrString(family.member, "__qualname__", qualified) != 0) {
                return error.Raised;
            }

            const names = c.PyTuple_New(Member.field_names.len) orelse return error.Raised;
            defer c.Py_DecRef(names);

            inline for (Member.field_names, 0..) |field, position| {
                const text = c.PyUnicode_FromStringAndSize(field.ptr, field.len) orelse {
                    return error.Raised;
                };

                const placed = c.PyTuple_SetItem(names, position, text);

                assert(placed == 0);
            }

            if (c.PyObject_SetAttrString(family.member, "__match_args__", names) != 0) {
                return error.Raised;
            }

            if (c.PyObject_SetAttrString(family.base, Member.python_name, family.member) != 0) {
                return error.Raised;
            }
        }

        fn class_from_metaclass(
            comptime source: class_module.MetaclassSource,
            state: *const State,
            object: *c.PyObject,
            creation: Creation,
        ) error{Raised}!*c.PyObject {
            comptime assert(native_module.available);
            comptime assert(@tagName(source).len > 0);
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(creation.specification.slots[0].slot != 0);
            if (creation.bases) |bases| assert(python.has_flag(bases, c.Py_TPFLAGS_TUPLE_SUBCLASS));

            const metaclass = switch (source) {
                .native => |Meta| if (comptime kind_module.class_index(Meta, classes)) |index|
                    python.reference_new(state.class_get(index))
                else
                    unreachable,
                .python => |path| try metaclass_import(path),
            };

            defer c.Py_DecRef(metaclass);

            const class = c.PyType_FromMetaclass(
                metaclass,
                object,
                creation.specification,
                creation.bases,
            ) orelse return error.Raised;

            errdefer c.Py_DecRef(class);

            try metaclass_initialize(state, .{ .class = class, .metaclass = metaclass });

            assert(python.class_is(class));

            return class;
        }

        fn metaclass_import(
            comptime path: class_module.MetaclassSource.Path,
        ) error{Raised}!*c.PyObject {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            comptime assert(path.module.len > 0);

            const imported = c.PyImport_ImportModule(path.module) orelse return error.Raised;
            defer c.Py_DecRef(imported);

            const metaclass = c.PyObject_GetAttrString(imported, path.name) orelse {
                return error.Raised;
            };

            if (python.class_is(metaclass)) return metaclass;

            c.Py_DecRef(metaclass);

            python.exception_raise(.{
                .class_name = "TypeError",
                .message = "the metaclass " ++ path.module ++ "." ++ path.name ++
                    " is not a class",
            });

            return error.Raised;
        }

        fn metaclass_initialize(state: *const State, created: Created) error{Raised}!void {
            assert(python.class_is(created.metaclass));
            assert(python.class_is(created.class));

            const class = created.class;

            const label = c.PyObject_GetAttrString(class, "__name__") orelse return error.Raised;
            defer c.Py_DecRef(label);

            const bases = c.PyObject_GetAttrString(class, "__bases__") orelse return error.Raised;
            defer c.Py_DecRef(bases);

            const proxy = c.PyObject_GetAttrString(class, "__dict__") orelse return error.Raised;
            defer c.Py_DecRef(proxy);

            const namespace = c.PyObject_CallFunction(
                state.builtins.get(.dictionary),
                "O",
                proxy,
            ) orelse return error.Raised;

            defer c.Py_DecRef(namespace);

            const result = c.PyObject_CallMethod(
                created.metaclass,
                "__init__",
                "OOOO",
                class,
                label,
                bases,
                namespace,
            ) orelse return error.Raised;

            c.Py_DecRef(result);
        }

        fn native_bases_of(comptime native: native_module.Native) error{Raised}!*c.PyObject {
            comptime assert(native_module.available);
            comptime assert(!native_module.variable_size(native));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const base = python.builtin_new(native_module.python_name_of(native)) orelse {
                return error.Raised;
            };

            defer c.Py_DecRef(base);

            return bases_single(base);
        }

        fn bases_single(base: *c.PyObject) error{Raised}!*c.PyObject {
            assert(python.class_is(base));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const result = c.PyTuple_New(1) orelse return error.Raised;
            const status = c.PyTuple_SetItem(result, 0, python.reference_new(base));

            assert(status == 0);

            return result;
        }

        fn base_index_of(comptime Class: type) ?u32 {
            comptime assert(@typeInfo(Class) == .@"struct");
            comptime assert(classes.len <= registry.class_count_max);

            const Base = instance_module.InstanceType(Class).base orelse return null;
            return kind_module.class_index(Base, classes).?;
        }

        fn class_constants_add(comptime Class: type, state: *State) error{Raised}!void {
            comptime assert(@hasDecl(Class, "constants"));
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);

            const index = comptime kind_module.class_index(Class, classes).?;
            const class = state.class_get(index);

            inline for (@typeInfo(@TypeOf(Class.constants)).@"struct".field_names) |member| {
                const constant = @field(Class.constants, member);
                const Constant = Typed(constant);

                comptime signature_module.identifier_check(member);

                const item = try to_python_module.to_python(
                    Binding,
                    Constant,
                    state,
                    &@as(Constant, constant),
                );

                defer c.Py_DecRef(item);

                if (c.PyObject_SetAttrString(class, member, item) != 0) return error.Raised;
            }
        }

        fn constants_add(state: *State, object: *c.PyObject) error{Raised}!void {
            if (std.debug.runtime_safety) assert(c.PyErr_Occurred() == null);
            assert(state.objects[0] != null);

            const Namespace = module.constants orelse return;

            inline for (@typeInfo(Namespace).@"struct".decl_names) |member| {
                const constant = @field(Namespace, member);
                const Constant = Typed(constant);

                const item = try to_python_module.to_python(
                    Binding,
                    Constant,
                    state,
                    &@as(Constant, constant),
                );

                defer c.Py_DecRef(item);

                if (c.PyModule_AddObjectRef(object, terminated(member), item) != 0) {
                    return error.Raised;
                }
            }
        }

        fn Typed(comptime constant: anytype) type {
            comptime assert(@TypeOf(constant) != type);
            comptime assert(@typeInfo(@TypeOf(constant)) != .@"fn");

            const T = @TypeOf(constant);

            return switch (@typeInfo(T)) {
                .comptime_float => f64,
                .comptime_int => if (constant < 0) i64 else u64,
                .pointer => |pointer| pointer_typed(T, pointer),
                else => T,
            };
        }

        fn pointer_typed(comptime T: type, comptime pointer: std.lang.Type.Pointer) type {
            comptime assert(@typeInfo(T) == .pointer);
            comptime assert(pointer.child != void);

            if (pointer.size != .one) return T;
            if (@typeInfo(pointer.child) != .array) return T;
            return []const @typeInfo(pointer.child).array.child;
        }

        fn traverse(
            object: *c.PyObject,
            visitor: c.visitproc,
            argument: ?*anyopaque,
        ) callconv(.c) c_int {
            assert(visitor != null);
            assert(@intFromPtr(argument) % @alignOf(*anyopaque) == 0);
            assert(definition.m_traverse != null);

            const pointer = c.PyModule_GetState(object) orelse return 0;
            const state: *State = @ptrCast(@alignCast(pointer));
            const visit: python.Visit = .{ .argument = argument, .visitor = visitor };
            const builtins = python.visit_all(&state.builtins.objects, visit);
            if (builtins != 0) return builtins;
            return python.visit_all(&state.objects, visit);
        }

        fn clear(object: *c.PyObject) callconv(.c) c_int {
            assert(definition.m_size == @sizeOf(State));
            assert(definition.m_clear != null);

            const pointer = c.PyModule_GetState(object) orelse return 0;
            const state: *State = @ptrCast(@alignCast(pointer));

            state.clear();

            return 0;
        }

        fn free(pointer: ?*anyopaque) callconv(.c) void {
            assert(pointer != null);
            assert(definition.m_free != null);

            const object: *c.PyObject = @ptrCast(pointer.?);

            _ = clear(object);
        }
    };
}

fn pickled_any(comptime classes: []const type) bool {
    comptime assert(classes.len <= registry.class_count_max);

    for (classes) |Class| {
        if (class_module.picklable(Class)) return true;
    }

    return false;
}

test module_export {
    const Functions = struct {
        pub fn ping() error{Unreachable}!void {}
    };

    const Binding = BindingType(.{ .name = "probe", .functions = Functions });

    try std.testing.expectEqualStrings("probe", Binding.name);
    try std.testing.expectEqual(1, Binding.errors.len);
    try std.testing.expect(@sizeOf(Binding.State) > @sizeOf(state_module.Builtins));
}
