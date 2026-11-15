const std = @import("std");

const builtin = @import("builtin");
const c = @import("c.zig");

pub const PyInterpreterGuard = opaque {};
pub const PyInterpreterView = opaque {};
pub const PyLongWriter = opaque {};
pub const Py_tss_t = opaque {};
pub const fork_available = builtin.target.os.tag != .windows;

pub const thread_native_id_available = switch (builtin.target.os.tag) {
    .dragonfly, .freebsd, .linux, .netbsd, .openbsd, .windows => true,
    else => builtin.target.os.tag.isDarwin(),
};

pub const wchar_t = std.c.wchar_t;

pub const gates = struct {
    pub const PyABIInfo_Check: c.Gate = .{ .minor = 15 };
    pub const PyAIter_Check: c.Gate = .{ .minor = 10 };
    pub const PyArg_Parse: c.Gate = .{ .minor = 2, .link_name = "_PyArg_Parse_SizeT" };
    pub const PyArg_ParseTuple: c.Gate = .{ .minor = 2, .link_name = "_PyArg_ParseTuple_SizeT" };

    pub const PyArg_ParseTupleAndKeywords: c.Gate = .{
        .minor = 2,
        .link_name = "_PyArg_ParseTupleAndKeywords_SizeT",
    };

    pub const PyArg_UnpackTuple: c.Gate = .{ .minor = 2 };
    pub const PyArg_ValidateKeywordArguments: c.Gate = .{ .minor = 2 };
    pub const PyBool_FromLong: c.Gate = .{ .minor = 2 };
    pub const PyBuffer_FillContiguousStrides: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_FillInfo: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_FromContiguous: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_GetPointer: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_IsContiguous: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_Release: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_SizeFromFormat: c.Gate = .{ .minor = 11 };
    pub const PyBuffer_ToContiguous: c.Gate = .{ .minor = 11 };
    pub const PyByteArray_AsString: c.Gate = .{ .minor = 2 };
    pub const PyByteArray_Concat: c.Gate = .{ .minor = 2 };
    pub const PyByteArray_FromObject: c.Gate = .{ .minor = 2 };
    pub const PyByteArray_FromStringAndSize: c.Gate = .{ .minor = 2 };
    pub const PyByteArray_Resize: c.Gate = .{ .minor = 2 };
    pub const PyByteArray_Size: c.Gate = .{ .minor = 2 };
    pub const PyBytes_AsString: c.Gate = .{ .minor = 2 };
    pub const PyBytes_AsStringAndSize: c.Gate = .{ .minor = 2 };
    pub const PyBytes_Concat: c.Gate = .{ .minor = 2 };
    pub const PyBytes_ConcatAndDel: c.Gate = .{ .minor = 2 };
    pub const PyBytes_DecodeEscape: c.Gate = .{ .minor = 2 };
    pub const PyBytes_FromFormat: c.Gate = .{ .minor = 2 };
    pub const PyBytes_FromObject: c.Gate = .{ .minor = 2 };
    pub const PyBytes_FromString: c.Gate = .{ .minor = 2 };
    pub const PyBytes_FromStringAndSize: c.Gate = .{ .minor = 2 };
    pub const PyBytes_Repr: c.Gate = .{ .minor = 2 };
    pub const PyBytes_Size: c.Gate = .{ .minor = 2 };
    pub const PyCFunction_GetFlags: c.Gate = .{ .minor = 2 };
    pub const PyCFunction_GetFunction: c.Gate = .{ .minor = 2 };
    pub const PyCFunction_GetSelf: c.Gate = .{ .minor = 2 };
    pub const PyCFunction_New: c.Gate = .{ .minor = 4 };
    pub const PyCFunction_NewEx: c.Gate = .{ .minor = 2 };
    pub const PyCMethod_New: c.Gate = .{ .minor = 9 };
    pub const PyCallIter_New: c.Gate = .{ .minor = 2 };
    pub const PyCallable_Check: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_GetContext: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_GetDestructor: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_GetName: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_GetPointer: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_Import: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_IsValid: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_New: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_SetContext: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_SetDestructor: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_SetName: c.Gate = .{ .minor = 2 };
    pub const PyCapsule_SetPointer: c.Gate = .{ .minor = 2 };
    pub const PyCodec_BackslashReplaceErrors: c.Gate = .{ .minor = 2 };
    pub const PyCodec_Decode: c.Gate = .{ .minor = 2 };
    pub const PyCodec_Decoder: c.Gate = .{ .minor = 2 };
    pub const PyCodec_Encode: c.Gate = .{ .minor = 2 };
    pub const PyCodec_Encoder: c.Gate = .{ .minor = 2 };
    pub const PyCodec_IgnoreErrors: c.Gate = .{ .minor = 2 };
    pub const PyCodec_IncrementalDecoder: c.Gate = .{ .minor = 2 };
    pub const PyCodec_IncrementalEncoder: c.Gate = .{ .minor = 2 };
    pub const PyCodec_KnownEncoding: c.Gate = .{ .minor = 2 };
    pub const PyCodec_LookupError: c.Gate = .{ .minor = 2 };
    pub const PyCodec_NameReplaceErrors: c.Gate = .{ .minor = 7 };
    pub const PyCodec_Register: c.Gate = .{ .minor = 2 };
    pub const PyCodec_RegisterError: c.Gate = .{ .minor = 2 };
    pub const PyCodec_ReplaceErrors: c.Gate = .{ .minor = 2 };
    pub const PyCodec_StreamReader: c.Gate = .{ .minor = 2 };
    pub const PyCodec_StreamWriter: c.Gate = .{ .minor = 2 };
    pub const PyCodec_StrictErrors: c.Gate = .{ .minor = 2 };
    pub const PyCodec_Unregister: c.Gate = .{ .minor = 10 };
    pub const PyCodec_XMLCharRefReplaceErrors: c.Gate = .{ .minor = 2 };
    pub const PyComplex_FromDoubles: c.Gate = .{ .minor = 2 };
    pub const PyComplex_ImagAsDouble: c.Gate = .{ .minor = 2 };
    pub const PyComplex_RealAsDouble: c.Gate = .{ .minor = 2 };
    pub const PyCriticalSection2_Begin: c.Gate = .{ .minor = 15 };
    pub const PyCriticalSection2_End: c.Gate = .{ .minor = 15 };
    pub const PyCriticalSection_Begin: c.Gate = .{ .minor = 15 };
    pub const PyCriticalSection_End: c.Gate = .{ .minor = 15 };
    pub const PyDescr_NewClassMethod: c.Gate = .{ .minor = 2 };
    pub const PyDescr_NewGetSet: c.Gate = .{ .minor = 2 };
    pub const PyDescr_NewMember: c.Gate = .{ .minor = 2 };
    pub const PyDescr_NewMethod: c.Gate = .{ .minor = 2 };
    pub const PyDictProxy_New: c.Gate = .{ .minor = 2 };
    pub const PyDict_Clear: c.Gate = .{ .minor = 2 };
    pub const PyDict_Contains: c.Gate = .{ .minor = 2 };
    pub const PyDict_Copy: c.Gate = .{ .minor = 2 };
    pub const PyDict_DelItem: c.Gate = .{ .minor = 2 };
    pub const PyDict_DelItemString: c.Gate = .{ .minor = 2 };
    pub const PyDict_GetItem: c.Gate = .{ .minor = 2 };
    pub const PyDict_GetItemRef: c.Gate = .{ .minor = 13 };
    pub const PyDict_GetItemString: c.Gate = .{ .minor = 2 };
    pub const PyDict_GetItemStringRef: c.Gate = .{ .minor = 13 };
    pub const PyDict_GetItemWithError: c.Gate = .{ .minor = 2 };
    pub const PyDict_Items: c.Gate = .{ .minor = 2 };
    pub const PyDict_Keys: c.Gate = .{ .minor = 2 };
    pub const PyDict_Merge: c.Gate = .{ .minor = 2 };
    pub const PyDict_MergeFromSeq2: c.Gate = .{ .minor = 2 };
    pub const PyDict_New: c.Gate = .{ .minor = 2 };
    pub const PyDict_Next: c.Gate = .{ .minor = 2 };
    pub const PyDict_SetDefaultRef: c.Gate = .{ .minor = 15 };
    pub const PyDict_SetItem: c.Gate = .{ .minor = 2 };
    pub const PyDict_SetItemString: c.Gate = .{ .minor = 2 };
    pub const PyDict_Size: c.Gate = .{ .minor = 2 };
    pub const PyDict_Update: c.Gate = .{ .minor = 2 };
    pub const PyDict_Values: c.Gate = .{ .minor = 2 };
    pub const PyErr_BadArgument: c.Gate = .{ .minor = 2 };
    pub const PyErr_BadInternalCall: c.Gate = .{ .minor = 2 };
    pub const PyErr_CheckSignals: c.Gate = .{ .minor = 2 };
    pub const PyErr_Clear: c.Gate = .{ .minor = 2 };
    pub const PyErr_Display: c.Gate = .{ .minor = 2 };
    pub const PyErr_DisplayException: c.Gate = .{ .minor = 12 };
    pub const PyErr_ExceptionMatches: c.Gate = .{ .minor = 2 };
    pub const PyErr_Fetch: c.Gate = .{ .minor = 2 };
    pub const PyErr_Format: c.Gate = .{ .minor = 2 };
    pub const PyErr_GetExcInfo: c.Gate = .{ .minor = 7 };
    pub const PyErr_GetHandledException: c.Gate = .{ .minor = 11 };
    pub const PyErr_GetRaisedException: c.Gate = .{ .minor = 12 };
    pub const PyErr_GivenExceptionMatches: c.Gate = .{ .minor = 2 };
    pub const PyErr_NewException: c.Gate = .{ .minor = 2 };
    pub const PyErr_NewExceptionWithDoc: c.Gate = .{ .minor = 2 };
    pub const PyErr_NoMemory: c.Gate = .{ .minor = 2 };
    pub const PyErr_NormalizeException: c.Gate = .{ .minor = 2 };
    pub const PyErr_Occurred: c.Gate = .{ .minor = 2 };
    pub const PyErr_Print: c.Gate = .{ .minor = 2 };
    pub const PyErr_PrintEx: c.Gate = .{ .minor = 2 };
    pub const PyErr_ProgramText: c.Gate = .{ .minor = 2 };
    pub const PyErr_ResourceWarning: c.Gate = .{ .minor = 6 };
    pub const PyErr_Restore: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetExcInfo: c.Gate = .{ .minor = 7 };
    pub const PyErr_SetFromErrno: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetFromErrnoWithFilename: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetFromErrnoWithFilenameObject: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetFromErrnoWithFilenameObjects: c.Gate = .{ .minor = 7 };
    pub const PyErr_SetHandledException: c.Gate = .{ .minor = 11 };
    pub const PyErr_SetImportError: c.Gate = .{ .minor = 7 };
    pub const PyErr_SetImportErrorSubclass: c.Gate = .{ .minor = 6 };
    pub const PyErr_SetInterrupt: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetInterruptEx: c.Gate = .{ .minor = 10 };
    pub const PyErr_SetNone: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetObject: c.Gate = .{ .minor = 2 };
    pub const PyErr_SetRaisedException: c.Gate = .{ .minor = 12 };
    pub const PyErr_SetString: c.Gate = .{ .minor = 2 };
    pub const PyErr_SyntaxLocation: c.Gate = .{ .minor = 2 };
    pub const PyErr_SyntaxLocationEx: c.Gate = .{ .minor = 7 };
    pub const PyErr_WarnEx: c.Gate = .{ .minor = 2 };
    pub const PyErr_WarnExplicit: c.Gate = .{ .minor = 2 };
    pub const PyErr_WarnFormat: c.Gate = .{ .minor = 2 };
    pub const PyErr_WriteUnraisable: c.Gate = .{ .minor = 2 };
    pub const PyEval_AcquireThread: c.Gate = .{ .minor = 2 };
    pub const PyEval_EvalCode: c.Gate = .{ .minor = 2 };
    pub const PyEval_EvalCodeEx: c.Gate = .{ .minor = 2 };
    pub const PyEval_EvalFrame: c.Gate = .{ .minor = 2 };
    pub const PyEval_EvalFrameEx: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetBuiltins: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetFrame: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetFrameBuiltins: c.Gate = .{ .minor = 13 };
    pub const PyEval_GetFrameGlobals: c.Gate = .{ .minor = 13 };
    pub const PyEval_GetFrameLocals: c.Gate = .{ .minor = 13 };
    pub const PyEval_GetFuncDesc: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetFuncName: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetGlobals: c.Gate = .{ .minor = 2 };
    pub const PyEval_GetLocals: c.Gate = .{ .minor = 2 };
    pub const PyEval_InitThreads: c.Gate = .{ .minor = 2 };
    pub const PyEval_ReleaseThread: c.Gate = .{ .minor = 2 };
    pub const PyEval_RestoreThread: c.Gate = .{ .minor = 2 };
    pub const PyEval_SaveThread: c.Gate = .{ .minor = 2 };
    pub const PyExceptionClass_Name: c.Gate = .{ .minor = 8 };
    pub const PyException_GetArgs: c.Gate = .{ .minor = 12 };
    pub const PyException_GetCause: c.Gate = .{ .minor = 2 };
    pub const PyException_GetContext: c.Gate = .{ .minor = 2 };
    pub const PyException_GetTraceback: c.Gate = .{ .minor = 2 };
    pub const PyException_SetArgs: c.Gate = .{ .minor = 12 };
    pub const PyException_SetCause: c.Gate = .{ .minor = 2 };
    pub const PyException_SetContext: c.Gate = .{ .minor = 2 };
    pub const PyException_SetTraceback: c.Gate = .{ .minor = 2 };
    pub const PyFile_FromFd: c.Gate = .{ .minor = 2 };
    pub const PyFile_GetLine: c.Gate = .{ .minor = 2 };
    pub const PyFile_WriteObject: c.Gate = .{ .minor = 2 };
    pub const PyFile_WriteString: c.Gate = .{ .minor = 2 };
    pub const PyFloat_AsDouble: c.Gate = .{ .minor = 2 };
    pub const PyFloat_FromDouble: c.Gate = .{ .minor = 2 };
    pub const PyFloat_FromString: c.Gate = .{ .minor = 2 };
    pub const PyFloat_GetInfo: c.Gate = .{ .minor = 2 };
    pub const PyFloat_GetMax: c.Gate = .{ .minor = 2 };
    pub const PyFloat_GetMin: c.Gate = .{ .minor = 2 };
    pub const PyFrame_GetCode: c.Gate = .{ .minor = 10 };
    pub const PyFrame_GetLineNumber: c.Gate = .{ .minor = 10 };
    pub const PyFrozenSet_New: c.Gate = .{ .minor = 2 };
    pub const PyGC_Collect: c.Gate = .{ .minor = 2 };
    pub const PyGC_Disable: c.Gate = .{ .minor = 10 };
    pub const PyGC_Enable: c.Gate = .{ .minor = 10 };
    pub const PyGC_IsEnabled: c.Gate = .{ .minor = 10 };
    pub const PyGILState_Ensure: c.Gate = .{ .minor = 2 };
    pub const PyGILState_GetThisThreadState: c.Gate = .{ .minor = 2 };
    pub const PyGILState_Release: c.Gate = .{ .minor = 2 };
    pub const PyImport_AddModule: c.Gate = .{ .minor = 2 };
    pub const PyImport_AddModuleObject: c.Gate = .{ .minor = 7 };
    pub const PyImport_AddModuleRef: c.Gate = .{ .minor = 13 };
    pub const PyImport_AppendInittab: c.Gate = .{ .minor = 2 };
    pub const PyImport_ExecCodeModule: c.Gate = .{ .minor = 2 };
    pub const PyImport_ExecCodeModuleEx: c.Gate = .{ .minor = 2 };
    pub const PyImport_ExecCodeModuleObject: c.Gate = .{ .minor = 7 };
    pub const PyImport_ExecCodeModuleWithPathnames: c.Gate = .{ .minor = 2 };
    pub const PyImport_GetImporter: c.Gate = .{ .minor = 2 };
    pub const PyImport_GetMagicNumber: c.Gate = .{ .minor = 2 };
    pub const PyImport_GetMagicTag: c.Gate = .{ .minor = 2 };
    pub const PyImport_GetModule: c.Gate = .{ .minor = 8 };
    pub const PyImport_GetModuleDict: c.Gate = .{ .minor = 2 };
    pub const PyImport_Import: c.Gate = .{ .minor = 2 };
    pub const PyImport_ImportFrozenModule: c.Gate = .{ .minor = 2 };
    pub const PyImport_ImportFrozenModuleObject: c.Gate = .{ .minor = 7 };
    pub const PyImport_ImportModule: c.Gate = .{ .minor = 2 };
    pub const PyImport_ImportModuleLevel: c.Gate = .{ .minor = 2 };
    pub const PyImport_ImportModuleLevelObject: c.Gate = .{ .minor = 7 };
    pub const PyImport_ReloadModule: c.Gate = .{ .minor = 2 };
    pub const PyIndex_Check: c.Gate = .{ .minor = 8 };
    pub const PyInterpreterGuard_Close: c.Gate = .{ .minor = 15 };
    pub const PyInterpreterGuard_FromCurrent: c.Gate = .{ .minor = 15 };
    pub const PyInterpreterGuard_FromView: c.Gate = .{ .minor = 15 };
    pub const PyInterpreterState_Clear: c.Gate = .{ .minor = 2 };
    pub const PyInterpreterState_Delete: c.Gate = .{ .minor = 2 };
    pub const PyInterpreterState_Get: c.Gate = .{ .minor = 9 };
    pub const PyInterpreterState_GetDict: c.Gate = .{ .minor = 8 };
    pub const PyInterpreterState_GetID: c.Gate = .{ .minor = 7 };
    pub const PyInterpreterState_New: c.Gate = .{ .minor = 2 };
    pub const PyInterpreterView_Close: c.Gate = .{ .minor = 15 };
    pub const PyInterpreterView_FromCurrent: c.Gate = .{ .minor = 15 };
    pub const PyInterpreterView_FromMain: c.Gate = .{ .minor = 15 };
    pub const PyIter_Check: c.Gate = .{ .minor = 8 };
    pub const PyIter_Next: c.Gate = .{ .minor = 2 };
    pub const PyIter_NextItem: c.Gate = .{ .minor = 14 };
    pub const PyIter_Send: c.Gate = .{ .minor = 10 };
    pub const PyList_Append: c.Gate = .{ .minor = 2 };
    pub const PyList_AsTuple: c.Gate = .{ .minor = 2 };
    pub const PyList_GetItem: c.Gate = .{ .minor = 2 };
    pub const PyList_GetItemRef: c.Gate = .{ .minor = 13 };
    pub const PyList_GetSlice: c.Gate = .{ .minor = 2 };
    pub const PyList_Insert: c.Gate = .{ .minor = 2 };
    pub const PyList_New: c.Gate = .{ .minor = 2 };
    pub const PyList_Reverse: c.Gate = .{ .minor = 2 };
    pub const PyList_SetItem: c.Gate = .{ .minor = 2 };
    pub const PyList_SetSlice: c.Gate = .{ .minor = 2 };
    pub const PyList_Size: c.Gate = .{ .minor = 2 };
    pub const PyList_Sort: c.Gate = .{ .minor = 2 };
    pub const PyLongWriter_Create: c.Gate = .{ .minor = 15 };
    pub const PyLongWriter_Discard: c.Gate = .{ .minor = 15 };
    pub const PyLongWriter_Finish: c.Gate = .{ .minor = 15 };
    pub const PyLong_AsDouble: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsInt: c.Gate = .{ .minor = 13 };
    pub const PyLong_AsInt32: c.Gate = .{ .minor = 14 };
    pub const PyLong_AsInt64: c.Gate = .{ .minor = 14 };
    pub const PyLong_AsLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsLongAndOverflow: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsLongLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsLongLongAndOverflow: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsNativeBytes: c.Gate = .{ .minor = 14 };
    pub const PyLong_AsSize_t: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsSsize_t: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsUInt32: c.Gate = .{ .minor = 14 };
    pub const PyLong_AsUInt64: c.Gate = .{ .minor = 14 };
    pub const PyLong_AsUnsignedLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsUnsignedLongLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsUnsignedLongLongMask: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsUnsignedLongMask: c.Gate = .{ .minor = 2 };
    pub const PyLong_AsVoidPtr: c.Gate = .{ .minor = 2 };
    pub const PyLong_Export: c.Gate = .{ .minor = 15 };
    pub const PyLong_FreeExport: c.Gate = .{ .minor = 15 };
    pub const PyLong_FromDouble: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromInt32: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromInt64: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromLongLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromNativeBytes: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromSize_t: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromSsize_t: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromString: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromUInt32: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromUInt64: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromUnsignedLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromUnsignedLongLong: c.Gate = .{ .minor = 2 };
    pub const PyLong_FromUnsignedNativeBytes: c.Gate = .{ .minor = 14 };
    pub const PyLong_FromVoidPtr: c.Gate = .{ .minor = 2 };
    pub const PyLong_GetInfo: c.Gate = .{ .minor = 2 };
    pub const PyLong_GetNativeLayout: c.Gate = .{ .minor = 15 };
    pub const PyMapping_Check: c.Gate = .{ .minor = 2 };
    pub const PyMapping_GetItemString: c.Gate = .{ .minor = 2 };
    pub const PyMapping_GetOptionalItem: c.Gate = .{ .minor = 13 };
    pub const PyMapping_GetOptionalItemString: c.Gate = .{ .minor = 13 };
    pub const PyMapping_HasKey: c.Gate = .{ .minor = 2 };
    pub const PyMapping_HasKeyString: c.Gate = .{ .minor = 2 };
    pub const PyMapping_HasKeyStringWithError: c.Gate = .{ .minor = 13 };
    pub const PyMapping_HasKeyWithError: c.Gate = .{ .minor = 13 };
    pub const PyMapping_Items: c.Gate = .{ .minor = 2 };
    pub const PyMapping_Keys: c.Gate = .{ .minor = 2 };
    pub const PyMapping_Length: c.Gate = .{ .minor = 2 };
    pub const PyMapping_SetItemString: c.Gate = .{ .minor = 2 };
    pub const PyMapping_Size: c.Gate = .{ .minor = 2 };
    pub const PyMapping_Values: c.Gate = .{ .minor = 2 };
    pub const PyMem_Calloc: c.Gate = .{ .minor = 7 };
    pub const PyMem_Free: c.Gate = .{ .minor = 2 };
    pub const PyMem_Malloc: c.Gate = .{ .minor = 2 };
    pub const PyMem_RawCalloc: c.Gate = .{ .minor = 13 };
    pub const PyMem_RawFree: c.Gate = .{ .minor = 13 };
    pub const PyMem_RawMalloc: c.Gate = .{ .minor = 13 };
    pub const PyMem_RawRealloc: c.Gate = .{ .minor = 13 };
    pub const PyMem_Realloc: c.Gate = .{ .minor = 2 };
    pub const PyMember_GetOne: c.Gate = .{ .minor = 2 };
    pub const PyMember_SetOne: c.Gate = .{ .minor = 2 };
    pub const PyMemoryView_FromBuffer: c.Gate = .{ .minor = 11 };
    pub const PyMemoryView_FromMemory: c.Gate = .{ .minor = 7 };
    pub const PyMemoryView_FromObject: c.Gate = .{ .minor = 2 };
    pub const PyMemoryView_GetContiguous: c.Gate = .{ .minor = 2 };
    pub const PyModuleDef_Init: c.Gate = .{ .minor = 5 };
    pub const PyModule_Add: c.Gate = .{ .minor = 13 };
    pub const PyModule_AddFunctions: c.Gate = .{ .minor = 7 };
    pub const PyModule_AddIntConstant: c.Gate = .{ .minor = 2 };
    pub const PyModule_AddObject: c.Gate = .{ .minor = 2 };
    pub const PyModule_AddObjectRef: c.Gate = .{ .minor = 10 };
    pub const PyModule_AddStringConstant: c.Gate = .{ .minor = 2 };
    pub const PyModule_AddType: c.Gate = .{ .minor = 10 };
    pub const PyModule_Create2: c.Gate = .{ .minor = 2 };
    pub const PyModule_Exec: c.Gate = .{ .minor = 15 };
    pub const PyModule_ExecDef: c.Gate = .{ .minor = 7 };
    pub const PyModule_FromDefAndSpec2: c.Gate = .{ .minor = 7 };
    pub const PyModule_FromSlotsAndSpec: c.Gate = .{ .minor = 15 };
    pub const PyModule_GetDef: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetDict: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetFilename: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetFilenameObject: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetName: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetNameObject: c.Gate = .{ .minor = 7 };
    pub const PyModule_GetState: c.Gate = .{ .minor = 2 };
    pub const PyModule_GetStateSize: c.Gate = .{ .minor = 15 };
    pub const PyModule_GetState_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyModule_GetToken: c.Gate = .{ .minor = 15 };
    pub const PyModule_GetToken_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyModule_New: c.Gate = .{ .minor = 2 };
    pub const PyModule_NewObject: c.Gate = .{ .minor = 7 };
    pub const PyModule_SetDocString: c.Gate = .{ .minor = 7 };
    pub const PyNumber_Absolute: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Add: c.Gate = .{ .minor = 2 };
    pub const PyNumber_And: c.Gate = .{ .minor = 2 };
    pub const PyNumber_AsSsize_t: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Check: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Divmod: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Float: c.Gate = .{ .minor = 2 };
    pub const PyNumber_FloorDivide: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceAdd: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceAnd: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceFloorDivide: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceLshift: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceMatrixMultiply: c.Gate = .{ .minor = 7 };
    pub const PyNumber_InPlaceMultiply: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceOr: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlacePower: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceRemainder: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceRshift: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceSubtract: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceTrueDivide: c.Gate = .{ .minor = 2 };
    pub const PyNumber_InPlaceXor: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Index: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Invert: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Long: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Lshift: c.Gate = .{ .minor = 2 };
    pub const PyNumber_MatrixMultiply: c.Gate = .{ .minor = 7 };
    pub const PyNumber_Multiply: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Negative: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Or: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Positive: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Power: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Remainder: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Rshift: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Subtract: c.Gate = .{ .minor = 2 };
    pub const PyNumber_ToBase: c.Gate = .{ .minor = 2 };
    pub const PyNumber_TrueDivide: c.Gate = .{ .minor = 2 };
    pub const PyNumber_Xor: c.Gate = .{ .minor = 2 };
    pub const PyOS_AfterFork: c.Gate = .{ .minor = 2, .platform = .fork };
    pub const PyOS_AfterFork_Child: c.Gate = .{ .minor = 7, .platform = .fork };
    pub const PyOS_AfterFork_Parent: c.Gate = .{ .minor = 7, .platform = .fork };
    pub const PyOS_BeforeFork: c.Gate = .{ .minor = 7, .platform = .fork };
    pub const PyOS_FSPath: c.Gate = .{ .minor = 6 };
    pub const PyOS_InterruptOccurred: c.Gate = .{ .minor = 2 };
    pub const PyOS_double_to_string: c.Gate = .{ .minor = 2 };
    pub const PyOS_getsig: c.Gate = .{ .minor = 2 };
    pub const PyOS_mystricmp: c.Gate = .{ .minor = 2 };
    pub const PyOS_mystrnicmp: c.Gate = .{ .minor = 2 };
    pub const PyOS_setsig: c.Gate = .{ .minor = 2 };
    pub const PyOS_snprintf: c.Gate = .{ .minor = 2 };
    pub const PyOS_string_to_double: c.Gate = .{ .minor = 2 };
    pub const PyOS_strtol: c.Gate = .{ .minor = 2 };
    pub const PyOS_strtoul: c.Gate = .{ .minor = 2 };
    pub const PyObject_ASCII: c.Gate = .{ .minor = 2 };
    pub const PyObject_AsFileDescriptor: c.Gate = .{ .minor = 2 };
    pub const PyObject_Bytes: c.Gate = .{ .minor = 2 };
    pub const PyObject_Call: c.Gate = .{ .minor = 2 };
    pub const PyObject_CallFinalizerFromDealloc: c.Gate = .{ .minor = 15 };

    pub const PyObject_CallFunction: c.Gate = .{
        .minor = 2,
        .link_name = "_PyObject_CallFunction_SizeT",
    };

    pub const PyObject_CallFunctionObjArgs: c.Gate = .{ .minor = 2 };

    pub const PyObject_CallMethod: c.Gate = .{
        .minor = 2,
        .link_name = "_PyObject_CallMethod_SizeT",
    };

    pub const PyObject_CallMethodObjArgs: c.Gate = .{ .minor = 2 };
    pub const PyObject_CallNoArgs: c.Gate = .{ .minor = 10 };
    pub const PyObject_CallObject: c.Gate = .{ .minor = 2 };
    pub const PyObject_Calloc: c.Gate = .{ .minor = 7 };
    pub const PyObject_CheckBuffer: c.Gate = .{ .minor = 11 };
    pub const PyObject_ClearWeakRefs: c.Gate = .{ .minor = 2 };
    pub const PyObject_CopyData: c.Gate = .{ .minor = 11 };
    pub const PyObject_DelAttr: c.Gate = .{ .minor = 13 };
    pub const PyObject_DelAttrString: c.Gate = .{ .minor = 13 };
    pub const PyObject_DelItem: c.Gate = .{ .minor = 2 };
    pub const PyObject_DelItemString: c.Gate = .{ .minor = 2 };
    pub const PyObject_Dir: c.Gate = .{ .minor = 2 };
    pub const PyObject_Format: c.Gate = .{ .minor = 2 };
    pub const PyObject_Free: c.Gate = .{ .minor = 2 };
    pub const PyObject_GC_Del: c.Gate = .{ .minor = 2 };
    pub const PyObject_GC_IsFinalized: c.Gate = .{ .minor = 9 };
    pub const PyObject_GC_IsTracked: c.Gate = .{ .minor = 9 };
    pub const PyObject_GC_Track: c.Gate = .{ .minor = 2 };
    pub const PyObject_GC_UnTrack: c.Gate = .{ .minor = 2 };
    pub const PyObject_GenericGetAttr: c.Gate = .{ .minor = 2 };
    pub const PyObject_GenericGetDict: c.Gate = .{ .minor = 10 };
    pub const PyObject_GenericSetAttr: c.Gate = .{ .minor = 2 };
    pub const PyObject_GenericSetDict: c.Gate = .{ .minor = 7 };
    pub const PyObject_GetAIter: c.Gate = .{ .minor = 10 };
    pub const PyObject_GetAttr: c.Gate = .{ .minor = 2 };
    pub const PyObject_GetAttrString: c.Gate = .{ .minor = 2 };
    pub const PyObject_GetBuffer: c.Gate = .{ .minor = 11 };
    pub const PyObject_GetItem: c.Gate = .{ .minor = 2 };
    pub const PyObject_GetIter: c.Gate = .{ .minor = 2 };
    pub const PyObject_GetOptionalAttr: c.Gate = .{ .minor = 13 };
    pub const PyObject_GetOptionalAttrString: c.Gate = .{ .minor = 13 };
    pub const PyObject_GetTypeData: c.Gate = .{ .minor = 12 };
    pub const PyObject_GetTypeData_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyObject_HasAttr: c.Gate = .{ .minor = 2 };
    pub const PyObject_HasAttrString: c.Gate = .{ .minor = 2 };
    pub const PyObject_HasAttrStringWithError: c.Gate = .{ .minor = 13 };
    pub const PyObject_HasAttrWithError: c.Gate = .{ .minor = 13 };
    pub const PyObject_Hash: c.Gate = .{ .minor = 2 };
    pub const PyObject_HashNotImplemented: c.Gate = .{ .minor = 2 };
    pub const PyObject_Init: c.Gate = .{ .minor = 2 };
    pub const PyObject_InitVar: c.Gate = .{ .minor = 2 };
    pub const PyObject_IsInstance: c.Gate = .{ .minor = 2 };
    pub const PyObject_IsSubclass: c.Gate = .{ .minor = 2 };
    pub const PyObject_IsTrue: c.Gate = .{ .minor = 2 };
    pub const PyObject_Length: c.Gate = .{ .minor = 2 };
    pub const PyObject_Malloc: c.Gate = .{ .minor = 2 };
    pub const PyObject_Not: c.Gate = .{ .minor = 2 };
    pub const PyObject_Realloc: c.Gate = .{ .minor = 2 };
    pub const PyObject_Repr: c.Gate = .{ .minor = 2 };
    pub const PyObject_RichCompare: c.Gate = .{ .minor = 2 };
    pub const PyObject_RichCompareBool: c.Gate = .{ .minor = 2 };
    pub const PyObject_SelfIter: c.Gate = .{ .minor = 2 };
    pub const PyObject_SetAttr: c.Gate = .{ .minor = 2 };
    pub const PyObject_SetAttrString: c.Gate = .{ .minor = 2 };
    pub const PyObject_SetItem: c.Gate = .{ .minor = 2 };
    pub const PyObject_Size: c.Gate = .{ .minor = 2 };
    pub const PyObject_Str: c.Gate = .{ .minor = 2 };
    pub const PyObject_Type: c.Gate = .{ .minor = 2 };
    pub const PyObject_Vectorcall: c.Gate = .{ .minor = 12 };
    pub const PyObject_VectorcallMethod: c.Gate = .{ .minor = 12 };
    pub const PySeqIter_New: c.Gate = .{ .minor = 2 };
    pub const PySequence_Check: c.Gate = .{ .minor = 2 };
    pub const PySequence_Concat: c.Gate = .{ .minor = 2 };
    pub const PySequence_Contains: c.Gate = .{ .minor = 2 };
    pub const PySequence_Count: c.Gate = .{ .minor = 2 };
    pub const PySequence_DelItem: c.Gate = .{ .minor = 2 };
    pub const PySequence_DelSlice: c.Gate = .{ .minor = 2 };
    pub const PySequence_Fast: c.Gate = .{ .minor = 2 };
    pub const PySequence_GetItem: c.Gate = .{ .minor = 2 };
    pub const PySequence_GetSlice: c.Gate = .{ .minor = 2 };
    pub const PySequence_In: c.Gate = .{ .minor = 2 };
    pub const PySequence_InPlaceConcat: c.Gate = .{ .minor = 2 };
    pub const PySequence_InPlaceRepeat: c.Gate = .{ .minor = 2 };
    pub const PySequence_Index: c.Gate = .{ .minor = 2 };
    pub const PySequence_Length: c.Gate = .{ .minor = 2 };
    pub const PySequence_List: c.Gate = .{ .minor = 2 };
    pub const PySequence_Repeat: c.Gate = .{ .minor = 2 };
    pub const PySequence_SetItem: c.Gate = .{ .minor = 2 };
    pub const PySequence_SetSlice: c.Gate = .{ .minor = 2 };
    pub const PySequence_Size: c.Gate = .{ .minor = 2 };
    pub const PySequence_Tuple: c.Gate = .{ .minor = 2 };
    pub const PySet_Add: c.Gate = .{ .minor = 2 };
    pub const PySet_Clear: c.Gate = .{ .minor = 2 };
    pub const PySet_Contains: c.Gate = .{ .minor = 2 };
    pub const PySet_Discard: c.Gate = .{ .minor = 2 };
    pub const PySet_New: c.Gate = .{ .minor = 2 };
    pub const PySet_Pop: c.Gate = .{ .minor = 2 };
    pub const PySet_Size: c.Gate = .{ .minor = 2 };
    pub const PySlice_AdjustIndices: c.Gate = .{ .minor = 7 };
    pub const PySlice_GetIndices: c.Gate = .{ .minor = 2 };
    pub const PySlice_GetIndicesEx: c.Gate = .{ .minor = 2 };
    pub const PySlice_New: c.Gate = .{ .minor = 2 };
    pub const PySlice_Unpack: c.Gate = .{ .minor = 7 };
    pub const PyState_AddModule: c.Gate = .{ .minor = 3 };
    pub const PyState_FindModule: c.Gate = .{ .minor = 2 };
    pub const PyState_RemoveModule: c.Gate = .{ .minor = 3 };
    pub const PyStructSequence_GetItem: c.Gate = .{ .minor = 2 };
    pub const PyStructSequence_New: c.Gate = .{ .minor = 2 };
    pub const PyStructSequence_NewType: c.Gate = .{ .minor = 2 };
    pub const PyStructSequence_SetItem: c.Gate = .{ .minor = 2 };
    pub const PySys_Audit: c.Gate = .{ .minor = 13 };
    pub const PySys_AuditTuple: c.Gate = .{ .minor = 13 };
    pub const PySys_FormatStderr: c.Gate = .{ .minor = 2 };
    pub const PySys_FormatStdout: c.Gate = .{ .minor = 2 };
    pub const PySys_GetAttr: c.Gate = .{ .minor = 15 };
    pub const PySys_GetAttrString: c.Gate = .{ .minor = 15 };
    pub const PySys_GetObject: c.Gate = .{ .minor = 2 };
    pub const PySys_GetOptionalAttr: c.Gate = .{ .minor = 15 };
    pub const PySys_GetOptionalAttrString: c.Gate = .{ .minor = 15 };
    pub const PySys_GetXOptions: c.Gate = .{ .minor = 7 };
    pub const PySys_SetArgv: c.Gate = .{ .minor = 2 };
    pub const PySys_SetArgvEx: c.Gate = .{ .minor = 2 };
    pub const PySys_SetObject: c.Gate = .{ .minor = 2 };
    pub const PySys_WriteStderr: c.Gate = .{ .minor = 2 };
    pub const PySys_WriteStdout: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_Clear: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_Delete: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_Ensure: c.Gate = .{ .minor = 15 };
    pub const PyThreadState_EnsureFromView: c.Gate = .{ .minor = 15 };
    pub const PyThreadState_Get: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_GetDict: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_GetFrame: c.Gate = .{ .minor = 10 };
    pub const PyThreadState_GetID: c.Gate = .{ .minor = 10 };
    pub const PyThreadState_GetInterpreter: c.Gate = .{ .minor = 10 };
    pub const PyThreadState_New: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_Release: c.Gate = .{ .minor = 15 };
    pub const PyThreadState_SetAsyncExc: c.Gate = .{ .minor = 2 };
    pub const PyThreadState_Swap: c.Gate = .{ .minor = 2 };
    pub const PyThread_GetInfo: c.Gate = .{ .minor = 3 };
    pub const PyThread_ReInitTLS: c.Gate = .{ .minor = 2 };
    pub const PyThread_acquire_lock: c.Gate = .{ .minor = 2 };
    pub const PyThread_acquire_lock_timed: c.Gate = .{ .minor = 2 };
    pub const PyThread_allocate_lock: c.Gate = .{ .minor = 2 };
    pub const PyThread_create_key: c.Gate = .{ .minor = 2 };
    pub const PyThread_delete_key: c.Gate = .{ .minor = 2 };
    pub const PyThread_delete_key_value: c.Gate = .{ .minor = 2 };
    pub const PyThread_exit_thread: c.Gate = .{ .minor = 2 };
    pub const PyThread_free_lock: c.Gate = .{ .minor = 2 };
    pub const PyThread_get_key_value: c.Gate = .{ .minor = 2 };
    pub const PyThread_get_stacksize: c.Gate = .{ .minor = 2 };
    pub const PyThread_get_thread_ident: c.Gate = .{ .minor = 2 };

    pub const PyThread_get_thread_native_id: c.Gate = .{
        .minor = 2,
        .platform = .thread_native_id,
    };

    pub const PyThread_init_thread: c.Gate = .{ .minor = 2 };
    pub const PyThread_release_lock: c.Gate = .{ .minor = 2 };
    pub const PyThread_set_key_value: c.Gate = .{ .minor = 2 };
    pub const PyThread_set_stacksize: c.Gate = .{ .minor = 2 };
    pub const PyThread_start_new_thread: c.Gate = .{ .minor = 2 };
    pub const PyThread_tss_alloc: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_create: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_delete: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_free: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_get: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_is_created: c.Gate = .{ .minor = 7 };
    pub const PyThread_tss_set: c.Gate = .{ .minor = 7 };
    pub const PyTraceBack_Here: c.Gate = .{ .minor = 2 };
    pub const PyTraceBack_Print: c.Gate = .{ .minor = 2 };
    pub const PyTuple_GetItem: c.Gate = .{ .minor = 2 };
    pub const PyTuple_GetSlice: c.Gate = .{ .minor = 2 };
    pub const PyTuple_New: c.Gate = .{ .minor = 2 };
    pub const PyTuple_Pack: c.Gate = .{ .minor = 2 };
    pub const PyTuple_SetItem: c.Gate = .{ .minor = 2 };
    pub const PyTuple_Size: c.Gate = .{ .minor = 2 };
    pub const PyType_ClearCache: c.Gate = .{ .minor = 2 };
    pub const PyType_Freeze: c.Gate = .{ .minor = 14 };
    pub const PyType_FromMetaclass: c.Gate = .{ .minor = 12 };
    pub const PyType_FromModuleAndSpec: c.Gate = .{ .minor = 10 };
    pub const PyType_FromSlots: c.Gate = .{ .minor = 15 };
    pub const PyType_FromSpec: c.Gate = .{ .minor = 2 };
    pub const PyType_FromSpecWithBases: c.Gate = .{ .minor = 3 };
    pub const PyType_GenericAlloc: c.Gate = .{ .minor = 2 };
    pub const PyType_GenericNew: c.Gate = .{ .minor = 2 };
    pub const PyType_GetBaseByToken: c.Gate = .{ .minor = 14 };
    pub const PyType_GetBaseByToken_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyType_GetFlags: c.Gate = .{ .minor = 2 };
    pub const PyType_GetFullyQualifiedName: c.Gate = .{ .minor = 13 };
    pub const PyType_GetModule: c.Gate = .{ .minor = 10 };
    pub const PyType_GetModuleByDef: c.Gate = .{ .minor = 13 };
    pub const PyType_GetModuleByToken: c.Gate = .{ .minor = 15 };
    pub const PyType_GetModuleByToken_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyType_GetModuleName: c.Gate = .{ .minor = 13 };
    pub const PyType_GetModuleState: c.Gate = .{ .minor = 10 };
    pub const PyType_GetModuleState_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyType_GetModule_DuringGC: c.Gate = .{ .minor = 15 };
    pub const PyType_GetName: c.Gate = .{ .minor = 11 };
    pub const PyType_GetQualName: c.Gate = .{ .minor = 11 };
    pub const PyType_GetSlot: c.Gate = .{ .minor = 4 };
    pub const PyType_GetTypeDataSize: c.Gate = .{ .minor = 12 };
    pub const PyType_IsSubtype: c.Gate = .{ .minor = 2 };
    pub const PyType_Modified: c.Gate = .{ .minor = 2 };
    pub const PyType_Ready: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_Create: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_GetEncoding: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_GetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_GetObject: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_GetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_GetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_SetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_SetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeDecodeError_SetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_GetEncoding: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_GetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_GetObject: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_GetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_GetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_SetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_SetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeEncodeError_SetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_GetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_GetObject: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_GetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_GetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_SetEnd: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_SetReason: c.Gate = .{ .minor = 2 };
    pub const PyUnicodeTranslateError_SetStart: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Append: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AppendAndDel: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsASCIIString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsCharmapString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsEncodedString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsLatin1String: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsRawUnicodeEscapeString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsUCS4: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_AsUCS4Copy: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_AsUTF16String: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsUTF32String: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsUTF8AndSize: c.Gate = .{ .minor = 10 };
    pub const PyUnicode_AsUTF8String: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsUnicodeEscapeString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsWideChar: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_AsWideCharString: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_BuildEncodingMap: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Compare: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_CompareWithASCIIString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Concat: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Contains: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Count: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Decode: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeASCII: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeCharmap: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeFSDefault: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeFSDefaultAndSize: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeLatin1: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeLocale: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_DecodeLocaleAndSize: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_DecodeRawUnicodeEscape: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF16: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF16Stateful: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF32: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF32Stateful: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF7: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF7Stateful: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF8: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUTF8Stateful: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_DecodeUnicodeEscape: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_EncodeFSDefault: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_EncodeLocale: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_Equal: c.Gate = .{ .minor = 14 };
    pub const PyUnicode_EqualToUTF8: c.Gate = .{ .minor = 13 };
    pub const PyUnicode_EqualToUTF8AndSize: c.Gate = .{ .minor = 13 };
    pub const PyUnicode_FSConverter: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FSDecoder: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Find: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FindChar: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_Format: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromEncodedObject: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromFormat: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromObject: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromOrdinal: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromStringAndSize: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_FromWideChar: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_GetDefaultEncoding: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_GetLength: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_InternFromString: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_InternInPlace: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_IsIdentifier: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Join: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Partition: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_RPartition: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_RSplit: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_ReadChar: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_Replace: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Resize: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_RichCompare: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Split: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Splitlines: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Substring: c.Gate = .{ .minor = 7 };
    pub const PyUnicode_Tailmatch: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_Translate: c.Gate = .{ .minor = 2 };
    pub const PyUnicode_WriteChar: c.Gate = .{ .minor = 7 };
    pub const PyVectorcall_Call: c.Gate = .{ .minor = 12 };
    pub const PyVectorcall_NARGS: c.Gate = .{ .minor = 12 };
    pub const PyWeakref_GetRef: c.Gate = .{ .minor = 13 };
    pub const PyWeakref_NewProxy: c.Gate = .{ .minor = 2 };
    pub const PyWeakref_NewRef: c.Gate = .{ .minor = 2 };
    pub const PyWrapper_New: c.Gate = .{ .minor = 2 };
    pub const Py_AddPendingCall: c.Gate = .{ .minor = 2 };
    pub const Py_AtExit: c.Gate = .{ .minor = 2 };
    pub const Py_BuildValue: c.Gate = .{ .minor = 2, .link_name = "_Py_BuildValue_SizeT" };
    pub const Py_BytesMain: c.Gate = .{ .minor = 8 };
    pub const Py_CompileString: c.Gate = .{ .minor = 2 };
    pub const Py_DecRef: c.Gate = .{ .minor = 2 };
    pub const Py_DecodeLocale: c.Gate = .{ .minor = 7 };
    pub const Py_EncodeLocale: c.Gate = .{ .minor = 7 };
    pub const Py_EndInterpreter: c.Gate = .{ .minor = 2 };
    pub const Py_EnterRecursiveCall: c.Gate = .{ .minor = 9 };
    pub const Py_Exit: c.Gate = .{ .minor = 2 };
    pub const Py_FatalError: c.Gate = .{ .minor = 2 };
    pub const Py_Finalize: c.Gate = .{ .minor = 2 };
    pub const Py_FinalizeEx: c.Gate = .{ .minor = 6 };
    pub const Py_GenericAlias: c.Gate = .{ .minor = 9 };
    pub const Py_GetBuildInfo: c.Gate = .{ .minor = 2 };
    pub const Py_GetCompiler: c.Gate = .{ .minor = 2 };
    pub const Py_GetConstant: c.Gate = .{ .minor = 13 };
    pub const Py_GetConstantBorrowed: c.Gate = .{ .minor = 13 };
    pub const Py_GetCopyright: c.Gate = .{ .minor = 2 };
    pub const Py_GetPlatform: c.Gate = .{ .minor = 2 };
    pub const Py_GetRecursionLimit: c.Gate = .{ .minor = 2 };
    pub const Py_GetVersion: c.Gate = .{ .minor = 2 };
    pub const Py_IS_TYPE: c.Gate = .{ .minor = 15 };
    pub const Py_IncRef: c.Gate = .{ .minor = 2 };
    pub const Py_Initialize: c.Gate = .{ .minor = 2 };
    pub const Py_InitializeEx: c.Gate = .{ .minor = 2 };
    pub const Py_Is: c.Gate = .{ .minor = 10 };
    pub const Py_IsFalse: c.Gate = .{ .minor = 10 };
    pub const Py_IsFinalizing: c.Gate = .{ .minor = 13 };
    pub const Py_IsInitialized: c.Gate = .{ .minor = 2 };
    pub const Py_IsNone: c.Gate = .{ .minor = 10 };
    pub const Py_IsTrue: c.Gate = .{ .minor = 10 };
    pub const Py_LeaveRecursiveCall: c.Gate = .{ .minor = 9 };
    pub const Py_Main: c.Gate = .{ .minor = 2 };
    pub const Py_MakePendingCalls: c.Gate = .{ .minor = 2 };
    pub const Py_NewInterpreter: c.Gate = .{ .minor = 2 };
    pub const Py_NewRef: c.Gate = .{ .minor = 10 };
    pub const Py_PACK_FULL_VERSION: c.Gate = .{ .minor = 14 };
    pub const Py_PACK_VERSION: c.Gate = .{ .minor = 14 };
    pub const Py_REFCNT: c.Gate = .{ .minor = 14 };
    pub const Py_ReprEnter: c.Gate = .{ .minor = 2 };
    pub const Py_ReprLeave: c.Gate = .{ .minor = 2 };
    pub const Py_SET_SIZE: c.Gate = .{ .minor = 15 };
    pub const Py_SIZE: c.Gate = .{ .minor = 15 };
    pub const Py_SetProgramName: c.Gate = .{ .minor = 2 };
    pub const Py_SetPythonHome: c.Gate = .{ .minor = 2 };
    pub const Py_SetRecursionLimit: c.Gate = .{ .minor = 2 };
    pub const Py_TYPE: c.Gate = .{ .minor = 14 };
    pub const Py_XNewRef: c.Gate = .{ .minor = 10 };
};

pub const excluded_abi_only = [_][]const u8{
    "PyCFunction_Call",
    "PyEval_AcquireLock",
    "PyEval_CallFunction",
    "PyEval_CallMethod",
    "PyEval_CallObjectWithKeywords",
    "PyEval_ReleaseLock",
    "PyEval_ThreadsInitialized",
    "PyImport_ImportModuleNoBlock",
    "PyMarshal_ReadObjectFromString",
    "PyMarshal_WriteObjectToString",
    "PyObject_AsCharBuffer",
    "PyObject_AsReadBuffer",
    "PyObject_AsWriteBuffer",
    "PyObject_CheckReadBuffer",
    "PySys_AddWarnOption",
    "PySys_AddWarnOptionUnicode",
    "PySys_AddXOption",
    "PySys_HasWarnOptions",
    "PySys_ResetWarnOptions",
    "PySys_SetPath",
    "PyThreadState_DeleteCurrent",
    "PyUnicode_AsDecodedObject",
    "PyUnicode_AsDecodedUnicode",
    "PyUnicode_AsEncodedObject",
    "PyUnicode_AsEncodedUnicode",
    "PyUnicode_GetSize",
    "PyUnicode_InternImmortal",
    "PyWeakref_GetObject",
    "Py_GetArgcArgv",
    "Py_GetExecPrefix",
    "Py_GetPath",
    "Py_GetPrefix",
    "Py_GetProgramFullPath",
    "Py_GetProgramName",
    "Py_GetPythonHome",
    "Py_SetPath",
    "_PyArg_ParseTupleAndKeywords_SizeT",
    "_PyArg_ParseTuple_SizeT",
    "_PyArg_Parse_SizeT",
    "_PyArg_VaParseTupleAndKeywords_SizeT",
    "_PyArg_VaParse_SizeT",
    "_PyErr_BadInternalCall",
    "_PyObject_CallFunction_SizeT",
    "_PyObject_CallMethod_SizeT",
    "_PyObject_GC_New",
    "_PyObject_GC_NewVar",
    "_PyObject_GC_Resize",
    "_PyObject_New",
    "_PyObject_NewVar",
    "_PyState_AddModule",
    "_PyThreadState_Init",
    "_PyThreadState_Prealloc",
    "_Py_BuildValue_SizeT",
    "_Py_CheckRecursiveCall",
    "_Py_Dealloc",
    "_Py_DecRef",
    "_Py_IncRef",
    "_Py_SetRefcnt",
    "_Py_VaBuildValue_SizeT",
};

pub const excluded_debug = [_][]const u8{
    "_Py_NegativeRefcount",
};

pub const excluded_va_list = [_][]const u8{
    "PyArg_VaParse",
    "PyArg_VaParseTupleAndKeywords",
    "PyBytes_FromFormatV",
    "PyErr_FormatV",
    "PyOS_vsnprintf",
    "PyUnicode_FromFormatV",
    "Py_VaBuildValue",
};

pub const excluded_windows = [_][]const u8{
    "PyErr_SetExcFromWindowsErr",
    "PyErr_SetExcFromWindowsErrWithFilename",
    "PyErr_SetExcFromWindowsErrWithFilenameObject",
    "PyErr_SetExcFromWindowsErrWithFilenameObjects",
    "PyErr_SetFromWindowsErr",
    "PyErr_SetFromWindowsErrWithFilename",
    "PyOS_CheckStack",
    "PyUnicode_AsMBCSString",
    "PyUnicode_DecodeCodePageStateful",
    "PyUnicode_DecodeMBCS",
    "PyUnicode_DecodeMBCSStateful",
    "PyUnicode_EncodeCodePage",
};

pub const PyABIInfo_Check = c.Gate.declare(
    *const fn (?*anyopaque, [*c]const u8) callconv(.c) c_int,
    "PyABIInfo_Check",
);

pub const PyAIter_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyAIter_Check",
);

pub const PyArg_Parse = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ...) callconv(.c) c_int,
    "PyArg_Parse",
);

pub const PyArg_ParseTuple = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ...) callconv(.c) c_int,
    "PyArg_ParseTuple",
);

pub const PyArg_ParseTupleAndKeywords = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, [*c]const u8, [*c]const [*c]u8, ...) callconv(.c) c_int,
    "PyArg_ParseTupleAndKeywords",
);

pub const PyArg_UnpackTuple = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, c.Py_ssize_t, c.Py_ssize_t, ...) callconv(.c) c_int,
    "PyArg_UnpackTuple",
);

pub const PyArg_ValidateKeywordArguments = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyArg_ValidateKeywordArguments",
);

pub const PyBool_FromLong = c.Gate.declare(
    *const fn (c_long) callconv(.c) ?*c.PyObject,
    "PyBool_FromLong",
);

pub const PyBuffer_FillContiguousStrides = c.Gate.declare(
    *const fn (c_int, [*c]c.Py_ssize_t, [*c]c.Py_ssize_t, c_int, u8) callconv(.c) void,
    "PyBuffer_FillContiguousStrides",
);

pub const PyBuffer_FillInfo = c.Gate.declare(
    *const fn (
        [*c]c.Py_buffer,
        ?*c.PyObject,
        ?*anyopaque,
        c.Py_ssize_t,
        c_int,
        c_int,
    ) callconv(.c) c_int,
    "PyBuffer_FillInfo",
);

pub const PyBuffer_FromContiguous = c.Gate.declare(
    *const fn ([*c]const c.Py_buffer, ?*const anyopaque, c.Py_ssize_t, u8) callconv(.c) c_int,
    "PyBuffer_FromContiguous",
);

pub const PyBuffer_GetPointer = c.Gate.declare(
    *const fn ([*c]const c.Py_buffer, [*c]const c.Py_ssize_t) callconv(.c) ?*anyopaque,
    "PyBuffer_GetPointer",
);

pub const PyBuffer_IsContiguous = c.Gate.declare(
    *const fn ([*c]const c.Py_buffer, u8) callconv(.c) c_int,
    "PyBuffer_IsContiguous",
);

pub const PyBuffer_Release = c.Gate.declare(
    *const fn ([*c]c.Py_buffer) callconv(.c) void,
    "PyBuffer_Release",
);

pub const PyBuffer_SizeFromFormat = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) c.Py_ssize_t,
    "PyBuffer_SizeFromFormat",
);

pub const PyBuffer_ToContiguous = c.Gate.declare(
    *const fn (?*anyopaque, [*c]const c.Py_buffer, c.Py_ssize_t, u8) callconv(.c) c_int,
    "PyBuffer_ToContiguous",
);

pub const PyByteArray_AsString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]u8,
    "PyByteArray_AsString",
);

pub const PyByteArray_Concat = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyByteArray_Concat",
);

pub const PyByteArray_FromObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyByteArray_FromObject",
);

pub const PyByteArray_FromStringAndSize = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyByteArray_FromStringAndSize",
);

pub const PyByteArray_Resize = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyByteArray_Resize",
);

pub const PyByteArray_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyByteArray_Size",
);

pub const PyBytes_AsString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]u8,
    "PyBytes_AsString",
);

pub const PyBytes_AsStringAndSize = c.Gate.declare(
    *const fn (?*c.PyObject, [*c][*c]u8, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyBytes_AsStringAndSize",
);

pub const PyBytes_Concat = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyBytes_Concat",
);

pub const PyBytes_ConcatAndDel = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyBytes_ConcatAndDel",
);

pub const PyBytes_DecodeEscape = c.Gate.declare(
    *const fn (
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
    ) callconv(.c) ?*c.PyObject,
    "PyBytes_DecodeEscape",
);

pub const PyBytes_FromFormat = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "PyBytes_FromFormat",
);

pub const PyBytes_FromObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyBytes_FromObject",
);

pub const PyBytes_FromString = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyBytes_FromString",
);

pub const PyBytes_FromStringAndSize = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyBytes_FromStringAndSize",
);

pub const PyBytes_Repr = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyBytes_Repr",
);

pub const PyBytes_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyBytes_Size",
);

pub const PyCFunction_GetFlags = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyCFunction_GetFlags",
);

pub const PyCFunction_GetFunction = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*const anyopaque,
    "PyCFunction_GetFunction",
);

pub const PyCFunction_GetSelf = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCFunction_GetSelf",
);

pub const PyCFunction_New = c.Gate.declare(
    *const fn ([*c]c.PyMethodDef, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCFunction_New",
);

pub const PyCFunction_NewEx = c.Gate.declare(
    *const fn ([*c]c.PyMethodDef, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCFunction_NewEx",
);

pub const PyCMethod_New = c.Gate.declare(
    *const fn (
        [*c]c.PyMethodDef,
        ?*c.PyObject,
        ?*c.PyObject,
        ?*c.PyObject,
    ) callconv(.c) ?*c.PyObject,
    "PyCMethod_New",
);

pub const PyCallIter_New = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCallIter_New",
);

pub const PyCallable_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyCallable_Check",
);

pub const PyCapsule_GetContext = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyCapsule_GetContext",
);

pub const PyCapsule_GetDestructor = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*const anyopaque,
    "PyCapsule_GetDestructor",
);

pub const PyCapsule_GetName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyCapsule_GetName",
);

pub const PyCapsule_GetPointer = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*anyopaque,
    "PyCapsule_GetPointer",
);

pub const PyCapsule_Import = c.Gate.declare(
    *const fn ([*c]const u8, c_int) callconv(.c) ?*anyopaque,
    "PyCapsule_Import",
);

pub const PyCapsule_IsValid = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyCapsule_IsValid",
);

pub const PyCapsule_New = c.Gate.declare(
    *const fn (?*anyopaque, [*c]const u8, ?*const anyopaque) callconv(.c) ?*c.PyObject,
    "PyCapsule_New",
);

pub const PyCapsule_SetContext = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyCapsule_SetContext",
);

pub const PyCapsule_SetDestructor = c.Gate.declare(
    *const fn (?*c.PyObject, ?*const anyopaque) callconv(.c) c_int,
    "PyCapsule_SetDestructor",
);

pub const PyCapsule_SetName = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyCapsule_SetName",
);

pub const PyCapsule_SetPointer = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyCapsule_SetPointer",
);

pub const PyCodec_BackslashReplaceErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_BackslashReplaceErrors",
);

pub const PyCodec_Decode = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_Decode",
);

pub const PyCodec_Decoder = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_Decoder",
);

pub const PyCodec_Encode = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_Encode",
);

pub const PyCodec_Encoder = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_Encoder",
);

pub const PyCodec_IgnoreErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_IgnoreErrors",
);

pub const PyCodec_IncrementalDecoder = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_IncrementalDecoder",
);

pub const PyCodec_IncrementalEncoder = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_IncrementalEncoder",
);

pub const PyCodec_KnownEncoding = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) c_int,
    "PyCodec_KnownEncoding",
);

pub const PyCodec_LookupError = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_LookupError",
);

pub const PyCodec_NameReplaceErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_NameReplaceErrors",
);

pub const PyCodec_Register = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyCodec_Register",
);

pub const PyCodec_RegisterError = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyCodec_RegisterError",
);

pub const PyCodec_ReplaceErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_ReplaceErrors",
);

pub const PyCodec_StreamReader = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_StreamReader",
);

pub const PyCodec_StreamWriter = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyCodec_StreamWriter",
);

pub const PyCodec_StrictErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_StrictErrors",
);

pub const PyCodec_Unregister = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyCodec_Unregister",
);

pub const PyCodec_XMLCharRefReplaceErrors = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyCodec_XMLCharRefReplaceErrors",
);

pub const PyComplex_FromDoubles = c.Gate.declare(
    *const fn (f64, f64) callconv(.c) ?*c.PyObject,
    "PyComplex_FromDoubles",
);

pub const PyComplex_ImagAsDouble = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) f64,
    "PyComplex_ImagAsDouble",
);

pub const PyComplex_RealAsDouble = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) f64,
    "PyComplex_RealAsDouble",
);

pub const PyCriticalSection2_Begin = c.Gate.declare(
    *const fn ([*c]c.PyCriticalSection2, ?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyCriticalSection2_Begin",
);

pub const PyCriticalSection2_End = c.Gate.declare(
    *const fn ([*c]c.PyCriticalSection2) callconv(.c) void,
    "PyCriticalSection2_End",
);

pub const PyCriticalSection_Begin = c.Gate.declare(
    *const fn ([*c]c.PyCriticalSection, ?*c.PyObject) callconv(.c) void,
    "PyCriticalSection_Begin",
);

pub const PyCriticalSection_End = c.Gate.declare(
    *const fn ([*c]c.PyCriticalSection) callconv(.c) void,
    "PyCriticalSection_End",
);

pub const PyDescr_NewClassMethod = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyMethodDef) callconv(.c) ?*c.PyObject,
    "PyDescr_NewClassMethod",
);

pub const PyDescr_NewGetSet = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyGetSetDef) callconv(.c) ?*c.PyObject,
    "PyDescr_NewGetSet",
);

pub const PyDescr_NewMember = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyMemberDef) callconv(.c) ?*c.PyObject,
    "PyDescr_NewMember",
);

pub const PyDescr_NewMethod = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyMethodDef) callconv(.c) ?*c.PyObject,
    "PyDescr_NewMethod",
);

pub const PyDictProxy_New = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDictProxy_New",
);

pub const PyDict_Clear = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) void, "PyDict_Clear");

pub const PyDict_Contains = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyDict_Contains",
);

pub const PyDict_Copy = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_Copy",
);

pub const PyDict_DelItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyDict_DelItem",
);

pub const PyDict_DelItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyDict_DelItemString",
);

pub const PyDict_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_GetItem",
);

pub const PyDict_GetItemRef = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyDict_GetItemRef",
);

pub const PyDict_GetItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyDict_GetItemString",
);

pub const PyDict_GetItemStringRef = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*?*c.PyObject) callconv(.c) c_int,
    "PyDict_GetItemStringRef",
);

pub const PyDict_GetItemWithError = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_GetItemWithError",
);

pub const PyDict_Items = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_Items",
);

pub const PyDict_Keys = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_Keys",
);

pub const PyDict_Merge = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) c_int,
    "PyDict_Merge",
);

pub const PyDict_MergeFromSeq2 = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) c_int,
    "PyDict_MergeFromSeq2",
);

pub const PyDict_New = c.Gate.declare(*const fn () callconv(.c) ?*c.PyObject, "PyDict_New");

pub const PyDict_Next = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t, ?*?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyDict_Next",
);

pub const PyDict_SetDefaultRef = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyDict_SetDefaultRef",
);

pub const PyDict_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyDict_SetItem",
);

pub const PyDict_SetItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyDict_SetItemString",
);

pub const PyDict_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyDict_Size",
);

pub const PyDict_Update = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyDict_Update",
);

pub const PyDict_Values = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyDict_Values",
);

pub const PyErr_BadArgument = c.Gate.declare(*const fn () callconv(.c) c_int, "PyErr_BadArgument");

pub const PyErr_BadInternalCall = c.Gate.declare(
    *const fn () callconv(.c) void,
    "PyErr_BadInternalCall",
);

pub const PyErr_CheckSignals = c.Gate.declare(
    *const fn () callconv(.c) c_int,
    "PyErr_CheckSignals",
);

pub const PyErr_Clear = c.Gate.declare(*const fn () callconv(.c) void, "PyErr_Clear");

pub const PyErr_Display = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyErr_Display",
);

pub const PyErr_DisplayException = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyErr_DisplayException",
);

pub const PyErr_ExceptionMatches = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyErr_ExceptionMatches",
);

pub const PyErr_Fetch = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*?*c.PyObject, ?*?*c.PyObject) callconv(.c) void,
    "PyErr_Fetch",
);

pub const PyErr_Format = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "PyErr_Format",
);

pub const PyErr_GetExcInfo = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*?*c.PyObject, ?*?*c.PyObject) callconv(.c) void,
    "PyErr_GetExcInfo",
);

pub const PyErr_GetHandledException = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyErr_GetHandledException",
);

pub const PyErr_GetRaisedException = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyErr_GetRaisedException",
);

pub const PyErr_GivenExceptionMatches = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyErr_GivenExceptionMatches",
);

pub const PyErr_NewException = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_NewException",
);

pub const PyErr_NewExceptionWithDoc = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_NewExceptionWithDoc",
);

pub const PyErr_NoMemory = c.Gate.declare(*const fn () callconv(.c) ?*c.PyObject, "PyErr_NoMemory");

pub const PyErr_NormalizeException = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*?*c.PyObject, ?*?*c.PyObject) callconv(.c) void,
    "PyErr_NormalizeException",
);

pub const PyErr_Occurred = c.Gate.declare(*const fn () callconv(.c) ?*c.PyObject, "PyErr_Occurred");
pub const PyErr_Print = c.Gate.declare(*const fn () callconv(.c) void, "PyErr_Print");
pub const PyErr_PrintEx = c.Gate.declare(*const fn (c_int) callconv(.c) void, "PyErr_PrintEx");

pub const PyErr_ProgramText = c.Gate.declare(
    *const fn ([*c]const u8, c_int) callconv(.c) ?*c.PyObject,
    "PyErr_ProgramText",
);

pub const PyErr_ResourceWarning = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, [*c]const u8, ...) callconv(.c) c_int,
    "PyErr_ResourceWarning",
);

pub const PyErr_Restore = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyErr_Restore",
);

pub const PyErr_SetExcInfo = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyErr_SetExcInfo",
);

pub const PyErr_SetFromErrno = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_SetFromErrno",
);

pub const PyErr_SetFromErrnoWithFilename = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyErr_SetFromErrnoWithFilename",
);

pub const PyErr_SetFromErrnoWithFilenameObject = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_SetFromErrnoWithFilenameObject",
);

pub const PyErr_SetFromErrnoWithFilenameObjects = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_SetFromErrnoWithFilenameObjects",
);

pub const PyErr_SetHandledException = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyErr_SetHandledException",
);

pub const PyErr_SetImportError = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_SetImportError",
);

pub const PyErr_SetImportErrorSubclass = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyErr_SetImportErrorSubclass",
);

pub const PyErr_SetInterrupt = c.Gate.declare(*const fn () callconv(.c) void, "PyErr_SetInterrupt");

pub const PyErr_SetInterruptEx = c.Gate.declare(
    *const fn (c_int) callconv(.c) c_int,
    "PyErr_SetInterruptEx",
);

pub const PyErr_SetNone = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyErr_SetNone",
);

pub const PyErr_SetObject = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyErr_SetObject",
);

pub const PyErr_SetRaisedException = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyErr_SetRaisedException",
);

pub const PyErr_SetString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) void,
    "PyErr_SetString",
);

pub const PyErr_SyntaxLocation = c.Gate.declare(
    *const fn ([*c]const u8, c_int) callconv(.c) void,
    "PyErr_SyntaxLocation",
);

pub const PyErr_SyntaxLocationEx = c.Gate.declare(
    *const fn ([*c]const u8, c_int, c_int) callconv(.c) void,
    "PyErr_SyntaxLocationEx",
);

pub const PyErr_WarnEx = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, c.Py_ssize_t) callconv(.c) c_int,
    "PyErr_WarnEx",
);

pub const PyErr_WarnExplicit = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        [*c]const u8,
        [*c]const u8,
        c_int,
        [*c]const u8,
        ?*c.PyObject,
    ) callconv(.c) c_int,
    "PyErr_WarnExplicit",
);

pub const PyErr_WarnFormat = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, [*c]const u8, ...) callconv(.c) c_int,
    "PyErr_WarnFormat",
);

pub const PyErr_WriteUnraisable = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyErr_WriteUnraisable",
);

pub const PyEval_AcquireThread = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "PyEval_AcquireThread",
);

pub const PyEval_EvalCode = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyEval_EvalCode",
);

pub const PyEval_EvalCodeEx = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        ?*c.PyObject,
        ?*c.PyObject,
        ?[*]const ?*c.PyObject,
        c_int,
        ?[*]const ?*c.PyObject,
        c_int,
        ?[*]const ?*c.PyObject,
        c_int,
        ?*c.PyObject,
        ?*c.PyObject,
    ) callconv(.c) ?*c.PyObject,
    "PyEval_EvalCodeEx",
);

pub const PyEval_EvalFrame = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyEval_EvalFrame",
);

pub const PyEval_EvalFrameEx = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyEval_EvalFrameEx",
);

pub const PyEval_GetBuiltins = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetBuiltins",
);

pub const PyEval_GetFrame = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetFrame",
);

pub const PyEval_GetFrameBuiltins = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetFrameBuiltins",
);

pub const PyEval_GetFrameGlobals = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetFrameGlobals",
);

pub const PyEval_GetFrameLocals = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetFrameLocals",
);

pub const PyEval_GetFuncDesc = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyEval_GetFuncDesc",
);

pub const PyEval_GetFuncName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyEval_GetFuncName",
);

pub const PyEval_GetGlobals = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetGlobals",
);

pub const PyEval_GetLocals = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyEval_GetLocals",
);

pub const PyEval_InitThreads = c.Gate.declare(*const fn () callconv(.c) void, "PyEval_InitThreads");

pub const PyEval_ReleaseThread = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "PyEval_ReleaseThread",
);

pub const PyEval_RestoreThread = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "PyEval_RestoreThread",
);

pub const PyEval_SaveThread = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyThreadState,
    "PyEval_SaveThread",
);

pub const PyExceptionClass_Name = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyExceptionClass_Name",
);

pub const PyException_GetArgs = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyException_GetArgs",
);

pub const PyException_GetCause = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyException_GetCause",
);

pub const PyException_GetContext = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyException_GetContext",
);

pub const PyException_GetTraceback = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyException_GetTraceback",
);

pub const PyException_SetArgs = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyException_SetArgs",
);

pub const PyException_SetCause = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyException_SetCause",
);

pub const PyException_SetContext = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyException_SetContext",
);

pub const PyException_SetTraceback = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyException_SetTraceback",
);

pub const PyFile_FromFd = c.Gate.declare(
    *const fn (
        c_int,
        [*c]const u8,
        [*c]const u8,
        c_int,
        [*c]const u8,
        [*c]const u8,
        [*c]const u8,
        c_int,
    ) callconv(.c) ?*c.PyObject,
    "PyFile_FromFd",
);

pub const PyFile_GetLine = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyFile_GetLine",
);

pub const PyFile_WriteObject = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) c_int,
    "PyFile_WriteObject",
);

pub const PyFile_WriteString = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyFile_WriteString",
);

pub const PyFloat_AsDouble = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) f64,
    "PyFloat_AsDouble",
);

pub const PyFloat_FromDouble = c.Gate.declare(
    *const fn (f64) callconv(.c) ?*c.PyObject,
    "PyFloat_FromDouble",
);

pub const PyFloat_FromString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyFloat_FromString",
);

pub const PyFloat_GetInfo = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyFloat_GetInfo",
);

pub const PyFloat_GetMax = c.Gate.declare(*const fn () callconv(.c) f64, "PyFloat_GetMax");
pub const PyFloat_GetMin = c.Gate.declare(*const fn () callconv(.c) f64, "PyFloat_GetMin");

pub const PyFrame_GetCode = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyFrame_GetCode",
);

pub const PyFrame_GetLineNumber = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyFrame_GetLineNumber",
);

pub const PyFrozenSet_New = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyFrozenSet_New",
);

pub const PyGC_Collect = c.Gate.declare(*const fn () callconv(.c) c.Py_ssize_t, "PyGC_Collect");
pub const PyGC_Disable = c.Gate.declare(*const fn () callconv(.c) c_int, "PyGC_Disable");
pub const PyGC_Enable = c.Gate.declare(*const fn () callconv(.c) c_int, "PyGC_Enable");
pub const PyGC_IsEnabled = c.Gate.declare(*const fn () callconv(.c) c_int, "PyGC_IsEnabled");

pub const PyGILState_Ensure = c.Gate.declare(
    *const fn () callconv(.c) c.PyGILState_STATE,
    "PyGILState_Ensure",
);

pub const PyGILState_GetThisThreadState = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyThreadState,
    "PyGILState_GetThisThreadState",
);

pub const PyGILState_Release = c.Gate.declare(
    *const fn (c.PyGILState_STATE) callconv(.c) void,
    "PyGILState_Release",
);

pub const PyImport_AddModule = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyImport_AddModule",
);

pub const PyImport_AddModuleObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_AddModuleObject",
);

pub const PyImport_AddModuleRef = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyImport_AddModuleRef",
);

pub const PyImport_AppendInittab = c.Gate.declare(
    *const fn ([*c]const u8, ?*const anyopaque) callconv(.c) c_int,
    "PyImport_AppendInittab",
);

pub const PyImport_ExecCodeModule = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_ExecCodeModule",
);

pub const PyImport_ExecCodeModuleEx = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyImport_ExecCodeModuleEx",
);

pub const PyImport_ExecCodeModuleObject = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_ExecCodeModuleObject",
);

pub const PyImport_ExecCodeModuleWithPathnames = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyImport_ExecCodeModuleWithPathnames",
);

pub const PyImport_GetImporter = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_GetImporter",
);

pub const PyImport_GetMagicNumber = c.Gate.declare(
    *const fn () callconv(.c) c_long,
    "PyImport_GetMagicNumber",
);

pub const PyImport_GetMagicTag = c.Gate.declare(
    *const fn () callconv(.c) [*c]const u8,
    "PyImport_GetMagicTag",
);

pub const PyImport_GetModule = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_GetModule",
);

pub const PyImport_GetModuleDict = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyImport_GetModuleDict",
);

pub const PyImport_Import = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_Import",
);

pub const PyImport_ImportFrozenModule = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) c_int,
    "PyImport_ImportFrozenModule",
);

pub const PyImport_ImportFrozenModuleObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyImport_ImportFrozenModuleObject",
);

pub const PyImport_ImportModule = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyImport_ImportModule",
);

pub const PyImport_ImportModuleLevel = c.Gate.declare(
    *const fn (
        [*c]const u8,
        ?*c.PyObject,
        ?*c.PyObject,
        ?*c.PyObject,
        c_int,
    ) callconv(.c) ?*c.PyObject,
    "PyImport_ImportModuleLevel",
);

pub const PyImport_ImportModuleLevelObject = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        ?*c.PyObject,
        ?*c.PyObject,
        ?*c.PyObject,
        c_int,
    ) callconv(.c) ?*c.PyObject,
    "PyImport_ImportModuleLevelObject",
);

pub const PyImport_ReloadModule = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyImport_ReloadModule",
);

pub const PyIndex_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyIndex_Check",
);

pub const PyInterpreterGuard_Close = c.Gate.declare(
    *const fn (?*PyInterpreterGuard) callconv(.c) void,
    "PyInterpreterGuard_Close",
);

pub const PyInterpreterGuard_FromCurrent = c.Gate.declare(
    *const fn () callconv(.c) ?*PyInterpreterGuard,
    "PyInterpreterGuard_FromCurrent",
);

pub const PyInterpreterGuard_FromView = c.Gate.declare(
    *const fn (?*PyInterpreterView) callconv(.c) ?*PyInterpreterGuard,
    "PyInterpreterGuard_FromView",
);

pub const PyInterpreterState_Clear = c.Gate.declare(
    *const fn (?*c.PyInterpreterState) callconv(.c) void,
    "PyInterpreterState_Clear",
);

pub const PyInterpreterState_Delete = c.Gate.declare(
    *const fn (?*c.PyInterpreterState) callconv(.c) void,
    "PyInterpreterState_Delete",
);

pub const PyInterpreterState_Get = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyInterpreterState,
    "PyInterpreterState_Get",
);

pub const PyInterpreterState_GetDict = c.Gate.declare(
    *const fn (?*c.PyInterpreterState) callconv(.c) ?*c.PyObject,
    "PyInterpreterState_GetDict",
);

pub const PyInterpreterState_GetID = c.Gate.declare(
    *const fn (?*c.PyInterpreterState) callconv(.c) i64,
    "PyInterpreterState_GetID",
);

pub const PyInterpreterState_New = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyInterpreterState,
    "PyInterpreterState_New",
);

pub const PyInterpreterView_Close = c.Gate.declare(
    *const fn (?*PyInterpreterView) callconv(.c) void,
    "PyInterpreterView_Close",
);

pub const PyInterpreterView_FromCurrent = c.Gate.declare(
    *const fn () callconv(.c) ?*PyInterpreterView,
    "PyInterpreterView_FromCurrent",
);

pub const PyInterpreterView_FromMain = c.Gate.declare(
    *const fn () callconv(.c) ?*PyInterpreterView,
    "PyInterpreterView_FromMain",
);

pub const PyIter_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyIter_Check",
);

pub const PyIter_Next = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyIter_Next",
);

pub const PyIter_NextItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyIter_NextItem",
);

pub const PyIter_Send = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyIter_Send",
);

pub const PyList_Append = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyList_Append",
);

pub const PyList_AsTuple = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyList_AsTuple",
);

pub const PyList_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyList_GetItem",
);

pub const PyList_GetItemRef = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyList_GetItemRef",
);

pub const PyList_GetSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyList_GetSlice",
);

pub const PyList_Insert = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PyList_Insert",
);

pub const PyList_New = c.Gate.declare(
    *const fn (c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyList_New",
);

pub const PyList_Reverse = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyList_Reverse",
);

pub const PyList_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PyList_SetItem",
);

pub const PyList_SetSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PyList_SetSlice",
);

pub const PyList_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyList_Size",
);

pub const PyList_Sort = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c_int, "PyList_Sort");

pub const PyLongWriter_Create = c.Gate.declare(
    *const fn (c_int, c.Py_ssize_t, [*c]?*anyopaque) callconv(.c) ?*PyLongWriter,
    "PyLongWriter_Create",
);

pub const PyLongWriter_Discard = c.Gate.declare(
    *const fn (?*PyLongWriter) callconv(.c) void,
    "PyLongWriter_Discard",
);

pub const PyLongWriter_Finish = c.Gate.declare(
    *const fn (?*PyLongWriter) callconv(.c) ?*c.PyObject,
    "PyLongWriter_Finish",
);

pub const PyLong_AsDouble = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) f64,
    "PyLong_AsDouble",
);

pub const PyLong_AsInt = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyLong_AsInt",
);

pub const PyLong_AsInt32 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]i32) callconv(.c) c_int,
    "PyLong_AsInt32",
);

pub const PyLong_AsInt64 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]i64) callconv(.c) c_int,
    "PyLong_AsInt64",
);

pub const PyLong_AsLong = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_long,
    "PyLong_AsLong",
);

pub const PyLong_AsLongAndOverflow = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c_int) callconv(.c) c_long,
    "PyLong_AsLongAndOverflow",
);

pub const PyLong_AsLongLong = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_longlong,
    "PyLong_AsLongLong",
);

pub const PyLong_AsLongLongAndOverflow = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c_int) callconv(.c) c_longlong,
    "PyLong_AsLongLongAndOverflow",
);

pub const PyLong_AsNativeBytes = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque, c.Py_ssize_t, c_int) callconv(.c) c.Py_ssize_t,
    "PyLong_AsNativeBytes",
);

pub const PyLong_AsSize_t = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) usize,
    "PyLong_AsSize_t",
);

pub const PyLong_AsSsize_t = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyLong_AsSsize_t",
);

pub const PyLong_AsUInt32 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]u32) callconv(.c) c_int,
    "PyLong_AsUInt32",
);

pub const PyLong_AsUInt64 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]u64) callconv(.c) c_int,
    "PyLong_AsUInt64",
);

pub const PyLong_AsUnsignedLong = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_ulong,
    "PyLong_AsUnsignedLong",
);

pub const PyLong_AsUnsignedLongLong = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_ulonglong,
    "PyLong_AsUnsignedLongLong",
);

pub const PyLong_AsUnsignedLongLongMask = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_ulonglong,
    "PyLong_AsUnsignedLongLongMask",
);

pub const PyLong_AsUnsignedLongMask = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_ulong,
    "PyLong_AsUnsignedLongMask",
);

pub const PyLong_AsVoidPtr = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyLong_AsVoidPtr",
);

pub const PyLong_Export = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyLong_Export",
);

pub const PyLong_FreeExport = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyLong_FreeExport",
);

pub const PyLong_FromDouble = c.Gate.declare(
    *const fn (f64) callconv(.c) ?*c.PyObject,
    "PyLong_FromDouble",
);

pub const PyLong_FromInt32 = c.Gate.declare(
    *const fn (i32) callconv(.c) ?*c.PyObject,
    "PyLong_FromInt32",
);

pub const PyLong_FromInt64 = c.Gate.declare(
    *const fn (i64) callconv(.c) ?*c.PyObject,
    "PyLong_FromInt64",
);

pub const PyLong_FromLong = c.Gate.declare(
    *const fn (c_long) callconv(.c) ?*c.PyObject,
    "PyLong_FromLong",
);

pub const PyLong_FromLongLong = c.Gate.declare(
    *const fn (c_longlong) callconv(.c) ?*c.PyObject,
    "PyLong_FromLongLong",
);

pub const PyLong_FromNativeBytes = c.Gate.declare(
    *const fn (?*const anyopaque, usize, c_int) callconv(.c) ?*c.PyObject,
    "PyLong_FromNativeBytes",
);

pub const PyLong_FromSize_t = c.Gate.declare(
    *const fn (usize) callconv(.c) ?*c.PyObject,
    "PyLong_FromSize_t",
);

pub const PyLong_FromSsize_t = c.Gate.declare(
    *const fn (c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyLong_FromSsize_t",
);

pub const PyLong_FromString = c.Gate.declare(
    *const fn ([*c]const u8, [*c][*c]u8, c_int) callconv(.c) ?*c.PyObject,
    "PyLong_FromString",
);

pub const PyLong_FromUInt32 = c.Gate.declare(
    *const fn (u32) callconv(.c) ?*c.PyObject,
    "PyLong_FromUInt32",
);

pub const PyLong_FromUInt64 = c.Gate.declare(
    *const fn (u64) callconv(.c) ?*c.PyObject,
    "PyLong_FromUInt64",
);

pub const PyLong_FromUnsignedLong = c.Gate.declare(
    *const fn (c_ulong) callconv(.c) ?*c.PyObject,
    "PyLong_FromUnsignedLong",
);

pub const PyLong_FromUnsignedLongLong = c.Gate.declare(
    *const fn (c_ulonglong) callconv(.c) ?*c.PyObject,
    "PyLong_FromUnsignedLongLong",
);

pub const PyLong_FromUnsignedNativeBytes = c.Gate.declare(
    *const fn (?*const anyopaque, usize, c_int) callconv(.c) ?*c.PyObject,
    "PyLong_FromUnsignedNativeBytes",
);

pub const PyLong_FromVoidPtr = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) ?*c.PyObject,
    "PyLong_FromVoidPtr",
);

pub const PyLong_GetInfo = c.Gate.declare(*const fn () callconv(.c) ?*c.PyObject, "PyLong_GetInfo");

pub const PyLong_GetNativeLayout = c.Gate.declare(
    *const fn () callconv(.c) ?*const anyopaque,
    "PyLong_GetNativeLayout",
);

pub const PyMapping_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyMapping_Check",
);

pub const PyMapping_GetItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyMapping_GetItemString",
);

pub const PyMapping_GetOptionalItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyMapping_GetOptionalItem",
);

pub const PyMapping_GetOptionalItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*?*c.PyObject) callconv(.c) c_int,
    "PyMapping_GetOptionalItemString",
);

pub const PyMapping_HasKey = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyMapping_HasKey",
);

pub const PyMapping_HasKeyString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyMapping_HasKeyString",
);

pub const PyMapping_HasKeyStringWithError = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyMapping_HasKeyStringWithError",
);

pub const PyMapping_HasKeyWithError = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyMapping_HasKeyWithError",
);

pub const PyMapping_Items = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyMapping_Items",
);

pub const PyMapping_Keys = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyMapping_Keys",
);

pub const PyMapping_Length = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyMapping_Length",
);

pub const PyMapping_SetItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyMapping_SetItemString",
);

pub const PyMapping_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyMapping_Size",
);

pub const PyMapping_Values = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyMapping_Values",
);

pub const PyMem_Calloc = c.Gate.declare(
    *const fn (usize, usize) callconv(.c) ?*anyopaque,
    "PyMem_Calloc",
);

pub const PyMem_Free = c.Gate.declare(*const fn (?*anyopaque) callconv(.c) void, "PyMem_Free");
pub const PyMem_Malloc = c.Gate.declare(*const fn (usize) callconv(.c) ?*anyopaque, "PyMem_Malloc");

pub const PyMem_RawCalloc = c.Gate.declare(
    *const fn (usize, usize) callconv(.c) ?*anyopaque,
    "PyMem_RawCalloc",
);

pub const PyMem_RawFree = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyMem_RawFree",
);

pub const PyMem_RawMalloc = c.Gate.declare(
    *const fn (usize) callconv(.c) ?*anyopaque,
    "PyMem_RawMalloc",
);

pub const PyMem_RawRealloc = c.Gate.declare(
    *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    "PyMem_RawRealloc",
);

pub const PyMem_Realloc = c.Gate.declare(
    *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    "PyMem_Realloc",
);

pub const PyMember_GetOne = c.Gate.declare(
    *const fn ([*c]const u8, [*c]c.PyMemberDef) callconv(.c) ?*c.PyObject,
    "PyMember_GetOne",
);

pub const PyMember_SetOne = c.Gate.declare(
    *const fn ([*c]u8, [*c]c.PyMemberDef, ?*c.PyObject) callconv(.c) c_int,
    "PyMember_SetOne",
);

pub const PyMemoryView_FromBuffer = c.Gate.declare(
    *const fn ([*c]const c.Py_buffer) callconv(.c) ?*c.PyObject,
    "PyMemoryView_FromBuffer",
);

pub const PyMemoryView_FromMemory = c.Gate.declare(
    *const fn ([*c]u8, c.Py_ssize_t, c_int) callconv(.c) ?*c.PyObject,
    "PyMemoryView_FromMemory",
);

pub const PyMemoryView_FromObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyMemoryView_FromObject",
);

pub const PyMemoryView_GetContiguous = c.Gate.declare(
    *const fn (?*c.PyObject, c_int, u8) callconv(.c) ?*c.PyObject,
    "PyMemoryView_GetContiguous",
);

pub const PyModuleDef_Init = c.Gate.declare(
    *const fn ([*c]c.PyModuleDef) callconv(.c) ?*c.PyObject,
    "PyModuleDef_Init",
);

pub const PyModule_Add = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyModule_Add",
);

pub const PyModule_AddFunctions = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyMethodDef) callconv(.c) c_int,
    "PyModule_AddFunctions",
);

pub const PyModule_AddIntConstant = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, c_long) callconv(.c) c_int,
    "PyModule_AddIntConstant",
);

pub const PyModule_AddObject = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyModule_AddObject",
);

pub const PyModule_AddObjectRef = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyModule_AddObjectRef",
);

pub const PyModule_AddStringConstant = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) c_int,
    "PyModule_AddStringConstant",
);

pub const PyModule_AddType = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyModule_AddType",
);

pub const PyModule_Create2 = c.Gate.declare(
    *const fn ([*c]c.PyModuleDef, c_int) callconv(.c) ?*c.PyObject,
    "PyModule_Create2",
);

pub const PyModule_Exec = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyModule_Exec",
);

pub const PyModule_ExecDef = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyModuleDef) callconv(.c) c_int,
    "PyModule_ExecDef",
);

pub const PyModule_FromDefAndSpec2 = c.Gate.declare(
    *const fn ([*c]c.PyModuleDef, ?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyModule_FromDefAndSpec2",
);

pub const PyModule_FromSlotsAndSpec = c.Gate.declare(
    *const fn (?*const anyopaque, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyModule_FromSlotsAndSpec",
);

pub const PyModule_GetDef = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]c.PyModuleDef,
    "PyModule_GetDef",
);

pub const PyModule_GetDict = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyModule_GetDict",
);

pub const PyModule_GetFilename = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyModule_GetFilename",
);

pub const PyModule_GetFilenameObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyModule_GetFilenameObject",
);

pub const PyModule_GetName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]const u8,
    "PyModule_GetName",
);

pub const PyModule_GetNameObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyModule_GetNameObject",
);

pub const PyModule_GetState = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyModule_GetState",
);

pub const PyModule_GetStateSize = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyModule_GetStateSize",
);

pub const PyModule_GetState_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyModule_GetState_DuringGC",
);

pub const PyModule_GetToken = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]?*anyopaque) callconv(.c) c_int,
    "PyModule_GetToken",
);

pub const PyModule_GetToken_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]?*anyopaque) callconv(.c) c_int,
    "PyModule_GetToken_DuringGC",
);

pub const PyModule_New = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyModule_New",
);

pub const PyModule_NewObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyModule_NewObject",
);

pub const PyModule_SetDocString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyModule_SetDocString",
);

pub const PyNumber_Absolute = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Absolute",
);

pub const PyNumber_Add = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Add",
);

pub const PyNumber_And = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_And",
);

pub const PyNumber_AsSsize_t = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyNumber_AsSsize_t",
);

pub const PyNumber_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyNumber_Check",
);

pub const PyNumber_Divmod = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Divmod",
);

pub const PyNumber_Float = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Float",
);

pub const PyNumber_FloorDivide = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_FloorDivide",
);

pub const PyNumber_InPlaceAdd = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceAdd",
);

pub const PyNumber_InPlaceAnd = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceAnd",
);

pub const PyNumber_InPlaceFloorDivide = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceFloorDivide",
);

pub const PyNumber_InPlaceLshift = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceLshift",
);

pub const PyNumber_InPlaceMatrixMultiply = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceMatrixMultiply",
);

pub const PyNumber_InPlaceMultiply = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceMultiply",
);

pub const PyNumber_InPlaceOr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceOr",
);

pub const PyNumber_InPlacePower = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlacePower",
);

pub const PyNumber_InPlaceRemainder = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceRemainder",
);

pub const PyNumber_InPlaceRshift = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceRshift",
);

pub const PyNumber_InPlaceSubtract = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceSubtract",
);

pub const PyNumber_InPlaceTrueDivide = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceTrueDivide",
);

pub const PyNumber_InPlaceXor = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_InPlaceXor",
);

pub const PyNumber_Index = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Index",
);

pub const PyNumber_Invert = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Invert",
);

pub const PyNumber_Long = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Long",
);

pub const PyNumber_Lshift = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Lshift",
);

pub const PyNumber_MatrixMultiply = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_MatrixMultiply",
);

pub const PyNumber_Multiply = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Multiply",
);

pub const PyNumber_Negative = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Negative",
);

pub const PyNumber_Or = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Or",
);

pub const PyNumber_Positive = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Positive",
);

pub const PyNumber_Power = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Power",
);

pub const PyNumber_Remainder = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Remainder",
);

pub const PyNumber_Rshift = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Rshift",
);

pub const PyNumber_Subtract = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Subtract",
);

pub const PyNumber_ToBase = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyNumber_ToBase",
);

pub const PyNumber_TrueDivide = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_TrueDivide",
);

pub const PyNumber_Xor = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyNumber_Xor",
);

pub const PyOS_AfterFork = c.Gate.declare(*const fn () callconv(.c) void, "PyOS_AfterFork");

pub const PyOS_AfterFork_Child = c.Gate.declare(
    *const fn () callconv(.c) void,
    "PyOS_AfterFork_Child",
);

pub const PyOS_AfterFork_Parent = c.Gate.declare(
    *const fn () callconv(.c) void,
    "PyOS_AfterFork_Parent",
);

pub const PyOS_BeforeFork = c.Gate.declare(*const fn () callconv(.c) void, "PyOS_BeforeFork");

pub const PyOS_FSPath = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyOS_FSPath",
);

pub const PyOS_InterruptOccurred = c.Gate.declare(
    *const fn () callconv(.c) c_int,
    "PyOS_InterruptOccurred",
);

pub const PyOS_double_to_string = c.Gate.declare(
    *const fn (f64, u8, c_int, c_int, [*c]c_int) callconv(.c) [*c]u8,
    "PyOS_double_to_string",
);

pub const PyOS_getsig = c.Gate.declare(
    *const fn (c_int) callconv(.c) ?*const anyopaque,
    "PyOS_getsig",
);

pub const PyOS_mystricmp = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8) callconv(.c) c_int,
    "PyOS_mystricmp",
);

pub const PyOS_mystrnicmp = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8, c.Py_ssize_t) callconv(.c) c_int,
    "PyOS_mystrnicmp",
);

pub const PyOS_setsig = c.Gate.declare(
    *const fn (c_int, ?*const anyopaque) callconv(.c) ?*const anyopaque,
    "PyOS_setsig",
);

pub const PyOS_snprintf = c.Gate.declare(
    *const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int,
    "PyOS_snprintf",
);

pub const PyOS_string_to_double = c.Gate.declare(
    *const fn ([*c]const u8, [*c][*c]u8, ?*c.PyObject) callconv(.c) f64,
    "PyOS_string_to_double",
);

pub const PyOS_strtol = c.Gate.declare(
    *const fn ([*c]const u8, [*c][*c]u8, c_int) callconv(.c) c_long,
    "PyOS_strtol",
);

pub const PyOS_strtoul = c.Gate.declare(
    *const fn ([*c]const u8, [*c][*c]u8, c_int) callconv(.c) c_ulong,
    "PyOS_strtoul",
);

pub const PyObject_ASCII = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_ASCII",
);

pub const PyObject_AsFileDescriptor = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_AsFileDescriptor",
);

pub const PyObject_Bytes = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Bytes",
);

pub const PyObject_Call = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Call",
);

pub const PyObject_CallFinalizerFromDealloc = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_CallFinalizerFromDealloc",
);

pub const PyObject_CallFunction = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "PyObject_CallFunction",
);

pub const PyObject_CallFunctionObjArgs = c.Gate.declare(
    *const fn (?*c.PyObject, ...) callconv(.c) ?*c.PyObject,
    "PyObject_CallFunctionObjArgs",
);

pub const PyObject_CallMethod = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "PyObject_CallMethod",
);

pub const PyObject_CallMethodObjArgs = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ...) callconv(.c) ?*c.PyObject,
    "PyObject_CallMethodObjArgs",
);

pub const PyObject_CallNoArgs = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_CallNoArgs",
);

pub const PyObject_CallObject = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_CallObject",
);

pub const PyObject_Calloc = c.Gate.declare(
    *const fn (usize, usize) callconv(.c) ?*anyopaque,
    "PyObject_Calloc",
);

pub const PyObject_CheckBuffer = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_CheckBuffer",
);

pub const PyObject_ClearWeakRefs = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyObject_ClearWeakRefs",
);

pub const PyObject_CopyData = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_CopyData",
);

pub const PyObject_DelAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_DelAttr",
);

pub const PyObject_DelAttrString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyObject_DelAttrString",
);

pub const PyObject_DelItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_DelItem",
);

pub const PyObject_DelItemString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyObject_DelItemString",
);

pub const PyObject_Dir = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Dir",
);

pub const PyObject_Format = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Format",
);

pub const PyObject_Free = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyObject_Free",
);

pub const PyObject_GC_Del = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyObject_GC_Del",
);

pub const PyObject_GC_IsFinalized = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_GC_IsFinalized",
);

pub const PyObject_GC_IsTracked = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_GC_IsTracked",
);

pub const PyObject_GC_Track = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyObject_GC_Track",
);

pub const PyObject_GC_UnTrack = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyObject_GC_UnTrack",
);

pub const PyObject_GenericGetAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_GenericGetAttr",
);

pub const PyObject_GenericGetDict = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) ?*c.PyObject,
    "PyObject_GenericGetDict",
);

pub const PyObject_GenericSetAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_GenericSetAttr",
);

pub const PyObject_GenericSetDict = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyObject_GenericSetDict",
);

pub const PyObject_GetAIter = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_GetAIter",
);

pub const PyObject_GetAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_GetAttr",
);

pub const PyObject_GetAttrString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyObject_GetAttrString",
);

pub const PyObject_GetBuffer = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_buffer, c_int) callconv(.c) c_int,
    "PyObject_GetBuffer",
);

pub const PyObject_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_GetItem",
);

pub const PyObject_GetIter = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_GetIter",
);

pub const PyObject_GetOptionalAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyObject_GetOptionalAttr",
);

pub const PyObject_GetOptionalAttrString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*?*c.PyObject) callconv(.c) c_int,
    "PyObject_GetOptionalAttrString",
);

pub const PyObject_GetTypeData = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyObject_GetTypeData",
);

pub const PyObject_GetTypeData_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyObject_GetTypeData_DuringGC",
);

pub const PyObject_HasAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_HasAttr",
);

pub const PyObject_HasAttrString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyObject_HasAttrString",
);

pub const PyObject_HasAttrStringWithError = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyObject_HasAttrStringWithError",
);

pub const PyObject_HasAttrWithError = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_HasAttrWithError",
);

pub const PyObject_Hash = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_hash_t,
    "PyObject_Hash",
);

pub const PyObject_HashNotImplemented = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_hash_t,
    "PyObject_HashNotImplemented",
);

pub const PyObject_Init = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Init",
);

pub const PyObject_InitVar = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyObject_InitVar",
);

pub const PyObject_IsInstance = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_IsInstance",
);

pub const PyObject_IsSubclass = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_IsSubclass",
);

pub const PyObject_IsTrue = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_IsTrue",
);

pub const PyObject_Length = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyObject_Length",
);

pub const PyObject_Malloc = c.Gate.declare(
    *const fn (usize) callconv(.c) ?*anyopaque,
    "PyObject_Malloc",
);

pub const PyObject_Not = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyObject_Not",
);

pub const PyObject_Realloc = c.Gate.declare(
    *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque,
    "PyObject_Realloc",
);

pub const PyObject_Repr = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Repr",
);

pub const PyObject_RichCompare = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyObject_RichCompare",
);

pub const PyObject_RichCompareBool = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) c_int,
    "PyObject_RichCompareBool",
);

pub const PyObject_SelfIter = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_SelfIter",
);

pub const PyObject_SetAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_SetAttr",
);

pub const PyObject_SetAttrString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_SetAttrString",
);

pub const PyObject_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyObject_SetItem",
);

pub const PyObject_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyObject_Size",
);

pub const PyObject_Str = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Str",
);

pub const PyObject_Type = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Type",
);

pub const PyObject_Vectorcall = c.Gate.declare(
    *const fn (?*c.PyObject, ?[*]const ?*c.PyObject, usize, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_Vectorcall",
);

pub const PyObject_VectorcallMethod = c.Gate.declare(
    *const fn (?*c.PyObject, ?[*]const ?*c.PyObject, usize, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyObject_VectorcallMethod",
);

pub const PySeqIter_New = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySeqIter_New",
);

pub const PySequence_Check = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PySequence_Check",
);

pub const PySequence_Concat = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySequence_Concat",
);

pub const PySequence_Contains = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PySequence_Contains",
);

pub const PySequence_Count = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PySequence_Count",
);

pub const PySequence_DelItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PySequence_DelItem",
);

pub const PySequence_DelSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) c_int,
    "PySequence_DelSlice",
);

pub const PySequence_Fast = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PySequence_Fast",
);

pub const PySequence_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PySequence_GetItem",
);

pub const PySequence_GetSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PySequence_GetSlice",
);

pub const PySequence_In = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PySequence_In",
);

pub const PySequence_InPlaceConcat = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySequence_InPlaceConcat",
);

pub const PySequence_InPlaceRepeat = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PySequence_InPlaceRepeat",
);

pub const PySequence_Index = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PySequence_Index",
);

pub const PySequence_Length = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PySequence_Length",
);

pub const PySequence_List = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySequence_List",
);

pub const PySequence_Repeat = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PySequence_Repeat",
);

pub const PySequence_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PySequence_SetItem",
);

pub const PySequence_SetSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PySequence_SetSlice",
);

pub const PySequence_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PySequence_Size",
);

pub const PySequence_Tuple = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySequence_Tuple",
);

pub const PySet_Add = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PySet_Add",
);

pub const PySet_Clear = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c_int, "PySet_Clear");

pub const PySet_Contains = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PySet_Contains",
);

pub const PySet_Discard = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PySet_Discard",
);

pub const PySet_New = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySet_New",
);

pub const PySet_Pop = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySet_Pop",
);

pub const PySet_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PySet_Size",
);

pub const PySlice_AdjustIndices = c.Gate.declare(
    *const fn (
        c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        c.Py_ssize_t,
    ) callconv(.c) c.Py_ssize_t,
    "PySlice_AdjustIndices",
);

pub const PySlice_GetIndices = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
    ) callconv(.c) c_int,
    "PySlice_GetIndices",
);

pub const PySlice_GetIndicesEx = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
    ) callconv(.c) c_int,
    "PySlice_GetIndicesEx",
);

pub const PySlice_New = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySlice_New",
);

pub const PySlice_Unpack = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
        [*c]c.Py_ssize_t,
    ) callconv(.c) c_int,
    "PySlice_Unpack",
);

pub const PyState_AddModule = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyModuleDef) callconv(.c) c_int,
    "PyState_AddModule",
);

pub const PyState_FindModule = c.Gate.declare(
    *const fn ([*c]c.PyModuleDef) callconv(.c) ?*c.PyObject,
    "PyState_FindModule",
);

pub const PyState_RemoveModule = c.Gate.declare(
    *const fn ([*c]c.PyModuleDef) callconv(.c) c_int,
    "PyState_RemoveModule",
);

pub const PyStructSequence_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyStructSequence_GetItem",
);

pub const PyStructSequence_New = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyStructSequence_New",
);

pub const PyStructSequence_NewType = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) ?*c.PyObject,
    "PyStructSequence_NewType",
);

pub const PyStructSequence_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, ?*c.PyObject) callconv(.c) void,
    "PyStructSequence_SetItem",
);

pub const PySys_Audit = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8, ...) callconv(.c) c_int,
    "PySys_Audit",
);

pub const PySys_AuditTuple = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PySys_AuditTuple",
);

pub const PySys_FormatStderr = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) void,
    "PySys_FormatStderr",
);

pub const PySys_FormatStdout = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) void,
    "PySys_FormatStdout",
);

pub const PySys_GetAttr = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PySys_GetAttr",
);

pub const PySys_GetAttrString = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PySys_GetAttrString",
);

pub const PySys_GetObject = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PySys_GetObject",
);

pub const PySys_GetOptionalAttr = c.Gate.declare(
    *const fn (?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PySys_GetOptionalAttr",
);

pub const PySys_GetOptionalAttrString = c.Gate.declare(
    *const fn ([*c]const u8, ?*?*c.PyObject) callconv(.c) c_int,
    "PySys_GetOptionalAttrString",
);

pub const PySys_GetXOptions = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PySys_GetXOptions",
);

pub const PySys_SetArgv = c.Gate.declare(
    *const fn (c_int, [*c][*c]wchar_t) callconv(.c) void,
    "PySys_SetArgv",
);

pub const PySys_SetArgvEx = c.Gate.declare(
    *const fn (c_int, [*c][*c]wchar_t, c_int) callconv(.c) void,
    "PySys_SetArgvEx",
);

pub const PySys_SetObject = c.Gate.declare(
    *const fn ([*c]const u8, ?*c.PyObject) callconv(.c) c_int,
    "PySys_SetObject",
);

pub const PySys_WriteStderr = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) void,
    "PySys_WriteStderr",
);

pub const PySys_WriteStdout = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) void,
    "PySys_WriteStdout",
);

pub const PyThreadState_Clear = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "PyThreadState_Clear",
);

pub const PyThreadState_Delete = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "PyThreadState_Delete",
);

pub const PyThreadState_Ensure = c.Gate.declare(
    *const fn (?*PyInterpreterGuard) callconv(.c) ?*anyopaque,
    "PyThreadState_Ensure",
);

pub const PyThreadState_EnsureFromView = c.Gate.declare(
    *const fn (?*PyInterpreterView) callconv(.c) ?*anyopaque,
    "PyThreadState_EnsureFromView",
);

pub const PyThreadState_Get = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyThreadState,
    "PyThreadState_Get",
);

pub const PyThreadState_GetDict = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyThreadState_GetDict",
);

pub const PyThreadState_GetFrame = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) ?*c.PyObject,
    "PyThreadState_GetFrame",
);

pub const PyThreadState_GetID = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) u64,
    "PyThreadState_GetID",
);

pub const PyThreadState_GetInterpreter = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) ?*c.PyInterpreterState,
    "PyThreadState_GetInterpreter",
);

pub const PyThreadState_New = c.Gate.declare(
    *const fn (?*c.PyInterpreterState) callconv(.c) ?*c.PyThreadState,
    "PyThreadState_New",
);

pub const PyThreadState_Release = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyThreadState_Release",
);

pub const PyThreadState_SetAsyncExc = c.Gate.declare(
    *const fn (c_ulong, ?*c.PyObject) callconv(.c) c_int,
    "PyThreadState_SetAsyncExc",
);

pub const PyThreadState_Swap = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) ?*c.PyThreadState,
    "PyThreadState_Swap",
);

pub const PyThread_GetInfo = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyObject,
    "PyThread_GetInfo",
);

pub const PyThread_ReInitTLS = c.Gate.declare(*const fn () callconv(.c) void, "PyThread_ReInitTLS");

pub const PyThread_acquire_lock = c.Gate.declare(
    *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    "PyThread_acquire_lock",
);

pub const PyThread_acquire_lock_timed = c.Gate.declare(
    *const fn (?*anyopaque, c_longlong, c_int) callconv(.c) c_uint,
    "PyThread_acquire_lock_timed",
);

pub const PyThread_allocate_lock = c.Gate.declare(
    *const fn () callconv(.c) ?*anyopaque,
    "PyThread_allocate_lock",
);

pub const PyThread_create_key = c.Gate.declare(
    *const fn () callconv(.c) c_int,
    "PyThread_create_key",
);

pub const PyThread_delete_key = c.Gate.declare(
    *const fn (c_int) callconv(.c) void,
    "PyThread_delete_key",
);

pub const PyThread_delete_key_value = c.Gate.declare(
    *const fn (c_int) callconv(.c) void,
    "PyThread_delete_key_value",
);

pub const PyThread_exit_thread = c.Gate.declare(
    *const fn () callconv(.c) noreturn,
    "PyThread_exit_thread",
);

pub const PyThread_free_lock = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyThread_free_lock",
);

pub const PyThread_get_key_value = c.Gate.declare(
    *const fn (c_int) callconv(.c) ?*anyopaque,
    "PyThread_get_key_value",
);

pub const PyThread_get_stacksize = c.Gate.declare(
    *const fn () callconv(.c) usize,
    "PyThread_get_stacksize",
);

pub const PyThread_get_thread_ident = c.Gate.declare(
    *const fn () callconv(.c) c_ulong,
    "PyThread_get_thread_ident",
);

pub const PyThread_get_thread_native_id = c.Gate.declare(
    *const fn () callconv(.c) c_ulong,
    "PyThread_get_thread_native_id",
);

pub const PyThread_init_thread = c.Gate.declare(
    *const fn () callconv(.c) void,
    "PyThread_init_thread",
);

pub const PyThread_release_lock = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) void,
    "PyThread_release_lock",
);

pub const PyThread_set_key_value = c.Gate.declare(
    *const fn (c_int, ?*anyopaque) callconv(.c) c_int,
    "PyThread_set_key_value",
);

pub const PyThread_set_stacksize = c.Gate.declare(
    *const fn (usize) callconv(.c) c_int,
    "PyThread_set_stacksize",
);

pub const PyThread_start_new_thread = c.Gate.declare(
    *const fn (?*const anyopaque, ?*anyopaque) callconv(.c) c_ulong,
    "PyThread_start_new_thread",
);

pub const PyThread_tss_alloc = c.Gate.declare(
    *const fn () callconv(.c) ?*Py_tss_t,
    "PyThread_tss_alloc",
);

pub const PyThread_tss_create = c.Gate.declare(
    *const fn (?*Py_tss_t) callconv(.c) c_int,
    "PyThread_tss_create",
);

pub const PyThread_tss_delete = c.Gate.declare(
    *const fn (?*Py_tss_t) callconv(.c) void,
    "PyThread_tss_delete",
);

pub const PyThread_tss_free = c.Gate.declare(
    *const fn (?*Py_tss_t) callconv(.c) void,
    "PyThread_tss_free",
);

pub const PyThread_tss_get = c.Gate.declare(
    *const fn (?*Py_tss_t) callconv(.c) ?*anyopaque,
    "PyThread_tss_get",
);

pub const PyThread_tss_is_created = c.Gate.declare(
    *const fn (?*Py_tss_t) callconv(.c) c_int,
    "PyThread_tss_is_created",
);

pub const PyThread_tss_set = c.Gate.declare(
    *const fn (?*Py_tss_t, ?*anyopaque) callconv(.c) c_int,
    "PyThread_tss_set",
);

pub const PyTraceBack_Here = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyTraceBack_Here",
);

pub const PyTraceBack_Print = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyTraceBack_Print",
);

pub const PyTuple_GetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyTuple_GetItem",
);

pub const PyTuple_GetSlice = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyTuple_GetSlice",
);

pub const PyTuple_New = c.Gate.declare(
    *const fn (c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyTuple_New",
);

pub const PyTuple_Pack = c.Gate.declare(
    *const fn (c.Py_ssize_t, ...) callconv(.c) ?*c.PyObject,
    "PyTuple_Pack",
);

pub const PyTuple_SetItem = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, ?*c.PyObject) callconv(.c) c_int,
    "PyTuple_SetItem",
);

pub const PyTuple_Size = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyTuple_Size",
);

pub const PyType_ClearCache = c.Gate.declare(*const fn () callconv(.c) c_uint, "PyType_ClearCache");

pub const PyType_Freeze = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyType_Freeze",
);

pub const PyType_FromMetaclass = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        ?*c.PyObject,
        [*c]c.PyType_Spec,
        ?*c.PyObject,
    ) callconv(.c) ?*c.PyObject,
    "PyType_FromMetaclass",
);

pub const PyType_FromModuleAndSpec = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyType_Spec, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_FromModuleAndSpec",
);

pub const PyType_FromSlots = c.Gate.declare(
    *const fn (?*anyopaque) callconv(.c) ?*c.PyObject,
    "PyType_FromSlots",
);

pub const PyType_FromSpec = c.Gate.declare(
    *const fn ([*c]c.PyType_Spec) callconv(.c) ?*c.PyObject,
    "PyType_FromSpec",
);

pub const PyType_FromSpecWithBases = c.Gate.declare(
    *const fn ([*c]c.PyType_Spec, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_FromSpecWithBases",
);

pub const PyType_GenericAlloc = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyType_GenericAlloc",
);

pub const PyType_GenericNew = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GenericNew",
);

pub const PyType_GetBaseByToken = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque, ?*?*c.PyObject) callconv(.c) c_int,
    "PyType_GetBaseByToken",
);

pub const PyType_GetBaseByToken_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque, ?*?*c.PyObject) callconv(.c) c_int,
    "PyType_GetBaseByToken_DuringGC",
);

pub const PyType_GetFlags = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_ulong,
    "PyType_GetFlags",
);

pub const PyType_GetFullyQualifiedName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetFullyQualifiedName",
);

pub const PyType_GetModule = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetModule",
);

pub const PyType_GetModuleByDef = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.PyModuleDef) callconv(.c) ?*c.PyObject,
    "PyType_GetModuleByDef",
);

pub const PyType_GetModuleByToken = c.Gate.declare(
    *const fn (?*c.PyObject, ?*const anyopaque) callconv(.c) ?*c.PyObject,
    "PyType_GetModuleByToken",
);

pub const PyType_GetModuleByToken_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject, ?*const anyopaque) callconv(.c) ?*c.PyObject,
    "PyType_GetModuleByToken_DuringGC",
);

pub const PyType_GetModuleName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetModuleName",
);

pub const PyType_GetModuleState = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyType_GetModuleState",
);

pub const PyType_GetModuleState_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*anyopaque,
    "PyType_GetModuleState_DuringGC",
);

pub const PyType_GetModule_DuringGC = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetModule_DuringGC",
);

pub const PyType_GetName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetName",
);

pub const PyType_GetQualName = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyType_GetQualName",
);

pub const PyType_GetSlot = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*anyopaque,
    "PyType_GetSlot",
);

pub const PyType_GetTypeDataSize = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyType_GetTypeDataSize",
);

pub const PyType_IsSubtype = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyType_IsSubtype",
);

pub const PyType_Modified = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) void,
    "PyType_Modified",
);

pub const PyType_Ready = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyType_Ready",
);

pub const PyUnicodeDecodeError_Create = c.Gate.declare(
    *const fn (
        [*c]const u8,
        [*c]const u8,
        c.Py_ssize_t,
        c.Py_ssize_t,
        c.Py_ssize_t,
        [*c]const u8,
    ) callconv(.c) ?*c.PyObject,
    "PyUnicodeDecodeError_Create",
);

pub const PyUnicodeDecodeError_GetEncoding = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeDecodeError_GetEncoding",
);

pub const PyUnicodeDecodeError_GetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeDecodeError_GetEnd",
);

pub const PyUnicodeDecodeError_GetObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeDecodeError_GetObject",
);

pub const PyUnicodeDecodeError_GetReason = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeDecodeError_GetReason",
);

pub const PyUnicodeDecodeError_GetStart = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeDecodeError_GetStart",
);

pub const PyUnicodeDecodeError_SetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeDecodeError_SetEnd",
);

pub const PyUnicodeDecodeError_SetReason = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyUnicodeDecodeError_SetReason",
);

pub const PyUnicodeDecodeError_SetStart = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeDecodeError_SetStart",
);

pub const PyUnicodeEncodeError_GetEncoding = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeEncodeError_GetEncoding",
);

pub const PyUnicodeEncodeError_GetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeEncodeError_GetEnd",
);

pub const PyUnicodeEncodeError_GetObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeEncodeError_GetObject",
);

pub const PyUnicodeEncodeError_GetReason = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeEncodeError_GetReason",
);

pub const PyUnicodeEncodeError_GetStart = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeEncodeError_GetStart",
);

pub const PyUnicodeEncodeError_SetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeEncodeError_SetEnd",
);

pub const PyUnicodeEncodeError_SetReason = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyUnicodeEncodeError_SetReason",
);

pub const PyUnicodeEncodeError_SetStart = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeEncodeError_SetStart",
);

pub const PyUnicodeTranslateError_GetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeTranslateError_GetEnd",
);

pub const PyUnicodeTranslateError_GetObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeTranslateError_GetObject",
);

pub const PyUnicodeTranslateError_GetReason = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicodeTranslateError_GetReason",
);

pub const PyUnicodeTranslateError_GetStart = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeTranslateError_GetStart",
);

pub const PyUnicodeTranslateError_SetEnd = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeTranslateError_SetEnd",
);

pub const PyUnicodeTranslateError_SetReason = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyUnicodeTranslateError_SetReason",
);

pub const PyUnicodeTranslateError_SetStart = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicodeTranslateError_SetStart",
);

pub const PyUnicode_Append = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyUnicode_Append",
);

pub const PyUnicode_AppendAndDel = c.Gate.declare(
    *const fn (?*?*c.PyObject, ?*c.PyObject) callconv(.c) void,
    "PyUnicode_AppendAndDel",
);

pub const PyUnicode_AsASCIIString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsASCIIString",
);

pub const PyUnicode_AsCharmapString = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsCharmapString",
);

pub const PyUnicode_AsEncodedString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsEncodedString",
);

pub const PyUnicode_AsLatin1String = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsLatin1String",
);

pub const PyUnicode_AsRawUnicodeEscapeString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsRawUnicodeEscapeString",
);

pub const PyUnicode_AsUCS4 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]u32, c.Py_ssize_t, c_int) callconv(.c) [*c]u32,
    "PyUnicode_AsUCS4",
);

pub const PyUnicode_AsUCS4Copy = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) [*c]u32,
    "PyUnicode_AsUCS4Copy",
);

pub const PyUnicode_AsUTF16String = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsUTF16String",
);

pub const PyUnicode_AsUTF32String = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsUTF32String",
);

pub const PyUnicode_AsUTF8AndSize = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) [*c]const u8,
    "PyUnicode_AsUTF8AndSize",
);

pub const PyUnicode_AsUTF8String = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsUTF8String",
);

pub const PyUnicode_AsUnicodeEscapeString = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_AsUnicodeEscapeString",
);

pub const PyUnicode_AsWideChar = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]wchar_t, c.Py_ssize_t) callconv(.c) c.Py_ssize_t,
    "PyUnicode_AsWideChar",
);

pub const PyUnicode_AsWideCharString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]c.Py_ssize_t) callconv(.c) [*c]wchar_t,
    "PyUnicode_AsWideCharString",
);

pub const PyUnicode_BuildEncodingMap = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_BuildEncodingMap",
);

pub const PyUnicode_Compare = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyUnicode_Compare",
);

pub const PyUnicode_CompareWithASCIIString = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyUnicode_CompareWithASCIIString",
);

pub const PyUnicode_Concat = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_Concat",
);

pub const PyUnicode_Contains = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyUnicode_Contains",
);

pub const PyUnicode_Count = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) c.Py_ssize_t,
    "PyUnicode_Count",
);

pub const PyUnicode_Decode = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_Decode",
);

pub const PyUnicode_DecodeASCII = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeASCII",
);

pub const PyUnicode_DecodeCharmap = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, ?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeCharmap",
);

pub const PyUnicode_DecodeFSDefault = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeFSDefault",
);

pub const PyUnicode_DecodeFSDefaultAndSize = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeFSDefaultAndSize",
);

pub const PyUnicode_DecodeLatin1 = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeLatin1",
);

pub const PyUnicode_DecodeLocale = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeLocale",
);

pub const PyUnicode_DecodeLocaleAndSize = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeLocaleAndSize",
);

pub const PyUnicode_DecodeRawUnicodeEscape = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeRawUnicodeEscape",
);

pub const PyUnicode_DecodeUTF16 = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8, [*c]c_int) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF16",
);

pub const PyUnicode_DecodeUTF16Stateful = c.Gate.declare(
    *const fn (
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
        [*c]c_int,
        [*c]c.Py_ssize_t,
    ) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF16Stateful",
);

pub const PyUnicode_DecodeUTF32 = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8, [*c]c_int) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF32",
);

pub const PyUnicode_DecodeUTF32Stateful = c.Gate.declare(
    *const fn (
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
        [*c]c_int,
        [*c]c.Py_ssize_t,
    ) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF32Stateful",
);

pub const PyUnicode_DecodeUTF7 = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF7",
);

pub const PyUnicode_DecodeUTF7Stateful = c.Gate.declare(
    *const fn (
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
        [*c]c.Py_ssize_t,
    ) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF7Stateful",
);

pub const PyUnicode_DecodeUTF8 = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF8",
);

pub const PyUnicode_DecodeUTF8Stateful = c.Gate.declare(
    *const fn (
        [*c]const u8,
        c.Py_ssize_t,
        [*c]const u8,
        [*c]c.Py_ssize_t,
    ) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUTF8Stateful",
);

pub const PyUnicode_DecodeUnicodeEscape = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_DecodeUnicodeEscape",
);

pub const PyUnicode_EncodeFSDefault = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_EncodeFSDefault",
);

pub const PyUnicode_EncodeLocale = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_EncodeLocale",
);

pub const PyUnicode_Equal = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "PyUnicode_Equal",
);

pub const PyUnicode_EqualToUTF8 = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8) callconv(.c) c_int,
    "PyUnicode_EqualToUTF8",
);

pub const PyUnicode_EqualToUTF8AndSize = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicode_EqualToUTF8AndSize",
);

pub const PyUnicode_FSConverter = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyUnicode_FSConverter",
);

pub const PyUnicode_FSDecoder = c.Gate.declare(
    *const fn (?*c.PyObject, ?*anyopaque) callconv(.c) c_int,
    "PyUnicode_FSDecoder",
);

pub const PyUnicode_Find = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        ?*c.PyObject,
        c.Py_ssize_t,
        c.Py_ssize_t,
        c_int,
    ) callconv(.c) c.Py_ssize_t,
    "PyUnicode_Find",
);

pub const PyUnicode_FindChar = c.Gate.declare(
    *const fn (?*c.PyObject, u32, c.Py_ssize_t, c.Py_ssize_t, c_int) callconv(.c) c.Py_ssize_t,
    "PyUnicode_FindChar",
);

pub const PyUnicode_Format = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_Format",
);

pub const PyUnicode_FromEncodedObject = c.Gate.declare(
    *const fn (?*c.PyObject, [*c]const u8, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromEncodedObject",
);

pub const PyUnicode_FromFormat = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromFormat",
);

pub const PyUnicode_FromObject = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromObject",
);

pub const PyUnicode_FromOrdinal = c.Gate.declare(
    *const fn (c_int) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromOrdinal",
);

pub const PyUnicode_FromString = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromString",
);

pub const PyUnicode_FromStringAndSize = c.Gate.declare(
    *const fn ([*c]const u8, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromStringAndSize",
);

pub const PyUnicode_FromWideChar = c.Gate.declare(
    *const fn ([*c]const wchar_t, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_FromWideChar",
);

pub const PyUnicode_GetDefaultEncoding = c.Gate.declare(
    *const fn () callconv(.c) [*c]const u8,
    "PyUnicode_GetDefaultEncoding",
);

pub const PyUnicode_GetLength = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "PyUnicode_GetLength",
);

pub const PyUnicode_InternFromString = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_InternFromString",
);

pub const PyUnicode_InternInPlace = c.Gate.declare(
    *const fn (?*?*c.PyObject) callconv(.c) void,
    "PyUnicode_InternInPlace",
);

pub const PyUnicode_IsIdentifier = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "PyUnicode_IsIdentifier",
);

pub const PyUnicode_Join = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_Join",
);

pub const PyUnicode_Partition = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_Partition",
);

pub const PyUnicode_RPartition = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyUnicode_RPartition",
);

pub const PyUnicode_RSplit = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_RSplit",
);

pub const PyUnicode_ReadChar = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) u32,
    "PyUnicode_ReadChar",
);

pub const PyUnicode_Replace = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_Replace",
);

pub const PyUnicode_Resize = c.Gate.declare(
    *const fn (?*?*c.PyObject, c.Py_ssize_t) callconv(.c) c_int,
    "PyUnicode_Resize",
);

pub const PyUnicode_RichCompare = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyUnicode_RichCompare",
);

pub const PyUnicode_Split = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_Split",
);

pub const PyUnicode_Splitlines = c.Gate.declare(
    *const fn (?*c.PyObject, c_int) callconv(.c) ?*c.PyObject,
    "PyUnicode_Splitlines",
);

pub const PyUnicode_Substring = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, c.Py_ssize_t) callconv(.c) ?*c.PyObject,
    "PyUnicode_Substring",
);

pub const PyUnicode_Tailmatch = c.Gate.declare(
    *const fn (
        ?*c.PyObject,
        ?*c.PyObject,
        c.Py_ssize_t,
        c.Py_ssize_t,
        c_int,
    ) callconv(.c) c.Py_ssize_t,
    "PyUnicode_Tailmatch",
);

pub const PyUnicode_Translate = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, [*c]const u8) callconv(.c) ?*c.PyObject,
    "PyUnicode_Translate",
);

pub const PyUnicode_WriteChar = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t, u32) callconv(.c) c_int,
    "PyUnicode_WriteChar",
);

pub const PyVectorcall_Call = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyVectorcall_Call",
);

pub const PyVectorcall_NARGS = c.Gate.declare(
    *const fn (usize) callconv(.c) c.Py_ssize_t,
    "PyVectorcall_NARGS",
);

pub const PyWeakref_GetRef = c.Gate.declare(
    *const fn (?*c.PyObject, ?*?*c.PyObject) callconv(.c) c_int,
    "PyWeakref_GetRef",
);

pub const PyWeakref_NewProxy = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyWeakref_NewProxy",
);

pub const PyWeakref_NewRef = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyWeakref_NewRef",
);

pub const PyWrapper_New = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "PyWrapper_New",
);

pub const Py_AddPendingCall = c.Gate.declare(
    *const fn (?*const anyopaque, ?*anyopaque) callconv(.c) c_int,
    "Py_AddPendingCall",
);

pub const Py_AtExit = c.Gate.declare(*const fn (?*const anyopaque) callconv(.c) c_int, "Py_AtExit");

pub const Py_BuildValue = c.Gate.declare(
    *const fn ([*c]const u8, ...) callconv(.c) ?*c.PyObject,
    "Py_BuildValue",
);

pub const Py_BytesMain = c.Gate.declare(
    *const fn (c_int, [*c][*c]u8) callconv(.c) c_int,
    "Py_BytesMain",
);

pub const Py_CompileString = c.Gate.declare(
    *const fn ([*c]const u8, [*c]const u8, c_int) callconv(.c) ?*c.PyObject,
    "Py_CompileString",
);

pub const Py_DecRef = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) void, "Py_DecRef");

pub const Py_DecodeLocale = c.Gate.declare(
    *const fn ([*c]const u8, [*c]usize) callconv(.c) [*c]wchar_t,
    "Py_DecodeLocale",
);

pub const Py_EncodeLocale = c.Gate.declare(
    *const fn ([*c]const wchar_t, [*c]usize) callconv(.c) [*c]u8,
    "Py_EncodeLocale",
);

pub const Py_EndInterpreter = c.Gate.declare(
    *const fn (?*c.PyThreadState) callconv(.c) void,
    "Py_EndInterpreter",
);

pub const Py_EnterRecursiveCall = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) c_int,
    "Py_EnterRecursiveCall",
);

pub const Py_Exit = c.Gate.declare(*const fn (c_int) callconv(.c) noreturn, "Py_Exit");

pub const Py_FatalError = c.Gate.declare(
    *const fn ([*c]const u8) callconv(.c) noreturn,
    "Py_FatalError",
);

pub const Py_Finalize = c.Gate.declare(*const fn () callconv(.c) void, "Py_Finalize");
pub const Py_FinalizeEx = c.Gate.declare(*const fn () callconv(.c) c_int, "Py_FinalizeEx");

pub const Py_GenericAlias = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) ?*c.PyObject,
    "Py_GenericAlias",
);

pub const Py_GetBuildInfo = c.Gate.declare(
    *const fn () callconv(.c) [*c]const u8,
    "Py_GetBuildInfo",
);

pub const Py_GetCompiler = c.Gate.declare(*const fn () callconv(.c) [*c]const u8, "Py_GetCompiler");

pub const Py_GetConstant = c.Gate.declare(
    *const fn (c_uint) callconv(.c) ?*c.PyObject,
    "Py_GetConstant",
);

pub const Py_GetConstantBorrowed = c.Gate.declare(
    *const fn (c_uint) callconv(.c) ?*c.PyObject,
    "Py_GetConstantBorrowed",
);

pub const Py_GetCopyright = c.Gate.declare(
    *const fn () callconv(.c) [*c]const u8,
    "Py_GetCopyright",
);

pub const Py_GetPlatform = c.Gate.declare(*const fn () callconv(.c) [*c]const u8, "Py_GetPlatform");

pub const Py_GetRecursionLimit = c.Gate.declare(
    *const fn () callconv(.c) c_int,
    "Py_GetRecursionLimit",
);

pub const Py_GetVersion = c.Gate.declare(*const fn () callconv(.c) [*c]const u8, "Py_GetVersion");

pub const Py_IS_TYPE = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "Py_IS_TYPE",
);

pub const Py_IncRef = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) void, "Py_IncRef");
pub const Py_Initialize = c.Gate.declare(*const fn () callconv(.c) void, "Py_Initialize");
pub const Py_InitializeEx = c.Gate.declare(*const fn (c_int) callconv(.c) void, "Py_InitializeEx");

pub const Py_Is = c.Gate.declare(
    *const fn (?*c.PyObject, ?*c.PyObject) callconv(.c) c_int,
    "Py_Is",
);

pub const Py_IsFalse = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c_int, "Py_IsFalse");
pub const Py_IsFinalizing = c.Gate.declare(*const fn () callconv(.c) c_int, "Py_IsFinalizing");
pub const Py_IsInitialized = c.Gate.declare(*const fn () callconv(.c) c_int, "Py_IsInitialized");
pub const Py_IsNone = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c_int, "Py_IsNone");
pub const Py_IsTrue = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c_int, "Py_IsTrue");

pub const Py_LeaveRecursiveCall = c.Gate.declare(
    *const fn () callconv(.c) void,
    "Py_LeaveRecursiveCall",
);

pub const Py_Main = c.Gate.declare(
    *const fn (c_int, [*c][*c]wchar_t) callconv(.c) c_int,
    "Py_Main",
);

pub const Py_MakePendingCalls = c.Gate.declare(
    *const fn () callconv(.c) c_int,
    "Py_MakePendingCalls",
);

pub const Py_NewInterpreter = c.Gate.declare(
    *const fn () callconv(.c) ?*c.PyThreadState,
    "Py_NewInterpreter",
);

pub const Py_NewRef = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "Py_NewRef",
);

pub const Py_PACK_FULL_VERSION = c.Gate.declare(
    *const fn (c_int, c_int, c_int, c_int, c_int) callconv(.c) u32,
    "Py_PACK_FULL_VERSION",
);

pub const Py_PACK_VERSION = c.Gate.declare(
    *const fn (c_int, c_int) callconv(.c) u32,
    "Py_PACK_VERSION",
);

pub const Py_REFCNT = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t,
    "Py_REFCNT",
);

pub const Py_ReprEnter = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) c_int,
    "Py_ReprEnter",
);

pub const Py_ReprLeave = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) void, "Py_ReprLeave");

pub const Py_SET_SIZE = c.Gate.declare(
    *const fn (?*c.PyObject, c.Py_ssize_t) callconv(.c) void,
    "Py_SET_SIZE",
);

pub const Py_SIZE = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) c.Py_ssize_t, "Py_SIZE");

pub const Py_SetProgramName = c.Gate.declare(
    *const fn ([*c]const wchar_t) callconv(.c) void,
    "Py_SetProgramName",
);

pub const Py_SetPythonHome = c.Gate.declare(
    *const fn ([*c]const wchar_t) callconv(.c) void,
    "Py_SetPythonHome",
);

pub const Py_SetRecursionLimit = c.Gate.declare(
    *const fn (c_int) callconv(.c) void,
    "Py_SetRecursionLimit",
);

pub const Py_TYPE = c.Gate.declare(*const fn (?*c.PyObject) callconv(.c) ?*c.PyObject, "Py_TYPE");

pub const Py_XNewRef = c.Gate.declare(
    *const fn (?*c.PyObject) callconv(.c) ?*c.PyObject,
    "Py_XNewRef",
);
