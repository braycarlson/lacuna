import array
import asyncio
import concurrent.futures
import gc
import operator
import pickle
import sys
import types

import sample

from conftest import imbalance, raising, reduction_round


TYPE_CACHE_CALL_COUNT = 2000
TYPE_CACHE_ENTRY_COUNT = 4096
TYPE_CACHE_RELEASE_MAX = 16
TYPE_CACHE_ROUND_COUNT = 6


class Index:
    def __index__(self) -> int:
        result = 7

        assert 0 <= result <= 255

        return result


def test_cancellable_coroutines_do_not_leak() -> None:
    assert not imbalance(lambda: asyncio.run(sample.spin(4)), faults=False)


async def relayed_index(index: int) -> int:
    assert index >= 0

    await asyncio.sleep(0)

    return index


async def relayed_refusal(index: int) -> int:
    assert index >= 0

    message = f'refused {index}'
    raise LookupError(message)


def test_loop_awaits_do_not_leak() -> None:
    relayed = raising(LookupError, lambda: asyncio.run(sample.relay(relayed_refusal, 1)))

    assert not imbalance(lambda: asyncio.run(sample.relay(relayed_index, 3)), faults=False)
    assert not imbalance(lambda: asyncio.run(sample.awaited_double(relayed_index(4))), faults=False)
    assert not imbalance(relayed, faults=False)


def test_custom_conversions_do_not_leak() -> None:
    assert not imbalance(lambda: sample.fixed_double(1.25))
    assert not imbalance(raising(OverflowError, lambda: sample.fixed_double(1e12)))
    assert not imbalance(raising(TypeError, lambda: sample.fixed_double('1.5')))
    assert not imbalance(lambda: sample.mode_relay(identity, sample.Mode.exact))
    assert not imbalance(raising(TypeError, lambda: sample.mode_relay(int, sample.Mode.fast)))


def identity(mode: sample.Mode) -> sample.Mode:
    assert isinstance(mode, sample.Mode)

    return mode


def test_scalars_do_not_leak() -> None:
    index = Index()

    assert not imbalance(lambda: sample.add(2, 40))
    assert not imbalance(lambda: sample.add(right=2, left=1))
    assert not imbalance(raising(OverflowError, lambda: sample.add(2**63 - 1, 1)))
    assert not imbalance(lambda: sample.narrow(255))
    assert not imbalance(lambda: sample.narrow(index))
    assert not imbalance(raising(OverflowError, lambda: sample.narrow(2**70)))
    assert not imbalance(raising(TypeError, lambda: sample.narrow(1.5)))
    assert not imbalance(lambda: sample.wide(2**64 - 1))
    assert not imbalance(raising(OverflowError, lambda: sample.wide(-1)))
    assert not imbalance(raising(OverflowError, lambda: sample.negate(2**31)))
    assert not imbalance(lambda: sample.half(3))
    assert not imbalance(raising(TypeError, lambda: sample.half('x')))
    assert not imbalance(lambda: sample.invert(flag=True))
    assert not imbalance(raising(TypeError, lambda: sample.invert(flag=1)))
    assert not imbalance(lambda: sample.mode_flip(sample.Mode.exact))
    assert not imbalance(raising(TypeError, lambda: sample.mode_flip('slow')))
    assert not imbalance(raising(TypeError, lambda: sample.mode_flip(1)))
    assert not imbalance(lambda: sample.maybe(None))
    assert not imbalance(lambda: sample.maybe(4))
    assert not imbalance(raising(OverflowError, lambda: sample.maybe(2**62)))
    assert not imbalance(sample.nothing)
    assert not imbalance(raising(TypeError, lambda: sample.nothing(1)))
    assert not imbalance(lambda: sample.identity(index))
    assert not imbalance(sample.deinit_count)


def type_cache_release() -> int:
    pins = []

    sys._clear_internal_caches()
    gc.collect()

    for index in range(TYPE_CACHE_CALL_COUNT):
        sample.mode_flip(sample.Mode.exact)
        pin = f'{index:06}'
        pins.append(pin)

    gc.collect()
    references_held = sys.gettotalrefcount()

    sys._clear_internal_caches()
    gc.collect()
    references_released = references_held - sys.gettotalrefcount()

    assert references_released <= TYPE_CACHE_ENTRY_COUNT

    return references_released


def test_attribute_names_do_not_accumulate_in_the_type_cache() -> None:
    releases = [type_cache_release() for _ in range(TYPE_CACHE_ROUND_COUNT)]

    assert sum(releases) < TYPE_CACHE_RELEASE_MAX


def test_arguments_do_not_leak() -> None:
    assert not imbalance(raising(TypeError, lambda: sample.add(1, 2, 3)))
    assert not imbalance(raising(TypeError, lambda: sample.add(1, rite=2)))
    assert not imbalance(raising(TypeError, lambda: sample.add(1, left=2)))
    assert not imbalance(raising(TypeError, sample.add))


def test_text_does_not_leak() -> None:
    assert not imbalance(lambda: sample.shout('ab', 3))
    assert not imbalance(raising(sample.Empty, lambda: sample.shout('x', 0)))
    assert not imbalance(raising(sample.Negative, lambda: sample.shout('x' * 200, 2)))
    assert not imbalance(raising(TypeError, lambda: sample.shout(b'hi')))
    assert not imbalance(raising(UnicodeEncodeError, lambda: sample.shout('\ud800')))
    assert not imbalance(lambda: sample.terminated('abc'))
    assert not imbalance(raising(ValueError, lambda: sample.terminated('a\0b')))


def test_buffers_do_not_leak() -> None:
    items = [1.0, 2.0, 3.5]
    values = array.array('d', items)
    integers = array.array('q', [1])
    strided = memoryview(values)[::2]
    frozen = memoryview(values).toreadonly()
    mutable = bytearray(b'xyz')
    view = memoryview(b'12')

    assert not imbalance(lambda: sample.reverse(b'abc'))
    assert not imbalance(lambda: sample.reverse(mutable))
    assert not imbalance(lambda: sample.reverse(view))
    assert not imbalance(raising(TypeError, lambda: sample.reverse('text')))
    assert not imbalance(lambda: sample.total(values))
    assert not imbalance(lambda: sample.total(memoryview(values)[1:]))
    assert not imbalance(raising(TypeError, lambda: sample.total(integers)))
    assert not imbalance(raising(TypeError, lambda: sample.total(b'12345678')))
    assert not imbalance(raising(BufferError, lambda: sample.total(strided)))
    assert not imbalance(lambda: sample.scale(values, 1.0))
    assert not imbalance(raising(BufferError, lambda: sample.scale(frozen, 1.0)))
    assert not imbalance(lambda: sample.checksum(b'abc'))


def test_coroutines_do_not_leak() -> None:
    assert not imbalance(lambda: asyncio.run(sample.tally(b'abc')), faults=False)
    empty = raising(sample.Empty, lambda: asyncio.run(sample.tally(b'')))

    assert not imbalance(empty, faults=False)
    assert not imbalance(lambda: sample.tally(b'abc').close())


def test_collections_do_not_leak() -> None:
    pair = [1, 2]
    numbers = [1, 2, 3]
    overflowing = list(range(9))
    huge = [2**62]
    values = array.array('d', [1.0, 2.0])
    empty = array.array('d')

    assert not imbalance(lambda: sample.swap(pair))
    assert not imbalance(lambda: sample.swap((3, 4)))
    assert not imbalance(raising(ValueError, lambda: sample.swap([1])))
    assert not imbalance(raising(TypeError, lambda: sample.swap('ab')))
    assert not imbalance(raising(TypeError, lambda: sample.swap(iter(pair))))
    assert not imbalance(lambda: sample.doubled(numbers))
    assert not imbalance(raising(ValueError, lambda: sample.doubled(overflowing)))
    assert not imbalance(raising(OverflowError, lambda: sample.doubled(huge)))
    assert not imbalance(lambda: sample.divide(-7, 2))
    assert not imbalance(raising(ZeroDivisionError, lambda: sample.divide(1, 0)))
    assert not imbalance(raising(OverflowError, lambda: sample.divide(-(2**63), -1)))
    assert not imbalance(lambda: sample.summarize(values, 'x'))
    assert not imbalance(raising(sample.Empty, lambda: sample.summarize(empty)))


def test_records_do_not_leak() -> None:
    point = {'horizontal': 3.0, 'vertical': 4.0}
    missing = {'vertical': 1.0}
    unknown = {'horizontal': 1.0, 'z': 2.0}

    assert not imbalance(lambda: sample.norm(point))
    assert not imbalance(raising(KeyError, lambda: sample.norm(missing)))
    assert not imbalance(raising(KeyError, lambda: sample.norm(unknown)))
    assert not imbalance(raising(TypeError, lambda: sample.norm([1.0, 2.0])))


def test_attribute_records_do_not_leak() -> None:
    full = types.SimpleNamespace(width=2.0, height=3.0)
    flat = types.SimpleNamespace(width=2.0)
    missing = types.SimpleNamespace(height=3.0)
    wrong = types.SimpleNamespace(width='wide')

    assert not imbalance(lambda: sample.area_of(full))
    assert not imbalance(lambda: sample.area_of(flat))
    assert not imbalance(raising(AttributeError, lambda: sample.area_of(missing)))
    assert not imbalance(raising(TypeError, lambda: sample.area_of(wrong)))


def test_variant_classes_do_not_leak() -> None:
    circle = sample.Shape.Circle(1.0)
    empty = sample.Shape.Empty()

    assert not imbalance(lambda: sample.Shape.Circle(radius=2.0))
    assert not imbalance(lambda: sample.shape_echo(circle))
    assert not imbalance(lambda: sample.shape_scaled(circle, 2.0))
    assert not imbalance(lambda: repr(circle))
    assert not imbalance(lambda: hash(circle))
    assert not imbalance(lambda: circle == empty)
    assert not imbalance(lambda: circle.radius)
    assert not imbalance(lambda: pickle.loads(pickle.dumps(circle)), faults=False)
    assert not imbalance(lambda: reduction_round(circle))
    assert not imbalance(raising(TypeError, lambda: sample.shape_echo(1)))
    assert not imbalance(raising(TypeError, lambda: sample.Shape.Empty(1)))


def test_strided_buffers_do_not_leak() -> None:
    values = array.array('d', range(10))
    stepped = memoryview(values)[::2]
    deep = memoryview(array.array('d', [0.0] * 512)).cast('B').cast('d', [2] * 9)
    grid = sample.Grid(1.0)

    assert not imbalance(lambda: sample.sum_strided(stepped))
    assert not imbalance(lambda: sample.sum_strided(grid))
    assert not imbalance(lambda: memoryview(grid).release())
    assert not imbalance(lambda: bytes(grid))
    assert not imbalance(raising(BufferError, lambda: sample.sum_strided(deep)))
    assert not imbalance(raising(TypeError, lambda: sample.sum_strided(array.array('i', [1]))))


def row_assign(row: sample.Row) -> None:
    assert len(row) > 0

    row[-1] = 9


def test_sequence_and_mapping_do_not_leak() -> None:
    row = sample.Row([1, 2, 3, 4, 5])
    table = sample.Table()
    table[3] = 30

    assert not imbalance(lambda: row[-1])
    assert not imbalance(lambda: row[1:4])
    assert not imbalance(lambda: row_assign(row))
    assert not imbalance(lambda: list(row))
    assert not imbalance(raising(IndexError, lambda: row[-9]))
    assert not imbalance(raising(TypeError, lambda: row['x']))
    assert not imbalance(lambda: table.get(3))
    assert not imbalance(lambda: table.get(4, row))


def test_derived_methods_do_not_leak() -> None:
    small = sample.Pair(1, 2)
    large = sample.Pair(1, 3)

    assert not imbalance(lambda: small < large)
    assert not imbalance(lambda: small == large)
    assert not imbalance(lambda: hash(small))
    assert not imbalance(lambda: repr(small))
    assert not imbalance(raising(TypeError, lambda: small < 'pair'))


def test_derived_constructor_and_string_do_not_leak() -> None:
    ruler = sample.Ruler(3)
    invalid = sample.Ruler(1, 0xFF)

    assert not imbalance(lambda: sample.Ruler(3, ord('=')))
    assert not imbalance(raising(TypeError, sample.Ruler))
    assert not imbalance(raising(OverflowError, lambda: sample.Ruler(2**32)))
    assert not imbalance(lambda: str(ruler))
    assert not imbalance(raising(UnicodeDecodeError, lambda: str(invalid)))


def test_thread_affine_handle_does_not_leak() -> None:
    handle = sample.Handle(1)

    assert not imbalance(lambda: sample.Handle(3).advance())
    assert not imbalance(lambda: sample.Handle.serial_of(handle))

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        foreign = raising(RuntimeError, lambda: pool.submit(handle.advance).result())

        assert not imbalance(foreign, faults=False)


def test_segment_does_not_leak() -> None:
    start = sample.Vector(1.0, 2.0)
    end = sample.Vector(3.0, 4.0)
    segment = sample.Segment(start, end, 'label')
    placed = sample.Placement.At(start)
    state = {'value': start}

    assert not imbalance(lambda: sample.Segment(start, end, 'label'))
    assert not imbalance(raising(TypeError, lambda: sample.Segment(start, 5, 'label')))
    assert not imbalance(raising(ValueError, lambda: sample.Segment(start, end, 'c' * 17)))
    assert not imbalance(lambda: segment.start)
    assert not imbalance(lambda: setattr(segment, 'end', start))
    assert not imbalance(raising(TypeError, lambda: setattr(segment, 'end', 5)))
    assert not imbalance(lambda: setattr(segment, 'label', 'renamed'))
    assert not imbalance(lambda: str(segment))
    assert not imbalance(lambda: sample.Placement.At(start))
    assert not imbalance(raising(TypeError, lambda: sample.Placement.At(5)))
    assert not imbalance(lambda: placed.value)
    assert not imbalance(lambda: sample._lacuna_restore(sample.Placement.At, state))
    assert not imbalance(placed.__reduce__)


def test_palette_does_not_leak() -> None:
    modes = [sample.Mode.fast, sample.Mode.exact]
    palette = sample.Palette(modes)

    assert not imbalance(lambda: sample.Palette(modes))
    assert not imbalance(lambda: palette.modes)
    assert not imbalance(lambda: setattr(palette, 'modes', modes))
    assert not imbalance(palette.snapshot)
    assert not imbalance(lambda: palette.title)
    assert not imbalance(lambda: palette.retitle(shout=True))


def test_vector_does_not_leak() -> None:
    left = sample.Vector(3.0, 4.0)
    right = sample.Vector(1.0, 2.0)
    zero = sample.Vector()

    assert not imbalance(lambda: sample.Vector(1.0, 2.0))
    assert not imbalance(lambda: sample.Vector(vertical=1.0))
    assert not imbalance(raising(TypeError, lambda: sample.Vector(1, 2, 3)))
    assert not imbalance(sample.Vector.origin)
    assert not imbalance(lambda: left.length)
    assert not imbalance(lambda: left.horizontal)
    assert not imbalance(lambda: setattr(right, 'horizontal', 1.0))
    assert not imbalance(raising(TypeError, lambda: setattr(right, 'vertical', 'a')))
    assert not imbalance(raising(TypeError, lambda: delattr(right, 'horizontal')))
    assert not imbalance(raising(AttributeError, lambda: setattr(left, 'length', 1.0)))
    assert not imbalance(lambda: delattr(zero, 'length'))
    assert not imbalance(lambda: left.dot(right))
    assert not imbalance(raising(TypeError, lambda: left.dot(other=5)))
    assert not imbalance(lambda: right.scale(1.0))
    assert not imbalance(lambda: sample.midpoint(left, right))
    assert not imbalance(lambda: left + right)
    assert not imbalance(lambda: left - right)
    assert not imbalance(lambda: left * 2)
    assert not imbalance(lambda: 2 * left)
    assert not imbalance(lambda: -left)
    assert not imbalance(lambda: abs(left))
    assert not imbalance(lambda: bool(zero))
    assert not imbalance(lambda: left == right)
    assert not imbalance(lambda: left != 5)
    assert not imbalance(lambda: left < right)
    assert not imbalance(lambda: left >= right)
    assert not imbalance(raising(TypeError, lambda: operator.add(left, 1)))
    assert not imbalance(raising(TypeError, lambda: operator.lt(left, 1)))
    assert not imbalance(lambda: len(left))
    assert not imbalance(lambda: left[-1])
    assert not imbalance(raising(IndexError, lambda: operator.getitem(left, 2)))
    assert not imbalance(lambda: list(left))
    assert not imbalance(lambda: repr(left))
    assert not imbalance(raising(TypeError, lambda: hash(zero)))


def test_counter_does_not_leak() -> None:
    counter = sample.Counter(10**12)

    assert not imbalance(lambda: list(sample.Counter(5, start=2)))
    assert not imbalance(raising(sample.Negative, lambda: sample.Counter(1, start=5)))
    assert not imbalance(lambda: 3 in counter)
    assert not imbalance(lambda: 'x' in counter)
    assert not imbalance(lambda: counter(step=1))
    assert not imbalance(lambda: counter.current)
    assert not imbalance(raising(AttributeError, lambda: setattr(counter, 'current', 1)))


def test_table_does_not_leak() -> None:
    table = sample.Table()

    assert not imbalance(lambda: operator.setitem(table, 3, 7))
    assert not imbalance(lambda: table[3])
    assert not imbalance(lambda: len(table))
    assert not imbalance(raising(KeyError, lambda: operator.getitem(table, 4)))
    assert not imbalance(raising(KeyError, lambda: operator.delitem(table, 5)))
    assert not imbalance(raising(OverflowError, lambda: operator.setitem(table, 8, 1)))
    assert not imbalance(lambda: (operator.setitem(table, 2, 1), operator.delitem(table, 2)))
    assert not imbalance(sample.Table)
