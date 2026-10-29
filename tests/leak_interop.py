import datetime as dt
import decimal
import fractions
import ipaddress
import itertools
import logging
import pathlib
import pickle
import types
import uuid

import interop

from conftest import imbalance, raising, reduction_round


class Panel(interop.Shape):
    def __init__(self, *, width: float, height: float, name: str) -> None:
        assert width > 0
        assert height > 0
        assert name

        self.note = f'{name} {width}x{height}'


class Upper:
    def upper(self) -> int:
        return 1


def node_cycle() -> None:
    parent = interop.Node('parent')
    child = interop.Node('child', parent)

    parent.attach(0, child)


def refusing(value: int) -> int:
    assert isinstance(value, int)

    message = f'refused {value}'
    raise LookupError(message)


def test_diagnostics_do_not_leak() -> None:
    assert not imbalance(lambda: interop.parse('3..9'))
    assert not imbalance(raising(interop.RangeInverted, lambda: interop.parse('9..3')))
    assert not imbalance(raising(interop.SyntaxInvalid, lambda: interop.parse('9..x')))
    assert not imbalance(raising(interop.SyntaxInvalid, lambda: interop.parse('nine')))


def test_callbacks_do_not_leak() -> None:
    payload = [1, 2, 3]
    upper = Upper()

    assert not imbalance(lambda: interop.apply(abs, -14))
    assert not imbalance(raising(LookupError, lambda: interop.apply(refusing, 5)))
    assert not imbalance(
        raising(OverflowError, lambda: interop.apply(lambda value: 2**70 + value, 1))
    )
    assert not imbalance(lambda: interop.shout('quiet'))
    assert not imbalance(raising(TypeError, lambda: interop.shout(upper)))
    assert not imbalance(lambda: interop.item_length(payload))
    assert not imbalance(raising(AttributeError, lambda: interop.item_length(1)))
    assert not imbalance(lambda: interop.forward(lambda: payload))
    assert not imbalance(lambda: interop.forward_counted(lambda: payload))
    assert not imbalance(raising(AttributeError, lambda: interop.forward_counted(object)))
    assert not imbalance(raising(LookupError, lambda: interop.forward(lambda: refusing(1))))


def test_exceptions_do_not_leak() -> None:
    mapping = {'present': 4}
    failing = failing_function()

    assert not imbalance(lambda: interop.lookup(mapping, 'present'))
    assert not imbalance(lambda: interop.lookup(mapping, 'absent'))
    assert not imbalance(raising(TypeError, lambda: interop.lookup([], 'absent')))
    assert not imbalance(raising(interop.CallbackFailed, lambda: interop.guarded(failing)))
    assert not imbalance(lambda: interop.guarded(lambda: 7))
    assert not imbalance(lambda: interop.captured(failing))
    assert not imbalance(raising(RuntimeError, lambda: interop.captured(lambda: 1)))
    assert not imbalance(raising(LookupError, lambda: interop.rethrown(failing)))


def failing_function() -> object:
    def failing() -> int:
        return refusing(1)

    return failing


def test_warnings_do_not_leak() -> None:
    shape = interop.Shape(2, 3)

    subtract = raising(DeprecationWarning, lambda: interop.subtract(9, 4))
    surface = raising(DeprecationWarning, shape.surface)
    caution = raising(UserWarning, lambda: interop.caution('careful'))

    assert not imbalance(subtract, faults=False)
    assert not imbalance(surface, faults=False)
    assert not imbalance(caution, faults=False)


def test_signal_checks_do_not_leak() -> None:
    assert not imbalance(lambda: interop.interruptible(8))


def test_unbounded_containers_do_not_leak() -> None:
    values = list(range(8))
    data = bytearray(b'xy')
    mapping = {'a': 1, 'b': 2}

    assert not imbalance(lambda: interop.range_list(8))
    assert not imbalance(lambda: interop.list_total(values))
    assert not imbalance(raising(TypeError, lambda: interop.list_total((1, 2))))
    assert not imbalance(lambda: interop.squares(8))
    assert not imbalance(lambda: interop.dictionary_probe(dict(mapping), 'a'))
    assert not imbalance(lambda: interop.characters('abc'))
    assert not imbalance(lambda: interop.distinct(values))
    assert not imbalance(lambda: interop.spelled(8))
    assert not imbalance(lambda: interop.bytearray_grow(data, 0))
    assert not imbalance(lambda: interop.wrapped_lengths([1], (1,), {}, {1}, data))


def ledger_add(ledger: interop.Ledger) -> None:
    assert ledger.total >= 0

    ledger.add(1)


def test_python_names_do_not_leak() -> None:
    ledger = interop.Ledger(1)

    assert not imbalance(lambda: interop.python_doubled(python_value=21))
    assert not imbalance(raising(TypeError, lambda: interop.python_doubled(zig_value=1)))
    assert not imbalance(lambda: ledger_add(ledger))
    assert not imbalance(lambda: ledger.total)


def test_running_source_does_not_leak() -> None:
    assert not imbalance(lambda: interop.evaluated(40, 2))
    assert not imbalance(lambda: interop.executed('total = 1 + 2\n'))
    assert not imbalance(raising(SyntaxError, lambda: interop.executed('total = (')))
    assert not imbalance(raising(ZeroDivisionError, lambda: interop.executed('1 / 0\n')))


def test_value_types_and_object_calls_do_not_leak() -> None:
    half = fractions.Fraction(1, 2)
    six = ipaddress.IPv6Address('2001:db8::7')
    capsule = interop.capsule_made(41)
    target = Target()
    reference = interop.weak_reference(target)

    assert not imbalance(lambda: interop.fraction_echo(half))
    assert not imbalance(raising(TypeError, lambda: interop.fraction_echo(0.5)))
    assert not imbalance(lambda: interop.address_echo(six))
    assert not imbalance(lambda: interop.capsule_made(1))
    assert not imbalance(lambda: interop.capsule_read(capsule))
    assert not imbalance(raising(ValueError, lambda: interop.capsule_read(target)))
    assert not imbalance(lambda: interop.weak_reference(target))
    assert not imbalance(lambda: interop.weak_target(reference))
    assert not imbalance(raising(TypeError, lambda: interop.weak_target(target)))
    assert not imbalance(interop.singletons)
    assert not imbalance(interop.python_version)


def test_logging_does_not_leak() -> None:
    logging.getLogger('interop_zig').setLevel(logging.CRITICAL)

    assert not imbalance(lambda: interop.logged('quiet'))


def test_foreign_threads_do_not_leak() -> None:
    assert not imbalance(lambda: interop.fan_out(abs, 4), faults=False)
    assert not imbalance(raising(LookupError, lambda: interop.fan_out(refusing, 3)), faults=False)
    assert not imbalance(raising(TypeError, lambda: interop.fan_out(str, 2)), faults=False)


def test_new_conversions_do_not_leak() -> None:
    identifier = uuid.UUID(int=7)
    proxy = types.MappingProxyType({'ada': 1})
    keys = {1: 'a'}.keys()

    assert not imbalance(lambda: interop.rotate(1 + 2j))
    assert not imbalance(lambda: interop.rotate(3))
    assert not imbalance(raising(TypeError, lambda: interop.rotate('1')))
    assert not imbalance(lambda: interop.decimal_scale(decimal.Decimal('1.25'), 1))
    assert not imbalance(lambda: interop.decimal_scale(7, 1))
    assert not imbalance(
        raising(ValueError, lambda: interop.decimal_scale(decimal.Decimal('NaN'), 0))
    )
    assert not imbalance(
        raising(OverflowError, lambda: interop.decimal_scale(decimal.Decimal(2**130), 0))
    )
    assert not imbalance(lambda: interop.uuid_reverse(identifier))
    assert not imbalance(raising(TypeError, lambda: interop.uuid_reverse('x')))
    assert not imbalance(lambda: interop.frozen(keys))
    assert not imbalance(lambda: interop.invert(proxy))
    assert not imbalance(raising(TypeError, lambda: interop.invert([1])))


def test_object_api_does_not_leak() -> None:
    target = Target()
    mapping: dict[str, int] = {}
    items = [1, 2, 3]

    assert not imbalance(lambda: configure_fresh(target))
    assert not imbalance(raising(AttributeError, lambda: interop.configure(object())))
    assert not imbalance(lambda: store_fresh(mapping))
    assert not imbalance(raising(KeyError, lambda: interop.store({}, 'a', 1)))
    assert not imbalance(lambda: interop.summed(items))
    assert not imbalance(raising(LookupError, lambda: interop.summed(map(refusing, items))))
    assert not imbalance(raising(ValueError, lambda: interop.summed(itertools.repeat(0))))
    assert not imbalance(lambda: interop.split_count('a,b,c'))
    assert not imbalance(lambda: interop.describe(items))
    assert not imbalance(lambda: interop.inspect(3, int, 3))
    assert not imbalance(raising(TypeError, lambda: interop.inspect(items, list, items)))
    assert not imbalance(lambda: interop.dumps(mapping))
    assert not imbalance(raising(TypeError, lambda: interop.dumps(object())))


class Target:
    def __init__(self) -> None:
        self.legacy = 1


def configure_fresh(target: Target) -> None:
    assert isinstance(target, Target)

    target.legacy = 1
    interop.configure(target)


def store_fresh(mapping: dict[str, int]) -> None:
    assert isinstance(mapping, dict)

    mapping['stale'] = 0
    interop.store(mapping, 'fresh', 9)


def test_signatures_do_not_leak() -> None:
    assert not imbalance(lambda: interop.combine(1, 2, 3, scale=2, bonus=5))
    assert not imbalance(raising(TypeError, lambda: interop.combine(*range(10))))
    assert not imbalance(raising(TypeError, lambda: interop.combine(1, a=1, b=2, c=3, d=4, e=5)))
    assert not imbalance(raising(TypeError, lambda: interop.combine(first=1)))
    assert not imbalance(lambda: interop.keyword_count(a=1, b=2))
    assert not imbalance(lambda: interop.clamp(0.5, low=0.6))
    assert not imbalance(raising(TypeError, lambda: interop.clamp(0.5, 0.0, 1.0)))
    assert not imbalance(raising(ValueError, lambda: interop.clamp(0.5, low=1.0, high=0.0)))
    assert not imbalance(lambda: interop.difference(9, 4))
    assert not imbalance(raising(TypeError, lambda: interop.difference(9, right=4)))


def test_unions_do_not_leak() -> None:
    assert not imbalance(lambda: interop.measure('four'))
    assert not imbalance(lambda: interop.measure(None))
    assert not imbalance(raising(TypeError, lambda: interop.measure(1.5)))
    assert not imbalance(lambda: interop.parity(10))
    assert not imbalance(lambda: interop.parity(7))


def test_calendar_does_not_leak() -> None:
    zone = dt.timezone(dt.timedelta(hours=-6))
    day = dt.date(2026, 10, 23)
    clock = dt.time(23, 37, 5, 120)
    moment = dt.datetime(2026, 10, 23, 23, 37, 5, 120, tzinfo=zone)
    naive = moment.replace(tzinfo=None)
    span = dt.timedelta(days=-3, seconds=17, microseconds=9)
    aware = dt.time(1, tzinfo=dt.UTC)

    assert not imbalance(lambda: interop.moments(day, clock, moment, span))
    assert not imbalance(lambda: interop.moments(day, clock, naive, span))
    assert not imbalance(raising(ValueError, lambda: interop.moments(day, aware, naive, span)))
    assert not imbalance(
        raising(TypeError, lambda: interop.moments('2026-01-01', clock, naive, span))
    )
    assert not imbalance(lambda: interop.doubled_span(span))
    assert not imbalance(raising(OverflowError, lambda: interop.doubled_span(dt.timedelta.max)))


def test_paths_do_not_leak() -> None:
    path = pathlib.Path('x.tar.gz')

    assert not imbalance(lambda: interop.path_echo('a/b.txt'))
    assert not imbalance(lambda: interop.path_echo(path), faults=False)
    assert not imbalance(lambda: interop.path_echo(b'raw'))
    assert not imbalance(lambda: interop.extension(path), faults=False)
    assert not imbalance(raising(ValueError, lambda: interop.extension('a\x00b')))
    assert not imbalance(raising(TypeError, lambda: interop.extension(3)))


def test_sets_and_maps_do_not_leak() -> None:
    words = {'a', 'b'}
    scores = {'ada': 1, 'grace': 2}
    crowded = {str(index) for index in range(17)}

    assert not imbalance(lambda: interop.word_count(words))
    assert not imbalance(lambda: interop.word_count(frozenset(words)))
    assert not imbalance(raising(TypeError, lambda: interop.word_count(['a'])))
    assert not imbalance(raising(ValueError, lambda: interop.word_count(crowded)))
    assert not imbalance(lambda: interop.letters('banana'))
    assert not imbalance(lambda: interop.invert(scores))


def test_wide_integers_do_not_leak() -> None:
    assert not imbalance(lambda: interop.wide_add(2**200, -(2**199) + 7))
    assert not imbalance(raising(OverflowError, lambda: interop.wide_add(2**255, 0)))
    assert not imbalance(lambda: interop.unsigned_echo(2**128 - 1))
    assert not imbalance(raising(OverflowError, lambda: interop.unsigned_echo(-1)))
    assert not imbalance(raising(OverflowError, lambda: interop.unsigned_echo(2**128)))


def test_owned_text_does_not_leak() -> None:
    assert not imbalance(lambda: interop.repeat('ab', 3))
    assert not imbalance(raising(ValueError, lambda: interop.repeat('x' * 33, 1)))
    assert not imbalance(raising(interop.TextFull, lambda: interop.repeat('x' * 20, 2)))


def test_node_does_not_leak() -> None:
    payload = object()
    node = interop.Node('root', payload)

    assert not imbalance(lambda: interop.Node('leaf', payload))
    assert not imbalance(lambda: node.payload)
    assert not imbalance(lambda: setattr(node, 'payload', payload))
    assert not imbalance(lambda: node.label)
    assert not imbalance(lambda: setattr(node, 'label', 'renamed'))
    assert not imbalance(raising(ValueError, lambda: setattr(node, 'label', 'x' * 40)))
    assert not imbalance(lambda: node.attach(0, payload))
    assert not imbalance(lambda: node.child(0))
    assert not imbalance(lambda: node.attach(1, None))


def test_node_cycles_do_not_leak() -> None:
    assert not imbalance(node_cycle)


def test_shape_does_not_leak() -> None:
    shape = interop.Shape(2.5, 4, 'wide')
    panel = Panel(width=1, height=2, name='panel')
    fields = {'width': 1.0}

    assert not imbalance(lambda: interop.Shape(2, 3))
    assert not imbalance(lambda: interop.Shape.square(3))
    assert not imbalance(lambda: interop.Shape.unit.area)
    assert not imbalance(lambda: shape == interop.Shape.unit)
    assert not imbalance(lambda: Panel(width=1, height=2, name='panel'))
    assert not imbalance(lambda: pickle.loads(pickle.dumps(shape)), faults=False)
    assert not imbalance(lambda: pickle.loads(pickle.dumps(panel)), faults=False)
    assert not imbalance(lambda: pickle.dumps(shape))
    assert not imbalance(lambda: pickle.dumps(panel))
    assert not imbalance(lambda: reduction_round(shape))
    assert not imbalance(lambda: reduction_round(panel))
    assert not imbalance(raising(TypeError, lambda: interop._lacuna_restore(int, fields)))
    assert not imbalance(raising(KeyError, lambda: interop._lacuna_restore(interop.Shape, fields)))
