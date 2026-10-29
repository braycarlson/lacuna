const std = @import("std");

const root = @import("root");
const version_module = @import("version.zig");

const assert = std.debug.assert;

pub const ABI = union(enum) {
    free_threaded: Minor,
    pypy: Minor,
    stable,
    versioned: Minor,

    pub const Minor = struct {
        major: u8,
        minor: u8,
    };

    pub const Selection = struct {
        free_threaded_minor: ?u8,
        pypy_minor: ?u8,
        versioned_minor: ?u8,
    };

    pub fn select(selection: Selection) ABI {
        assert(selection.free_threaded_minor == null or selection.versioned_minor == null);

        const count = @as(u8, @intFromBool(selection.free_threaded_minor != null)) +
            @intFromBool(selection.pypy_minor != null) +
            @intFromBool(selection.versioned_minor != null);

        assert(count <= 1);

        if (selection.free_threaded_minor) |minor| {
            return .{ .free_threaded = .{ .major = 3, .minor = minor } };
        }

        if (selection.pypy_minor) |minor| return .{ .pypy = .{ .major = 3, .minor = minor } };
        if (selection.versioned_minor) |minor| {
            return .{ .versioned = .{ .major = 3, .minor = minor } };
        }

        return .stable;
    }
};

pub const PyObject = opaque {};
pub const PyInterpreterState = opaque {};
pub const PyThreadState = opaque {};

pub const PyGILState_STATE = enum(if (pypy) c_int else c_uint) {
    locked = 0,
    unlocked = 1,
};

pub const Py_hash_t = isize;
pub const Py_ssize_t = isize;

pub const pypy_unavailable = [_][]const u8{ "PyInterpreterState_Get", "PyObject_GC_UnTrack" };

pub const pypy_prefixed_3_12 = [_][]const u8{
    "PyGILState_Check",
    "PyUnicode_New",
    "_PyBytes_Resize",
};

pub const pypy_unprefixed_3_11 = [_][]const u8{"PyType_GetFlags"};
pub const pypy_unavailable_3_11 = [_][]const u8{"Py_CompileString"};
pub const headers_removed_3_15 = [_][]const u8{"PyWeakref_GetObject"};

fn symbol(comptime name: []const u8) []const u8 {
    comptime assert(std.mem.startsWith(u8, name, "Py") or std.mem.startsWith(u8, name, "_Py"));
    comptime assert(std.mem.findScalar(u8, name, 0) == null);

    if (!pypy) return name;

    const listed = if (abi.pypy.minor >= 12) &pypy_prefixed_3_12 else &pypy_unprefixed_3_11;
    const exception = for (listed) |entry| {
        if (std.mem.eql(u8, entry, name)) break true;
    } else false;

    const prefixed = if (abi.pypy.minor >= 12) exception else !exception;

    if (!prefixed) return name;
    if (name[0] == '_') return "_PyPy" ++ name[3..];
    return "PyPy" ++ name[2..];
}

pub const abi: ABI = if (@hasDecl(root, "lacuna_abi")) root.lacuna_abi else .stable;
pub const stable_minor: u8 = if (@hasDecl(root, "lacuna_stable_minor"))
    root.lacuna_stable_minor
else
    version_module.floor.minor;

comptime {
    assert(stable_minor >= version_module.floor.minor);
}

pub const free_threaded = abi == .free_threaded;
pub const pypy = abi == .pypy;
pub const pypy_linked_header = pypy and abi.pypy.minor < 12;
pub const versioned = abi == .versioned;

pub const abi_minor: ?ABI.Minor = switch (abi) {
    .free_threaded => |minor| minor,
    .pypy => |minor| minor,
    .stable => null,
    .versioned => |minor| minor,
};

pub const PyObject_Header = if (free_threaded) extern struct {
    ob_tid: usize,
    ob_flags: u16,
    ob_mutex: u8,
    ob_gc_bits: u8,
    ob_ref_local: u32,
    ob_ref_shared: Py_ssize_t,
    ob_type: ?*PyObject,
} else if (pypy_linked_header) extern struct {
    ob_refcnt: Py_ssize_t,
    ob_pypy_link: Py_ssize_t,
    ob_type: ?*PyObject,
} else extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: ?*PyObject,
};

const static_flags: u16 = if (!free_threaded)
    0
else if (abi.free_threaded.minor >= 14)
    api_free_threaded._Py_STATICALLY_ALLOCATED_FLAG
else
    0;

pub const object_head_static: PyObject_Header = if (free_threaded) .{
    .ob_tid = 0,
    .ob_flags = static_flags,
    .ob_mutex = 0,
    .ob_gc_bits = 0,
    .ob_ref_local = std.math.maxInt(u32),
    .ob_ref_shared = 0,
    .ob_type = null,
} else if (pypy_linked_header) .{
    .ob_refcnt = 1,
    .ob_pypy_link = 0,
    .ob_type = null,
} else if (pypy) .{
    .ob_refcnt = 1,
    .ob_type = null,
} else .{
    .ob_refcnt = if (@sizeOf(usize) == 8) 3 << 30 else 0x3fff_ffff,
    .ob_type = null,
};

pub const PyVarObject_Header = extern struct {
    ob_base: PyObject_Header,
    ob_size: Py_ssize_t,
};

pub const PyListObject = extern struct {
    ob_base: PyVarObject_Header,
    ob_item: ?[*]?*PyObject,
    allocated: Py_ssize_t,
};

pub const PyDictKeysObject = extern struct {
    dk_refcnt: Py_ssize_t,
    dk_log2_size: u8,
    dk_log2_index_bytes: u8,
    dk_kind: u8,
    dk_version: u32,
    dk_usable: Py_ssize_t,
    dk_nentries: Py_ssize_t,
    dk_indices: [0]u8,
};

pub const PyDictObject = extern struct {
    ob_base: PyObject_Header,
    ma_used: Py_ssize_t,
    ma_watcher_tag: u64,
    ma_keys: ?*PyDictKeysObject,
    ma_values: ?*anyopaque,
};

pub const PyDictKeyEntry = extern struct {
    me_hash: Py_hash_t,
    me_key: ?*PyObject,
    me_value: ?*PyObject,
};

pub const PyDictUnicodeEntry = extern struct {
    me_key: ?*PyObject,
    me_value: ?*PyObject,
};

pub const PyFloatObject = extern struct {
    ob_base: PyObject_Header,
    ob_fval: f64,
};

pub const PyLongValue = extern struct {
    lv_tag: usize,
    ob_digit: [1]u32,
};

pub const PyLongObject = extern struct {
    ob_base: PyObject_Header,
    long_value: PyLongValue,
};

pub const PyASCIIObject = extern struct {
    ob_base: PyObject_Header,
    length: Py_ssize_t,
    hash: Py_hash_t,
    state: u32,
};

pub const PyCompactUnicodeObject = extern struct {
    base: PyASCIIObject,
    utf8_length: Py_ssize_t,
    utf8: ?[*:0]u8,
};

pub const PyCriticalSection = extern struct {
    _cs_prev: usize,
    _cs_mutex: ?*anyopaque,
};

pub const PyModuleDef_Base = extern struct {
    ob_base: PyObject_Header,
    m_init: ?*const anyopaque,
    m_index: Py_ssize_t,
    m_copy: ?*PyObject,
};

pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: ?*const anyopaque,
    ml_flags: c_int,
    ml_doc: ?[*:0]const u8,
};

pub const PyModuleDef_Slot = extern struct {
    slot: c_int,
    value: ?*const anyopaque,
};

pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base,
    m_name: [*:0]const u8,
    m_doc: ?[*:0]const u8,
    m_size: Py_ssize_t,
    m_methods: ?[*]const PyMethodDef,
    m_slots: ?[*]const PyModuleDef_Slot,
    m_traverse: ?*const fn (*PyObject, visitproc, ?*anyopaque) callconv(.c) c_int,
    m_clear: ?*const fn (*PyObject) callconv(.c) c_int,
    m_free: ?*const fn (?*anyopaque) callconv(.c) void,
};

pub const PyType_Slot = extern struct {
    slot: c_int,
    pfunc: ?*const anyopaque,
};

pub const PyType_Spec = extern struct {
    name: [*:0]const u8,
    basicsize: c_int,
    itemsize: c_int,
    flags: c_uint,
    slots: [*]const PyType_Slot,
};

pub const PyGetSetDef = extern struct {
    name: ?[*:0]const u8,
    get: ?*const fn (*PyObject, ?*anyopaque) callconv(.c) ?*PyObject,
    set: ?*const fn (*PyObject, ?*PyObject, ?*anyopaque) callconv(.c) c_int,
    doc: ?[*:0]const u8,
    closure: ?*anyopaque,
};

pub const PyMemberDef = extern struct {
    name: ?[*:0]const u8,
    type: c_int,
    offset: Py_ssize_t,
    flags: c_int,
    doc: ?[*:0]const u8,
};

pub const Py_buffer = if (pypy) extern struct {
    buf: ?*anyopaque,
    obj: ?*PyObject,
    len: Py_ssize_t,
    itemsize: Py_ssize_t,
    readonly: c_int,
    ndim: c_int,
    format: ?[*:0]u8,
    shape: ?[*]Py_ssize_t,
    strides: ?[*]Py_ssize_t,
    suboffsets: ?[*]Py_ssize_t,
    internal: ?*anyopaque,
    flags: c_int,
    _strides: [PyBUF_MAX_NDIM]Py_ssize_t,
    _shape: [PyBUF_MAX_NDIM]Py_ssize_t,
} else extern struct {
    buf: ?*anyopaque,
    obj: ?*PyObject,
    len: Py_ssize_t,
    itemsize: Py_ssize_t,
    readonly: c_int,
    ndim: c_int,
    format: ?[*:0]u8,
    shape: ?[*]Py_ssize_t,
    strides: ?[*]Py_ssize_t,
    suboffsets: ?[*]Py_ssize_t,
    internal: ?*anyopaque,
};

pub const PyBUF_MAX_NDIM = 64;

pub const exports = [_][]const u8{
    "PyBool_FromLong",
    "PyBuffer_Release",
    "PyByteArray_AsString",
    "PyByteArray_FromStringAndSize",
    "PyByteArray_Resize",
    "PyByteArray_Size",
    "PyBytes_AsString",
    "PyBytes_FromStringAndSize",
    "PyBytes_Size",
    "PyCallable_Check",
    "PyCapsule_GetPointer",
    "PyCapsule_New",
    "PyComplex_FromDoubles",
    "PyComplex_ImagAsDouble",
    "PyComplex_RealAsDouble",
    "PyDict_Contains",
    "PyDict_DelItem",
    "PyDict_GetItemWithError",
    "PyDict_Items",
    "PyDict_Keys",
    "PyDict_New",
    "PyDict_Next",
    "PyDict_SetItem",
    "PyDict_SetItemString",
    "PyDict_Size",
    "PyErr_CheckSignals",
    "PyErr_Clear",
    "PyErr_ExceptionMatches",
    "PyErr_Fetch",
    "PyErr_Format",
    "PyErr_GivenExceptionMatches",
    "PyErr_NewExceptionWithDoc",
    "PyErr_NormalizeException",
    "PyErr_Occurred",
    "PyErr_Print",
    "PyErr_Restore",
    "PyErr_SetNone",
    "PyErr_SetObject",
    "PyErr_SetString",
    "PyErr_WarnEx",
    "PyErr_WriteUnraisable",
    "PyEval_EvalCode",
    "PyEval_RestoreThread",
    "PyEval_SaveThread",
    "PyException_GetTraceback",
    "PyException_SetCause",
    "PyException_SetContext",
    "PyException_SetTraceback",
    "PyFloat_AsDouble",
    "PyFloat_FromDouble",
    "PyFrozenSet_New",
    "PyGILState_Ensure",
    "PyGILState_GetThisThreadState",
    "PyGILState_Release",
    "PyImport_GetModuleDict",
    "PyImport_ImportModule",
    "PyIndex_Check",
    "PyInterpreterState_Get",
    "PyInterpreterState_GetID",
    "PyIter_Next",
    "PyList_Append",
    "PyList_GetItem",
    "PyList_New",
    "PyList_SetItem",
    "PyList_Size",
    "PyLong_AsDouble",
    "PyLong_AsLongLong",
    "PyLong_AsLongLongAndOverflow",
    "PyLong_AsUnsignedLongLong",
    "PyLong_FromLongLong",
    "PyLong_FromUnsignedLongLong",
    "PyMapping_Items",
    "PyMem_Free",
    "PyMem_Malloc",
    "PyModuleDef_Init",
    "PyModule_AddObjectRef",
    "PyModule_ExecDef",
    "PyModule_FromDefAndSpec2",
    "PyModule_GetDef",
    "PyModule_GetState",
    "PyNumber_And",
    "PyNumber_AsSsize_t",
    "PyNumber_Index",
    "PyNumber_Lshift",
    "PyNumber_Or",
    "PyNumber_Rshift",
    "PyOS_FSPath",
    "PyObject_Call",
    "PyObject_CallFunction",
    "PyObject_CallMethod",
    "PyObject_CallObject",
    "PyObject_ClearWeakRefs",
    "PyObject_DelItem",
    "PyObject_GC_UnTrack",
    "PyObject_GenericGetAttr",
    "PyObject_GenericGetDict",
    "PyObject_GenericSetAttr",
    "PyObject_GenericSetDict",
    "PyObject_GetAttrString",
    "PyObject_GetBuffer",
    "PyObject_GetItem",
    "PyObject_GetIter",
    "PyObject_Hash",
    "PyObject_IsInstance",
    "PyObject_IsTrue",
    "PyObject_Repr",
    "PyObject_RichCompareBool",
    "PyObject_SetAttrString",
    "PyObject_SetItem",
    "PyObject_Size",
    "PyObject_Str",
    "PyObject_Type",
    "PySequence_Check",
    "PySequence_Tuple",
    "PySet_Add",
    "PySet_Contains",
    "PySet_New",
    "PySet_Size",
    "PySlice_AdjustIndices",
    "PySlice_New",
    "PySlice_Unpack",
    "PyThreadState_Clear",
    "PyThreadState_Delete",
    "PyThreadState_GetDict",
    "PyThreadState_New",
    "PyTuple_GetItem",
    "PyTuple_New",
    "PyTuple_SetItem",
    "PyTuple_Size",
    "PyType_FromModuleAndSpec",
    "PyType_GetFlags",
    "PyType_GetModule",
    "PyType_GetSlot",
    "PyType_IsSubtype",
    "PyUnicode_AsUTF8AndSize",
    "PyUnicode_DecodeFSDefaultAndSize",
    "PyUnicode_DecodeUTF8",
    "PyUnicode_EncodeFSDefault",
    "PyUnicode_FromStringAndSize",
    "PyWeakref_GetObject",
    "PyWeakref_NewRef",
    "Py_BuildValue",
    "Py_CompileString",
    "Py_DecRef",
    "Py_GenericAlias",
    "Py_GetVersion",
    "Py_IncRef",
    "Py_IsInitialized",
};

pub const visitproc = ?*const fn (*PyObject, ?*anyopaque) callconv(.c) c_int;
pub const METH_CLASS = 0x0010;
pub const METH_COEXIST = 0x0040;
pub const PYTHON_ABI_VERSION = 3;
pub const METH_FASTCALL = 0x0080;
pub const METH_KEYWORDS = 0x0002;
pub const METH_METHOD = 0x0200;
pub const METH_NOARGS = 0x0004;
pub const METH_O = 0x0008;
pub const METH_STATIC = 0x0020;
pub const METH_VARARGS = 0x0001;
pub const PyBUF_C_CONTIGUOUS = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_FORMAT = 0x0004;
pub const PyBUF_INDIRECT = 0x0100 | PyBUF_STRIDES;
pub const PyBUF_ND = 0x0008;
pub const PyBUF_SIMPLE = 0;
pub const PyBUF_STRIDES = 0x0010 | PyBUF_ND;
pub const PyBUF_WRITABLE = 0x0001;
pub const Py_EQ = 2;
pub const Py_eval_input = 258;
pub const Py_file_input = 257;
pub const Py_GE = 5;
pub const Py_GT = 4;
pub const Py_LE = 1;
pub const Py_LT = 0;
pub const Py_NE = 3;
pub const Py_TPFLAGS_BASETYPE = 1 << 10;
pub const Py_TPFLAGS_BASE_EXC_SUBCLASS = 1 << 30;
pub const Py_TPFLAGS_BYTES_SUBCLASS = 1 << 27;
pub const Py_TPFLAGS_DEFAULT = 0;
pub const Py_TPFLAGS_DICT_SUBCLASS = 1 << 29;
pub const Py_TPFLAGS_DISALLOW_INSTANTIATION = 1 << 7;
pub const Py_TPFLAGS_HAVE_GC = 1 << 14;
pub const Py_TPFLAGS_HEAPTYPE = 1 << 9;
pub const Py_TPFLAGS_IMMUTABLETYPE = 1 << 8;
pub const Py_TPFLAGS_LIST_SUBCLASS = 1 << 25;
pub const Py_TPFLAGS_LONG_SUBCLASS = 1 << 24;
pub const Py_TPFLAGS_TUPLE_SUBCLASS = 1 << 26;
pub const Py_TPFLAGS_TYPE_SUBCLASS = 1 << 31;
pub const Py_TPFLAGS_UNICODE_SUBCLASS = 1 << 28;
pub const Py_am_aiter = 78;
pub const Py_am_anext = 79;
pub const Py_am_await = 77;
pub const Py_bf_getbuffer = 1;
pub const Py_bf_releasebuffer = 2;
pub const Py_mod_exec = 2;
pub const Py_mp_ass_subscript = 3;
pub const Py_mp_length = 4;
pub const Py_mp_subscript = 5;
pub const Py_nb_absolute = 6;
pub const Py_nb_add = 7;
pub const Py_nb_and = 8;
pub const Py_nb_bool = 9;
pub const Py_nb_divmod = 10;
pub const Py_nb_float = 11;
pub const Py_nb_floor_divide = 12;
pub const Py_nb_index = 13;
pub const Py_nb_inplace_add = 14;
pub const Py_nb_inplace_and = 15;
pub const Py_nb_inplace_floor_divide = 16;
pub const Py_nb_inplace_lshift = 17;
pub const Py_nb_inplace_matrix_multiply = 76;
pub const Py_nb_inplace_multiply = 18;
pub const Py_nb_inplace_or = 19;
pub const Py_nb_inplace_power = 20;
pub const Py_nb_inplace_remainder = 21;
pub const Py_nb_inplace_rshift = 22;
pub const Py_nb_inplace_subtract = 23;
pub const Py_nb_inplace_true_divide = 24;
pub const Py_nb_inplace_xor = 25;
pub const Py_nb_int = 26;
pub const Py_nb_invert = 27;
pub const Py_nb_lshift = 28;
pub const Py_nb_matrix_multiply = 75;
pub const Py_nb_multiply = 29;
pub const Py_nb_negative = 30;
pub const Py_nb_or = 31;
pub const Py_nb_positive = 32;
pub const Py_nb_power = 33;
pub const Py_nb_remainder = 34;
pub const Py_nb_rshift = 35;
pub const Py_nb_subtract = 36;
pub const Py_nb_true_divide = 37;
pub const Py_nb_xor = 38;
pub const Py_sq_ass_item = 39;
pub const Py_sq_contains = 41;
pub const Py_sq_item = 44;
pub const Py_sq_length = 45;
pub const Py_tp_alloc = 47;
pub const Py_tp_base = 48;
pub const Py_tp_call = 50;
pub const Py_tp_clear = 51;
pub const Py_tp_dealloc = 52;
pub const Py_tp_descr_get = 54;
pub const Py_tp_descr_set = 55;
pub const Py_tp_doc = 56;
pub const Py_tp_finalize = 80;
pub const Py_tp_free = 74;
pub const Py_tp_getattro = 58;
pub const Py_tp_getset = 73;
pub const Py_tp_hash = 59;
pub const Py_tp_init = 60;
pub const Py_tp_iter = 62;
pub const Py_tp_iternext = 63;
pub const Py_tp_members = 72;
pub const Py_tp_methods = 64;
pub const Py_tp_new = 65;
pub const Py_tp_repr = 66;
pub const Py_tp_richcompare = 67;
pub const Py_tp_setattro = 69;
pub const Py_tp_str = 70;
pub const Py_tp_traverse = 71;

pub const slots_renumbered_3_15 = struct {
    pub const version_hex = 0x030f0000;
    pub const Py_bf_getbuffer = 88;
    pub const Py_bf_releasebuffer = 89;
    pub const Py_mod_exec = 85;
    pub const Py_mod_gil = 87;
    pub const Py_mod_multiple_interpreters = 86;
    pub const Py_mp_ass_subscript = 90;
    pub const Py_mp_length = 91;
};

pub const api_pattern = struct {
    pub const Py_TPFLAGS_MAPPING = 1 << 6;
    pub const Py_TPFLAGS_SEQUENCE = 1 << 5;
};

pub const api_free_threaded = struct {
    pub const Py_mod_gil = 4;
    pub const Py_MOD_GIL_NOT_USED = 1;
    pub const _Py_STATICALLY_ALLOCATED_FLAG = 1 << 2;
};

pub const exports_free_threaded = [_][]const u8{
    "PyCriticalSection_Begin",
    "PyCriticalSection_End",
};

pub const api_versioned = struct {
    pub const DICT_KEYS_GENERAL = 0;
    pub const DICT_KEYS_SPLIT = 2;
    pub const DICT_KEYS_UNICODE = 1;
    pub const PyLong_SHIFT = 30;
    pub const PyUnicode_1BYTE_KIND = 1;
    pub const PyUnicode_2BYTE_KIND = 2;
    pub const PyUnicode_4BYTE_KIND = 4;
    pub const _PyLong_NON_SIZE_BITS = 3;
    pub const _PyLong_SIGN_MASK = 3;
};

pub const unicode_state_ascii: u32 = 1 << 6;
pub const unicode_state_compact: u32 = 1 << 5;
pub const unicode_state_kind_shift: u5 = 2;
pub const unicode_state_kind_mask: u32 = 0b111 << unicode_state_kind_shift;

pub const exports_versioned = [_][]const u8{
    "PyUnicode_New",
    "_PyBytes_Resize",
    "_PyDict_NewPresized",
    "_PyDict_SetItem_KnownHash",
};

pub const exports_3_12 = [_][]const u8{
    "PyErr_GetRaisedException",
    "PyErr_SetRaisedException",
    "PyObject_GetTypeData",
    "PyType_FromMetaclass",
};

pub const api_3_12_linked = if (abi_minor) |minor| minor.minor >= 12 else stable_minor >= 12;

pub const exports_3_13 = [_][]const u8{"PyWeakref_GetRef"};
pub const exports_pypy = [_][]const u8{"PyGILState_Check"};

pub const api_3_13_linked = if (pypy)
    false
else if (abi_minor) |minor|
    minor.minor >= 13
else
    false;

pub const api_3_12 = struct {
    pub const version_hex = 0x030c0000;
    pub const Py_READONLY = 1;
    pub const Py_T_PYSSIZET = 19;
    pub const Py_mod_multiple_interpreters = 3;
    pub const Py_MOD_PER_INTERPRETER_GIL_SUPPORTED = 2;
};

comptime {
    const header_words: u32 = if (free_threaded) 4 else if (pypy_linked_header) 3 else 2;

    assert(@sizeOf(PyObject_Header) == header_words * @sizeOf(usize));
    assert(@sizeOf(PyCriticalSection) == 2 * @sizeOf(usize));
    assert(@sizeOf(PyCompactUnicodeObject) == @sizeOf(PyASCIIObject) + 2 * @sizeOf(usize));
    assert(@offsetOf(PyListObject, "ob_item") == @sizeOf(PyObject_Header) + @sizeOf(usize));

    if (!free_threaded) {
        if (!pypy) assert(@sizeOf(PyASCIIObject) == if (@sizeOf(usize) == 8) 40 else 20);
    }

    assert(@sizeOf(Py_ssize_t) == @sizeOf(usize));
    if (!pypy) assert(@sizeOf(Py_buffer) == if (@sizeOf(usize) == 8) 80 else 44);
    assert(PyBUF_C_CONTIGUOUS == 0x38);
}

pub const PyBool_FromLong = @extern(
    *const fn (value: c_long) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyBool_FromLong") },
);

pub const PyBuffer_Release = @extern(
    *const fn (view: *Py_buffer) callconv(.c) void,
    .{ .name = symbol("PyBuffer_Release") },
);

pub const PyByteArray_AsString = @extern(
    *const fn (array: *PyObject) callconv(.c) ?[*]u8,
    .{ .name = symbol("PyByteArray_AsString") },
);

pub const PyByteArray_FromStringAndSize = @extern(
    *const fn (bytes: ?[*]const u8, size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyByteArray_FromStringAndSize") },
);

pub const PyByteArray_Resize = @extern(
    *const fn (array: *PyObject, size: Py_ssize_t) callconv(.c) c_int,
    .{ .name = symbol("PyByteArray_Resize") },
);

pub const PyByteArray_Size = @extern(
    *const fn (array: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyByteArray_Size") },
);

pub const PyBytes_AsString = @extern(
    *const fn (bytes: *PyObject) callconv(.c) ?[*]u8,
    .{ .name = symbol("PyBytes_AsString") },
);

pub const PyBytes_FromStringAndSize = @extern(
    *const fn (bytes: ?[*]const u8, size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyBytes_FromStringAndSize") },
);

pub const PyBytes_Size = @extern(
    *const fn (bytes: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyBytes_Size") },
);

pub const PyCallable_Check = @extern(
    *const fn (object: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyCallable_Check") },
);

pub const PyCapsule_GetPointer = @extern(
    *const fn (capsule: *PyObject, name: ?[*:0]const u8) callconv(.c) ?*anyopaque,
    .{ .name = symbol("PyCapsule_GetPointer") },
);

pub const PyCapsule_New = @extern(
    *const fn (
        pointer: *anyopaque,
        name: ?[*:0]const u8,
        destructor: ?*const fn (*PyObject) callconv(.c) void,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyCapsule_New") },
);

pub const PyComplex_FromDoubles = @extern(
    *const fn (real: f64, imaginary: f64) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyComplex_FromDoubles") },
);

pub const PyComplex_ImagAsDouble = @extern(
    *const fn (object: *PyObject) callconv(.c) f64,
    .{ .name = symbol("PyComplex_ImagAsDouble") },
);

pub const PyComplex_RealAsDouble = @extern(
    *const fn (object: *PyObject) callconv(.c) f64,
    .{ .name = symbol("PyComplex_RealAsDouble") },
);

pub const PyCriticalSection_Begin = @extern(
    *const fn (section: *PyCriticalSection, object: *PyObject) callconv(.c) void,
    .{ .name = symbol("PyCriticalSection_Begin") },
);

pub const PyCriticalSection_End = @extern(
    *const fn (section: *PyCriticalSection) callconv(.c) void,
    .{ .name = symbol("PyCriticalSection_End") },
);

pub const PyDict_Contains = @extern(
    *const fn (dictionary: *PyObject, key: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyDict_Contains") },
);

pub const PyDict_DelItem = @extern(
    *const fn (dictionary: *PyObject, key: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyDict_DelItem") },
);

pub const PyDict_GetItemWithError = @extern(
    *const fn (dictionary: *PyObject, key: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyDict_GetItemWithError") },
);

pub const PyDict_Items = @extern(
    *const fn (dictionary: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyDict_Items") },
);

pub const PyDict_Keys = @extern(
    *const fn (dictionary: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyDict_Keys") },
);

pub const PyDict_New = @extern(
    *const fn () callconv(.c) ?*PyObject,
    .{ .name = symbol("PyDict_New") },
);

pub const PyDict_Next = @extern(
    *const fn (
        dictionary: *PyObject,
        position: *Py_ssize_t,
        key: *?*PyObject,
        value: *?*PyObject,
    ) callconv(.c) c_int,
    .{ .name = symbol("PyDict_Next") },
);

pub const PyDict_SetItem = @extern(
    *const fn (dictionary: *PyObject, key: *PyObject, value: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyDict_SetItem") },
);

pub const PyDict_SetItemString = @extern(
    *const fn (dictionary: *PyObject, key: [*:0]const u8, value: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyDict_SetItemString") },
);

pub const PyDict_Size = @extern(
    *const fn (dictionary: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyDict_Size") },
);

pub const PyErr_CheckSignals = @extern(
    *const fn () callconv(.c) c_int,
    .{ .name = symbol("PyErr_CheckSignals") },
);

pub const PyErr_Clear = @extern(
    *const fn () callconv(.c) void,
    .{ .name = symbol("PyErr_Clear") },
);

pub const PyErr_ExceptionMatches = @extern(
    *const fn (exception: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyErr_ExceptionMatches") },
);

pub const PyErr_Fetch = @extern(
    *const fn (kind: *?*PyObject, instance: *?*PyObject, traceback: *?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_Fetch") },
);

pub const PyErr_Format = @extern(
    *const fn (exception: *PyObject, format: [*:0]const u8, ...) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyErr_Format") },
);

pub const PyErr_GivenExceptionMatches = @extern(
    *const fn (given: *PyObject, exception: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyErr_GivenExceptionMatches") },
);

pub const PyErr_NewExceptionWithDoc = @extern(
    *const fn (
        name: [*:0]const u8,
        doc: ?[*:0]const u8,
        base: ?*PyObject,
        dictionary: ?*PyObject,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyErr_NewExceptionWithDoc") },
);

pub const PyErr_NormalizeException = @extern(
    *const fn (kind: *?*PyObject, instance: *?*PyObject, traceback: *?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_NormalizeException") },
);

pub const PyErr_Occurred = @extern(
    *const fn () callconv(.c) ?*PyObject,
    .{ .name = symbol("PyErr_Occurred") },
);

pub const PyErr_GetRaisedException = @extern(
    *const fn () callconv(.c) ?*PyObject,
    .{ .name = symbol("PyErr_GetRaisedException") },
);

pub const PyErr_Print = @extern(
    *const fn () callconv(.c) void,
    .{ .name = symbol("PyErr_Print") },
);

pub const PyErr_Restore = @extern(
    *const fn (kind: ?*PyObject, instance: ?*PyObject, traceback: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_Restore") },
);

pub const PyErr_SetNone = @extern(
    *const fn (exception: *PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_SetNone") },
);

pub const PyErr_SetObject = @extern(
    *const fn (exception: *PyObject, value: *PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_SetObject") },
);

pub const PyErr_SetRaisedException = @extern(
    *const fn (raised: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_SetRaisedException") },
);

pub const PyErr_SetString = @extern(
    *const fn (exception: *PyObject, message: [*:0]const u8) callconv(.c) void,
    .{ .name = symbol("PyErr_SetString") },
);

pub const PyErr_WarnEx = @extern(
    *const fn (
        category: *PyObject,
        message: [*:0]const u8,
        stack_level: if (pypy) (if (abi.pypy.minor < 12) c_int else Py_ssize_t) else Py_ssize_t,
    ) callconv(.c) c_int,
    .{ .name = symbol("PyErr_WarnEx") },
);

pub const PyErr_WriteUnraisable = @extern(
    *const fn (context: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyErr_WriteUnraisable") },
);

pub const PyEval_EvalCode = @extern(
    *const fn (code: *PyObject, globals: *PyObject, locals: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyEval_EvalCode") },
);

pub const PyEval_RestoreThread = @extern(
    *const fn (state: *PyThreadState) callconv(.c) void,
    .{ .name = symbol("PyEval_RestoreThread") },
);

pub const PyEval_SaveThread = @extern(
    *const fn () callconv(.c) ?*PyThreadState,
    .{ .name = symbol("PyEval_SaveThread") },
);

pub const PyException_GetTraceback = @extern(
    *const fn (exception: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyException_GetTraceback") },
);

pub const PyException_SetCause = @extern(
    *const fn (exception: *PyObject, cause: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyException_SetCause") },
);

pub const PyException_SetContext = @extern(
    *const fn (exception: *PyObject, context: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("PyException_SetContext") },
);

pub const PyException_SetTraceback = @extern(
    *const fn (exception: *PyObject, traceback: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyException_SetTraceback") },
);

pub const PyFloat_AsDouble = @extern(
    *const fn (object: *PyObject) callconv(.c) f64,
    .{ .name = symbol("PyFloat_AsDouble") },
);

pub const PyFloat_FromDouble = @extern(
    *const fn (value: f64) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyFloat_FromDouble") },
);

pub const PyFrozenSet_New = @extern(
    *const fn (iterable: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyFrozenSet_New") },
);

pub const PyGILState_Check = @extern(
    *const fn () callconv(.c) c_int,
    .{ .name = symbol("PyGILState_Check") },
);

pub const PyGILState_Ensure = @extern(
    *const fn () callconv(.c) PyGILState_STATE,
    .{ .name = symbol("PyGILState_Ensure") },
);

pub const PyGILState_GetThisThreadState = @extern(
    *const fn () callconv(.c) ?*PyThreadState,
    .{ .name = symbol("PyGILState_GetThisThreadState") },
);

pub const PyGILState_Release = @extern(
    *const fn (state: PyGILState_STATE) callconv(.c) void,
    .{ .name = symbol("PyGILState_Release") },
);

pub const PyImport_GetModuleDict = @extern(
    *const fn () callconv(.c) ?*PyObject,
    .{ .name = symbol("PyImport_GetModuleDict") },
);

pub const PyImport_ImportModule = @extern(
    *const fn (name: [*:0]const u8) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyImport_ImportModule") },
);

pub const PyIndex_Check = @extern(
    *const fn (object: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyIndex_Check") },
);

pub const PyInterpreterState_Get = @extern(
    *const fn () callconv(.c) *PyInterpreterState,
    .{ .name = symbol("PyInterpreterState_Get") },
);

pub const PyInterpreterState_GetID = @extern(
    *const fn (state: *PyInterpreterState) callconv(.c) i64,
    .{ .name = symbol("PyInterpreterState_GetID") },
);

pub const PyIter_Next = @extern(
    *const fn (iterator: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyIter_Next") },
);

pub const PyList_Append = @extern(
    *const fn (list: *PyObject, item: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyList_Append") },
);

pub const PyList_GetItem = @extern(
    *const fn (list: *PyObject, index: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyList_GetItem") },
);

pub const PyList_New = @extern(
    *const fn (size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyList_New") },
);

pub const PyList_SetItem = @extern(
    *const fn (list: *PyObject, index: Py_ssize_t, item: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyList_SetItem") },
);

pub const PyList_Size = @extern(
    *const fn (list: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyList_Size") },
);

pub const PyLong_AsDouble = @extern(
    *const fn (object: *PyObject) callconv(.c) f64,
    .{ .name = symbol("PyLong_AsDouble") },
);

pub const PyLong_AsLongLong = @extern(
    *const fn (object: *PyObject) callconv(.c) c_longlong,
    .{ .name = symbol("PyLong_AsLongLong") },
);

pub const PyLong_AsLongLongAndOverflow = @extern(
    *const fn (object: *PyObject, overflow: *c_int) callconv(.c) c_longlong,
    .{ .name = symbol("PyLong_AsLongLongAndOverflow") },
);

pub const PyLong_AsUnsignedLongLong = @extern(
    *const fn (object: *PyObject) callconv(.c) c_ulonglong,
    .{ .name = symbol("PyLong_AsUnsignedLongLong") },
);

pub const PyLong_FromLongLong = @extern(
    *const fn (value: c_longlong) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyLong_FromLongLong") },
);

pub const PyLong_FromUnsignedLongLong = @extern(
    *const fn (value: c_ulonglong) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyLong_FromUnsignedLongLong") },
);

pub const PyMapping_Items = @extern(
    *const fn (mapping: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyMapping_Items") },
);

pub const PyMem_Free = @extern(
    *const fn (pointer: ?*anyopaque) callconv(.c) void,
    .{ .name = symbol("PyMem_Free") },
);

pub const PyMem_Malloc = @extern(
    *const fn (size: usize) callconv(.c) ?*anyopaque,
    .{ .name = symbol("PyMem_Malloc") },
);

pub const PyModuleDef_Init = @extern(
    *const fn (definition: *PyModuleDef) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyModuleDef_Init") },
);

pub const PyModule_AddObjectRef = @extern(
    *const fn (module: *PyObject, name: [*:0]const u8, value: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyModule_AddObjectRef") },
);

pub const PyModule_ExecDef = @extern(
    *const fn (module: *PyObject, definition: *PyModuleDef) callconv(.c) c_int,
    .{ .name = symbol("PyModule_ExecDef") },
);

pub const PyModule_FromDefAndSpec2 = @extern(
    *const fn (
        definition: *PyModuleDef,
        specification: *PyObject,
        version: c_int,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyModule_FromDefAndSpec2") },
);

pub const PyModule_GetDef = @extern(
    *const fn (module: *PyObject) callconv(.c) ?*PyModuleDef,
    .{ .name = symbol("PyModule_GetDef") },
);

pub const PyModule_GetState = @extern(
    *const fn (module: *PyObject) callconv(.c) ?*anyopaque,
    .{ .name = symbol("PyModule_GetState") },
);

pub const PyNumber_And = @extern(
    *const fn (left: *PyObject, right: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyNumber_And") },
);

pub const PyNumber_AsSsize_t = @extern(
    *const fn (object: *PyObject, exception: ?*PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyNumber_AsSsize_t") },
);

pub const PyNumber_Index = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyNumber_Index") },
);

pub const PyNumber_Lshift = @extern(
    *const fn (left: *PyObject, right: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyNumber_Lshift") },
);

pub const PyNumber_Or = @extern(
    *const fn (left: *PyObject, right: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyNumber_Or") },
);

pub const PyNumber_Rshift = @extern(
    *const fn (left: *PyObject, right: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyNumber_Rshift") },
);

pub const PyOS_FSPath = @extern(
    *const fn (path: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyOS_FSPath") },
);

pub const PyObject_Call = @extern(
    *const fn (
        callable: *PyObject,
        arguments: *PyObject,
        keywords: ?*PyObject,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_Call") },
);

pub const PyObject_CallFunction = @extern(
    *const fn (callable: *PyObject, format: ?[*:0]const u8, ...) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_CallFunction") },
);

pub const PyObject_CallMethod = @extern(
    *const fn (
        object: *PyObject,
        name: [*:0]const u8,
        format: ?[*:0]const u8,
        ...,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_CallMethod") },
);

pub const PyObject_CallObject = @extern(
    *const fn (callable: *PyObject, arguments: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_CallObject") },
);

pub const PyObject_ClearWeakRefs = @extern(
    *const fn (object: *PyObject) callconv(.c) void,
    .{ .name = symbol("PyObject_ClearWeakRefs") },
);

pub const PyObject_GC_UnTrack = @extern(
    *const fn (object: *anyopaque) callconv(.c) void,
    .{ .name = symbol("PyObject_GC_UnTrack") },
);

pub const PyObject_GenericGetDict = @extern(
    *const fn (object: *PyObject, context: ?*anyopaque) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_GenericGetDict") },
);

pub const PyObject_GenericSetDict = @extern(
    *const fn (object: *PyObject, value: ?*PyObject, context: ?*anyopaque) callconv(.c) c_int,
    .{ .name = symbol("PyObject_GenericSetDict") },
);

pub const PyObject_GenericGetAttr = @extern(
    *const fn (object: *PyObject, name: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_GenericGetAttr") },
);

pub const PyObject_GenericSetAttr = @extern(
    *const fn (object: *PyObject, name: *PyObject, value: ?*PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_GenericSetAttr") },
);

pub const PyObject_GetAttrString = @extern(
    *const fn (object: *PyObject, name: [*:0]const u8) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_GetAttrString") },
);

pub const PyObject_GetBuffer = @extern(
    *const fn (object: *PyObject, view: *Py_buffer, flags: c_int) callconv(.c) c_int,
    .{ .name = symbol("PyObject_GetBuffer") },
);

pub const PyObject_DelItem = @extern(
    *const fn (object: *PyObject, key: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_DelItem") },
);

pub const PyObject_GetItem = @extern(
    *const fn (object: *PyObject, key: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_GetItem") },
);

pub const PyObject_GetTypeData = @extern(
    *const fn (object: *PyObject, class: *PyObject) callconv(.c) ?*anyopaque,
    .{ .name = symbol("PyObject_GetTypeData") },
);

pub const PyObject_GetIter = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_GetIter") },
);

pub const PyObject_Hash = @extern(
    *const fn (object: *PyObject) callconv(.c) Py_hash_t,
    .{ .name = symbol("PyObject_Hash") },
);

pub const PyObject_IsInstance = @extern(
    *const fn (object: *PyObject, class: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_IsInstance") },
);

pub const PyObject_IsTrue = @extern(
    *const fn (object: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_IsTrue") },
);

pub const PyObject_Size = @extern(
    *const fn (object: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyObject_Size") },
);

pub const PyObject_Repr = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_Repr") },
);

pub const PyObject_RichCompareBool = @extern(
    *const fn (left: *PyObject, right: *PyObject, operation: c_int) callconv(.c) c_int,
    .{ .name = symbol("PyObject_RichCompareBool") },
);

pub const PyObject_SetAttrString = @extern(
    *const fn (object: *PyObject, name: [*:0]const u8, value: ?*PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_SetAttrString") },
);

pub const PyObject_SetItem = @extern(
    *const fn (object: *PyObject, key: *PyObject, value: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyObject_SetItem") },
);

pub const PyObject_Str = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_Str") },
);

pub const PyObject_Type = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyObject_Type") },
);

pub const PySequence_Check = @extern(
    *const fn (object: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PySequence_Check") },
);

pub const PySequence_Tuple = @extern(
    *const fn (object: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PySequence_Tuple") },
);

pub const PySet_Add = @extern(
    *const fn (set: *PyObject, key: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PySet_Add") },
);

pub const PySet_Contains = @extern(
    *const fn (set: *PyObject, key: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PySet_Contains") },
);

pub const PySet_New = @extern(
    *const fn (iterable: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PySet_New") },
);

pub const PySet_Size = @extern(
    *const fn (set: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PySet_Size") },
);

pub const PySlice_AdjustIndices = @extern(
    *const fn (
        length: Py_ssize_t,
        start: *Py_ssize_t,
        stop: *Py_ssize_t,
        step: Py_ssize_t,
    ) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PySlice_AdjustIndices") },
);

pub const PySlice_New = @extern(
    *const fn (start: ?*PyObject, stop: ?*PyObject, step: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PySlice_New") },
);

pub const PySlice_Unpack = @extern(
    *const fn (
        slice: *PyObject,
        start: *Py_ssize_t,
        stop: *Py_ssize_t,
        step: *Py_ssize_t,
    ) callconv(.c) c_int,
    .{ .name = symbol("PySlice_Unpack") },
);

pub const PyThreadState_Clear = @extern(
    *const fn (thread: *PyThreadState) callconv(.c) void,
    .{ .name = symbol("PyThreadState_Clear") },
);

pub const PyThreadState_Delete = @extern(
    *const fn (thread: *PyThreadState) callconv(.c) void,
    .{ .name = symbol("PyThreadState_Delete") },
);

pub const PyThreadState_GetDict = @extern(
    *const fn () callconv(.c) ?*PyObject,
    .{ .name = symbol("PyThreadState_GetDict") },
);

pub const PyThreadState_New = @extern(
    *const fn (state: *PyInterpreterState) callconv(.c) ?*PyThreadState,
    .{ .name = symbol("PyThreadState_New") },
);

pub const PyTuple_GetItem = @extern(
    *const fn (tuple: *PyObject, index: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyTuple_GetItem") },
);

pub const PyTuple_New = @extern(
    *const fn (size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyTuple_New") },
);

pub const PyTuple_SetItem = @extern(
    *const fn (tuple: *PyObject, index: Py_ssize_t, item: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyTuple_SetItem") },
);

pub const PyTuple_Size = @extern(
    *const fn (tuple: *PyObject) callconv(.c) Py_ssize_t,
    .{ .name = symbol("PyTuple_Size") },
);

pub const PyType_FromMetaclass = @extern(
    *const fn (
        metaclass: *PyObject,
        module: *PyObject,
        specification: *const PyType_Spec,
        bases: ?*PyObject,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyType_FromMetaclass") },
);

pub const PyType_FromModuleAndSpec = @extern(
    *const fn (
        module: *PyObject,
        specification: *const PyType_Spec,
        bases: ?*PyObject,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyType_FromModuleAndSpec") },
);

pub const PyType_GetFlags = @extern(
    *const fn (class: *PyObject) callconv(.c) c_ulong,
    .{ .name = symbol("PyType_GetFlags") },
);

pub const PyType_GetModule = @extern(
    *const fn (class: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyType_GetModule") },
);

pub const PyType_GetSlot = @extern(
    *const fn (class: *PyObject, slot: c_int) callconv(.c) ?*anyopaque,
    .{ .name = symbol("PyType_GetSlot") },
);

pub const PyType_IsSubtype = @extern(
    *const fn (class: *PyObject, base: *PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyType_IsSubtype") },
);

pub const PyUnicode_AsUTF8AndSize = @extern(
    *const fn (text: *PyObject, size: *Py_ssize_t) callconv(.c) ?[*:0]const u8,
    .{ .name = symbol("PyUnicode_AsUTF8AndSize") },
);

pub const PyUnicode_DecodeFSDefaultAndSize = @extern(
    *const fn (bytes: [*]const u8, size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyUnicode_DecodeFSDefaultAndSize") },
);

pub const PyUnicode_DecodeUTF8 = @extern(
    *const fn (
        bytes: [*]const u8,
        size: Py_ssize_t,
        errors: ?[*:0]const u8,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyUnicode_DecodeUTF8") },
);

pub const PyUnicode_EncodeFSDefault = @extern(
    *const fn (text: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyUnicode_EncodeFSDefault") },
);

pub const PyUnicode_FromStringAndSize = @extern(
    *const fn (text: ?[*]const u8, size: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyUnicode_FromStringAndSize") },
);

pub const PyWeakref_GetObject = @extern(
    *const fn (reference: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyWeakref_GetObject") },
);

pub const PyWeakref_GetRef = @extern(
    *const fn (reference: *PyObject, target: *?*PyObject) callconv(.c) c_int,
    .{ .name = symbol("PyWeakref_GetRef") },
);

pub const PyWeakref_NewRef = @extern(
    *const fn (object: *PyObject, callback: ?*PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyWeakref_NewRef") },
);

pub const PyUnicode_New = @extern(
    *const fn (size: Py_ssize_t, character_max: u32) callconv(.c) ?*PyObject,
    .{ .name = symbol("PyUnicode_New") },
);

pub const Py_BuildValue = @extern(
    *const fn (format: [*:0]const u8, ...) callconv(.c) ?*PyObject,
    .{ .name = symbol("Py_BuildValue") },
);

pub const Py_CompileString = @extern(
    *const fn (
        source: [*:0]const u8,
        filename: [*:0]const u8,
        start: c_int,
    ) callconv(.c) ?*PyObject,
    .{ .name = symbol("Py_CompileString") },
);

pub const Py_DecRef = @extern(
    *const fn (object: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("Py_DecRef") },
);

pub const Py_GenericAlias = @extern(
    *const fn (origin: *PyObject, arguments: *PyObject) callconv(.c) ?*PyObject,
    .{ .name = symbol("Py_GenericAlias") },
);

pub const Py_GetVersion = @extern(
    *const fn () callconv(.c) [*:0]const u8,
    .{ .name = symbol("Py_GetVersion") },
);

pub const Py_IncRef = @extern(
    *const fn (object: ?*PyObject) callconv(.c) void,
    .{ .name = symbol("Py_IncRef") },
);

pub const Py_IsInitialized = @extern(
    *const fn () callconv(.c) c_int,
    .{ .name = symbol("Py_IsInitialized") },
);

pub const _PyBytes_Resize = @extern(
    *const fn (bytes: *?*PyObject, size: Py_ssize_t) callconv(.c) c_int,
    .{ .name = symbol("_PyBytes_Resize") },
);

pub const _PyDict_NewPresized = @extern(
    *const fn (used_min: Py_ssize_t) callconv(.c) ?*PyObject,
    .{ .name = symbol("_PyDict_NewPresized") },
);

pub const _PyDict_SetItem_KnownHash = @extern(
    *const fn (
        dictionary: *PyObject,
        key: *PyObject,
        value: *PyObject,
        hash: Py_hash_t,
    ) callconv(.c) c_int,
    .{ .name = symbol("_PyDict_SetItem_KnownHash") },
);
