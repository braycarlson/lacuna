import functools
import gc
import math
import pickle
import struct
import sys

import protocols

from hypothesis import given, settings
from hypothesis import strategies as st

from conftest import HOSTILE_ARGUMENT_COUNT_MAX, hostile_check, hostile_targets, hostile_values


FINITE_MAX = 1e150
FINITE = st.floats(allow_nan=False, allow_infinity=False, min_value=0, max_value=FINITE_MAX)
HOSTILE_SETTINGS = settings(database=None, deadline=None, max_examples=2000)
SETTINGS = settings(database=None, deadline=None, max_examples=400)
SIGNED_64 = (-(2**63), 2**63 - 1)
SIGNED_64_VALUES = st.integers(min_value=SIGNED_64[0], max_value=SIGNED_64[1])
STEP_COUNT_MAX = 16


@SETTINGS
@given(inner=FINITE, extra=FINITE, factor=st.floats(min_value=0.5, max_value=4))
def test_ring_pickle_round_trip(*, inner: float, extra: float, factor: float) -> None:
    assert 0 <= inner <= FINITE_MAX
    assert 0 <= extra <= FINITE_MAX
    assert 0.5 <= factor <= 4

    outer = inner + extra
    ring = protocols.Ring(inner, outer)
    ring.grow(factor)
    restored = pickle.loads(pickle.dumps(ring))

    assert type(restored) is protocols.Ring
    assert restored.inner == inner
    assert restored.radius == outer
    assert restored.scale == ring.scale
    assert restored.width() == ring.width()


@SETTINGS
@given(start=SIGNED_64_VALUES, steps=st.lists(SIGNED_64_VALUES, max_size=STEP_COUNT_MAX))
def test_accumulator_matches_python(start: int, steps: list[int]) -> None:
    assert SIGNED_64[0] <= start <= SIGNED_64[1]
    assert len(steps) <= STEP_COUNT_MAX

    accumulator = protocols.Accumulator(start)
    expected = start

    for step in steps:
        if not SIGNED_64[0] <= expected + step <= SIGNED_64[1]:
            break

        accumulator += step
        expected += step

    assert accumulator.total == expected


@SETTINGS
@given(names=st.lists(st.text('abcdefgh', min_size=1, max_size=8), max_size=4, unique=True))
def test_bag_matches_dictionary(names: list[str]) -> None:
    assert len(set(names)) == len(names)
    assert all(name.isidentifier() for name in names)

    bag = protocols.Bag()
    expected = {}

    for index, name in enumerate(names):
        setattr(bag, name, index)
        expected[name] = index

    assert bag.size() == len(expected)
    assert {name: getattr(bag, name) for name in expected} == expected


@SETTINGS
@given(start=st.floats(allow_nan=False, allow_infinity=False, width=64))
def test_buffer_matches_values(start: float) -> None:
    assert math.isfinite(start)

    samples = protocols.Samples(start)
    unpacked = struct.unpack('6d', bytes(samples))
    expected = [start + index for index in range(6)]

    assert list(unpacked) == expected
    assert memoryview(samples).tolist() == expected


@HOSTILE_SETTINGS
@given(data=st.data())
def test_hostile_arguments_raise_cleanly(data: st.DataObject) -> None:
    assert isinstance(data, st.DataObject)

    instances = [
        protocols.Shape(3),
        protocols.Circle(1.0),
        protocols.Ring(1.0, 2.0),
        protocols.Accumulator(1),
        protocols.Bag(),
        protocols.Clamped(0, 1),
        protocols.Countdown(1),
        protocols.Samples(0.0),
        protocols.Handle(0),
        protocols.Session('alpha'),
    ]

    point = protocols.geometry.Point(1.0, 2.0)
    targets = hostile_targets(protocols, instances) + hostile_targets(protocols.geometry, [point])
    pool = hostile_values()
    values = st.integers(min_value=0, max_value=len(pool) - 1).map(pool.__getitem__)
    target_index = data.draw(st.integers(min_value=0, max_value=len(targets) - 1))
    arguments = data.draw(st.lists(values, max_size=HOSTILE_ARGUMENT_COUNT_MAX))
    names = st.sampled_from(['radius', 'inner', 'outer', 'sides', 'value', 'bogus'])
    keywords = data.draw(st.dictionaries(names, values, max_size=2))
    call = functools.partial(targets[target_index], *arguments, **keywords)
    reported: list[type] = []
    previous = sys.unraisablehook
    sys.unraisablehook = functools.partial(unraisable_note, reported)

    try:
        hostile_check(call)
        gc.collect()
    finally:
        sys.unraisablehook = previous

    assert all(kind is protocols.Unflushed for kind in reported), reported


def unraisable_note(reported: list[type], unraisable: object) -> None:
    assert len(reported) < HOSTILE_ARGUMENT_COUNT_MAX + 1
    assert issubclass(unraisable.exc_type, BaseException)

    reported.append(unraisable.exc_type)
