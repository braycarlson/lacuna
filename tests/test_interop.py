import collections
import collections.abc
import datetime as dt
import decimal
import fractions
import functools
import gc
import importlib
import inspect
import ipaddress
import itertools
import logging
import pathlib
import pickle
import signal
import sys
import threading
import time
import traceback
import types
import uuid
import warnings
import weakref
import zoneinfo

import pytest

from collections.abc import Iterator

import interop

from conftest import CPYTHON, counts_references, subinterpreter_run, subinterpreters, zone_install


ATTACHMENT_ROUNDS = 1 << 20
COLLECT_ROUNDS = 20
INTERRUPT_ATTEMPTS = 1 if CPYTHON else 64
INTERRUPT_ROUNDS = 1 << 30 if CPYTHON else 1 << 20
REFCOUNT_ROUNDS = 1000
SPIN_ROUNDS_MAX = 1 << 30
THREAD_COUNT = 8
THREAD_ROUNDS = 500


def test_diagnostic_message_and_details() -> None:
    with pytest.raises(interop.RangeInverted) as information:
        interop.parse('9..3')

    assert str(information.value) == '1:4: the minimum 9 is greater than the maximum 3'
    assert information.value.line == 1
    assert information.value.column == 4
    assert isinstance(information.value, interop.Error)


def test_diagnostic_absent_falls_back() -> None:
    with pytest.raises(interop.SyntaxInvalid) as information:
        interop.parse('9..x')

    assert str(information.value) == "the range is not two integers joined by '..'"
    assert information.value.line is None
    assert interop.Error.line is None
    assert interop.parse('3..9') == 6


def test_diagnostic_without_details() -> None:
    with pytest.raises(interop.SyntaxInvalid) as information:
        interop.parse('nine')

    assert str(information.value) == "1:1: no '..' in nine"
    assert information.value.column == 1


def test_callback_result() -> None:
    assert interop.apply(lambda value: value * 3, 14) == 42
    assert interop.shout('quiet') == 'QUIET'
    assert interop.item_length([1, 2, 3]) == 3


def test_callback_exception_propagates() -> None:
    with pytest.raises(LookupError, match='refused 5'):
        interop.apply(refusing, 5)


def refusing(value: int) -> int:
    assert isinstance(value, int)

    message = f'refused {value}'
    raise LookupError(message)


def test_callback_result_type_checked() -> None:
    with pytest.raises(TypeError, match='callback result must be str'):
        interop.shout(Upper())

    with pytest.raises(OverflowError):
        interop.apply(lambda value: 2**70 + value, 1)


class Upper:
    def upper(self) -> int:
        return 1


def test_error_bases() -> None:
    assert issubclass(interop.RangeInverted, interop.Error)
    assert issubclass(interop.RangeInverted, ValueError)
    assert issubclass(interop.SyntaxInvalid, ValueError)
    assert not issubclass(interop.CallbackFailed, ValueError)

    with pytest.raises(ValueError, match='minimum 9'):
        interop.parse('9..3')


def test_error_hierarchy() -> None:
    assert issubclass(interop.SyntaxInvalid, interop.ParseError)
    assert issubclass(interop.RangeInverted, interop.ParseError)
    assert issubclass(interop.ParseError, interop.Error)
    assert not issubclass(interop.CallbackFailed, interop.ParseError)

    with pytest.raises(interop.ParseError):
        interop.parse('9..x')

    with pytest.raises(interop.ParseError):
        interop.parse('9..3')

    expected = (
        interop.SyntaxInvalid,
        interop.ParseError,
        interop.Error,
        ValueError,
        Exception,
        BaseException,
        object,
    )

    assert interop.SyntaxInvalid.__mro__ == expected


def test_deprecated_function_warns() -> None:
    with pytest.warns(DeprecationWarning, match='use difference instead') as record:
        assert interop.subtract(9, 4) == 5

    assert record[0].filename == __file__

    with pytest.warns(DeprecationWarning, match='use area instead') as record:
        assert interop.Shape(2, 3).surface() == 6

    assert record[0].filename == __file__


def test_warning_emitted() -> None:
    with pytest.warns(UserWarning, match='careful') as record:
        assert interop.caution('careful') == 7

    assert len(record) == 1
    assert record[0].filename == __file__


def test_warning_filter_raises() -> None:
    with warnings.catch_warnings():
        warnings.simplefilter('error')

        with pytest.raises(DeprecationWarning, match='use difference instead'):
            interop.subtract(9, 4)

        with pytest.raises(DeprecationWarning, match='use area instead'):
            interop.Shape(2, 3).surface()

        with pytest.raises(UserWarning, match='careful'):
            interop.caution('careful')


def test_signal_interrupts_a_long_loop() -> None:
    previous = signal.signal(signal.SIGINT, interrupted)
    started = threading.Event()
    sender = threading.Thread(target=signal_send, args=(started,))

    try:
        sender.start()

        with pytest.raises(KeyboardInterrupt, match='signal 2'):
            interruptible_repeat(started)
    finally:
        sender.join()
        signal.signal(signal.SIGINT, previous)

    assert interop.interruptible(8) == 8


def interruptible_repeat(started: threading.Event) -> None:
    assert INTERRUPT_ATTEMPTS > 0
    assert not started.is_set()

    started.set()

    for _ in range(INTERRUPT_ATTEMPTS):
        interop.interruptible(INTERRUPT_ROUNDS)


def interrupted(number: int, frame: types.FrameType | None) -> None:
    assert number == signal.SIGINT
    assert frame is None or isinstance(frame, types.FrameType)

    message = f'signal {number}'
    raise KeyboardInterrupt(message)


def signal_send(started: threading.Event) -> None:
    assert isinstance(started, threading.Event)

    ready = started.wait()
    assert ready

    time.sleep(0.01)
    signal.raise_signal(signal.SIGINT)


def test_attachment_stays_with_its_thread() -> None:
    running = threading.Event()
    stop = threading.Event()
    spinner = threading.Thread(target=spin, args=(running, stop))

    spinner.start()

    try:
        ready = running.wait()
        assert ready

        seen = interop.attachment_seen(ATTACHMENT_ROUNDS)
    finally:
        stop.set()
        spinner.join()

    assert seen == (0, 0)

    with pytest.raises(ValueError, match='no rounds'):
        interop.attachment_seen(0)


def spin(running: threading.Event, stop: threading.Event) -> None:
    assert not running.is_set()
    assert not stop.is_set()

    running.set()

    for _ in range(SPIN_ROUNDS_MAX):
        if stop.is_set():
            return

    message = 'the spinner was never stopped'
    raise AssertionError(message)


def test_unbounded_containers() -> None:
    count = 1 << 17
    values = interop.range_list(count)

    assert type(values) is list
    assert len(values) == count
    assert values[-1] == count - 1
    assert interop.list_total(values) == sum(range(count))

    squares = interop.squares(1 << 17)

    assert len(squares) == 1 << 17
    assert squares[300] == 90000
    assert interop.dictionary_probe({'a': 1, 'b': 2}, 'a') == (True, 1)
    assert interop.dictionary_probe({'b': 2}, 'a') == (False, 1)
    assert interop.characters('abc') == ('a', 'b', 'c')
    assert interop.distinct([1, 2, 2, 3]) == ({1, 2, 3}, frozenset({1, 2, 3}))
    assert type(interop.distinct([])[1]) is frozenset

    text = interop.spelled(1 << 20)

    assert len(text) == 1 << 21
    assert text[:4] == 'abab'


def test_unbounded_containers_check_exact_types() -> None:
    data = bytearray(b'xy')
    grown = interop.bytearray_grow(data, 3)

    assert grown is data
    assert data == bytearray(b'xy!!!')
    assert interop.wrapped_lengths([1], (1, 2), {}, {1, 2, 3}, bytearray(4)) == (1, 2, 0, 3, 4)

    with pytest.raises(TypeError, match='must be list'):
        interop.list_total((1, 2))

    with pytest.raises(TypeError, match='must be list'):
        interop.list_total(Listed([1, 2]))

    with pytest.raises(TypeError, match='must be bytearray'):
        interop.bytearray_grow(b'xy', 1)

    with pytest.raises(TypeError, match='expected a set'):
        interop.wrapped_lengths([], (), {}, frozenset(), bytearray())


class Listed(list):
    pass


def test_python_names() -> None:
    assert interop.python_doubled(python_value=21) == 42
    assert not hasattr(interop, 'zig_doubled')
    assert 'python_value' in inspect.signature(interop.python_doubled).parameters

    with pytest.raises(TypeError, match="unexpected keyword argument 'zig_value'"):
        interop.python_doubled(zig_value=21)

    ledger = interop.Ledger(1)
    ledger.add(2)

    assert ledger.total == 3
    assert type(ledger).__name__ == 'Ledger'
    assert not hasattr(interop, 'Tally')
    assert not hasattr(ledger, 'zig_add')
    assert not hasattr(ledger, 'zig_total')


def test_running_python_source() -> None:
    assert interop.evaluated(40, 2) == 42

    namespace = interop.executed('total = sum(range(5))\nlabel = "done"\n')

    assert namespace['total'] == 10
    assert namespace['label'] == 'done'

    with pytest.raises(SyntaxError):
        interop.executed('total = (')

    with pytest.raises(ZeroDivisionError) as information:
        interop.executed('ratio = 1 / 0\n')

    frames = traceback.extract_tb(information.value.__traceback__)

    assert frames[-1].filename == '<lacuna>'
    assert frames[-1].lineno == 1


def test_fraction_and_address_round_trip() -> None:
    half = fractions.Fraction(1, 2)
    wide = fractions.Fraction(2**200 + 1, 3**100)

    assert interop.fraction_echo(half) == half
    assert type(interop.fraction_echo(half)) is fractions.Fraction
    assert interop.fraction_echo(wide) == wide
    assert interop.fraction_echo(7) == fractions.Fraction(7)

    with pytest.raises(TypeError, match=r'must be fractions\.Fraction'):
        interop.fraction_echo(0.5)

    with pytest.raises(TypeError, match=r'must be fractions\.Fraction'):
        interop.fraction_echo(value=True)

    with pytest.raises(OverflowError):
        interop.fraction_echo(fractions.Fraction(2**300, 3))

    four = ipaddress.IPv4Address('192.0.2.7')
    six = ipaddress.IPv6Address('2001:db8::7')

    assert interop.address_echo(four) == four
    assert interop.address_echo(six) == six
    assert type(interop.address_echo(six)) is ipaddress.IPv6Address

    with pytest.raises(TypeError, match=r'IPv4Address or ipaddress\.IPv6Address'):
        interop.address_echo('192.0.2.7')


def test_capsules_weak_references_and_singletons() -> None:
    capsule = interop.capsule_made(41)

    assert type(capsule).__name__ == 'PyCapsule'
    assert interop.capsule_read(capsule) == 41

    with pytest.raises(ValueError, match='invalid PyCapsule'):
        interop.capsule_read(object())

    with pytest.raises(TypeError, match='expected a weakref'):
        interop.weak_target(object())

    target = Target()
    reference = interop.weak_reference(target)

    assert reference() is target
    assert interop.weak_target(reference) is target

    del target
    gc.collect()

    assert interop.weak_target(reference) is None
    assert interop.singletons() == (None, Ellipsis, NotImplemented)
    assert interop.python_version() == tuple(sys.version_info[:2])


def test_zone_name_round_trip() -> None:
    key = zone_install()
    zone = zoneinfo.ZoneInfo(key)
    moment = dt.datetime(2024, 5, 1, 12, 30, tzinfo=zone)
    day = dt.date(2024, 5, 1)
    clock = dt.time(1, 2)
    span = dt.timedelta(seconds=3)

    echoed = interop.moments(day, clock, moment, span)[2]

    assert echoed == moment
    assert echoed.tzinfo is zone
    assert echoed.utcoffset() == dt.timedelta(minutes=90)


def test_zig_logs_reach_python_logging(caplog: pytest.LogCaptureFixture) -> None:
    assert not caplog.records

    with caplog.at_level(logging.DEBUG, logger='interop_zig'):
        interop.logged('hello')

    records = [(record.name, record.levelno, record.getMessage()) for record in caplog.records]

    assert records == [
        ('interop_zig', logging.WARNING, 'logged hello'),
        ('interop_zig', logging.DEBUG, 'detail 5'),
        ('interop_zig', logging.INFO, 'detached 5'),
    ]


def test_zig_log_lines_truncate(caplog: pytest.LogCaptureFixture) -> None:
    assert not caplog.records

    with caplog.at_level(logging.WARNING, logger='interop_zig'):
        interop.logged('x' * 5000)
        interop.logged('x' + '\u00e9' * 3000)

    first, second = (record.getMessage() for record in caplog.records)

    assert first == 'logged ' + 'x' * 4086 + '...'
    assert second == 'logged x' + '\u00e9' * 2042 + '\ufffd...'


def test_exception_matching() -> None:
    assert interop.lookup({'present': 4}, 'present') == 4
    assert interop.lookup({}, 'absent') == -1

    with pytest.raises(TypeError):
        interop.lookup([], 'absent')


def test_exception_chained_as_cause() -> None:
    with pytest.raises(interop.CallbackFailed) as information:
        interop.guarded(refusing_call)

    cause = information.value.__cause__

    assert isinstance(cause, LookupError)
    assert str(cause) == 'refused'
    assert information.value.__context__ is cause
    assert cause.__traceback__ is not None
    assert interop.guarded(lambda: 7) == 7


def refusing_call() -> int:
    message = 'refused'
    raise LookupError(message)


def test_base_exceptions_are_not_chained() -> None:
    with pytest.raises(KeyboardInterrupt):
        interop.guarded(interrupt)


def interrupt() -> int:
    raise KeyboardInterrupt


def test_restore_keeps_the_original_context() -> None:
    try:
        handled()
    except RuntimeError:
        with pytest.raises(LookupError) as information:
            interop.rethrown(chained)

    assert isinstance(information.value.__context__, ValueError)
    assert isinstance(information.value.__cause__, ValueError)


def handled() -> None:
    message = 'handled'
    raise RuntimeError(message)


def inner() -> None:
    message = 'inner'
    raise ValueError(message)


def chained() -> int:
    try:
        inner()
    except ValueError as error:
        message = 'outer'
        raise LookupError(message) from error

    return 0


def test_exception_matching_without_frame_builtins() -> None:
    namespace = {'__builtins__': {}, 'interop': interop}
    isolated = types.FunctionType(lookup_absent.__code__, namespace)

    assert isolated({}) == -1


def lookup_absent(mapping: dict[str, int]) -> int:
    assert 'absent' not in mapping

    return interop.lookup(mapping, 'absent')


def test_deep_reference_chain_is_freed() -> None:
    outcome: list[str] = []
    previous = threading.stack_size(1 << 20)

    try:
        worker = threading.Thread(target=chain_build, args=(outcome,))
        worker.start()
        worker.join()
    finally:
        threading.stack_size(previous)

    assert outcome == ['freed']


def chain_build(outcome: list[str]) -> None:
    assert outcome == []

    head = None

    for _ in range(200_000):
        node = interop.Node('n')

        if head is not None:
            node.attach(0, head)

        head = node

    del head
    gc.collect()
    outcome.append('freed')


def test_exception_take_and_restore() -> None:
    taken = interop.captured(refusing_call)

    assert isinstance(taken, LookupError)
    assert taken.__traceback__ is not None

    with pytest.raises(RuntimeError, match='the callback returned'):
        interop.captured(lambda: 1)

    with pytest.raises(LookupError, match='refused'):
        interop.rethrown(refusing_call)

    assert interop.rethrown(lambda: 1) is None


def test_attribute_access() -> None:
    target = Target()

    interop.configure(target)

    assert target.enabled is True
    assert target.label == 'configured'
    assert not hasattr(target, 'legacy')

    with pytest.raises(AttributeError):
        interop.configure(target)


class Target:
    def __init__(self) -> None:
        self.legacy = 1


def test_item_access() -> None:
    mapping = {'stale': 0}

    interop.store(mapping, 'fresh', 9)

    assert mapping == {'fresh': 9}

    with pytest.raises(KeyError):
        interop.store(mapping, 'again', 1)


def test_iteration() -> None:
    assert interop.summed([1, 2, 3]) == 6
    assert interop.summed(iter(range(10))) == 45
    assert interop.summed(()) == 0

    with pytest.raises(TypeError):
        interop.summed(5)

    with pytest.raises(LookupError):
        interop.summed(map(refusing, [1]))

    with pytest.raises(ValueError, match='more than'):
        interop.summed(itertools.repeat(0))


def test_keyword_call_and_import() -> None:
    assert interop.split_count('a,b,c') == 2
    assert interop.split_count('abc') == 1
    assert interop.dumps({'b': 1, 'a': 2}) == '{"a": 2, "b": 1}'

    with pytest.raises(TypeError):
        interop.dumps(object())


def test_object_queries() -> None:
    assert interop.describe([1, 'x']) == "[1, 'x']"
    assert interop.inspect(3, int, 3) == (True, True, True, True, False, hash(3))
    assert interop.inspect(1.5, float, 2) == (True, True, True, False, True, hash(1.5))
    assert interop.inspect('', str, 'a') == (True, True, False, False, True, hash(''))

    with pytest.raises(TypeError):
        interop.inspect([], list, [])

    with pytest.raises(TypeError):
        interop.inspect(1, 2, 1)


@subinterpreters
def test_foreign_threads_call_back_in_a_subinterpreter() -> None:
    directory = str(pathlib.Path(interop.__file__).parent.parent)

    source = (
        'import sys, threading\n'
        f'sys.path.insert(0, {directory!r})\n'
        'import interop\n'
        'seen = []\n'
        'def record(index):\n'
        '    seen.append(threading.get_ident())\n'
        '    return index\n'
        'assert interop.fan_out(record, 4) == 6\n'
        'assert len(seen) == 4\n'
    )

    subinterpreter_run(source)


def test_foreign_threads_call_back() -> None:
    seen: list[int] = []
    lock = threading.Lock()
    record = functools.partial(recorded, lock=lock, seen=seen)

    assert interop.fan_out(record, 8) == sum(index * 10 for index in range(8))
    assert sorted(seen) == list(range(8))
    assert interop.fan_out(record, 0) == 0

    with pytest.raises(ValueError, match='at most 8'):
        interop.fan_out(record, 9)

    with pytest.raises(LookupError, match='refused'):
        interop.fan_out(refusing, 3)

    with pytest.raises(TypeError):
        interop.fan_out(str, 2)


def recorded(index: int, *, lock: threading.Lock, seen: list[int]) -> int:
    assert 0 <= index < THREAD_COUNT
    assert len(seen) < THREAD_COUNT
    assert callable(lock.acquire)

    with lock:
        seen.append(index)

    result = index * 10

    assert result >= index

    return result


def test_complex() -> None:
    assert interop.rotate(1 + 2j) == -2 + 1j
    assert interop.rotate(3) == 3j
    assert interop.rotate(1.5) == 1.5j
    assert interop.rotate(Complexish()) == -4 + 3j
    assert interop.narrow_complex(0.5 - 0.25j) == 0.5 - 0.25j

    with pytest.raises(TypeError, match='must be complex'):
        interop.rotate('1+2j')

    with pytest.raises(TypeError, match='must be complex'):
        interop.rotate(None)


class Complexish:
    def __complex__(self) -> complex:
        return 3 + 4j


def test_decimal() -> None:
    assert interop.decimal_scale(decimal.Decimal('1.25'), 2) == decimal.Decimal(125)
    assert interop.decimal_scale(decimal.Decimal('-0.5'), 0) == decimal.Decimal('-0.5')
    assert interop.decimal_scale(7, -1) == decimal.Decimal('0.7')
    assert str(interop.decimal_scale(decimal.Decimal('1.00'), 0)) == '1.00'

    huge = decimal.Decimal(2**128)

    with pytest.raises(OverflowError):
        interop.decimal_scale(huge, 0)

    with pytest.raises(ValueError, match='finite'):
        interop.decimal_scale(decimal.Decimal('NaN'), 0)

    with pytest.raises(ValueError, match='finite'):
        interop.decimal_scale(decimal.Decimal('-Infinity'), 0)

    with pytest.raises(TypeError):
        interop.decimal_scale(1.5, 0)

    with pytest.raises(TypeError, match='sign must be 0 or 1'):
        interop.decimal_scale(LyingDecimal('1'), 0)

    with pytest.raises(TypeError):
        interop.decimal_scale(value=True, shift=0)


class LyingDecimal(decimal.Decimal):
    def as_tuple(self) -> object:
        return (5, (1,), 0)


def test_uuid() -> None:
    identifier = uuid.UUID('12345678-1234-5678-1234-567812345678')
    reversed_bytes = identifier.bytes[::-1]

    assert interop.uuid_reverse(identifier) == uuid.UUID(bytes=reversed_bytes)
    assert interop.uuid_reverse(interop.uuid_reverse(identifier)) == identifier

    with pytest.raises(TypeError, match=r'must be uuid\.UUID'):
        interop.uuid_reverse(str(identifier))


def test_frozenset_and_abstract_containers() -> None:
    result = interop.frozen({1, 2})

    assert isinstance(result, frozenset)
    assert result == frozenset({1, 2})
    assert interop.frozen({1: 'a', 2: 'b'}.keys()) == frozenset({1, 2})
    assert interop.invert(types.MappingProxyType({'ada': 1})) == {1: 'ada'}
    assert interop.combine(1, *range(3)) == 4
    assert interop.word_count(collections.OrderedDict.fromkeys(['a', 'b']).keys()) == 2

    with pytest.raises(TypeError, match='must be a mapping'):
        interop.invert([('ada', 1)])

    with pytest.raises(TypeError, match='items must be pairs'):
        interop.invert(BrokenMapping())


class BrokenMapping(collections.abc.Mapping):
    def __getitem__(self, key: object) -> object:
        assert isinstance(key, int)

        return key

    def __iter__(self) -> Iterator[object]:
        return iter([1])

    def __len__(self) -> int:
        return 1

    def items(self) -> list[object]:
        return [1]


def test_signature_markers() -> None:
    combine = inspect.signature(interop.combine)
    clamp = inspect.signature(interop.clamp)

    assert str(combine) == '(first, /, *rest, scale=1, **options)'
    assert str(clamp) == '(value, *, low=0.0, high=1.0)'
    assert str(inspect.signature(interop.keyword_count)) == '(**extra)'


def test_variadic_and_keywords() -> None:
    assert interop.combine(1) == 1
    assert interop.combine(1, 2, 3) == 6
    assert interop.combine(1, 2, scale=10) == 30
    assert interop.combine(1, bonus=5, extra=1) == 7
    assert interop.keyword_count(a=1, b=2, c=3) == 3
    assert interop.keyword_count() == 0

    with pytest.raises(TypeError, match='at most 8 extra positional'):
        interop.combine(*range(10))

    with pytest.raises(TypeError, match='at most 4 extra keyword'):
        interop.combine(1, a=1, b=2, c=3, d=4, e=5)


def test_positional_only_and_keyword_only() -> None:
    assert interop.clamp(2.0) == 1.0
    assert interop.clamp(0.5, low=0.6) == 0.6

    with pytest.raises(TypeError):
        interop.clamp(0.5, 0.0, 1.0)

    assert interop.difference(9, 4) == 5
    assert str(inspect.signature(interop.difference)) == '(left, right, /)'

    with pytest.raises(TypeError, match='positional-only'):
        _ = interop.difference(9, right=4)

    with pytest.raises(TypeError, match="missing required argument 'first'"):
        interop.combine(first=1)

    assert interop.combine(1, first=9) == 10


def test_union_argument_and_result() -> None:
    assert interop.measure(41) == 41
    assert interop.measure('four') == 4
    assert interop.measure(None) == -1
    assert interop.parity(10) == 5
    assert interop.parity(7) == 'odd'

    with pytest.raises(TypeError, match='must be int or str or None'):
        interop.measure(1.5)


def test_calendar_round_trip() -> None:
    zone = dt.timezone(dt.timedelta(hours=-6))
    day = dt.date(2026, 10, 23)
    clock = dt.time(23, 37, 5, 120)
    moment = dt.datetime(2026, 10, 23, 23, 37, 5, 120, tzinfo=zone)
    span = dt.timedelta(days=-3, seconds=17, microseconds=9)

    assert interop.moments(day, clock, moment, span) == (day, clock, moment, span)

    naive = moment.replace(tzinfo=None)

    assert interop.moments(day, clock, naive, span)[2] == naive
    assert interop.doubled_span(span) == span * 2


def test_calendar_rejections() -> None:
    zone = dt.UTC
    span = dt.timedelta(0)
    moment = dt.datetime(2026, 1, 1, tzinfo=zone).replace(tzinfo=None)

    with pytest.raises(ValueError, match='naive time'):
        interop.moments(moment.date(), dt.time(1, tzinfo=zone), moment, span)

    with pytest.raises(TypeError, match=r'must be datetime\.date'):
        interop.moments('2026-01-01', dt.time(1), moment, span)

    with pytest.raises(OverflowError):
        interop.doubled_span(dt.timedelta.max)

    with pytest.raises(TypeError, match=r'must be datetime\.timedelta'):
        interop.doubled_span(type)


def test_paths() -> None:
    assert interop.path_echo('a/b.txt') == pathlib.Path('a/b.txt')
    assert interop.path_echo(pathlib.Path('x.tar.gz')) == pathlib.Path('x.tar.gz')
    assert interop.path_echo(b'raw') == pathlib.Path('raw')
    assert interop.extension(pathlib.PurePosixPath('archive.tar.gz')) == '.gz'

    with pytest.raises(ValueError, match='embedded null'):
        interop.extension('a\x00b')

    with pytest.raises(TypeError):
        interop.extension(3)


def test_sets_and_maps() -> None:
    assert interop.word_count({'a', 'b'}) == 2
    assert interop.word_count(frozenset({'a'})) == 1
    assert interop.letters('banana') == {ord('b'), ord('a'), ord('n')}
    assert interop.invert({'ada': 1, 'grace': 2}) == {1: 'ada', 2: 'grace'}

    with pytest.raises(TypeError, match='must be a set'):
        interop.word_count(['a'])

    with pytest.raises(ValueError, match='at most 16'):
        interop.word_count({str(index) for index in range(17)})


def test_wide_integers() -> None:
    left = 2**200
    right = -(2**199) + 7

    assert interop.wide_add(left, right) == left + right
    assert interop.wide_add(-(2**255), 0) == -(2**255)
    assert interop.unsigned_echo(2**128 - 1) == 2**128 - 1
    assert interop.unsigned_echo(0) == 0

    with pytest.raises(OverflowError):
        interop.wide_add(2**255, 0)

    with pytest.raises(OverflowError):
        interop.unsigned_echo(-1)

    with pytest.raises(OverflowError):
        interop.unsigned_echo(2**128)

    with pytest.raises(OverflowError):
        interop.wide_add(2**255 - 1, 1)


def test_wide_integer_boundaries() -> None:
    values = [0, 1, -1, 2**64, -(2**64), 2**127, -(2**127), 2**255 - 1, -(2**255)]

    for value in values:
        assert interop.wide_add(value, 0) == value


def test_owned_text() -> None:
    assert interop.repeat('ab', 3) == 'ababab'

    with pytest.raises(ValueError, match='at most 32 bytes'):
        interop.repeat('x' * 33, 1)

    with pytest.raises(interop.TextFull):
        interop.repeat('x' * 20, 2)


@counts_references
def test_node_holds_references() -> None:
    payload = object()
    before = sys.getrefcount(payload)
    node = interop.Node('root', payload)

    assert node.payload is payload
    assert sys.getrefcount(payload) == before + 1

    node.payload = None

    assert node.payload is None
    assert sys.getrefcount(payload) == before

    node.payload = payload

    del node
    gc.collect()

    assert sys.getrefcount(payload) == before


@counts_references
def test_node_child_is_borrowed() -> None:
    payload = object()
    node = interop.Node('root')

    node.attach(0, payload)

    before = sys.getrefcount(payload)

    for _ in range(REFCOUNT_ROUNDS):
        assert node.child(0) is payload

    assert node.child(1) is None
    assert sys.getrefcount(payload) == before


@counts_references
def test_returned_reference_is_moved() -> None:
    payload = [1, 2, 3]
    before = sys.getrefcount(payload)

    for _ in range(REFCOUNT_ROUNDS):
        assert interop.forward(lambda: payload) is payload

    assert sys.getrefcount(payload) == before

    for _ in range(REFCOUNT_ROUNDS):
        assert interop.forward_counted(lambda: payload) == (payload, 3)

    assert sys.getrefcount(payload) == before


@counts_references
def test_returned_reference_released_on_failure() -> None:
    payload = object()
    before = sys.getrefcount(payload)

    for _ in range(REFCOUNT_ROUNDS):
        with pytest.raises(AttributeError):
            interop.forward_counted(lambda: payload)

    with pytest.raises(LookupError):
        interop.forward(lambda: refusing(1))

    assert sys.getrefcount(payload) == before


@counts_references
def test_node_cycles_are_collected() -> None:
    parent = interop.Node('parent')
    child = interop.Node('child', parent)

    parent.attach(0, child)

    assert parent.child(0) is child
    assert parent.child(1) is None

    tracker = Tracker()

    child.attach(1, tracker)

    probe = weakref.ref(tracker)

    del parent, child, tracker
    gc.collect()

    assert probe() is None


class Tracker:
    pass


def test_node_label_field() -> None:
    node = interop.Node('a')
    node.label = 'renamed'

    assert node.label == 'renamed'

    with pytest.raises(ValueError, match='at most 32 bytes'):
        node.label = 'x' * 40


def test_equality_without_hash_is_unhashable() -> None:
    with pytest.raises(TypeError, match='unhashable'):
        hash(interop.Shape(1, 1))


def test_static_method_and_constants() -> None:
    square = interop.Shape.square(3)

    assert square.area == 9
    assert square.name == 'square'
    assert interop.Shape.sides == 4
    assert interop.Shape.unit.area == 1
    assert isinstance(inspect.getattr_static(interop.Shape, 'square'), staticmethod)


def test_subclass() -> None:
    tile = Tile(2, 3, 'tile')

    assert tile.describe() == 'tile 6.0'
    assert tile == interop.Shape(2, 3)
    assert isinstance(tile, interop.Shape)
    assert interop.Shape.square(2) == Tile(2, 2)

    tile.extra = 'kept'

    assert tile.extra == 'kept'


class Tile(interop.Shape):
    def describe(self) -> str:
        assert self.area >= 0

        return f'{self.name} {self.area}'


def test_pickle_round_trip() -> None:
    shape = interop.Shape(2.5, 4, 'wide')
    restored = pickle.loads(pickle.dumps(shape))

    assert restored == shape
    assert restored.name == 'wide'
    assert type(restored) is interop.Shape


def test_pickle_subclass_keeps_its_attributes() -> None:
    panel = Panel(width=1, height=2, name='panel')
    restored = pickle.loads(pickle.dumps(panel))

    assert isinstance(restored, Panel)
    assert restored.area == 2
    assert restored.note == 'panel 1x2'


class Panel(interop.Shape):
    def __init__(self, *, width: float, height: float, name: str) -> None:
        assert width > 0
        assert height > 0
        assert name

        self.note = f'{name} {width}x{height}'


def test_restore_rejects_foreign_classes() -> None:
    fields = {'width': 1.0}

    with pytest.raises(TypeError, match='picklable class'):
        interop._lacuna_restore(int, fields)

    with pytest.raises(KeyError):
        interop._lacuna_restore(interop.Shape, fields)


@counts_references
def test_threads_share_one_node() -> None:
    root = interop.Node('root')
    payloads = [object() for _ in range(THREAD_COUNT)]
    before = [sys.getrefcount(payload) for payload in payloads]
    barrier = threading.Barrier(THREAD_COUNT + 1)
    collector = threading.Thread(target=collect_work, args=(barrier,))
    threads = [
        threading.Thread(target=node_work, args=(barrier, root, payloads, index))
        for index in range(THREAD_COUNT)
    ]

    for thread in [*threads, collector]:
        thread.start()

    for thread in [*threads, collector]:
        thread.join()

    root.attach(0, None)
    root.attach(1, None)
    gc.collect()

    assert [sys.getrefcount(payload) for payload in payloads] == before


def node_work(
    barrier: threading.Barrier,
    root: interop.Node,
    payloads: list[object],
    index: int,
) -> None:
    assert 0 <= index < len(payloads)
    assert isinstance(root, interop.Node)
    assert barrier.parties == len(payloads) + 1

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for round_index in range(THREAD_ROUNDS):
        child = interop.Node('child', payloads[index])
        root.attach(round_index % 2, child)
        current = root.child(round_index % 2)

        assert isinstance(current, interop.Node)
        assert any(current.payload is payload for payload in payloads)


def collect_work(barrier: threading.Barrier) -> None:
    assert barrier.parties > 1

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(COLLECT_ROUNDS):
        gc.collect()


def test_threads_first_use_of_library_types() -> None:
    original = sys.modules.pop('interop')

    try:
        fresh = importlib.import_module('interop')
    finally:
        sys.modules['interop'] = original

    zone = dt.timezone(dt.timedelta(hours=2))
    arguments = (
        dt.date(2026, 10, 26),
        dt.time(9, 30),
        dt.datetime(2026, 10, 26, 9, 30, tzinfo=zone),
        dt.timedelta(days=1),
    )

    results: list[object] = []
    barrier = threading.Barrier(THREAD_COUNT)
    threads = [
        threading.Thread(target=library_work, args=(barrier, fresh, arguments, results))
        for _ in range(THREAD_COUNT)
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    expected = (arguments, pathlib.Path('a.b'))

    assert results == [expected] * THREAD_COUNT


def library_work(
    barrier: threading.Barrier,
    module: object,
    arguments: tuple[object, ...],
    results: list[object],
) -> None:
    assert len(arguments) == 4
    assert module is not interop
    assert len(results) < THREAD_COUNT
    assert barrier.parties == THREAD_COUNT

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    moments = module.moments(*arguments)
    path = module.path_echo('a.b')
    result = (moments, path)
    results.append(result)
