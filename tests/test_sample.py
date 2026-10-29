import array
import asyncio
import ctypes
import enum
import gc
import importlib
import inspect
import math
import operator
import pickle
import sys
import sysconfig
import threading
import warnings

import pytest

from pathlib import Path

import sample

from conftest import CPYTHON, counts_references, pythonapi, subinterpreter_run, subinterpreters


COROUTINE_COUNT = 64
COUNTER_ROUNDS = 5000
REFCOUNT_ROUNDS = 1000
TABLE_KEY_COUNT = 8
THREAD_COUNT = 4
THREAD_ROUNDS = 50


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


def test_vector_fields_and_properties() -> None:
    vector = sample.Vector(3.0, 4.0)

    assert vector.length == 5.0

    vector.horizontal = 6

    assert vector.horizontal == 6.0

    with pytest.raises(AttributeError):
        vector.length = 1.0

    with pytest.raises(TypeError):
        del vector.horizontal

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

    if CPYTHON:
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
