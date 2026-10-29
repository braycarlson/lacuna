import array
import asyncio
import copy
import functools
import gc
import operator
import os
import pickle
import sys
import types
import weakref

import pytest

import protocols

from collections.abc import Callable

from conftest import CPYTHON
from protocols import geometry


COLLECT_ROUNDS = 4
UNRAISABLE_OBJECT = CPYTHON or sys.version_info >= (3, 12)


class Wheel(protocols.Circle):
    pass


class Holder:
    level = protocols.Clamped(0, 10)


class Buffered(protocols.Handle):
    pass


class InternedChild(protocols.Interned):
    pass


class Logged(protocols.Handle):
    def __del__(self) -> None:
        assert isinstance(self, Logged)


def test_submodule() -> None:
    assert geometry is protocols.geometry
    assert sys.modules['protocols.geometry'] is geometry
    assert geometry.__name__ == 'protocols.geometry'
    assert geometry.qualified() == 'protocols.geometry'
    assert geometry.Point.__module__ == 'protocols.geometry'
    assert geometry.distance(geometry.Point(0, 0), geometry.Point(3, 4)) == 5.0
    assert geometry.Point.origin().horizontal == 0.0

    restored = pickle.loads(pickle.dumps(geometry.Point(1, 2)))

    assert type(restored) is geometry.Point
    assert restored.vertical == 2.0

    with pytest.raises(TypeError):
        geometry.distance(protocols.Shape(1), geometry.Point(0, 0))


def test_module_object_context() -> None:
    assert protocols.module_name() == 'protocols'

    with pytest.raises(TypeError):
        protocols.module_name(1)


def test_inheritance_layout() -> None:
    circle = protocols.Circle(2.0)

    assert isinstance(circle, protocols.Shape)
    assert issubclass(protocols.Ring, protocols.Circle)
    assert protocols.Ring.__mro__[:3] == (protocols.Ring, protocols.Circle, protocols.Shape)
    assert circle.sides == 0
    assert circle.radius == 2.0
    assert circle.area() == pytest.approx(4 * 3.141592653589793)

    circle.grow(2.0)

    assert circle.scale == 2.0
    assert circle.area() == pytest.approx(16 * 3.141592653589793)


def test_inheritance_two_levels() -> None:
    ring = protocols.Ring(1.0, 3.0)

    assert ring.inner == 1.0
    assert ring.radius == 3.0
    assert ring.sides == 0
    assert ring.width() == 2.0
    assert ring.area() == pytest.approx(9 * 3.141592653589793)

    with pytest.raises(protocols.Negative):
        protocols.Ring(3.0, 1.0)


def test_extended_result() -> None:
    ring = protocols.ring_of(0.5, 2.0)

    assert type(ring) is protocols.Ring
    assert ring.width() == 1.5
    assert ring.scale == 1.0


def test_base_methods_accept_derived() -> None:
    ring = protocols.Ring(1.0, 2.0)

    protocols.Shape.grow(ring, 3.0)

    assert ring.scale == 3.0

    with pytest.raises(TypeError):
        protocols.Circle.area(protocols.Shape(3))


def test_derived_not_constructible_without_initializer() -> None:
    shape = protocols.Shape(4)

    assert shape.sides == 4

    if CPYTHON:
        assert not hasattr(shape, '__dict__')


def test_class_method_receives_class() -> None:
    assert protocols.Shape.kind() == 'Shape'
    assert protocols.Circle.kind() == 'Circle'
    assert Wheel.kind() == 'Wheel'
    assert protocols.Ring(1.0, 2.0).kind() == 'Ring'

    unit = Wheel.unit()

    assert type(unit) is Wheel
    assert unit.radius == 1.0
    assert type(protocols.Circle.unit()) is protocols.Circle


def test_subclass_hook_receives_class_keywords() -> None:
    class Pentagon(protocols.Shape, sides=5):
        pass

    class Spoked(Wheel):
        pass

    assert Pentagon.sides_declared == 5
    assert Pentagon(3).sides == 3
    assert Wheel.sides_declared == 0
    assert Spoked.sides_declared == 0
    assert 'sides_declared' not in vars(protocols.Shape)

    with pytest.raises(TypeError, match='unknown'):

        class Unknown(protocols.Shape, unknown=1):
            pass


def test_new_returns_one_instance_per_class_and_key() -> None:
    first = protocols.Interned(3)
    child = InternedChild(3)

    assert protocols.Interned(key=3) is first
    assert protocols.Interned(4) is not first
    assert first.key == 3
    assert InternedChild(3) is child
    assert child is not first
    assert type(child) is InternedChild

    with pytest.raises(TypeError, match='key'):
        protocols.Interned()


def test_new_rejects_a_foreign_result() -> None:
    with pytest.raises(TypeError, match='not an instance'):
        protocols.Impostor()


def test_instance_new_builds_the_named_class() -> None:
    built = protocols.interned_built(protocols.Interned, 5)
    wheel = protocols.circle_built(Wheel, 2.0)

    assert built.key == 5
    assert built is not protocols.Interned(5)
    assert type(wheel) is Wheel
    assert wheel.radius == 2.0
    assert wheel.sides == 0

    with pytest.raises(TypeError, match='expects a type'):
        protocols.interned_built(3, 1)

    with pytest.raises(TypeError, match='subclass'):
        protocols.interned_built(protocols.Shape, 1)


def test_property_setter() -> None:
    shape = protocols.Shape(3)

    assert shape.doubled == 2.0

    shape.doubled = 10.0

    assert shape.scale == 5.0

    with pytest.raises(protocols.Negative):
        shape.doubled = -1.0

    with pytest.raises(TypeError):
        shape.doubled = 'x'

    with pytest.raises(TypeError):
        del shape.doubled

    with pytest.raises(AttributeError):
        shape.scale = 1.0


def test_deinit_error_reaches_unraisable_hook() -> None:
    handles = [protocols.Handle(3)]
    identity = id(handles[0]) if UNRAISABLE_OBJECT else None
    seen = unraisable_collect(handles.clear)

    assert seen == [(protocols.Unflushed, 'the handle was dropped with writes pending', identity)]


def test_deinit_without_error_is_silent() -> None:
    handles = [protocols.Handle(3)]
    handles[0].flush()

    assert unraisable_collect(handles.clear) == []


def test_deinit_error_of_a_python_subclass() -> None:
    handles = [Buffered(1)]
    identity = id(handles[0]) if UNRAISABLE_OBJECT else None
    seen = unraisable_collect(handles.clear)

    assert seen == [(protocols.Unflushed, 'the handle was dropped with writes pending', identity)]

    handles = [Logged(1)]
    seen = unraisable_collect(handles.clear)

    assert seen == [(protocols.Unflushed, 'the handle was dropped with writes pending', None)]


def test_deinit_error_hook_may_keep_the_instance() -> None:
    kept: list[object] = []
    handles = [protocols.Handle(2)]
    previous = sys.unraisablehook
    sys.unraisablehook = functools.partial(unraisable_keep, kept)

    try:
        handles.clear()
        collect()
    finally:
        sys.unraisablehook = previous

    assert len(kept) == 1

    if UNRAISABLE_OBJECT:
        assert type(kept[0]) is protocols.Handle

        with pytest.raises(TypeError, match='never initialized'):
            kept[0].flush()
    else:
        assert kept[0] is None

    kept.clear()
    collect()


def collect() -> None:
    for _ in range(COLLECT_ROUNDS):
        gc.collect()


def unraisable_collect(drop: Callable[[], None]) -> list[tuple[type, str, int | None]]:
    seen: list[tuple[type, str, int | None]] = []
    previous = sys.unraisablehook
    sys.unraisablehook = functools.partial(unraisable_record, seen)

    try:
        drop()
        collect()
    finally:
        sys.unraisablehook = previous

    return seen


def unraisable_keep(kept: list[object], unraisable: object) -> None:
    assert not kept
    assert unraisable.exc_type is protocols.Unflushed

    kept.append(unraisable.object)


def unraisable_record(
    seen: list[tuple[type, str, int | None]],
    unraisable: object,
) -> None:
    assert not seen
    assert issubclass(unraisable.exc_type, Exception)

    target = unraisable.object
    identity = None if target is None else id(target)
    record = (unraisable.exc_type, str(unraisable.exc_value), identity)

    seen.append(record)


def test_generic_class_subscripts() -> None:
    alias = protocols.Bag[int]

    assert isinstance(alias, types.GenericAlias)
    assert alias.__origin__ is protocols.Bag
    assert alias.__args__ == (int,)
    assert isinstance(alias(), protocols.Bag)


def test_dunders_resolved_by_name() -> None:
    session = protocols.Session('alpha')

    with session as entered:
        assert entered is session
        assert session.depth == 1

    assert session.closed

    asyncio.run(session_drive(session))

    assert format(session, '>3') == 'alpha:>3'
    assert bytes(session) == b'alpha'
    assert list(reversed(session)) == list(b'ahpla')
    assert dir(session) == ['closed', 'depth', 'name']
    assert os.fspath(session) == 'alpha'
    assert session.__missing__('key') == 'missing key'
    assert complex(session) == 0j
    assert round(session) == 5
    assert round(session, 2) == 7
    assert session.__sizeof__() > 0
    assert operator.length_hint(session) == 5
    assert copy.copy(session).name == 'alpha'
    assert copy.copy(session) is not session
    assert copy.deepcopy(session).name == 'alpha'
    assert pickle.loads(pickle.dumps(session)).name == 'alpha'
    assert session.__getnewargs__() == ('alpha',)

    if CPYTHON:
        assert sys.getsizeof(session) >= session.__sizeof__()


async def session_drive(session: protocols.Session) -> None:
    assert session.depth == 0

    async with session as entered:
        assert entered is False
        assert session.depth == 1

    assert session.closed


def test_native_bases() -> None:
    assert hasattr(protocols, 'Registry') is protocols.native_bases
    assert hasattr(protocols, 'ParseFailure') is protocols.native_bases

    if protocols.native_bases:
        native_check()


def native_check() -> None:
    registry = protocols.Registry('names')
    registry['a'] = 1
    registry.update(b=2)

    assert isinstance(registry, dict)
    assert dict(registry) == {'a': 1, 'b': 2}
    assert registry.label == 'names'
    assert len(registry) == 2

    failure = protocols.ParseFailure('bad input', 3)

    with pytest.raises(protocols.ParseFailure) as information:
        raise failure

    assert isinstance(information.value, Exception)
    assert information.value.line == 3
    assert str(information.value) == 'bad input'


def test_native_metaclass() -> None:
    assert hasattr(protocols, 'Catalog') is protocols.native_metaclasses
    assert hasattr(protocols, 'Palette') is protocols.native_metaclasses

    if not CPYTHON:
        assert not protocols.native_metaclasses

    if sys.version_info < (3, 12):
        assert not protocols.native_metaclasses

    if protocols.native_metaclasses:
        metaclass_check()
        metaclass_classes_are_collected()


def metaclass_check() -> None:
    palette = protocols.Palette

    assert type(palette) is protocols.Catalog
    assert issubclass(protocols.Catalog, type)
    assert len(palette) == 3
    assert palette[0] == 'red'
    assert palette[-1] == 'blue'
    assert list(palette) == ['red', 'green', 'blue']
    assert 'green' in palette
    assert 'pink' not in palette
    assert repr(palette) == 'Palette'
    assert palette.describe() == 'Palette'
    assert palette(3).shade == 3

    class Warm(palette):
        members = ('amber', 'rust')

    dynamic = protocols.Catalog('Dynamic', (), {'members': (1, 2)})

    assert type(Warm) is protocols.Catalog
    assert list(Warm) == ['amber', 'rust']
    assert Warm.describe().endswith('.Warm')
    assert Warm(9).shade == 9
    assert len(dynamic) == 2

    with pytest.raises(IndexError):
        palette[5]

    with pytest.raises(TypeError):
        protocols.Catalog.describe(5)

    bare = protocols.Catalog('Bare', (), {})

    with pytest.raises(AttributeError):
        assert len(bare) >= 0


def metaclass_classes_are_collected() -> None:
    dynamic = protocols.Catalog('Transient', (), {'members': ()})
    reference = weakref.ref(dynamic)

    del dynamic

    for _ in range(COLLECT_ROUNDS):
        gc.collect()

    assert reference() is None


def test_instance_dictionary() -> None:
    circle = protocols.Circle(1.0)
    circle.note = 'kept'

    assert circle.__dict__ == {'note': 'kept'}

    if CPYTHON:
        assert protocols.Circle.__dictoffset__ > 0
        assert protocols.Ring.__dictoffset__ == protocols.Circle.__dictoffset__

    del circle.note

    assert circle.__dict__ == {}


def test_instance_dictionary_cycle_is_collected() -> None:
    circle = protocols.Circle(1.0)
    circle.self = circle
    reference = weakref.ref(Wheel(1.0))
    del circle
    gc.collect()

    assert reference() is None


def test_weak_references() -> None:
    ring = protocols.Ring(1.0, 2.0)
    reference = weakref.ref(ring)

    assert reference() is ring

    del ring
    gc.collect()

    assert reference() is None

    if CPYTHON:
        assert protocols.Ring.__weakrefoffset__ > protocols.Ring.__dictoffset__

        with pytest.raises(TypeError):
            weakref.ref(protocols.Shape(1))


def test_pickle_derived() -> None:
    ring = protocols.Ring(1.0, 4.0)
    ring.grow(2.0)
    restored = pickle.loads(pickle.dumps(ring))

    assert type(restored) is protocols.Ring
    assert restored.inner == 1.0
    assert restored.radius == 4.0
    assert restored.scale == 2.0
    assert copy.deepcopy(protocols.Circle(3.0)).radius == 3.0

    wheel = Wheel(2.0)
    wheel.label = 'front'
    copied = pickle.loads(pickle.dumps(wheel))

    assert type(copied) is Wheel
    assert copied.label == 'front'


def test_pickle_rejects_malformed_state() -> None:
    with pytest.raises(TypeError):
        protocols._lacuna_restore(protocols.Ring, {'inner': 1.0})

    with pytest.raises(ValueError, match='wrong length'):
        protocols._lacuna_restore(protocols.Ring, ({'inner': 1.0},))


def test_inplace_operators() -> None:
    accumulator = protocols.Accumulator(5)
    retained = (accumulator,)
    accumulator += 3
    accumulator -= 1

    assert accumulator is retained[0]
    assert accumulator.total == 7

    accumulator **= 2

    assert accumulator.total == 49

    with pytest.raises(TypeError):
        accumulator += 'x'

    with pytest.raises(OverflowError):
        accumulator += 2**63 - 1

    with pytest.raises(TypeError):
        pow(accumulator, 2, 3)


def test_attribute_hooks() -> None:
    bag = protocols.Bag()
    bag.alpha = 1
    bag.beta = 2

    assert bag.alpha == 1
    assert bag.beta == 2
    assert bag.size() == 2

    del bag.alpha

    assert bag.size() == 1

    assert not hasattr(bag, 'alpha')

    with pytest.raises(AttributeError):
        del bag.alpha

    with pytest.raises(TypeError):
        bag.gamma = 'text'

    bag.c = 3
    bag.d = 4
    bag.e = 5

    with pytest.raises(MemoryError):
        bag.f = 6


def test_descriptor() -> None:
    holder = Holder()
    holder.level = 25

    assert holder.level == 10

    holder.level = -3

    assert holder.level == 0
    assert Holder.level is None

    holder.level = 7
    del holder.level

    assert holder.level == 0


def test_async_iteration() -> None:
    assert asyncio.run(countdown_collected()) == [2, 1, 0]


async def countdown_collected() -> list[int]:
    return [value async for value in protocols.Countdown(3)]


def test_await() -> None:
    assert asyncio.run(countdown_awaited()) == 2


async def countdown_awaited() -> object:
    return await protocols.Countdown(2)


def test_buffer_export() -> None:
    samples = protocols.Samples(1.0)
    view = memoryview(samples)

    assert view.format == 'd'
    assert view.itemsize == 8
    assert view.shape == (6,)
    assert view.tolist() == [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]

    view[0] = 10.0
    view.release()

    numbers = array.array('d')
    numbers.frombytes(samples)

    assert samples.total() == 30.0
    assert numbers.tolist() == [10.0, 2.0, 3.0, 4.0, 5.0, 6.0]
    assert bytes(samples) == numbers.tobytes()
    assert memoryview(samples).cast('B').nbytes == 48


def test_buffer_keeps_owner_alive() -> None:
    view = memoryview(protocols.Samples(2.0))
    gc.collect()

    assert view[5] == 7.0


def test_power_with_foreign_operands() -> None:
    accumulator = protocols.Accumulator(2)

    assert pow(accumulator, 3).total == 8
    assert accumulator.total == 2

    with pytest.raises(TypeError):
        pow(2, 3, accumulator)

    with pytest.raises(TypeError):
        pow(accumulator, 3, 5)

    assert accumulator.__ipow__(2, None) is accumulator
    assert accumulator.total == 4
    assert accumulator.__ipow__(2, 7) is NotImplemented


def test_attribute_hooks_reject_non_text_names() -> None:
    bag = protocols.Bag()

    with pytest.raises(TypeError, match='attribute name must be str'):
        bag.__getattribute__(0)

    with pytest.raises(TypeError, match='attribute name must be str'):
        bag.__setattr__(0, 1)

    with pytest.raises(TypeError, match='attribute name must be str'):
        bag.__delattr__(0)


def test_python_subclass_attribute_fallback() -> None:
    class Pouch(protocols.Bag):
        pass

    pouch = Pouch()
    pouch.alpha = 4

    assert pouch.alpha == 4
    assert pouch.size() == 1
    assert not hasattr(pouch, 'missing')


def test_deep_python_subclass_chain() -> None:
    chained = protocols.Shape

    for _ in range(300):
        chained = type('Chained', (chained,), {})

    shape = chained(5)

    assert shape.sides == 5
    assert shape.doubled == 2.0
    assert isinstance(shape, protocols.Shape)
