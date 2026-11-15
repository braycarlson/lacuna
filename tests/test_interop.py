import array
import asyncio
import builtins
import collections
import collections.abc
import concurrent.futures
import ctypes
import datetime as dt
import decimal
import fractions
import functools
import gc
import importlib
import importlib.util
import inspect
import ipaddress
import itertools
import json
import logging
import math
import os
import pathlib
import pickle
import signal
import subprocess
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
from unittest import mock

import interop

from conftest import (
    CPYTHON,
    ZONE_FOLDED_KEY,
    counts_references,
    pythonapi,
    subinterpreter_run,
    subinterpreters,
    zone_install,
)


ATTACHMENT_ROUNDS = 1 << 20
BIG_VALUES = types.MappingProxyType(
    {
        'mersenne': 2**4423 - 1,
        'minus_one': -1,
        'near_cap': 2**16380 + 1,
        'negative_power': -(7**2000),
        'one': 1,
        'past_one_limb': -(2**64) - 1,
        'past_wide': 2**1025 + 3,
        'top_bit': 2**63,
        'zero': 0,
    }
)
COLLECT_ROUNDS = 20
ENCODED_REFUSAL = r"cannot convert 'int' object to bytes|'int' object is not iterable"
INTERRUPT_ATTEMPTS = 1 if CPYTHON else 64
INTERRUPT_ROUNDS = 1 << 30 if CPYTHON else 1 << 20
REFCOUNT_ROUNDS = 1000
SHARED_BASE = 10**12
SHARED_LENGTH = 8
SPIN_ROUNDS_MAX = 1 << 40
SPIN_SECONDS_MAX = 120
THREAD_COUNT = 8
THREAD_ROUNDS = 500
TRAVERSE_ARGUMENTS = (1, 3, 8, 0x1001, 2 ** (8 * ctypes.sizeof(ctypes.c_size_t) - 1) + 5)
TRAVERSE_MASK = 0x3FFF_FFFF
TRAVERSE_SLOT = 71


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


class NoteRefusedError(Exception):
    def add_note(self, note: str) -> None:
        assert isinstance(note, str)

        message = f'no room for {note!r}'
        raise RuntimeError(message)


def note_refused_raise(value: int) -> int:
    assert isinstance(value, int)

    raise NoteRefusedError(value)


def ratio_rounded_expected(*, denominator: int, numerator: int) -> int:
    assert denominator != 0
    assert isinstance(numerator, int)

    ratio = fractions.Fraction(numerator, denominator)
    magnitude = math.floor(abs(ratio) + fractions.Fraction(1, 2))
    result = magnitude if ratio >= 0 else -magnitude

    assert abs(result - ratio) <= fractions.Fraction(1, 2)

    return result


def value_refuse(value: int) -> int:
    assert isinstance(value, int)

    message = f'no {value}'
    raise ValueError(message)


def test_module_warning_is_a_user_warning_outside_the_error_tree() -> None:
    assert issubclass(interop.PrecisionLost, UserWarning)
    assert not issubclass(interop.PrecisionLost, interop.Error)
    assert interop.PrecisionLost.__module__ == 'interop'

    with pytest.warns(interop.PrecisionLost, match='not a whole number') as record:
        assert interop.ratio_rounded(7, 2) == 4

    assert len(record) == 1
    assert record[0].filename == __file__

    with warnings.catch_warnings():
        warnings.simplefilter('error', interop.PrecisionLost)

        with pytest.raises(interop.PrecisionLost):
            interop.ratio_rounded(7, 2)

        assert interop.ratio_rounded(8, 2) == 4


@pytest.mark.parametrize(
    ('numerator', 'denominator'),
    [
        (7, 2),
        (-7, 2),
        (7, -2),
        (-7, -2),
        (5, 3),
        (-5, 3),
        (4, 3),
        (1, -2),
        (9, 3),
        (2**63 - 1, 2),
        (-(2**63), 3),
        (-(2**63) + 1, -(2**63)),
    ],
)
def test_ratio_rounded_rounds_halves_away_from_zero(*, denominator: int, numerator: int) -> None:
    assert denominator != 0
    assert isinstance(numerator, int)

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter('always', interop.PrecisionLost)

        result = interop.ratio_rounded(numerator, denominator)

    lost = [entry for entry in caught if issubclass(entry.category, interop.PrecisionLost)]
    whole = numerator % denominator == 0

    assert result == ratio_rounded_expected(denominator=denominator, numerator=numerator)
    assert len(lost) == (0 if whole else 1)


def test_std_errors_derive_from_their_python_builtins() -> None:
    assert issubclass(interop.DivisionByZero, interop.Error)
    assert issubclass(interop.DivisionByZero, ZeroDivisionError)
    assert issubclass(interop.Overflow, interop.Error)
    assert issubclass(interop.Overflow, OverflowError)

    with pytest.raises(ZeroDivisionError):
        interop.ratio_rounded(1, 0)

    with pytest.warns(interop.PrecisionLost), pytest.raises(interop.Overflow):
        interop.ratio_truncated(-(2**63), -1)

    with pytest.raises(OverflowError):
        interop.ratio_rounded(-(2**63), -1)


def test_deprecations_carry_their_categories() -> None:
    with pytest.warns(FutureWarning, match='use ratio_rounded instead') as record:
        assert interop.ratio_floored(-7, 2) == -4

    assert len(record) == 1
    assert record[0].filename == __file__

    with pytest.warns(interop.PrecisionLost, match='drops the remainder') as record:
        assert interop.ratio_truncated(-7, 2) == -3

    assert len(record) == 1
    assert record[0].filename == __file__


def test_note_names_the_failed_callback() -> None:
    with pytest.raises(ValueError, match='no 3') as information:
        interop.apply_noted(value_refuse, 3)

    assert information.value.__notes__ == ['the callback failed on 3']
    assert interop.apply_noted(lambda value: value + 1, -(2**63)) == -(2**63) + 1


def test_note_that_cannot_be_added_keeps_the_original_as_context() -> None:
    with pytest.raises(RuntimeError, match='no room') as information:
        interop.apply_noted(note_refused_raise, -(2**63))

    assert isinstance(information.value.__context__, NoteRefusedError)
    assert information.value.__context__.args == (-(2**63),)


def test_frozendict_wraps_where_python_has_it() -> None:
    if sys.version_info < (3, 15):
        with pytest.raises(AttributeError, match='frozendict'):
            interop.frozen_from({'a': 1})

        with pytest.raises(AttributeError, match='frozendict'):
            interop.frozen_total({'a': 1})

        return

    frozen_class = vars(builtins)['frozendict']
    frozen = interop.frozen_from({'a': 1, 'b': 2})

    assert type(frozen) is frozen_class
    assert frozen == frozen_class({'a': 1, 'b': 2})
    assert interop.frozen_lookup(frozen, 'b') == 2
    assert interop.frozen_lookup(frozen, 'z') == -1
    assert interop.frozen_lookup(frozen, 'z', default=5) == 5
    assert interop.frozen_total(frozen_class({'a': 3, 'b': 4})) == 7

    with pytest.raises(TypeError, match='must be frozendict'):
        interop.frozen_lookup({'a': 1}, 'a')

    with pytest.raises(TypeError, match='expected a frozendict'):
        interop.frozen_total({'a': 1})


@pytest.mark.parametrize('name', sorted(BIG_VALUES))
def test_big_integers_round_trip(name: str) -> None:
    assert name in BIG_VALUES

    value = BIG_VALUES[name]

    assert interop.big_bits(value) == abs(value).bit_length()
    assert interop.big_scaled(value, 3) == -(value << 3)
    assert interop.big_scaled(value, 0) == -value


def test_big_integers_are_bounded_and_typed() -> None:
    widest = (1 << 16384) - 1

    assert interop.big_factorial(0) == 1
    assert interop.big_factorial(1000) == math.factorial(1000)
    assert interop.big_bits(value=True) == 1
    assert interop.big_bits(widest) == 16384
    assert interop.big_bits(-widest) == 16384
    assert interop.big_scaled(1 << 16380, 3) == -(1 << 16383)

    with pytest.raises(OverflowError, match='at most 16384 bits'):
        interop.big_bits(1 << 16384)

    with pytest.raises(OverflowError, match='at most 16384 bits'):
        interop.big_scaled(1 << 16380, 10)

    with pytest.raises(ValueError, match=r'above 2\*\*14'):
        interop.big_scaled(1, (1 << 14) + 1)

    with pytest.raises(TypeError):
        interop.big_bits(1.5)

    with pytest.raises(ValueError, match='above 1000'):
        interop.big_factorial(1001)


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

    deadline = time.monotonic() + SPIN_SECONDS_MAX

    for _ in range(SPIN_ROUNDS_MAX):
        if stop.is_set():
            return

        if time.monotonic() > deadline:
            break

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


def test_list_assign_matches_python_item_assignment() -> None:
    values = [1, 2, 3]
    expected = [1, 2, 3]
    expected[1] = 20

    interop.list_assign(values, 1, 20)

    assert values == expected

    with pytest.raises(IndexError):
        expected[3] = 0

    with pytest.raises(IndexError):
        interop.list_assign(values, 3, 0)

    assert values == expected


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


def test_capsule_destructor_runs_when_the_capsule_dies() -> None:
    before = interop.capsules_freed()
    capsule = interop.capsule_owned(9)

    assert interop.capsule_read(capsule) == 9
    assert interop.capsules_freed() == before

    del capsule
    gc.collect()

    assert interop.capsules_freed() == before + 1


def test_capsule_import_reads_a_module_attribute() -> None:
    capsule = interop.capsule_owned(17)

    with mock.patch.object(interop, 'counter', capsule, create=True):
        assert interop.capsule_imported() == 17

    with pytest.raises(AttributeError, match='counter'):
        interop.capsule_imported()


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


def test_fold_survives_a_round_trip() -> None:
    zone_install()

    zone = zoneinfo.ZoneInfo(ZONE_FOLDED_KEY)
    first = dt.datetime(2026, 10, 25, 1, 30, tzinfo=zone)
    second = first.replace(fold=1)
    day = dt.date(2026, 10, 25)
    clock = dt.time(1, 30, fold=1)
    span = dt.timedelta(0)

    assert first.utcoffset() == dt.timedelta(hours=1)
    assert second.utcoffset() == dt.timedelta(0)

    moments = (first, second, second.replace(tzinfo=None), second.replace(tzinfo=dt.UTC))

    for moment in moments:
        echoed = interop.moments(day, clock, moment, span)

        assert echoed[1].fold == clock.fold
        assert echoed[2].fold == moment.fold
        assert echoed[2].utcoffset() == moment.utcoffset()
        assert echoed[2].replace(tzinfo=None) == moment.replace(tzinfo=None)


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


def test_raw_layer() -> None:
    reflected = 1 + decimal.Decimal(2)

    assert interop.raw_symbols_resolved() > 0
    assert interop.raw_bytes('a\x00b') == b'a\x00b'
    assert interop.raw_sum(2, 3) == 5
    assert interop.raw_sum('a', 'b') == 'ab'
    assert interop.raw_sum(1, decimal.Decimal(2)) == reflected

    with pytest.raises(TypeError):
        interop.raw_sum(1, 'a')


def test_object_queries() -> None:
    assert interop.describe([1, 'x']) == "[1, 'x']"
    assert interop.inspect(3, int, 3) == (True, True, True, True, False, hash(3))
    assert interop.inspect(1.5, float, 2) == (True, True, True, False, True, hash(1.5))
    assert interop.inspect('', str, 'a') == (True, True, False, False, True, hash(''))

    with pytest.raises(TypeError):
        interop.inspect([], list, [])

    with pytest.raises(TypeError):
        interop.inspect(1, 2, 1)


def relayed(
    span: dict[str, int],
    day: dt.date,
    shape: interop.Shape,
    values: tuple[float, ...],
    *,
    seen: list[tuple[object, ...]],
) -> tuple[dict[str, int], dt.date, interop.Shape]:
    assert not seen
    assert span['start'] < span['stop']
    assert isinstance(day, dt.date)
    assert isinstance(shape, interop.Shape)
    assert len(values) == 2

    seen.append((span, day, shape.width, shape.height, shape.name, values))
    moved = {'start': span['start'] + 1, 'stop': span['stop'] + 1}
    doubled = interop.Shape(shape.width * 2, shape.height, 'doubled')

    return (moved, day + dt.timedelta(days=1), doubled)


def flattened(*values: object) -> str:
    assert len(values) == 4

    return repr(values)


def test_object_api_converts_rich_values_both_ways() -> None:
    seen: list[tuple[object, ...]] = []
    echo = functools.partial(relayed, seen=seen)

    span, day, shape = interop.relay(echo)

    assert seen == [
        ({'start': 1, 'stop': 5}, dt.date(2026, 10, 30), 2.0, 2.0, 'square', (1.5, 2.5)),
    ]
    assert span == {'start': 2, 'stop': 6}
    assert day == dt.date(2026, 10, 31)
    assert (shape.width, shape.height, shape.name) == (4.0, 2.0, 'doubled')

    with pytest.raises(ValueError, match='callback result must hold exactly 3 items'):
        interop.relay(lambda *values: values)

    with pytest.raises(TypeError, match='callback result must be'):
        interop.relay(flattened)


class Shelf:
    def __contains__(self, item: object) -> bool:
        assert isinstance(item, str)

        result = item == 'book'

        assert isinstance(result, bool)

        return result

    def __call__(self) -> str:
        result = 'called'

        assert isinstance(self, Shelf)

        return result


class Named:
    def name(self) -> str:
        result = 'parent'

        assert isinstance(self, Named)

        return result


class Renamed(Named):
    def name(self) -> str:
        result = 'child'

        assert isinstance(self, Renamed)

        return result


def interval_widths(interval: interop.Interval, rounds: int, barrier: threading.Barrier) -> int:
    assert rounds > 0
    assert interval.start <= interval.stop
    assert barrier.parties == THREAD_COUNT

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    return sum(interval.width() for _ in range(rounds))


def test_frozen_classes_read_without_the_instance_lock() -> None:
    interval = interop.Interval(2, 9)
    rounds = 2000
    barrier = threading.Barrier(THREAD_COUNT)

    assert (interval.start, interval.stop, interval.width()) == (2, 9, 7)
    assert interval.overlaps(interop.Interval(8, 12))
    assert not interval.overlaps(interop.Interval(9, 12))

    with pytest.raises(AttributeError):
        interval.start = 3

    with pytest.raises(ValueError, match='ends before it starts'):
        interop.Interval(5, 1)

    with concurrent.futures.ThreadPoolExecutor(THREAD_COUNT) as pool:
        futures = [
            pool.submit(interval_widths, interval, rounds, barrier) for _ in range(THREAD_COUNT)
        ]

    assert [future.result() for future in futures] == [7 * rounds] * THREAD_COUNT


def test_critical_sections_keep_a_read_modify_write_whole() -> None:
    values = [0]
    rounds = 2000

    threads = [
        threading.Thread(target=interop.guarded_increment, args=(values, rounds))
        for _ in range(THREAD_COUNT)
    ]

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    assert values == [THREAD_COUNT * rounds]


def test_types_with_constants_freeze_where_python_allows_it() -> None:
    assert interop.Shape.sides == 4

    if interop.types_freezable:
        with pytest.raises(TypeError, match='immutable'):
            interop.Shape.sides = 5
    else:
        interop.Shape.sides = 5
        interop.Shape.sides = 4

    assert interop.Shape.sides == 4


def prime(number: int) -> bool:
    assert isinstance(number, int)

    if number < 2:
        return False

    return all(number % divisor for divisor in range(2, math.isqrt(number) + 1))


async def prime_count_cancelled(interval: interop.Interval) -> float:
    assert interval.start < interval.stop

    task = asyncio.ensure_future(interval.prime_count())

    await asyncio.sleep(0.05)

    task.cancel()
    started = time.perf_counter()

    with pytest.raises(asyncio.CancelledError):
        await task

    elapsed = time.perf_counter() - started

    assert elapsed >= 0

    return elapsed


def test_async_methods_run_off_the_event_loop_and_cancel() -> None:
    interval = interop.Interval(-5, 400)
    expected = sum(1 for number in range(-5, 400) if prime(number))

    assert inspect.iscoroutinefunction(interop.Interval.prime_count)
    assert inspect.iscoroutinefunction(interval.prime_count)
    assert str(inspect.signature(interval.prime_count)) == '()'
    assert interop.Interval.prime_count.__qualname__ == 'Interval.prime_count'
    assert interop.Interval.prime_count.__module__ == 'interop'
    assert asyncio.run(interval.prime_count()) == expected == 78
    assert asyncio.run(interop.Interval(7, 7).prime_count()) == 0
    assert asyncio.run(prime_count_cancelled(interop.Interval(1 << 40, 1 << 41))) < 30


def test_static_methods_find_their_own_module() -> None:
    specification = importlib.util.find_spec('interop')

    assert specification is not None
    assert specification.loader is not None

    fresh = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(fresh)

    assert fresh is not interop
    assert fresh.Shape is not interop.Shape

    with mock.patch.dict(sys.modules, {'interop': fresh}):
        square = interop.Shape.square(2)

    owner = interop.Shape if interop.types_freezable else fresh.Shape

    assert type(square) is owner
    assert square.area == 4


def test_zig_panic_reports_the_call_and_the_python_stack() -> None:
    directory = str(pathlib.Path(interop.__file__).parent.parent)

    assert pathlib.Path(directory).is_dir()

    source = (
        'import sys\n'
        f'sys.path.insert(0, {directory!r})\n'
        'import interop\n'
        'def caller():\n'
        '    interop.panic_witness("witness message")\n'
        'caller()\n'
    )

    command = [sys.executable, '-c', source]
    completed = subprocess.run(command, capture_output=True, check=False, text=True, timeout=120)

    assert completed.returncode != 0
    assert 'lacuna: panic in interop.panic_witness: witness message' in completed.stderr

    if CPYTHON:
        assert 'in caller' in completed.stderr


def test_object_operators_match_python() -> None:
    values = [1, 2]

    assert interop.operate(7, 'add', 5) == 12
    assert interop.operate(7, 'divmod', 2) == (3, 1)
    assert interop.operate('ab', 'multiply', 2) == 'abab'
    assert interop.operate(values, 'add', [3], in_place=True) is values
    assert values == [1, 2, 3]
    assert interop.operate(5, 'divmod', 2, in_place=True) == (2, 1)
    assert interop.operate_unary(5, 'invert') == -6
    assert interop.powered(3, 4) == 81
    assert interop.powered(3, 4, 5) == 1

    with pytest.raises(ValueError, match='operator name is unknown'):
        interop.operate(1, 'nope', 2)

    with pytest.raises(ZeroDivisionError):
        interop.operate(1, 'true_divide', 0)


def test_object_queries_match_python() -> None:
    items = [1, 2]
    contained, present, callable_, found = interop.queried(items, 2, 'append')

    assert (contained, present, callable_) == (True, True, False)
    assert found == items.append
    assert interop.queried({'k': 1}, 'k', 'missing') == (True, False, False, None)

    contained, present, callable_, found = interop.queried(Shelf(), 'book', '__call__')

    assert (contained, present, callable_) == (True, True, True)
    assert found() == 'called'

    with pytest.raises(TypeError):
        interop.queried(3, 1, 'real')

    assert interop.formatted(255, '#x') == '0xff'
    assert 'append' in interop.listing([])
    assert interop.encoded(bytearray(b'ab')) == b'ab'
    assert interop.encoded(memoryview(b'cd')) == b'cd'

    with pytest.raises(TypeError, match=ENCODED_REFUSAL):
        interop.encoded(3)
    assert interop.parent_name(Renamed(), Renamed) == 'parent'
    assert interop.subclass_check(Renamed, Named) is True
    assert interop.subclass_check(Named, Renamed) is False

    with pytest.raises(TypeError, match='expected a type'):
        interop.subclass_check(Renamed(), Named)


def test_arena_results_convert_before_the_arena_is_freed() -> None:
    text = 'the quick brown the lazy the'

    assert interop.split_words(text) == text.split()
    assert interop.split_words('') == []
    assert interop.word_counts(text) == collections.Counter(text.split())
    assert list(interop.word_counts(text)) == ['the', 'quick', 'brown', 'lazy']
    assert interop.reserve(1 << 20) == 1 << 20

    with pytest.raises(MemoryError):
        interop.reserve(1 << 31)


def test_exec_hook_fills_the_module_state() -> None:
    item = {'b': 1, 'a': [2]}

    assert interop._exec_ran is True

    before = interop.cache_hits()

    assert interop.cached_dumps(item) == json.dumps(item)
    assert interop.cache_hits() == before + 1


def test_module_state_belongs_to_each_module_instance() -> None:
    interop.cached_dumps(1)
    original = sys.modules.pop('interop')

    try:
        fresh = importlib.import_module('interop')
    finally:
        sys.modules['interop'] = original

    assert fresh is not original
    assert fresh.cache_hits() == 0
    assert original.cache_hits() >= 1
    assert fresh.cached_dumps([1]) == '[1]'
    assert fresh.cache_hits() == 1


def test_failing_exec_hook_fails_the_import() -> None:
    original = sys.modules.pop('interop')
    os.environ['INTEROP_EXEC_FAIL'] = '1'

    try:
        with pytest.raises(RuntimeError, match='told to fail'):
            importlib.import_module('interop')
    finally:
        del os.environ['INTEROP_EXEC_FAIL']
        sys.modules['interop'] = original

    assert sys.modules['interop'] is original


@subinterpreters
def test_module_state_in_a_subinterpreter() -> None:
    directory = str(pathlib.Path(interop.__file__).parent.parent)

    source = (
        'import sys\n'
        f'sys.path.insert(0, {directory!r})\n'
        'import interop\n'
        'assert interop.cache_hits() == 0\n'
        'assert interop.cached_dumps([1]) == "[1]"\n'
        'assert interop.cache_hits() == 1\n'
    )

    subinterpreter_run(source)


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


class ComplexBroken:
    @property
    def __complex__(self) -> complex:
        message = 'the complex hook is broken'
        raise LookupError(message)

    def __float__(self) -> float:
        return 1.0


def test_complex_hook_errors_propagate() -> None:
    with pytest.raises(LookupError, match='the complex hook is broken'):
        interop.rotate(ComplexBroken())


class Haunted(interop.Shape):
    @property
    def __dict__(self) -> dict[str, object]:
        message = 'the instance dictionary is gone'
        raise LookupError(message)


def test_pickle_propagates_a_failing_instance_dictionary() -> None:
    with pytest.raises(LookupError, match='the instance dictionary is gone'):
        pickle.dumps(Haunted(1.0, 2.0))


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


def test_variadic_tuple_has_no_capacity() -> None:
    values = list(range(100_000))

    assert interop.total_all(*values) == sum(values)
    assert interop.total_all() == 0

    with pytest.raises(TypeError, match='unexpected keyword'):
        interop.total_all(values=1)

    with pytest.raises(TypeError):
        interop.total_all(1, 'two')


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


def test_blobs_are_copied_out_of_their_buffers() -> None:
    packet = interop.Packet(b'ab')

    packet.data = bytearray(b'xyz')

    assert packet.data == b'xyz'
    assert pickle.loads(pickle.dumps(packet)).data == b'xyz'
    assert interop.blobs([b'a', bytearray(b'bc'), memoryview(b'defg')]) == [b'a', b'bc', b'defg']

    with pytest.raises(ValueError, match='at most 8 bytes'):
        packet.data = b'123456789'

    with pytest.raises(ValueError, match='at most 4 bytes'):
        interop.blobs([b'12345'])

    assert packet.data == b'xyz'


def test_an_unencodable_keyword_is_an_unknown_keyword() -> None:
    surrogate = '\ud800'

    with pytest.raises(TypeError, match='unexpected keyword argument'):
        interop.clamp(0.5, **{surrogate: 1.0})

    with pytest.raises(UnicodeEncodeError):
        interop.combine(1, **{surrogate: 1})


def test_arrays_of_odd_widths_round_trip() -> None:
    narrow = (-1, -(2**14), 2**14 - 1)
    single = (-(2**30),)
    colors = (2**12 - 1, 0)

    assert interop.widths(narrow, single, colors, ()) == (narrow, single, colors, ())
    assert interop.widths([-1, -1, -1], [-1], [1, 2], []) == ((-1, -1, -1), (-1,), (1, 2), ())

    with pytest.raises(OverflowError):
        interop.widths(narrow, single, (2**12, 0), ())

    with pytest.raises(ValueError, match='exactly 0 items'):
        interop.widths(narrow, single, colors, (1,))


def test_union_tries_every_record_shape() -> None:
    circle = {'radius': 1.0}
    rectangle = {'width': 2.0, 'height': 3.0}
    partial = {'width': 2.0}
    shapes = "a dict with keys 'radius' or a dict with keys 'width', 'height'"
    attributes = "an object with attributes 'real', 'imag', not <class 'str'>"

    assert interop.outline(circle) == 'circle'
    assert interop.outline(rectangle) == 'rectangle'
    assert interop.outline(2j) == 'spot'
    assert interop.outline(5) == 'spot'

    with pytest.raises(TypeError, match=shapes):
        interop.outline(partial)

    with pytest.raises(TypeError, match=attributes):
        interop.outline('round')


def test_union_falls_back_from_a_writable_buffer() -> None:
    values = array.array('d', [1.0, 2.0])
    frozen = memoryview(values).toreadonly()

    assert interop.writable(values)
    assert not interop.writable(frozen)

    with pytest.raises(TypeError, match='a writable buffer of f64 items or a buffer of f64 items'):
        interop.writable(array.array('q', [1]))


def test_union_releases_the_locks_of_a_rejected_variant() -> None:
    first = interop.Ledger(1)
    second = interop.Ledger(2)

    assert interop.ledger_pick((first, 5), second) == 'amount'
    assert interop.ledger_pick((first, 'memo'), second) == 'memo'
    assert interop.ledger_pick((first, 'memo'), first) == 'memo'

    with pytest.raises(TypeError, match='a sequence of 2 items or a sequence of 2 items'):
        interop.ledger_pick((first, 1.5), second)


def test_union_holds_a_big_integer() -> None:
    assert interop.magnitude(2**100) == 101
    assert interop.magnitude(-(2**200)) == 201
    assert interop.magnitude(0) == 0
    assert interop.magnitude('four') == 4

    with pytest.raises(TypeError, match='must be int or str'):
        interop.magnitude(1.5)


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


def traverse_visit(item: int, argument: int) -> int:
    assert item != 0
    assert argument in TRAVERSE_ARGUMENTS

    return argument & TRAVERSE_MASK


@pythonapi
def test_traverse_hands_the_visitor_any_argument() -> None:
    visit_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_size_t, ctypes.c_size_t)
    traverse_type = ctypes.PYFUNCTYPE(ctypes.c_int, ctypes.py_object, visit_type, ctypes.c_size_t)
    slot_of = ctypes.pythonapi.PyType_GetSlot
    slot_of.restype = ctypes.c_size_t
    slot_of.argtypes = (ctypes.py_object, ctypes.c_int)
    visitor = visit_type(traverse_visit)
    node = interop.Node('root', object())

    for target in (interop, node):
        traverse = traverse_type(slot_of(type(target), TRAVERSE_SLOT))

        for argument in TRAVERSE_ARGUMENTS:
            assert traverse(target, visitor, argument) == argument & TRAVERSE_MASK


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
class Payload:
    pass


def released_is(probe: weakref.ref) -> bool:
    assert isinstance(probe, weakref.ref)

    return probe() is None


@counts_references
def test_pooled_nodes_start_fresh_and_keep_collecting() -> None:
    for round_index in range(4):
        payload = Payload()
        probe = weakref.ref(payload)
        nodes = [interop.Node(f'n{round_index}{index}', payload) for index in range(12)]

        nodes[0].attach(0, nodes[1])
        nodes[1].attach(0, nodes[0])

        del nodes, payload
        gc.collect()

        assert released_is(probe)

        fresh = [interop.Node('fresh') for _ in range(12)]

        assert all(node.payload is None for node in fresh)
        assert all(node.child(0) is None for node in fresh)
        assert all(node.label == 'fresh' for node in fresh)
        assert all(gc.is_tracked(node) for node in fresh)


@counts_references
def test_bag_traverses_its_list_so_cycles_are_collected() -> None:
    bag = interop.Bag()
    tracker = Tracker()

    bag.add(tracker)
    bag.add(bag)

    assert len(bag) == 2
    assert tracker in gc.get_referents(bag)
    assert bag in gc.get_referents(bag)
    assert gc.is_tracked(bag)

    probe = weakref.ref(tracker)

    del bag, tracker
    gc.collect()

    assert probe() is None


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


def test_threads_share_one_list() -> None:
    values = [SHARED_BASE + index for index in range(SHARED_LENGTH)]
    expected = sum(values)
    barrier = threading.Barrier(THREAD_COUNT + 1)
    totals: list[int] = []
    arguments = (barrier, values, totals)
    threads = [
        threading.Thread(target=list_reader_work, args=arguments) for _ in range(THREAD_COUNT)
    ]

    writer_arguments = (barrier, values)
    writer = threading.Thread(target=list_writer_work, args=writer_arguments)

    threads.append(writer)

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    assert len(totals) == THREAD_COUNT * THREAD_ROUNDS
    assert set(totals) == {expected}


def list_reader_work(barrier: threading.Barrier, values: list[int], totals: list[int]) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(values) == SHARED_LENGTH
    assert not totals

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(THREAD_ROUNDS):
        total = interop.list_total(values)
        totals.append(total)


def list_writer_work(barrier: threading.Barrier, values: list[int]) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(values) == SHARED_LENGTH

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for round_index in range(THREAD_ROUNDS):
        index = round_index % SHARED_LENGTH
        values[index] = SHARED_BASE + index


def test_threads_share_one_dictionary() -> None:
    mapping = {f'key{index}': SHARED_BASE + index for index in range(SHARED_LENGTH)}
    barrier = threading.Barrier(THREAD_COUNT + 1)
    probes: list[tuple[bool, int]] = []
    arguments = (barrier, mapping, probes)
    threads = [
        threading.Thread(target=dictionary_reader_work, args=arguments) for _ in range(THREAD_COUNT)
    ]

    writer_arguments = (barrier, mapping)
    writer = threading.Thread(target=dictionary_writer_work, args=writer_arguments)

    threads.append(writer)

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    assert len(probes) == THREAD_COUNT * THREAD_ROUNDS
    assert set(probes) == {(False, SHARED_LENGTH)}


def dictionary_reader_work(
    barrier: threading.Barrier,
    mapping: dict[str, int],
    probes: list[tuple[bool, int]],
) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(mapping) == SHARED_LENGTH
    assert not probes

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for _ in range(THREAD_ROUNDS):
        probe = interop.dictionary_probe(mapping, 'missing')
        probes.append(probe)


def dictionary_writer_work(barrier: threading.Barrier, mapping: dict[str, int]) -> None:
    assert barrier.parties == THREAD_COUNT + 1
    assert len(mapping) == SHARED_LENGTH

    arrival = barrier.wait()

    assert 0 <= arrival < barrier.parties

    for round_index in range(THREAD_ROUNDS):
        index = round_index % SHARED_LENGTH
        mapping[f'key{index}'] = SHARED_BASE + index


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
