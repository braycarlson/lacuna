import array
import asyncio
import ctypes
import datetime as dt
import functools
import gc
import inspect
import itertools
import operator
import pathlib
import pickle
import struct
import sys
import sysconfig
import tempfile
import zoneinfo

import pytest

from collections.abc import Callable, Iterator
from types import ModuleType
from typing import NoReturn

if hasattr(sys, 'gettotalrefcount'):
    import _testcapi

if sys.implementation.name == 'cpython':
    if sys.version_info >= (3, 14):
        from concurrent import interpreters
    elif sys.version_info >= (3, 13):
        import _interpreters as interpreters
    else:
        import _xxsubinterpreters as interpreters


BINARY_OPERATORS = (
    operator.add,
    operator.and_,
    operator.contains,
    operator.eq,
    operator.floordiv,
    operator.ge,
    operator.getitem,
    operator.gt,
    operator.le,
    operator.lshift,
    operator.lt,
    operator.matmul,
    operator.mod,
    operator.mul,
    operator.ne,
    operator.or_,
    operator.pow,
    operator.rshift,
    operator.sub,
    operator.truediv,
    operator.xor,
    divmod,
)
CALL_COUNT = 100
CPYTHON = sys.implementation.name == 'cpython'
FAULT_PROBE_BYTES = 64
FAULT_SETTLE_COUNT = 8
FAULT_START_MAX = 1024
FAULT_SWEEP_COUNT = 10
HOSTILE_ARGUMENT_COUNT_MAX = 4
LEAK_ROUND_COUNT = 4
SIZED_LENGTH = 2
UNARY_OPERATORS = (
    abs,
    bool,
    float,
    hash,
    int,
    iter,
    len,
    operator.index,
    operator.invert,
    operator.neg,
    operator.pos,
    repr,
    str,
)
WARMUP_ROUND_COUNT = 3
ZONE_KEY = 'Lacuna/Central'
ZONE_OFFSET_SECONDS = 5400

counts_references = pytest.mark.skipif(
    not CPYTHON,
    reason='counts references with sys.getrefcount, which only CPython provides',
)
pythonapi = pytest.mark.skipif(
    not CPYTHON,
    reason='calls the C API through ctypes.pythonapi, which only CPython provides',
)
subinterpreters = pytest.mark.skipif(
    not CPYTHON,
    reason='creates subinterpreters, which only CPython provides',
)


def zone_install() -> str:
    assert ZONE_KEY.count('/') == 1

    root = pathlib.Path(tempfile.mkdtemp())
    region, city = ZONE_KEY.split('/')
    (root / region).mkdir()

    header = b'TZif' + bytes(16) + struct.pack('>6l', 0, 0, 0, 0, 1, 4)
    information = struct.pack('>lBB', ZONE_OFFSET_SECONDS, 0, 0) + b'LCT\0'
    (root / region / city).write_bytes(header + information)
    zoneinfo.reset_tzpath(to=[str(root)])

    return ZONE_KEY


def detector_check() -> None:
    sentinel = object()
    handle = ctypes.py_object(sentinel)
    acquire = functools.partial(ctypes.pythonapi.Py_IncRef, handle)
    release = functools.partial(ctypes.pythonapi.Py_DecRef, handle)
    balanced = functools.partial(id, sentinel)
    leaking = functools.partial(fault_leak, handle)
    masking = functools.partial(fault_check, fault_mask)

    assert imbalance(acquire), 'the leak detector missed a deliberate leak'
    assert imbalance(release), 'the leak detector missed a deliberate over-release'
    assert not imbalance(balanced), 'the leak detector flagged balanced code'
    assert imbalance(leaking), 'the fault sweep missed a leak on an allocation failure path'

    raised(SystemError, masking)


def fault_check(run: Callable[[], object]) -> None:
    assert callable(run)
    assert hasattr(sys, 'gettotalrefcount'), 'a fault sweep needs a debug build of CPython'

    fault_sweep(single=True, run=run)
    fault_sweep(single=False, run=run)


def fault_failed(*, start: int, stop: int, run: Callable[[], object]) -> bool:
    assert start >= 0
    assert stop == 0 or stop > start

    _testcapi.set_nomemory(start, stop)

    try:
        run()
    except MemoryError:
        result = True
    except Exception as error:
        error.add_note(f'raised instead of MemoryError when allocation {start} failed')
        raise
    else:
        result = False
    finally:
        _testcapi.remove_mem_hooks()

    return result


def fault_leak(handle: ctypes.py_object) -> None:
    assert handle.value is not None

    try:
        bytearray(FAULT_PROBE_BYTES)
    except MemoryError:
        ctypes.pythonapi.Py_IncRef(handle)


def fault_mask() -> None:
    assert FAULT_PROBE_BYTES > 0

    try:
        bytearray(FAULT_PROBE_BYTES)
    except MemoryError:
        message = 'an allocation failure surfaced as the wrong exception'
        raise SystemError(message) from None


def fault_sweep(*, single: bool, run: Callable[[], object]) -> None:
    assert callable(run)
    assert FAULT_SETTLE_COUNT < FAULT_START_MAX

    settled_count = 0

    for start in range(FAULT_START_MAX):
        stop = start + 1 if single else 0
        failed = fault_failed(start=start, stop=stop, run=run)
        settled_count = 0 if failed else settled_count + 1

        if settled_count == FAULT_SETTLE_COUNT:
            return

    message = f'{run} still failed allocations after {FAULT_START_MAX} fault starts'
    raise AssertionError(message)


def hostile_check(call: Callable[[], object]) -> None:
    assert callable(call)
    assert not isinstance(call, type)

    try:
        result = call()

        if inspect.iscoroutine(result):
            asyncio.run(result)
    except Exception as error:
        if isinstance(error, SystemError):
            raise


def hostile_objects() -> list[object]:
    refusing = {'__eq__': refuse, '__float__': refuse, '__hash__': object.__hash__}
    unsized = {'__iter__': refuse_after_first, '__len__': refuse}
    sized = {'__iter__': refuse_after_first, '__len__': sized_length}
    wrong_index = {'__index__': wrong}
    wrong_path = {'__fspath__': wrong}
    offset_raising = type('OffsetRaising', (dt.tzinfo,), {'utcoffset': refuse})
    offset_wrong = type('OffsetWrong', (dt.tzinfo,), {'utcoffset': wrong})
    offset_fraction = dt.timezone(dt.timedelta(microseconds=1))
    text_subclass = type('TextSubclass', (str,), {'__slots__': ()})
    result = [
        type('Refusing', (), refusing)(),
        type('IndexRefusing', (), {'__index__': refuse})(),
        type('IndexWrong', (), wrong_index)(),
        type('Unsized', (), unsized)(),
        type('Sized', (), sized)(),
        type('PathWrong', (), wrong_path)(),
        text_subclass('fast'),
        dt.datetime(2026, 1, 1, tzinfo=offset_raising()),
        dt.datetime(2026, 1, 1, tzinfo=offset_wrong()),
        dt.datetime(2026, 1, 1, tzinfo=offset_fraction),
    ]

    assert type(result[0]).__eq__ is refuse
    assert all(item.utcoffset is not None for item in result[-3:])

    return result


def hostile_scalars() -> list[object]:
    numbers = array.array('d', [1.0, 2.0, 3.0, 4.0])
    naive_minimum = dt.datetime.min.replace(tzinfo=dt.UTC).replace(tzinfo=None)
    result = [
        None,
        True,
        Ellipsis,
        NotImplemented,
        0,
        -1,
        255,
        2**63,
        -(2**63) - 1,
        2**2000,
        -0.0,
        float('nan'),
        float('inf'),
        complex(1, 2),
        '',
        '\0',
        '\ud800',
        'x' * 4096,
        b'',
        b'\0',
        bytearray(16),
        memoryview(b'abcd')[::2],
        memoryview(numbers).toreadonly(),
        numbers,
        array.array('q', [1, 2]),
        array.array('f', [1.0]),
        pathlib.Path('a.b'),
        dt.date.max,
        naive_minimum,
        dt.time(1, tzinfo=dt.UTC),
        dt.timedelta.max,
        object(),
        type,
        abs,
    ]

    assert result[0] is None
    assert len(result) > HOSTILE_ARGUMENT_COUNT_MAX

    return result


def hostile_targets(module: ModuleType, instances: list[object]) -> list[Callable[..., object]]:
    assert instances
    assert all(type(instance).__module__ == module.__name__ for instance in instances)

    targets = [member for name, member in vars(module).items() if module_target(module, name)]

    for instance in instances:
        targets.extend(instance_targets(instance))

    assert all(callable(target) for target in targets)

    return targets


def hostile_values() -> list[object]:
    looped: list[object] = []
    looped.append(looped)

    containers = [
        range(3),
        looped,
        [1, 'two', 3.0],
        (1, 2),
        {'horizontal': 'x'},
        {1: 2},
        frozenset({1, 2}),
        {'a', 'b'},
    ]

    result = hostile_scalars() + containers + hostile_objects()

    assert looped[0] is looped
    assert len(result) > len(containers)

    return result


def imbalance(run: Callable[[], object], *, faults: bool = True) -> list[int]:
    assert callable(run)
    assert hasattr(sys, 'gettotalrefcount'), 'a leak check needs a debug build of CPython'

    deltas = reference_deltas(call_count=CALL_COUNT, run=run)

    if skewed(deltas, call_count=CALL_COUNT):
        return deltas

    if not faults:
        return []

    sweep = functools.partial(fault_check, run)
    deltas = reference_deltas(call_count=FAULT_SWEEP_COUNT, run=sweep)

    if skewed(deltas, call_count=FAULT_SWEEP_COUNT):
        return deltas

    return []


def instance_targets(instance: object) -> list[Callable[..., object]]:
    assert instance is not None
    assert not isinstance(instance, type)

    targets: list[Callable[..., object]] = []
    kind = type(instance)

    for name, member in vars(kind).items():
        attribute = getattr(instance, name)

        if inspect.isgetsetdescriptor(member):
            targets.append(functools.partial(setattr, instance, name))
        elif name.startswith('__'):
            continue
        elif callable(attribute):
            targets.append(attribute)
        else:
            continue

    for binary in BINARY_OPERATORS:
        targets.append(functools.partial(binary, instance))
        targets.append(functools.partial(reflected, instance=instance, binary=binary))

    targets.extend(functools.partial(unary, instance) for unary in UNARY_OPERATORS)
    targets.append(functools.partial(operator.setitem, instance))
    targets.append(functools.partial(operator.delitem, instance))

    return targets


def module_target(module: ModuleType, name: str) -> bool:
    assert isinstance(module, ModuleType)
    assert name in vars(module)

    member = vars(module)[name]

    if isinstance(member, ModuleType):
        return False

    if name.startswith('__'):
        return False

    if not callable(member):
        return False

    if not isinstance(member, type):
        return True

    return not issubclass(member, BaseException)


def pytest_sessionstart() -> None:
    if hasattr(sys, 'gettotalrefcount'):
        detector_check()

    if '--with-thread-sanitizer' in (sysconfig.get_config_var('CONFIG_ARGS') or ''):
        tsan_check()


def raised(expected: type[Exception], call: Callable[[], object]) -> None:
    assert issubclass(expected, Exception)
    assert callable(call)

    try:
        call()
    except expected:
        pass
    else:
        message = f'{call} did not raise {expected.__name__}'
        raise AssertionError(message)


def raising(expected: type[Exception], call: Callable[[], object]) -> Callable[[], None]:
    assert issubclass(expected, Exception)
    assert callable(call)

    return functools.partial(raised, expected, call)


def reduction_round(instance: object) -> object:
    assert instance is not None
    assert not isinstance(instance, type)

    restore, arguments, *_ = instance.__reduce_ex__(pickle.HIGHEST_PROTOCOL)

    assert callable(restore)

    return restore(*arguments)


def reference_deltas(*, call_count: int, run: Callable[[], object]) -> list[int]:
    assert callable(run)
    assert call_count > 1

    deltas = []

    for _ in range(WARMUP_ROUND_COUNT * call_count):
        run()

    gc.collect()
    references_previous = sys.gettotalrefcount()

    for _ in range(LEAK_ROUND_COUNT):
        for _ in range(call_count):
            run()

        gc.collect()

        references = sys.gettotalrefcount()
        delta = references - references_previous
        deltas.append(delta)
        references_previous = references

    assert len(deltas) == LEAK_ROUND_COUNT

    return deltas


def reflected(
    other: object,
    instance: object,
    binary: Callable[[object, object], object],
) -> object:
    assert instance is not other
    assert callable(binary)

    return binary(other, instance)


def refuse(*arguments: object) -> NoReturn:
    assert arguments, 'a refusing hook receives at least its instance'
    assert arguments[0] is not None

    message = f'{type(arguments[0]).__name__} refused'
    raise RuntimeError(message)


def refuse_after_first(instance: object) -> Iterator[object]:
    assert instance is not None
    assert not isinstance(instance, type)

    return itertools.chain([1], map(refuse, [instance]))


def sized_length(instance: object) -> int:
    assert instance is not None
    assert not isinstance(instance, type)

    return SIZED_LENGTH


def skewed(deltas: list[int], *, call_count: int) -> bool:
    assert len(deltas) == LEAK_ROUND_COUNT
    assert call_count > 1

    threshold = call_count // 2

    if all(delta >= threshold for delta in deltas):
        return True

    return all(delta <= -threshold for delta in deltas)


def subinterpreter_run(source: str) -> None:
    assert source.endswith('\n')

    if sys.version_info >= (3, 14):
        interpreter = interpreters.create()

        try:
            interpreter.exec(source)
        finally:
            interpreter.close()
    elif sys.version_info >= (3, 13):
        identifier = interpreters.create('isolated')

        try:
            failure = interpreters.exec(identifier, source)
        finally:
            interpreters.destroy(identifier)

        assert failure is None
    else:
        identifier = interpreters.create(isolated=True)

        try:
            interpreters.run_string(identifier, source)
        finally:
            interpreters.destroy(identifier)


def tsan_check() -> None:
    directory = pathlib.Path(__file__).resolve().parent
    binaries = sorted(directory.rglob('*.so'))

    assert binaries, f'no extension binary sits beside {__file__}'

    for binary in binaries:
        message = f'{binary.name} carries no ThreadSanitizer instrumentation'

        assert b'__tsan_func_entry' in binary.read_bytes(), message


def wrong(*arguments: object) -> object:
    assert arguments, 'a wrong hook receives at least its instance'
    assert arguments[0] is not None

    return arguments
