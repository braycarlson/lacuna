import array
import asyncio
import concurrent.futures
import ctypes
import dataclasses
import enum
import functools
import gc
import importlib
import inspect
import math
import operator
import pickle
import sys
import sysconfig
import threading
import time
import types
import typing
import warnings

import pytest

from pathlib import Path
from unittest import mock

import sample

from conftest import (
    CPYTHON,
    GRAALPY,
    collect_until,
    counts_references,
    pythonapi,
    subinterpreter_run,
    subinterpreters,
)


BIASED_REFERENCE_COUNTING = bool(sysconfig.get_config_var('Py_GIL_DISABLED'))
COROUTINE_COUNT = 64
COUNTER_ROUNDS = 5000
IMMUTABLE_TYPES = CPYTHON or GRAALPY
RELEASING_THREAD_DEALLOCATES = CPYTHON and not BIASED_REFERENCE_COUNTING
RECORD_HORIZONTAL = 3
RECORD_VERTICAL = 4
REFCOUNT_ROUNDS = 1000
SEGMENT_LABELS = ('a' * 16, 'b' * 16)
TABLE_KEY_COUNT = 8
THREAD_COUNT = 4
THREAD_ROUNDS = 50


async def spin_cancelled(rounds: int) -> float:
    assert rounds > 0

    task = asyncio.ensure_future(sample.spin(rounds))

    await asyncio.sleep(0.05)

    task.cancel()
    started = time.perf_counter()

    with pytest.raises(asyncio.CancelledError):
        await task

    elapsed = time.perf_counter() - started

    assert elapsed >= 0

    return elapsed


def test_cancellation_reaches_the_zig_loop() -> None:
    assert asyncio.run(sample.spin(10)) == 10
    assert inspect.iscoroutinefunction(sample.spin)
    assert str(inspect.signature(sample.spin)) == '(rounds)'
    assert asyncio.run(spin_cancelled(1 << 30)) < 30


async def thread_recorded(threads: list[int], index: int) -> int:
    assert isinstance(threads, list)
    assert index >= 0

    threads.append(threading.get_ident())
    await asyncio.sleep(0)

    result = index * 10

    assert result >= index

    return result


async def relays_awaited(threads: list[int]) -> tuple[int, int, int, int]:
    assert not threads

    source = functools.partial(thread_recorded, threads)
    successor = functools.partial(operator.add, 1)
    relayed = await sample.relay(source, 4)
    synchronous = await sample.relay(successor, 3)
    doubled = await sample.awaited_double(asyncio.sleep(0, 21))

    return relayed, synchronous, doubled, threading.get_ident()


def test_coroutines_await_python_on_the_callers_loop() -> None:
    threads: list[int] = []

    relayed, synchronous, doubled, loop_thread = asyncio.run(relays_awaited(threads))

    assert (relayed, synchronous, doubled) == (60, 6, 42)
    assert threads == [loop_thread] * 4
    assert inspect.iscoroutinefunction(sample.relay)


async def relay_refused(index: int) -> int:
    assert index >= 0

    message = f'refused {index}'
    raise LookupError(message)


def test_coroutine_awaits_propagate_errors() -> None:
    with pytest.raises(LookupError, match='refused 0'):
        asyncio.run(sample.relay(relay_refused, 2))

    with pytest.raises(TypeError):
        asyncio.run(sample.relay(lambda _: 'text', 1))

    with pytest.raises(sample.Overflow):
        asyncio.run(sample.awaited_double(asyncio.sleep(0, 2**62)))


async def events_awaited(index: int, *, never: asyncio.Event, started: asyncio.Event) -> int:
    assert index >= 0
    assert not never.is_set()
    assert not started.is_set()

    started.set()
    await never.wait()

    return index


async def relay_cancelled() -> None:
    started = asyncio.Event()
    never = asyncio.Event()
    source = functools.partial(events_awaited, never=never, started=started)
    task = asyncio.ensure_future(sample.relay(source, 1))

    await started.wait()
    task.cancel()

    with pytest.raises(asyncio.CancelledError):
        await task


def test_cancelling_a_coroutine_cancels_its_inner_await() -> None:
    asyncio.run(relay_cancelled())


def test_custom_conversions_follow_their_declaration() -> None:
    assert sample.fixed_double(1.25) == 2.5
    assert sample.fixed_double(-0.5) == -1.0
    assert sample.fixed_double(1 / 65536) == 2 / 65536

    with pytest.raises(OverflowError, match='out of range'):
        sample.fixed_double(1e12)

    with pytest.raises(OverflowError):
        sample.fixed_double(30000.0)

    with pytest.raises(TypeError):
        sample.fixed_double('1.5')

    with pytest.raises(ValueError, match='not a number'):
        sample.fixed_double(math.nan)


def kept(mode: sample.Mode, *, received: list[sample.Mode]) -> sample.Mode:
    assert isinstance(mode, sample.Mode)
    assert not received

    received.append(mode)

    return sample.Mode.fast


def test_enum_members_cross_a_callback() -> None:
    received: list[sample.Mode] = []
    keep = functools.partial(kept, received=received)

    assert sample.mode_relay(keep, sample.Mode.exact) is sample.Mode.fast
    assert received == [sample.Mode.exact]

    with pytest.raises(TypeError, match='callback result must be Mode'):
        sample.mode_relay(int, sample.Mode.exact)


def test_variant_classes_round_trip() -> None:
    circle = sample.Shape.Circle(radius=2.0)
    square = sample.Shape.Square(3.0)
    empty = sample.Shape.Empty()

    for shape in (circle, square, empty):
        echoed = sample.shape_echo(shape)

        assert echoed == shape
        assert type(echoed) is type(shape)
        assert isinstance(echoed, sample.Shape)

    assert circle.radius == 2.0
    assert square.side == 3.0
    assert sample.shape_scaled(square, 2.0) == sample.Shape.Square(6.0)
    assert sample.shape_area(empty) == 0.0
    assert repr(circle) == 'Shape.Circle(radius=2.0)'
    assert repr(empty) == 'Shape.Empty()'
    assert hash(circle) == hash(sample.Shape.Circle(2.0))
    assert circle != sample.Shape.Square(2.0)
    assert circle != sample.Shape.Circle(2.5)

    with pytest.raises(AttributeError):
        circle.radius = 1.0

    with pytest.raises(TypeError, match='must be Shape'):
        sample.shape_echo(1)

    with pytest.raises(TypeError):
        sample.Shape.Empty(1)


def test_variant_classes_match() -> None:
    shapes = [sample.Shape.Circle(1.0), sample.Shape.Square(side=2.0), sample.Shape.Empty()]

    assert [variant_describe(shape) for shape in shapes] == ['circle 1.0', 'square 2.0', 'empty']


def variant_describe(shape: sample.Shape) -> str:
    assert isinstance(shape, sample.Shape)

    match shape:
        case sample.Shape.Circle(radius):
            result = f'circle {radius}'
        case sample.Shape.Square(side=side):
            result = f'square {side}'
        case sample.Shape.Empty():
            result = 'empty'
        case _:
            result = 'unknown'

    return result


def test_variant_classes_pickle() -> None:
    circle = sample.Shape.Circle(1.5)
    restored = pickle.loads(pickle.dumps(circle))

    assert restored == circle
    assert type(restored) is sample.Shape.Circle
    assert pickle.loads(pickle.dumps(sample.Shape.Empty())) == sample.Shape.Empty()

    with pytest.raises(TypeError, match='picklable class'):
        sample._lacuna_restore(1, {'radius': 1.0})

    with pytest.raises(KeyError, match='radius'):
        sample._lacuna_restore(sample.Shape.Circle, {'side': 1.0})


def test_variant_base_is_not_constructible() -> None:
    with pytest.raises(TypeError):
        sample.Shape()

    assert sample.Shape.Circle.__match_args__ == ('radius',)
    assert sample.Shape.Empty.__match_args__ == ()
    assert sample.Shape.Circle.__qualname__ == 'Shape.Circle'
    assert sample.Shape.Circle.__module__ == 'sample'
    assert issubclass(sample.Shape.Square, sample.Shape)

    with pytest.raises(TypeError):
        type('Wider', (sample.Shape.Circle,), {})


def test_variant_classes_hold_class_values() -> None:
    vector = sample.Vector(1.0, 2.0)
    original = sample.Vector(1.0, 2.0)
    placed = sample.Placement.At(vector)
    state = {'value': vector}
    restored = sample._lacuna_restore(sample.Placement.At, state)
    nowhere = sample.Placement.Nowhere()

    vector.scale(10.0)

    restorer, (kind, fields) = placed.__reduce__()
    reduced = restorer(kind, fields)

    assert placed.value == original
    assert restored == placed
    assert type(restored) is sample.Placement.At
    assert restored.value == original
    assert restorer is sample._lacuna_restore
    assert kind is sample.Placement.At
    assert fields == {'value': original}
    assert reduced == placed
    assert sample.Placement.At.__match_args__ == ('value',)
    assert pickle.loads(pickle.dumps(nowhere)) == nowhere

    with pytest.raises(TypeError, match='must be Vector'):
        sample.Placement.At(5)


def test_strided_buffers() -> None:
    values = array.array('d', range(10))
    grid_view = memoryview(array.array('d', range(6))).cast('B').cast('d', [2, 3])

    assert sample.sum_strided(values) == 45.0
    assert sample.sum_strided(memoryview(values)[::2]) == 20.0
    assert sample.sum_strided(memoryview(values)[::-3]) == 18.0
    assert sample.sum_strided(grid_view) == 15.0
    assert sample.sum_strided(array.array('d')) == 0.0

    with pytest.raises(TypeError, match='must be a buffer of f64 items'):
        sample.sum_strided(array.array('i', [1]))

    deep = memoryview(array.array('d', [0.0] * 512)).cast('B').cast('d', [2] * 9)

    with pytest.raises(BufferError, match='buffer_dimensions_max'):
        sample.sum_strided(deep)

    with pytest.raises(ValueError, match='one-dimensional'):
        sample.total(grid_view)


def test_grid_exports_two_dimensions() -> None:
    grid = sample.Grid(1.0)
    view = memoryview(grid)

    assert view.shape == (2, 3)
    assert view.strides == (24, 8)
    assert view.format == 'd'
    assert view.tolist() == [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]]

    view[1, 2] = 10.0
    view.release()

    assert sample.sum_strided(grid) == 25.0
    assert bytes(grid) == array.array('d', [1, 2, 3, 4, 5, 10]).tobytes()


def test_grid_starts_at_any_float() -> None:
    with memoryview(sample.Grid(math.nan)) as view:
        assert all(math.isnan(cell) for row in view.tolist() for cell in row)

    with memoryview(sample.Grid(-0.0)) as view:
        assert view.tolist() == [[0.0, 1.0, 2.0], [3.0, 4.0, 5.0]]
        assert math.copysign(1.0, view[0, 0]) == 1.0

    with memoryview(sample.Grid(math.inf)) as view:
        assert view[1, 2] == math.inf


def test_sequence_class_indices_and_slices() -> None:
    row = sample.Row([1, 2, 3, 4, 5])

    assert len(row) == 5
    assert row[-1] == 5
    assert row[0] == 1
    assert row[1:3] == [2, 3]
    assert row[::-2] == [5, 3, 1]
    assert row[-2:] == [4, 5]
    assert list(row) == [1, 2, 3, 4, 5]

    row[-1] = 50

    assert row[4] == 50

    with pytest.raises(IndexError):
        row[5]

    with pytest.raises(IndexError):
        row[-6]

    with pytest.raises(IndexError):
        row[-6] = 1


def test_sequence_and_mapping_patterns() -> None:
    table = sample.Table()
    table[3] = 30

    assert [pattern_kind(item) for item in (sample.Row([1, 2, 3]), table, 7)] == [
        'sequence 1 2 [3]',
        'mapping 30',
        'neither',
    ]


def pattern_kind(subject: object) -> str:
    assert subject is not None

    match subject:
        case [first, second, *rest]:
            result = f'sequence {first} {second} {rest}'
        case {3: value}:
            result = f'mapping {value}'
        case _:
            result = 'neither'

    return result


def test_derived_protocol_methods() -> None:
    small = sample.Pair(1, 2)
    large = sample.Pair(1, 3)

    assert small == sample.Pair(1, 2)
    assert small != large
    assert small < large
    assert small <= sample.Pair(1, 2)
    assert large > small
    assert large >= small
    assert sorted([large, small]) == [small, large]
    assert {small: 'small'}[sample.Pair(1, 2)] == 'small'
    assert repr(small) == 'Pair(left=1, right=2)'
    assert (small == 'pair') is False

    with pytest.raises(TypeError):
        operator.lt(small, 'pair')


def test_derived_constructor_and_string() -> None:
    ruler = sample.Ruler(3)

    assert (ruler.length, ruler.mark) == (3, ord('-'))
    assert str(ruler) == '---'
    assert str(sample.Ruler(4, ord('='))) == '===='
    assert str(sample.Ruler(0)) == ''
    assert repr(ruler) == 'Ruler(length=3, mark=45)'
    assert sample.Ruler(mark=ord('-'), length=3) == ruler

    if CPYTHON:
        assert str(inspect.signature(sample.Ruler)) == '(length, mark=45)'

    with pytest.raises(TypeError):
        sample.Ruler()

    with pytest.raises(OverflowError):
        sample.Ruler(2**32)

    with pytest.raises(OverflowError):
        sample.Ruler(1, 256)


def test_derived_string_refuses_oversized_and_invalid_text() -> None:
    with pytest.raises(ValueError, match='wrote more than 16777216 bytes'):
        _ = str(sample.Ruler(2**24 + 1))

    with pytest.raises(UnicodeDecodeError):
        _ = str(sample.Ruler(1, 0xFF))

    assert len(str(sample.Ruler(2**24))) == 2**24


def test_rename_all_and_every_field() -> None:
    tuning = sample.Tuning(2.0)

    assert (tuning.gainLevel, tuning.noiseFloor) == (2.0, 0.0)

    tuning.noiseFloor = 0.5
    tuning.gainLevel = 3.0

    assert (tuning.gainLevel, tuning.noiseFloor) == (3.0, 0.5)

    tuning.gainReset()

    assert tuning.gainLevel == 1.0
    assert not hasattr(tuning, 'gain_level')
    assert not hasattr(tuning, 'gain_reset')

    if CPYTHON:
        assert str(inspect.signature(sample.Tuning)) == '(gain_level=1.0, noise_floor=0.0)'

    with pytest.raises(TypeError):
        tuning.noiseFloor = 'quiet'


def test_add() -> None:
    assert sample.add(2, 40) == 42
    assert sample.add(41) == 42
    assert sample.add(right=2, left=1) == 3


def test_add_overflow_maps_to_builtin() -> None:
    with pytest.raises(OverflowError):
        sample.add(2**63 - 1, 1)


def test_integer_ranges() -> None:
    assert sample.narrow(0) == 0
    assert sample.narrow(255) == 255
    assert sample.wide(2**64 - 1) == 2**64 - 1
    assert sample.negate(-(2**31) + 1) == 2**31 - 1

    with pytest.raises(OverflowError):
        sample.wide(-1)

    with pytest.raises(OverflowError):
        sample.negate(2**31)

    with pytest.raises(OverflowError):
        sample.negate(-(2**31))


@pytest.mark.parametrize('value', [256, -1, 2**70])
def test_integer_out_of_range(value: int) -> None:
    assert not 0 <= value <= 255

    with pytest.raises(OverflowError, match=r'\[0, 255\]'):
        sample.narrow(value)


def test_integer_index_protocol() -> None:
    index = Index()

    assert sample.narrow(index) == 7


class Index:
    def __index__(self) -> int:
        result = 7

        assert 0 <= result <= 255

        return result


@pytest.mark.parametrize('value', [1.5, '3', None, b'1', type])
def test_integer_rejects_other_types(value: object) -> None:
    assert not isinstance(value, int)

    with pytest.raises(TypeError):
        sample.narrow(value)


def test_float() -> None:
    assert sample.half(3.0) == 1.5
    assert sample.half(3) == 1.5

    with pytest.raises(TypeError):
        sample.half('x')


def test_bool() -> None:
    assert sample.invert(flag=True) is False
    assert sample.invert(flag=False) is True


@pytest.mark.parametrize('value', [0, 1, None, 'yes'])
def test_bool_is_strict(value: object) -> None:
    assert not isinstance(value, bool)

    with pytest.raises(TypeError, match='must be bool'):
        sample.invert(flag=value)


def test_text() -> None:
    assert sample.shout('hi') == 'HI'
    assert sample.shout('ab', 3) == 'ABABAB'
    assert sample.shout('') == ''
    assert sample.terminated('abc') == 3

    with pytest.raises(TypeError, match='must be str'):
        sample.shout(b'hi')

    with pytest.raises(TypeError, match='must be str'):
        sample.shout(type)

    with pytest.raises(ValueError, match='embedded null'):
        sample.terminated('a\0b')


def test_text_rejects_lone_surrogates() -> None:
    with pytest.raises(UnicodeEncodeError):
        sample.shout('\ud800')


def test_enumeration() -> None:
    assert issubclass(sample.Mode, enum.Enum)
    assert [member.name for member in sample.Mode] == ['fast', 'exact']
    assert sample.Mode.fast.value == 0
    assert sample.Mode.__module__ == 'sample'
    assert sample.Mode.__doc__ == 'How carefully to compute.'
    assert sample.mode_flip() is sample.Mode.exact
    assert sample.mode_flip(sample.Mode.exact) is sample.Mode.fast
    assert pickle.loads(pickle.dumps(sample.Mode.exact)) is sample.Mode.exact

    with pytest.raises(TypeError, match='must be Mode'):
        sample.mode_flip('fast')

    with pytest.raises(TypeError, match='must be Mode'):
        sample.mode_flip(0)

    other = enum.Enum('Mode', [('fast', 0), ('exact', 1)])

    with pytest.raises(TypeError, match='must be Mode'):
        sample.mode_flip(other.fast)


def palette_written(palette: object, modes: list[object], rounds: int) -> None:
    assert isinstance(palette, sample.Palette)
    assert len(modes) == 8
    assert rounds > 0

    for _ in range(rounds):
        palette.modes = modes


def palette_read(
    palette: object,
    torn: list[object],
    rounds: int,
    read: typing.Callable[[object], object],
) -> None:
    assert isinstance(palette, sample.Palette)
    assert isinstance(torn, list)
    assert rounds > 0

    for _ in range(rounds):
        modes = read(palette)

        if len(set(modes)) != 1:
            torn.append(modes)


@pytest.mark.parametrize(
    'read',
    [operator.attrgetter('modes'), operator.methodcaller('snapshot')],
    ids=['field', 'borrowed_result'],
)
def test_a_read_never_mixes_two_writes(read: typing.Callable[[object], object]) -> None:
    fast = [sample.Mode.fast] * 8
    exact = [sample.Mode.exact] * 8
    palette = sample.Palette(fast)
    torn: list[object] = []
    rounds = 4000
    writers = [
        threading.Thread(target=palette_written, args=(palette, modes, rounds))
        for modes in (fast, exact)
    ]
    readers = [
        threading.Thread(target=palette_read, args=(palette, torn, rounds, read)) for _ in range(2)
    ]
    interval = sys.getswitchinterval()

    sys.setswitchinterval(1e-6)

    try:
        for thread in (*writers, *readers):
            thread.start()

        for thread in (*writers, *readers):
            thread.join()
    finally:
        sys.setswitchinterval(interval)

    assert not torn, torn[0]


def test_a_borrowed_field_reads_the_text_it_points_to() -> None:
    palette = sample.Palette([sample.Mode.fast])

    assert palette.title == 'palette'

    palette.retitle(shout=True)

    assert palette.title == 'PALETTE'

    with pytest.raises(AttributeError):
        palette.title = 'other'


def test_enumeration_wider_than_64_bits() -> None:
    registers = [member.value for member in sample.Register]
    magnitudes = [member.value for member in sample.Magnitude]

    assert registers == [0, 2**63, 2**64 - 1]
    assert magnitudes == [-(2**100), -(2**64), 0, 2**64, 2**100]

    for member in sample.Register:
        assert sample.register_next(sample.register_next(sample.register_next(member))) is member

    for member in sample.Magnitude:
        negated = sample.magnitude_negate(member)

        assert negated.value == -member.value
        assert sample.magnitude_negate(negated) is member

    assert pickle.loads(pickle.dumps(sample.Magnitude.huge)) is sample.Magnitude.huge

    with pytest.raises(TypeError, match='must be Register'):
        sample.register_next(2**63)


def test_optional() -> None:
    assert sample.maybe() is None
    assert sample.maybe(None) is None
    assert sample.maybe(4) == 8

    with pytest.raises(OverflowError):
        sample.maybe(2**62)


def test_none() -> None:
    assert sample.nothing() is None

    with pytest.raises(TypeError, match='takes no arguments'):
        sample.nothing(1)


def test_object() -> None:
    item = object()

    assert sample.identity(item) is item


def test_bytes() -> None:
    mutable = bytearray(b'xyz')
    view = memoryview(b'12')

    assert sample.reverse(b'abc') == b'cba'
    assert sample.reverse(mutable) == b'zyx'
    assert sample.reverse(view) == b'21'
    assert sample.reverse(b'') == b''

    with pytest.raises(TypeError):
        sample.reverse('text')


def test_typed_buffer() -> None:
    items = [1.0, 2.0, 3.5]
    values = array.array('d', items)
    empty = array.array('d')
    tail = memoryview(values)[1:]

    assert sample.total(values) == 6.5
    assert sample.total(empty) == 0.0
    assert sample.total(tail) == 5.5


@pytest.mark.parametrize('typecode', ['f', 'q', 'b'])
def test_typed_buffer_rejects_other_items(typecode: str) -> None:
    assert typecode in array.typecodes
    assert typecode != 'd'

    items = [1]
    values = array.array(typecode, items)

    with pytest.raises(TypeError, match='f64 items'):
        sample.total(values)


def test_typed_buffer_rejects_bytes() -> None:
    with pytest.raises(TypeError, match='f64 items'):
        sample.total(b'12345678')


def test_typed_buffer_rejects_strides() -> None:
    items = [1.0, 2.0, 3.0, 4.0]
    values = array.array('d', items)
    strided = memoryview(values)[::2]

    with pytest.raises(BufferError):
        sample.total(strided)


def test_mutable_buffer() -> None:
    items = [1.0, 2.0]
    values = array.array('d', items)
    expected = [3.0, 6.0]

    sample.scale(values, 3.0)

    assert values.tolist() == expected

    frozen = memoryview(values).toreadonly()

    with pytest.raises(BufferError):
        sample.scale(frozen, 1.0)


def test_buffer_export_is_released() -> None:
    values = bytearray(b'abc')

    sample.reverse(values)
    values.extend(b'def')

    assert values == b'abcdef'


def test_parallel_function() -> None:
    data = bytes(range(256)) * 64
    results: list[int] = []
    arguments = (data, results)
    threads = [threading.Thread(target=checksum_work, args=arguments) for _ in range(THREAD_COUNT)]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    expected = [sum(data)] * (THREAD_COUNT * THREAD_ROUNDS)

    assert results == expected


def test_coroutine_function() -> None:
    assert inspect.iscoroutinefunction(sample.tally)
    assert str(inspect.signature(sample.tally)) == '(data)'
    assert sample.tally.__module__ == 'sample'
    assert asyncio.run(sample.tally(b'abc')) == sum(b'abc')
    assert asyncio.run(sample.tally(data=bytes([255]) * 3)) == 765
    assert pickle.loads(pickle.dumps(sample.tally)) is sample.tally

    with pytest.raises(sample.Empty, match='no items'):
        asyncio.run(sample.tally(b''))

    with pytest.raises(TypeError, match='bytes-like'):
        asyncio.run(sample.tally('text'))


async def tallies_gathered(payloads: list[bytes]) -> list[int]:
    assert payloads

    return await asyncio.gather(*(sample.tally(payload) for payload in payloads))


async def tally_legacy_awaited() -> int:
    return await sample.tally_legacy(b'ab')


def test_coroutine_functions_gather() -> None:
    payloads = [bytes([index % 256 or 1]) * (index + 1) * 512 for index in range(COROUTINE_COUNT)]
    expected = [sum(payload) for payload in payloads]

    assert asyncio.run(tallies_gathered(payloads)) == expected


def test_deprecated_coroutine_warns_at_its_await() -> None:
    with pytest.warns(DeprecationWarning, match='use tally instead') as record:
        assert asyncio.run(tally_legacy_awaited()) == sum(b'ab')

    assert record[0].filename == __file__

    with warnings.catch_warnings():
        warnings.simplefilter('error', DeprecationWarning)

        with pytest.raises(DeprecationWarning):
            asyncio.run(tally_legacy_awaited())


def checksum_work(data: bytes, results: list[int]) -> None:
    assert data
    assert len(results) <= THREAD_COUNT * THREAD_ROUNDS

    checksums = [sample.checksum(data) for _ in range(THREAD_ROUNDS)]

    results.extend(checksums)


def test_array() -> None:
    pair = [1, 2]
    other = (3, 4)
    single = [1]
    iterator = iter(pair)

    assert sample.swap(pair) == (2, 1)
    assert sample.swap(other) == (4, 3)

    with pytest.raises(ValueError, match='exactly 2'):
        sample.swap(single)

    with pytest.raises(TypeError, match='must be a sequence'):
        sample.swap('ab')

    with pytest.raises(TypeError):
        sample.swap(iterator)


def test_list() -> None:
    numbers = [1, 2, 3]
    expected = [2, 4, 6]
    empty = []
    overflowing = list(range(9))

    assert sample.doubled(numbers) == expected
    assert sample.doubled(empty) == empty

    with pytest.raises(ValueError, match='at most 8'):
        sample.doubled(overflowing)

    huge = [2**62]

    with pytest.raises(OverflowError):
        sample.doubled(huge)


def test_tuple() -> None:
    assert sample.divide(7, 2) == (3, 1)
    assert sample.divide(-7, 2) == (-4, 1)

    with pytest.raises(ZeroDivisionError):
        sample.divide(1, 0)

    with pytest.raises(OverflowError):
        sample.divide(-(2**63), -1)


def test_record_result() -> None:
    items = [1.0, 2.0]
    values = array.array('d', items)
    expected = {'count': 2, 'mean': 1.5, 'label': None}

    assert sample.summarize(values) == expected
    assert sample.summarize(values, 'x')['label'] == 'x'


def test_record_argument() -> None:
    point = {'horizontal': 3.0, 'vertical': 4.0}
    integral = {'horizontal': 3}
    missing = {'vertical': 1.0}
    unknown = {'horizontal': 1.0, 'z': 2.0}
    sequence = [1.0, 2.0]

    assert sample.norm(point) == 5.0
    assert sample.norm(integral) == 3.0

    with pytest.raises(KeyError, match="key 'horizontal' is missing"):
        sample.norm(missing)

    with pytest.raises(KeyError, match="has no key 'z'"):
        sample.norm(unknown)

    with pytest.raises(TypeError, match='must be dict'):
        sample.norm(sequence)


@dataclasses.dataclass(frozen=True)
class Box:
    width: float
    height: float


class Flat(typing.NamedTuple):
    width: float


class Sealed:
    @property
    def width(self) -> float:
        message = 'the width is sealed'
        raise PermissionError(message)


def test_record_from_attributes() -> None:
    assert sample.area_of(Box(2.0, 3.0)) == 6.0
    assert sample.area_of(Flat(4.0)) == 4.0
    assert sample.area_of(types.SimpleNamespace(width=2, height=5)) == 10.0

    with pytest.raises(AttributeError, match='width'):
        sample.area_of(types.SimpleNamespace(height=5))

    with pytest.raises(AttributeError, match='width'):
        sample.area_of({'width': 2.0})

    with pytest.raises(TypeError, match='must be real number'):
        sample.area_of(types.SimpleNamespace(width='wide'))

    with pytest.raises(PermissionError, match='sealed'):
        sample.area_of(Sealed())


def test_error_hierarchy() -> None:
    assert issubclass(sample.Error, Exception)
    assert issubclass(sample.Empty, sample.Error)
    assert issubclass(sample.Negative, sample.Error)
    assert issubclass(sample.ListFull, sample.Error)


def test_error_message() -> None:
    with pytest.raises(sample.Empty, match=r'^the input holds no items$'):
        sample.shout('x', 0)

    assert sample.Empty.__doc__ == 'the input holds no items'
    assert sample.ListFull.__doc__ is None


def test_argument_errors() -> None:
    with pytest.raises(TypeError, match=r'at most 2 positional arguments \(3 given\)'):
        sample.add(1, 2, 3)

    with pytest.raises(TypeError, match="unexpected keyword argument 'rite'"):
        sample.add(1, rite=2)

    with pytest.raises(TypeError, match="multiple values for argument 'left'"):
        sample.add(1, left=2)

    with pytest.raises(TypeError, match="missing required argument 'left'"):
        sample.add()


def test_signatures() -> None:
    assert str(inspect.signature(sample.add)) == '(left, right=1)'
    assert str(inspect.signature(sample.mode_flip)) == '(mode=<Mode.fast: 0>)'
    assert str(inspect.signature(sample.maybe)) == '(value=None)'
    assert str(inspect.signature(sample.Vector.dot)) == '(self, /, other)'

    if CPYTHON:
        assert str(inspect.signature(sample.Vector)) == '(horizontal=0.0, vertical=0.0)'


def test_docs() -> None:
    assert sample.__doc__ == 'Every conversion and protocol that lacuna supports.'
    assert sample.add.__doc__ == 'Add two integers.'
    assert sample.Vector.__doc__ == 'A two-dimensional vector.'
    assert sample.Vector.length.__doc__ == 'The Euclidean length.'
    assert sample.Vector.horizontal.__doc__ == 'The horizontal component.'


def test_constants() -> None:
    assert sample.count_max == 8
    assert sample.ratio == 0.5
    assert sample.version == '0.1.0'
    assert sample.enabled is True


def test_class_identity() -> None:
    assert sample.Vector.__module__ == 'sample'
    assert sample.Vector.__qualname__ == 'Vector'


def test_vector_construction() -> None:
    vector = sample.Vector(3.0, 4.0)
    upward = sample.Vector(vertical=1.0)
    expected = sample.Vector(0.0, 1.0)
    origin = sample.Vector.origin()
    zero = sample.Vector()

    assert (vector.horizontal, vector.vertical) == (3.0, 4.0)
    assert upward == expected
    assert origin == zero

    with pytest.raises(TypeError, match='at most 2 positional'):
        sample.Vector(1, 2, 3)


def test_pooled_vectors_start_fresh() -> None:
    for _ in range(4):
        vectors = [sample.Vector(index, -index) for index in range(24)]

        del vectors

        fresh = [sample.Vector() for _ in range(24)]

        assert all((vector.horizontal, vector.vertical) == (0.0, 0.0) for vector in fresh)
        assert all(vector.length == 0.0 for vector in fresh)


def foreign_refusals_check(pool: concurrent.futures.Executor, handle: sample.Handle) -> None:
    assert isinstance(pool, concurrent.futures.Executor)
    assert isinstance(handle, sample.Handle)

    serial_read = functools.partial(getattr, handle, 'serial')
    serial_of = functools.partial(sample.Handle.serial_of, handle)
    works = (handle.advance, serial_read, serial_of)

    for work in works:
        with pytest.raises(RuntimeError, match='belongs to the thread that created it'):
            pool.submit(work).result()


def test_thread_affine_handle_refuses_other_threads() -> None:
    handles = [sample.Handle(4)]
    seen: list[object] = []

    assert handles[0].advance() == 5
    assert sample.Handle.serial_of(handles[0]) == 5

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        foreign_refusals_check(pool, handles[0])
        handles.append(pool.submit(sample.Handle, 9).result())

    with pytest.raises(RuntimeError, match='belongs to the thread that created it'):
        handles[1].advance()

    assert handles[0].serial == 5

    released = sample.Handle.released_count()

    with mock.patch.object(sys, 'unraisablehook', seen.append):
        handles.clear()
        collect_until(lambda: sample.Handle.released_count() + len(seen) == released + 2)

    assert sample.Handle.released_count() + len(seen) == released + 2
    assert all(record.exc_type is RuntimeError for record in seen)

    if CPYTHON:
        assert len(seen) == 1


def test_thread_affine_handle_released_elsewhere_skips_deinit() -> None:
    local = sample.Handle(1)
    before = sample.Handle.released_count()
    seen: list[object] = []

    with mock.patch.object(sys, 'unraisablehook', seen.append):
        del local
        collect_until(lambda: sample.Handle.released_count() + len(seen) > before)

    assert sample.Handle.released_count() + len(seen) == before + 1

    if CPYTHON:
        assert sample.Handle.released_count() == before + 1

    released = sample.Handle.released_count()
    holder = [sample.Handle(2)]
    seen.clear()

    with mock.patch.object(sys, 'unraisablehook', seen.append):
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            pool.submit(holder.clear).result()

        collect_until(lambda: sample.Handle.released_count() + len(seen) > released)

    assert sample.Handle.released_count() + len(seen) == released + 1

    if RELEASING_THREAD_DEALLOCATES:
        assert sample.Handle.released_count() == released
        assert seen[0].exc_type is RuntimeError
        assert 'its deinit did not run' in str(seen[0].exc_value)
    else:
        assert all(record.exc_type is RuntimeError for record in seen)


def test_vector_fields_and_properties() -> None:
    vector = sample.Vector(3.0, 4.0)

    assert vector.length == 5.0

    vector.horizontal = 6

    assert vector.horizontal == 6.0

    with pytest.raises(AttributeError, match=r"attribute 'length' of 'sample\.Vector'"):
        vector.length = 1.0

    with pytest.raises(TypeError):
        del vector.horizontal

    del vector.length

    assert (vector.horizontal, vector.vertical, vector.length) == (0.0, 0.0, 0.0)

    with pytest.raises(TypeError):
        vector.vertical = 'a'


def test_vector_methods() -> None:
    vector = sample.Vector(3.0, 4.0)
    diagonal = sample.Vector(1.0, 1.0)
    expected = sample.Vector(6.0, 8.0)

    assert vector.dot(diagonal) == 7.0
    assert vector.scale(2.0) is vector
    assert vector == expected

    with pytest.raises(TypeError, match='must be Vector'):
        vector.dot(other=5)


def test_vector_operators() -> None:
    left = sample.Vector(3.0, 4.0)
    right = sample.Vector(1.0, 2.0)
    total = sample.Vector(4.0, 6.0)
    difference = sample.Vector(2.0, 2.0)
    doubled = sample.Vector(6.0, 8.0)
    negated = sample.Vector(-3.0, -4.0)

    assert left + right == total
    assert left - right == difference
    assert left * 2 == doubled
    assert 2 * left == doubled
    assert -left == negated
    assert abs(left) == 5.0
    assert right < left
    assert right <= left
    assert left > right
    assert left >= right
    assert left != right
    assert left != 5

    zero = sample.Vector()

    assert not zero
    assert left

    with pytest.raises(TypeError):
        _ = left + 1

    with pytest.raises(TypeError):
        _ = left < 1


def test_segments_copy_vectors_in_and_out() -> None:
    start = sample.Vector(1.0, 2.0)
    end = sample.Vector(3.0, 4.0)
    moved = sample.Vector(5.0, 6.0)
    original_start = sample.Vector(1.0, 2.0)
    original_moved = sample.Vector(5.0, 6.0)
    segment = sample.Segment(start, end, 'first')

    start.scale(10.0)

    assert segment.start == original_start
    assert segment.end == end
    assert str(segment) == 'first'

    segment.start = moved
    segment.label = 'second'
    moved.scale(10.0)

    assert segment.start == original_moved
    assert str(segment) == 'second'

    with pytest.raises(TypeError, match='must be Vector'):
        segment.end = 5

    with pytest.raises(ValueError, match='at most 16 bytes'):
        segment.label = 'c' * 17

    assert segment.end == end
    assert str(segment) == 'second'


def test_segment_assignment_survives_a_thread_switch() -> None:
    segment = sample.Segment(sample.Vector(), sample.Vector(), SEGMENT_LABELS[0])

    for index in range(THREAD_ROUNDS):
        moved = sample.Vector(float(index), 1.0)
        segment.start = moved
        time.sleep(0)

        assert segment.start == moved


def test_vector_receives_itself() -> None:
    vector = sample.Vector(3.0, 4.0)
    doubled = sample.Vector(6.0, 8.0)

    assert vector.dot(vector) == 25.0
    assert vector + vector == doubled
    assert operator.eq(vector, vector)
    assert not operator.lt(vector, vector)
    assert sample.midpoint(vector, vector) == vector


def test_vector_sequence() -> None:
    vector = sample.Vector(3.0, 4.0)
    components = [3.0, 4.0]
    reversed_components = [4.0, 3.0]

    assert len(vector) == 2
    assert (vector[0], vector[1], vector[-1]) == (3.0, 4.0, 4.0)
    assert list(vector) == components
    assert list(reversed(vector)) == reversed_components

    with pytest.raises(IndexError):
        _ = vector[2]

    with pytest.raises(IndexError):
        _ = vector[-3]


def test_vector_hash_and_repr() -> None:
    vector = sample.Vector(1.5, 2.0)
    zero = sample.Vector()

    assert repr(vector) == 'Vector(1.5, 2)'

    with pytest.raises(TypeError):
        hash(zero)


def test_vector_final_and_immutable() -> None:
    bases = (sample.Vector,)
    namespace = {}

    with pytest.raises(TypeError):
        type('Child', bases, namespace)

    if IMMUTABLE_TYPES:
        with pytest.raises(TypeError):
            object.__new__(sample.Vector)

        with pytest.raises(TypeError):
            sample.Vector.z = 1
    else:
        bare = object.__new__(sample.Vector)

        with pytest.raises(TypeError, match='never initialized'):
            bare.dot(sample.Vector())

        with pytest.raises(TypeError, match='never initialized'):
            sample.midpoint(bare, sample.Vector())


def test_vector_argument() -> None:
    start = sample.Vector(0.0, 0.0)
    end = sample.Vector(2.0, 4.0)
    expected = sample.Vector(1.0, 2.0)

    assert sample.midpoint(start, end) == expected


def test_counter_iteration() -> None:
    counter = sample.Counter(5, start=2)
    expected = [2, 3, 4]

    assert iter(counter) is counter
    assert list(counter) == expected
    assert counter.current == 5
    assert list(counter) == []


def test_counter_contains_and_call() -> None:
    counter = sample.Counter(10)

    assert 3 in counter
    assert 10 not in counter
    assert 'x' not in counter
    assert 2**63 not in counter
    assert -(2**63) - 1 not in counter
    assert counter() == 1
    assert counter(step=3) == 4
    assert counter(100) == 10
    assert counter(2**63 - 1) == 10


def test_counter_read_only_field() -> None:
    counter = sample.Counter(3)

    with pytest.raises(AttributeError):
        counter.current = 1


def test_counter_failed_initialization_skips_teardown() -> None:
    gc.collect()

    before = sample.deinit_count()

    with pytest.raises(sample.Negative):
        sample.Counter(1, start=5)

    sample.Counter(4)
    gc.collect()

    assert sample.deinit_count() == before + 1


def test_table_mapping() -> None:
    table = sample.Table()
    table[3] = 7
    table[0] = -1

    assert len(table) == 2
    assert table[3] == 7

    del table[3]

    assert len(table) == 1

    with pytest.raises(KeyError):
        _ = table[3]

    with pytest.raises(KeyError):
        del table[5]

    with pytest.raises(OverflowError):
        table[8] = 1


@counts_references
def test_arguments_do_not_leak() -> None:
    text = f'refcount-{id(REFCOUNT_ROUNDS)}'
    item = object()
    data = bytes(range(16))
    point = {'horizontal': 1.0}
    numbers = [1, 2]
    before = (sys.getrefcount(text), sys.getrefcount(item), sys.getrefcount(data))

    for _ in range(REFCOUNT_ROUNDS):
        sample.shout(text)
        sample.identity(item)
        sample.reverse(data)
        sample.norm(point)
        sample.doubled(numbers)

    after = (sys.getrefcount(text), sys.getrefcount(item), sys.getrefcount(data))

    assert before == after


@counts_references
def test_failed_calls_do_not_leak() -> None:
    text = f'refcount-{id(REFCOUNT_ROUNDS)}'
    texts = [text]
    before = sys.getrefcount(text)

    for _ in range(REFCOUNT_ROUNDS):
        with pytest.raises(sample.Empty):
            sample.shout(text, 0)

        with pytest.raises(TypeError):
            sample.doubled(texts)

    assert sys.getrefcount(text) == before


def test_instances_are_freed() -> None:
    gc.collect()

    before = sample.deinit_count()

    for _ in range(REFCOUNT_ROUNDS):
        sample.Counter(1)

    if not CPYTHON:
        gc.collect()

    assert sample.deinit_count() == before + REFCOUNT_ROUNDS


def test_reimport_creates_a_new_module() -> None:
    original = sys.modules.pop('sample')

    try:
        fresh = importlib.import_module('sample')
    finally:
        sys.modules['sample'] = original

    stale_start = original.Vector()
    stale_end = original.Vector()
    current = fresh.Vector()
    fresh_sum = fresh.add(1, 2)

    assert fresh is not original
    assert fresh.Vector is not original.Vector
    assert fresh_sum == 3

    with pytest.raises(fresh.Empty):
        fresh.shout('x', 0)

    with pytest.raises(TypeError, match='must be Vector'):
        fresh.midpoint(stale_start, stale_end)

    with pytest.raises(TypeError):
        _ = stale_start + current


@subinterpreters
def test_subinterpreter() -> None:
    directory = str(Path(sample.__file__).parent.parent)

    source = (
        'import sys\n'
        f'sys.path.insert(0, {directory!r})\n'
        'import sample\n'
        'assert sample.add(1, 2) == 3\n'
        'assert list(sample.Counter(3)) == [0, 1, 2]\n'
    )

    subinterpreter_run(source)


@subinterpreters
def test_subinterpreter_failure_surfaces() -> None:
    source = "raise RuntimeError('subinterpreter witness')\n"

    with pytest.raises(Exception, match='subinterpreter witness'):
        subinterpreter_run(source)


def test_gil_matches_the_build() -> None:
    disabled = bool(sysconfig.get_config_var('Py_GIL_DISABLED'))
    enabled = getattr(sys, '_is_gil_enabled', lambda: True)()

    assert enabled is not disabled


def test_threads_share_one_counter() -> None:
    thread_count = 8
    counter = sample.Counter(10**12)
    barrier = threading.Barrier(thread_count)
    arguments = (barrier, counter)
    threads = [threading.Thread(target=counter_work, args=arguments) for _ in range(thread_count)]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    assert counter.current == thread_count * COUNTER_ROUNDS


def counter_work(barrier: threading.Barrier, counter: sample.Counter) -> None:
    assert barrier.parties > 1
    assert counter.current < 10**12

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        counter(1)


def test_threads_share_one_table() -> None:
    table = sample.Table()
    barrier = threading.Barrier(TABLE_KEY_COUNT)
    threads = [
        threading.Thread(target=table_work, args=(barrier, table, key))
        for key in range(TABLE_KEY_COUNT)
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    expected = [key * COUNTER_ROUNDS for key in range(TABLE_KEY_COUNT)]

    assert len(table) == TABLE_KEY_COUNT
    assert [table[key] for key in range(TABLE_KEY_COUNT)] == expected


def table_work(barrier: threading.Barrier, table: sample.Table, key: int) -> None:
    assert 0 <= key < TABLE_KEY_COUNT
    assert len(table) <= TABLE_KEY_COUNT
    assert barrier.parties == TABLE_KEY_COUNT

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for index in range(COUNTER_ROUNDS):
        table[key] = index

        assert table[key] == index

        del table[key]

        assert len(table) < TABLE_KEY_COUNT

    table[key] = key * COUNTER_ROUNDS


def test_threads_share_one_record() -> None:
    point = {'horizontal': float(RECORD_HORIZONTAL), 'vertical': float(RECORD_VERTICAL)}
    barrier = threading.Barrier(THREAD_COUNT + 1)
    norms: list[float] = []
    arguments = (barrier, point, norms)
    threads = [
        threading.Thread(target=record_reader_work, args=arguments) for _ in range(THREAD_COUNT)
    ]

    writer_arguments = (barrier, point)
    writer = threading.Thread(target=record_writer_work, args=writer_arguments)

    threads.append(writer)

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    expected = math.hypot(RECORD_HORIZONTAL, RECORD_VERTICAL)

    assert len(norms) == THREAD_COUNT * COUNTER_ROUNDS
    assert set(norms) == {expected}


def record_reader_work(
    barrier: threading.Barrier,
    point: dict[str, float],
    norms: list[float],
) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(point) == 2
    assert not norms

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        norm = sample.norm(point)
        norms.append(norm)


def record_writer_work(barrier: threading.Barrier, point: dict[str, float]) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(point) == 2

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        point['horizontal'] = float(RECORD_HORIZONTAL)
        point['vertical'] = float(RECORD_VERTICAL)


def test_threads_share_two_vectors() -> None:
    left = sample.Vector(RECORD_HORIZONTAL, RECORD_VERTICAL)
    right = sample.Vector(RECORD_HORIZONTAL, RECORD_VERTICAL)
    unit = sample.Vector(RECORD_HORIZONTAL, RECORD_VERTICAL)
    barrier = threading.Barrier(3)
    products: list[float] = []
    midpoints: list[sample.Vector] = []
    reader_arguments = (barrier, left, right, products, midpoints)
    left_arguments = (barrier, left)
    right_arguments = (barrier, right)

    threads = [
        threading.Thread(target=vector_reader_work, args=reader_arguments),
        threading.Thread(target=vector_flipper_work, args=left_arguments),
        threading.Thread(target=vector_flipper_work, args=right_arguments),
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    norm = float(RECORD_HORIZONTAL**2 + RECORD_VERTICAL**2)
    expected_products = {-norm, norm}
    expected_midpoints = (sample.Vector(), unit, -unit)

    assert len(products) == COUNTER_ROUNDS
    assert len(midpoints) == COUNTER_ROUNDS
    assert set(products) <= expected_products
    assert all(midpoint in expected_midpoints for midpoint in midpoints)


def vector_reader_work(
    barrier: threading.Barrier,
    left: sample.Vector,
    right: sample.Vector,
    products: list[float],
    midpoints: list[sample.Vector],
) -> None:
    assert barrier.parties == 3
    assert left is not right
    assert not products
    assert not midpoints

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        product = left.dot(right)
        products.append(product)

        midpoint = sample.midpoint(left, right)
        midpoints.append(midpoint)


def vector_flipper_work(barrier: threading.Barrier, vector: sample.Vector) -> None:
    assert barrier.parties == 3
    assert abs(vector) == math.hypot(RECORD_HORIZONTAL, RECORD_VERTICAL)

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        vector.scale(-1.0)


def test_threads_share_one_segment() -> None:
    segment = sample.Segment(sample.Vector(), sample.Vector(), SEGMENT_LABELS[0])
    barrier = threading.Barrier(2)
    labels: list[str] = []
    reader_arguments = (barrier, segment, labels)
    writer_arguments = (barrier, segment)

    threads = [
        threading.Thread(target=segment_reader_work, args=reader_arguments),
        threading.Thread(target=segment_writer_work, args=writer_arguments),
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    expected = set(SEGMENT_LABELS)

    assert len(labels) == COUNTER_ROUNDS
    assert set(labels) <= expected


def segment_reader_work(
    barrier: threading.Barrier,
    segment: sample.Segment,
    labels: list[str],
) -> None:
    assert barrier.parties == 2
    assert str(segment) in SEGMENT_LABELS
    assert not labels

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COUNTER_ROUNDS):
        label = str(segment)
        labels.append(label)


def segment_writer_work(barrier: threading.Barrier, segment: sample.Segment) -> None:
    assert barrier.parties == 2
    assert str(segment) in SEGMENT_LABELS

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for index in range(COUNTER_ROUNDS):
        segment.label = SEGMENT_LABELS[index % 2]


class Spelled(str):
    __slots__ = ()
    __hash__ = object.__hash__

    def __eq__(self, other: object) -> bool:
        assert isinstance(other, str)

        return self is other


def test_record_rejects_repeated_keys() -> None:
    spelled = {Spelled('horizontal'): 1.0, Spelled('horizontal'): 2.0, Spelled('vertical'): 3.0}

    with pytest.raises(ValueError, match='repeats a key'):
        sample.norm(spelled)


class Endless:
    def __getitem__(self, index: int) -> int:
        assert index >= 0

        return index


def test_sequences_are_read_within_capacity() -> None:
    with pytest.raises(ValueError, match='at most 8'):
        sample.doubled(Endless())

    if GRAALPY:
        with pytest.raises(OverflowError, match='index-sized integer'):
            sample.doubled(range(10**12))
    elif sys.maxsize < 10**12:
        with pytest.raises(OverflowError, match='too large to convert to C ssize_t'):
            sample.doubled(range(10**12))
    else:
        with pytest.raises(ValueError, match='at most 8'):
            sample.doubled(range(10**12))

    assert sample.doubled(range(3)) == [0, 2, 4]


@pythonapi
def test_sequence_item_accepts_negative_indices() -> None:
    getter = ctypes.pythonapi.PySequence_GetItem
    getter.restype = ctypes.py_object
    getter.argtypes = (ctypes.py_object, ctypes.c_ssize_t)
    vector = sample.Vector(1.0, 2.0)

    assert getter(vector, -1) == 2.0

    with pytest.raises(IndexError):
        getter(vector, -5)
