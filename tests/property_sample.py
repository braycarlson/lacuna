import array
import ctypes
import functools
import math
import operator

import pytest
import sample

from hypothesis import given, settings
from hypothesis import strategies as st
from hypothesis.stateful import RuleBasedStateMachine, initialize, invariant, rule

from conftest import (
    HOSTILE_ARGUMENT_COUNT_MAX,
    hostile_check,
    hostile_targets,
    hostile_values,
    raised,
)


HOSTILE_SETTINGS = settings(database=None, deadline=None, max_examples=2000)
SETTINGS = settings(database=None, deadline=None, max_examples=400)
SHOUTED_BYTES_MAX = 256
SIGNED_32 = (-(2**31), 2**31 - 1)
SIGNED_64 = (-(2**63), 2**63 - 1)
TABLE_KEYS = (0, 7)
UNSIGNED_64 = (0, 2**64 - 1)
UNSIGNED_8 = (0, 2**8 - 1)


def ascii_upper(text: str) -> str:
    assert isinstance(text, str)

    characters = [item.upper() if 'a' <= item <= 'z' else item for item in text]

    assert len(characters) == len(text)

    return ''.join(characters)


def float32(value: float) -> float:
    assert isinstance(value, float | int)

    result = ctypes.c_float(value).value

    assert math.isnan(result) == math.isnan(value)

    return result


def inside(value: int, bounds: tuple[int, int]) -> bool:
    assert isinstance(value, int)
    assert bounds[0] < bounds[1]

    return bounds[0] <= value <= bounds[1]


def integers_near(bounds: tuple[int, int]) -> st.SearchStrategy[int]:
    assert bounds[0] < bounds[1]
    assert bounds[0] <= 0 <= bounds[1]

    edges = [bounds[0] - 1, bounds[0], bounds[0] + 1, 0, -1, 1, bounds[1] - 1, bounds[1]]
    edges.append(bounds[1] + 1)

    wide = st.integers(min_value=bounds[0] * 2 - 2, max_value=bounds[1] * 2 + 2)

    return st.sampled_from(edges) | wide


def same_float(*, left: float, right: float) -> bool:
    assert isinstance(left, float)
    assert isinstance(right, float)

    if math.isnan(left):
        return math.isnan(right)

    if left != right:
        return False

    return math.copysign(1.0, left) == math.copysign(1.0, right)


def surrogate(text: str) -> bool:
    assert isinstance(text, str)

    return any(0xD800 <= ord(item) <= 0xDFFF for item in text)


@SETTINGS
@given(left=integers_near(SIGNED_64), right=integers_near(SIGNED_64))
def test_add_matches_python(*, left: int, right: int) -> None:
    assert abs(left) <= 2**64 + 2
    assert abs(right) <= 2**64 + 2

    expected = left + right

    if all(inside(value, SIGNED_64) for value in (left, right, expected)):
        assert sample.add(left, right) == expected
    else:
        with pytest.raises(OverflowError):
            sample.add(left, right)


@SETTINGS
@given(
    value=integers_near(UNSIGNED_8) | integers_near(UNSIGNED_64) | integers_near(SIGNED_32),
)
def test_integer_kinds_match_their_ranges(value: int) -> None:
    assert abs(value) <= 2**65 + 2

    for function, bounds in ((sample.narrow, UNSIGNED_8), (sample.wide, UNSIGNED_64)):
        if inside(value, bounds):
            assert function(value) == value
        else:
            with pytest.raises(OverflowError):
                function(value)

    if all(inside(item, SIGNED_32) for item in (value, -value)):
        assert sample.negate(value) == -value
    else:
        with pytest.raises(OverflowError):
            sample.negate(value)


@SETTINGS
@given(value=st.floats() | st.integers(min_value=-(2**60), max_value=2**60))
def test_half_rounds_through_float32(value: float) -> None:
    assert isinstance(value, float | int)

    expected = float32(float32(value) * 0.5)

    assert same_float(left=sample.half(value), right=expected)


@SETTINGS
@given(
    text=st.text(st.characters(codec='utf-8') | st.sampled_from(['\ud800', '\0']), max_size=80),
    times=st.integers(min_value=-1, max_value=256),
)
def test_shout_matches_ascii_upper(text: str, times: int) -> None:
    assert len(text) <= 80
    assert -1 <= times <= 256

    if surrogate(text):
        with pytest.raises(UnicodeEncodeError):
            sample.shout(text, times)
    elif not inside(times, UNSIGNED_8):
        with pytest.raises(OverflowError):
            sample.shout(text, times)
    else:
        shout_valid(text, times)


def shout_valid(text: str, times: int) -> None:
    assert not surrogate(text)
    assert inside(times, UNSIGNED_8)

    if times == 0:
        with pytest.raises(sample.Empty):
            sample.shout(text, times)
    elif len(text.encode()) * times > SHOUTED_BYTES_MAX:
        with pytest.raises(sample.Negative):
            sample.shout(text, times)
    else:
        assert sample.shout(text, times) == ascii_upper(text) * times


@SETTINGS
@given(text=st.text(st.characters(codec='utf-8') | st.just('\0'), max_size=64))
def test_terminated_counts_bytes(text: str) -> None:
    assert not surrogate(text)

    if '\0' in text:
        with pytest.raises(ValueError, match='embedded null'):
            sample.terminated(text)
    else:
        assert sample.terminated(text) == len(text.encode())


@SETTINGS
@given(data=st.binary(max_size=200))
def test_reverse_matches_slice(data: bytes) -> None:
    assert len(data) <= 200

    expected = data[:64][::-1]
    mutable = bytearray(data)
    view = memoryview(data)

    assert sample.reverse(data) == expected
    assert sample.reverse(mutable) == expected
    assert sample.reverse(view) == expected
    assert sample.checksum(data) == sum(data)


@SETTINGS
@given(values=st.lists(st.floats(), max_size=40))
def test_total_matches_sequential_sum(values: list[float]) -> None:
    assert len(values) <= 40

    buffer = array.array('d', values)
    expected = functools.reduce(operator.add, values, 0.0)

    assert same_float(left=sample.total(buffer), right=expected)


@SETTINGS
@given(values=st.lists(st.floats(allow_nan=False), max_size=16), factor=st.floats())
def test_scale_matches_python(values: list[float], factor: float) -> None:
    assert len(values) <= 16
    assert isinstance(factor, float)

    buffer = array.array('d', values)
    expected = [value * factor for value in values]

    sample.scale(buffer, factor)

    pairs = zip(buffer, expected, strict=True)

    assert all(same_float(left=left, right=right) for left, right in pairs)


@SETTINGS
@given(numbers=st.lists(integers_near(SIGNED_64), max_size=10))
def test_doubled_matches_python(numbers: list[int]) -> None:
    assert len(numbers) <= 10

    doubled = [number * 2 for number in numbers]

    if len(numbers) > sample.count_max:
        with pytest.raises(ValueError, match='at most 8'):
            sample.doubled(numbers)
    elif all(inside(number, SIGNED_64) for number in doubled):
        assert sample.doubled(numbers) == doubled
    else:
        with pytest.raises(OverflowError):
            sample.doubled(numbers)


@SETTINGS
@given(left=integers_near(SIGNED_64), right=integers_near(SIGNED_64) | st.just(0))
def test_divide_matches_floor_division(*, left: int, right: int) -> None:
    assert abs(left) <= 2**64 + 2
    assert abs(right) <= 2**64 + 2

    if not all(inside(value, SIGNED_64) for value in (left, right)):
        with pytest.raises(OverflowError):
            sample.divide(left, right)
    elif right == 0:
        with pytest.raises(ZeroDivisionError):
            sample.divide(left, right)
    else:
        divide_nonzero(left=left, right=right)


def divide_nonzero(*, left: int, right: int) -> None:
    assert inside(left, SIGNED_64)
    assert right != 0

    if inside(left // right, SIGNED_64):
        assert sample.divide(left, right) == divmod(left, right)
    else:
        with pytest.raises(OverflowError):
            sample.divide(left, right)


@SETTINGS
@given(
    pair=st.tuples(integers_near(SIGNED_64), integers_near(SIGNED_64)),
    value=integers_near(SIGNED_32),
)
def test_pairs_and_optionals_round_trip(pair: tuple[int, int], value: int) -> None:
    assert len(pair) == 2
    assert abs(value) <= 2**32 + 2

    if all(inside(item, SIGNED_64) for item in pair):
        assert sample.swap(pair) == pair[::-1]
        assert sample.swap(list(pair)) == pair[::-1]
    else:
        with pytest.raises(OverflowError):
            sample.swap(pair)

    if inside(value, SIGNED_32):
        assert sample.maybe(value) == value * 2
    else:
        with pytest.raises(OverflowError):
            sample.maybe(value)

    assert sample.maybe(None) is None


@SETTINGS
@given(mode=st.sampled_from(list(sample.Mode)) | st.text(max_size=8) | st.integers())
def test_mode_flip_accepts_only_its_members(mode: object) -> None:
    assert isinstance(mode, sample.Mode | str | int)

    flipped = {sample.Mode.exact: sample.Mode.fast, sample.Mode.fast: sample.Mode.exact}

    if isinstance(mode, sample.Mode):
        assert sample.mode_flip(mode) is flipped[mode]
        assert sample.mode_flip(sample.mode_flip(mode)) is mode
    else:
        with pytest.raises(TypeError, match='must be Mode'):
            sample.mode_flip(mode)


FINITE = st.floats(allow_nan=False, allow_infinity=False)


@SETTINGS
@given(
    values=st.lists(st.floats(allow_nan=False, allow_infinity=False), max_size=24),
    window=st.slices(24),
)
def test_strided_sum_matches_slice(values: list[float], window: slice) -> None:
    assert len(values) <= 24
    assert isinstance(window, slice)

    view = memoryview(array.array('d', values))[window]
    expected = functools.reduce(operator.add, values[window], 0.0)

    assert sample.sum_strided(view) == expected


@SETTINGS
@given(
    values=st.lists(st.integers(*SIGNED_64), max_size=8),
    window=st.slices(8),
    index=st.integers(-9, 9),
)
def test_row_matches_list(values: list[int], window: slice, index: int) -> None:
    assert len(values) <= 8
    assert isinstance(window, slice)
    assert -9 <= index <= 9

    row = sample.Row(values)

    assert row[window] == values[window]

    present = index in range(-len(values), len(values))

    if present:
        assert row[index] == values[index]
    else:
        with pytest.raises(IndexError):
            row[index]


PAIR_VALUES = st.tuples(st.integers(*SIGNED_64), st.integers(*SIGNED_64))


@SETTINGS
@given(operands=st.tuples(PAIR_VALUES, PAIR_VALUES))
def test_derived_pair_matches_tuples(operands: tuple[tuple[int, int], tuple[int, int]]) -> None:
    assert len(operands) == 2

    left, right = operands
    first = sample.Pair(*left)
    second = sample.Pair(*right)

    assert (first == second) == (left == right)
    assert (first < second) == (left < right)
    assert (first <= second) == (left <= right)
    assert (first > second) == (left > right)
    assert (first >= second) == (left >= right)

    if left == right:
        assert hash(first) == hash(second)


SHAPES = st.one_of(
    st.builds(sample.Shape.Circle, radius=FINITE),
    st.builds(sample.Shape.Square, side=FINITE),
    st.just(sample.Shape.Empty()),
)


@SETTINGS
@given(shape=SHAPES, factor=FINITE)
def test_variant_classes_round_trip(shape: sample.Shape, factor: float) -> None:
    assert isinstance(shape, sample.Shape)
    assert math.isfinite(factor)

    echoed = sample.shape_echo(shape)
    scaled = sample.shape_scaled(shape, factor)

    assert echoed == shape
    assert hash(echoed) == hash(shape)
    assert type(scaled) is type(shape)
    assert sample.shape_echo(scaled) == scaled


@SETTINGS
@given(horizontal=st.floats(), vertical=st.floats(), label=st.none() | st.text(max_size=8))
def test_records_round_trip(*, horizontal: float, vertical: float, label: str | None) -> None:
    assert isinstance(horizontal, float)
    assert isinstance(vertical, float)
    assert label is None or len(label) <= 8

    point = {'horizontal': horizontal, 'vertical': vertical}
    values = array.array('d', [horizontal, vertical])
    expected = math.hypot(horizontal, vertical)
    summary = sample.summarize(values, label)

    if math.isnan(expected):
        assert math.isnan(sample.norm(point))
    else:
        assert math.isclose(sample.norm(point), expected, rel_tol=1e-15)

    assert summary['count'] == 2
    assert summary['label'] == label


@SETTINGS
@given(
    left=st.tuples(st.floats(allow_nan=False), st.floats(allow_nan=False)),
    right=st.tuples(st.floats(allow_nan=False), st.floats(allow_nan=False)),
    factor=st.floats(allow_nan=False),
)
def test_vector_matches_component_arithmetic(
    *,
    left: tuple[float, float],
    right: tuple[float, float],
    factor: float,
) -> None:
    assert len(left) == 2
    assert len(right) == 2
    assert not math.isnan(factor)

    first = sample.Vector(*left)
    second = sample.Vector(*right)
    total = first + second
    scaled = first * factor

    assert same_float(left=total.horizontal, right=left[0] + right[0])
    assert same_float(left=total.vertical, right=left[1] + right[1])
    assert same_float(left=scaled.horizontal, right=left[0] * factor)
    assert (first == second) == (left == right)
    assert bool(first) == (left != (0.0, 0.0))


@SETTINGS
@given(index=integers_near(SIGNED_64))
def test_vector_index_matches_sequence(index: int) -> None:
    assert abs(index) <= 2**64 + 2

    vector = sample.Vector(3.0, 4.0)
    components = {0: 3.0, 1: 4.0, -1: 4.0, -2: 3.0}

    if index in components:
        assert vector[index] == components[index]
    else:
        with pytest.raises(IndexError):
            operator.getitem(vector, index)


class TableMachine(RuleBasedStateMachine):
    keys = st.integers(min_value=-2, max_value=10)

    @initialize()
    def table_create(self) -> None:
        self.model: dict[int, int] = {}
        self.table = sample.Table()

        assert len(self.table) == 0

    @rule(key=keys, value=integers_near(SIGNED_64))
    def assign(self, *, key: int, value: int) -> None:
        assert -2 <= key <= 10
        assert abs(value) <= 2**64 + 2

        if all(inside(item, bounds) for item, bounds in ((key, TABLE_KEYS), (value, SIGNED_64))):
            self.table[key] = value
            self.model[key] = value
        else:
            with pytest.raises(OverflowError):
                operator.setitem(self.table, key, value)

    @rule(key=keys)
    def remove(self, key: int) -> None:
        assert -2 <= key <= 10

        if not inside(key, TABLE_KEYS):
            with pytest.raises(OverflowError):
                operator.delitem(self.table, key)
        elif key in self.model:
            del self.table[key]
            del self.model[key]
        else:
            with pytest.raises(KeyError):
                operator.delitem(self.table, key)

    @rule(key=st.integers(min_value=TABLE_KEYS[0], max_value=TABLE_KEYS[1]))
    def read(self, key: int) -> None:
        assert inside(key, TABLE_KEYS)

        if key in self.model:
            assert self.table[key] == self.model[key]
        else:
            with pytest.raises(KeyError):
                operator.getitem(self.table, key)

    @invariant()
    def invariant_length(self) -> None:
        assert len(self.table) == len(self.model)


class CounterMachine(RuleBasedStateMachine):
    @initialize(start=integers_near(SIGNED_64), span=st.integers(min_value=-3, max_value=6))
    def counter_create(self, *, start: int, span: int) -> None:
        assert abs(start) <= 2**64 + 2
        assert -3 <= span <= 6

        stop = start + span

        if not all(inside(item, SIGNED_64) for item in (start, stop)):
            start = 0
            stop = abs(span)

        if stop < start:
            with pytest.raises(sample.Negative):
                sample.Counter(stop, start=start)

            stop = start

        self.counter = sample.Counter(stop, start=start)
        self.position = start
        self.stop = stop

    @rule(step=integers_near(SIGNED_64))
    def advance(self, step: int) -> None:
        assert abs(step) <= 2**64 + 2

        if not inside(step, SIGNED_64):
            with pytest.raises(OverflowError):
                self.counter(step)

            return

        moved = max(min(self.position + step, SIGNED_64[1]), SIGNED_64[0])
        self.position = min(moved, self.stop)
        result = self.counter(step)

        assert result == self.position

    @rule()
    def draw(self) -> None:
        assert self.position <= self.stop

        if self.position == self.stop:
            raised(StopIteration, functools.partial(next, self.counter))
        else:
            item = next(self.counter)

            assert item == self.position

            self.position += 1

    @rule(value=integers_near(SIGNED_64))
    def contains(self, value: int) -> None:
        assert abs(value) <= 2**64 + 2

        member = self.position <= value < self.stop

        assert (value in self.counter) == member

    @invariant()
    def invariant_position(self) -> None:
        assert self.counter.current == self.position


TestTable = TableMachine.TestCase
TestTable.settings = SETTINGS
TestCounter = CounterMachine.TestCase
TestCounter.settings = SETTINGS


@HOSTILE_SETTINGS
@given(data=st.data())
def test_hostile_arguments_raise_cleanly(data: st.DataObject) -> None:
    assert isinstance(data, st.DataObject)

    instances = [sample.Vector(1.0, 2.0), sample.Counter(5), sample.Table()]
    targets = hostile_targets(sample, instances)
    pool = hostile_values()
    values = st.integers(min_value=0, max_value=len(pool) - 1).map(pool.__getitem__)
    target_index = data.draw(st.integers(min_value=0, max_value=len(targets) - 1))
    arguments = data.draw(st.lists(values, max_size=HOSTILE_ARGUMENT_COUNT_MAX))
    names = st.sampled_from(['left', 'value', 'text', 'times', 'other', 'key', 'bogus'])
    keywords = data.draw(st.dictionaries(names, values, max_size=2))
    call = functools.partial(targets[target_index], *arguments, **keywords)

    hostile_check(call)
