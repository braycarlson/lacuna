import asyncio
import copy
import inspect
import pickle
import sys
import weakref

import protocols

from collections.abc import Coroutine

from conftest import imbalance, raising, reduction_round


COUNTDOWN_SEND_MAX = 8


class Holder:
    level = protocols.Clamped(0, 10)


class Wheel(protocols.Circle):
    pass


class InternedChild(protocols.Interned):
    pass


def attribute_round(bag: protocols.Bag) -> None:
    assert isinstance(bag, protocols.Bag)

    bag.alpha = 1
    assert bag.alpha == 1
    del bag.alpha


def countdown_collect() -> list[int]:
    return asyncio.run(countdown_values())


def countdown_drive() -> list[int]:
    coroutine = countdown_values()

    try:
        result = countdown_finish(coroutine)
    finally:
        coroutine.close()

    return result


def countdown_finish(coroutine: Coroutine[object, None, list[int]]) -> list[int]:
    assert inspect.iscoroutine(coroutine)

    for _ in range(COUNTDOWN_SEND_MAX):
        try:
            coroutine.send(None)
        except StopIteration as stop:
            result: list[int] = stop.value
            break
    else:
        message = f'Countdown did not finish within {COUNTDOWN_SEND_MAX} sends'
        raise AssertionError(message)

    return result


async def countdown_values() -> list[int]:
    return [value async for value in protocols.Countdown(2)]


def descriptor_round(holder: Holder) -> None:
    assert isinstance(holder, Holder)

    holder.level = 25
    assert holder.level == 10
    del holder.level


def dictionary_cycle() -> None:
    circle = protocols.Circle(1.0)
    circle.self = circle


def handle_drop() -> None:
    handles = [protocols.Handle(1)]
    handles.clear()


def inplace_round(accumulator: protocols.Accumulator) -> None:
    assert isinstance(accumulator, protocols.Accumulator)

    accumulator += 1
    accumulator -= 1


def view_round(samples: protocols.Samples) -> None:
    assert isinstance(samples, protocols.Samples)

    with memoryview(samples) as view:
        assert view[0] == 1.0


def unraisable_ignore(unraisable: object) -> None:
    assert issubclass(unraisable.exc_type, Exception)


def weak_round() -> None:
    ring = protocols.Ring(1.0, 2.0)
    reference = weakref.ref(ring)
    assert reference() is ring


def test_inheritance_does_not_leak() -> None:
    ring = protocols.Ring(1.0, 3.0)

    assert not imbalance(lambda: protocols.Ring(1.0, 3.0))
    assert not imbalance(raising(protocols.Negative, lambda: protocols.Ring(3.0, 1.0)))
    assert not imbalance(lambda: protocols.ring_of(0.5, 2.0))
    assert not imbalance(ring.width)
    assert not imbalance(ring.area)
    assert not imbalance(lambda: protocols.Shape.grow(ring, 1.0))
    assert not imbalance(Wheel.unit)
    assert not imbalance(protocols.Circle.kind)
    assert not imbalance(lambda: pickle.loads(pickle.dumps(ring)), faults=False)
    assert not imbalance(lambda: pickle.dumps(ring))
    assert not imbalance(lambda: reduction_round(ring))
    assert not imbalance(raising(ValueError, lambda: protocols._lacuna_restore(protocols.Ring, ())))
    assert not imbalance(dictionary_cycle)
    assert not imbalance(weak_round)


def test_creators_do_not_leak() -> None:
    assert not imbalance(lambda: protocols.Interned(7))
    assert not imbalance(lambda: InternedChild(7))
    assert not imbalance(lambda: protocols.interned_built(InternedChild, 8))
    assert not imbalance(lambda: protocols.circle_built(Wheel, 1.0))
    assert not imbalance(raising(TypeError, protocols.Impostor))
    assert not imbalance(raising(TypeError, lambda: protocols.interned_built(int, 1)))
    assert not imbalance(raising(TypeError, lambda: protocols.interned_built(3, 1)))


def test_context_parameters_do_not_leak() -> None:
    assert not imbalance(protocols.module_name)
    assert not imbalance(raising(TypeError, lambda: protocols.module_name(1)))


def test_protocols_do_not_leak() -> None:
    shape = protocols.Shape(3)
    accumulator = protocols.Accumulator(0)
    bag = protocols.Bag()
    holder = Holder()
    samples = protocols.Samples(1.0)

    assert not imbalance(lambda: setattr(shape, 'doubled', 4.0))
    assert not imbalance(raising(protocols.Negative, lambda: setattr(shape, 'doubled', -1.0)))
    assert not imbalance(lambda: inplace_round(accumulator))
    assert not imbalance(raising(TypeError, lambda: inplace_round(protocols.Accumulator(None))))
    assert not imbalance(lambda: attribute_round(bag))
    assert not imbalance(raising(AttributeError, lambda: bag.missing))
    assert not imbalance(lambda: descriptor_round(holder))
    assert not imbalance(countdown_collect, faults=False)
    assert not imbalance(countdown_drive)
    assert not imbalance(lambda: view_round(samples))
    assert not imbalance(lambda: bytes(samples))


def session_round() -> None:
    session = protocols.Session('alpha')

    with session:
        formatted = format(session, 'x')

    reversed_name = list(reversed(session))
    copied = copy.deepcopy(session)
    restored = pickle.loads(pickle.dumps(session))

    assert formatted == 'alpha:x'
    assert bytes(session) == b'alpha'
    assert reversed_name == list(b'ahpla')
    assert dir(session) == ['closed', 'depth', 'name']
    assert copied.name == restored.name == 'alpha'


def test_session_dunders_do_not_leak() -> None:
    assert not imbalance(session_round)


def native_round() -> None:
    registry = protocols.Registry('names')
    registry['a'] = 1
    failure = protocols.ParseFailure('bad input', 3)

    assert failure.line == 3


def test_native_bases_do_not_leak() -> None:
    if protocols.native_bases:
        assert not imbalance(native_round)


def metaclass_round() -> None:
    palette = protocols.Palette

    assert len(palette) == 3
    assert list(palette) == ['red', 'green', 'blue']
    assert 'green' in palette
    assert palette[1] == 'green'
    assert repr(palette) == palette.describe() == 'Palette'


def test_native_metaclasses_do_not_leak() -> None:
    if protocols.native_metaclasses:
        assert not imbalance(metaclass_round)
        assert not imbalance(raising(IndexError, lambda: protocols.Palette[9]))


def test_generic_subscripts_do_not_leak() -> None:
    assert not imbalance(lambda: protocols.Bag[int])


def test_deinit_errors_do_not_leak() -> None:
    previous = sys.unraisablehook
    sys.unraisablehook = unraisable_ignore

    try:
        assert not imbalance(handle_drop)
        assert not imbalance(lambda: protocols.Handle(0))
    finally:
        sys.unraisablehook = previous
