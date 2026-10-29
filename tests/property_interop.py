import datetime as dt
import fractions
import functools
import ipaddress
import os
import pathlib
import pickle
import re
import zoneinfo

import interop
import pytest

from hypothesis import example, given, settings
from hypothesis import strategies as st

from conftest import (
    HOSTILE_ARGUMENT_COUNT_MAX,
    hostile_check,
    hostile_targets,
    hostile_values,
    zone_install,
)


HOSTILE_SETTINGS = settings(database=None, deadline=None, max_examples=2000)
KEYWORDS_RESERVED = frozenset({'first', 'options', 'rest', 'scale'})
LABEL_BYTES_MAX = 32
LETTERS_COUNT_MAX = 64
MICROSECONDS_PER_SECOND = 1_000_000
NAME_BYTES_MAX = 16
OFFSET_SECONDS_MAX = 86_399
OPTIONS_COUNT_MAX = 4
RANGE_SIMPLE = re.compile(r'(-?[0-9]{1,18})\.\.(-?[0-9]{1,18})')
REST_COUNT_MAX = 8
SCORES_COUNT_MAX = 8
SECONDS_PER_DAY = 86_400
SETTINGS = settings(database=None, deadline=None, max_examples=400)
SIGNED_256 = (-(2**255), 2**255 - 1)
SIGNED_64 = (-(2**63), 2**63 - 1)
UNSIGNED_128 = (0, 2**128 - 1)
WORDS_COUNT_MAX = 16
ZONE = zoneinfo.ZoneInfo(zone_install())


def checked(value: int) -> int:
    assert isinstance(value, int)

    if not inside(value, SIGNED_64):
        message = f'{value} overflows i64'
        raise OverflowError(message)

    return value


def combine_reference(*, first: int, rest: list[int], scale: int, options: dict[str, int]) -> int:
    assert inside(first, SIGNED_64)
    assert len(rest) <= REST_COUNT_MAX
    assert inside(scale, SIGNED_64)
    assert len(options) <= OPTIONS_COUNT_MAX

    total = first

    for item in rest:
        total = checked(total + item)

    total = checked(total * scale)

    for value in options.values():
        total = checked(total + value)

    assert inside(total, SIGNED_64)

    return total


def extension_reference(path: str | bytes) -> str:
    assert isinstance(path, str | bytes)

    encoded = os.fsencode(path)
    dot = encoded.rfind(b'.')

    if dot < 0:
        return ''

    try:
        suffix = encoded[dot:].decode('utf-8')
    except UnicodeDecodeError:
        return ''
    else:
        return suffix


def fsdecode_reference(raw: bytes) -> str | None:
    assert b'\0' not in raw

    try:
        text = os.fsdecode(raw)
    except UnicodeDecodeError:
        return None
    else:
        return text


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


def microseconds_of(span: dt.timedelta) -> int:
    assert isinstance(span, dt.timedelta)

    result = (span.days * SECONDS_PER_DAY + span.seconds) * MICROSECONDS_PER_SECOND
    result += span.microseconds

    assert result // MICROSECONDS_PER_SECOND // SECONDS_PER_DAY == span.days

    return result


def offsets() -> st.SearchStrategy[dt.timezone]:
    seconds = st.integers(min_value=-OFFSET_SECONDS_MAX, max_value=OFFSET_SECONDS_MAX)

    assert OFFSET_SECONDS_MAX < SECONDS_PER_DAY

    return seconds.map(lambda count: dt.timezone(dt.timedelta(seconds=count)))


def surrogate(text: str) -> bool:
    assert isinstance(text, str)

    return any(0xD800 <= ord(item) <= 0xDFFF for item in text)


def texts(size_max: int) -> st.SearchStrategy[str]:
    assert size_max > 0

    characters = st.characters(codec='utf-8', exclude_characters='\0')

    return st.text(characters, max_size=size_max)


@SETTINGS
@given(count=st.integers(min_value=0, max_value=4096))
def test_unbounded_list_matches_range(count: int) -> None:
    assert count >= 0

    values = interop.range_list(count)

    assert values == list(range(count))
    assert interop.list_total(values) == sum(values)
    assert interop.squares(count) == {index: index * index for index in range(count)}
    assert len(interop.spelled(count)) == 2 * count


@SETTINGS
@given(
    value=st.fractions(min_value=-(2**120), max_value=2**120, max_denominator=2**120),
    address=st.ip_addresses(),
    moment=st.datetimes(timezones=st.just(ZONE)),
)
def test_value_types_round_trip(
    value: fractions.Fraction,
    address: ipaddress.IPv4Address | ipaddress.IPv6Address,
    moment: dt.datetime,
) -> None:
    assert value.denominator > 0
    assert moment.tzinfo is ZONE

    echoed = interop.moments(moment.date(), moment.time(), moment, dt.timedelta())[2]

    assert interop.fraction_echo(value) == value
    assert interop.address_echo(address) == address
    assert type(interop.address_echo(address)) is type(address)
    assert echoed == moment
    assert echoed.tzinfo is ZONE


@SETTINGS
@given(text=st.text(alphabet='0123456789-+._x ', max_size=24) | st.text(max_size=12))
def test_parse_raises_only_its_own_errors(text: str) -> None:
    assert len(text) <= 24

    match = RANGE_SIMPLE.fullmatch(text)

    try:
        width = interop.parse(text)
    except interop.Error:
        assert match is None or int(match[1]) > int(match[2])
    else:
        assert width >= 0

        if match is not None:
            assert width == int(match[2]) - int(match[1])


@SETTINGS
@given(left=integers_near(SIGNED_256), right=integers_near(SIGNED_256))
def test_wide_add_matches_python(*, left: int, right: int) -> None:
    assert abs(left) <= 2**256 + 2
    assert abs(right) <= 2**256 + 2

    if all(inside(value, SIGNED_256) for value in (left, right, left + right)):
        assert interop.wide_add(left, right) == left + right
    else:
        with pytest.raises(OverflowError):
            interop.wide_add(left, right)


@SETTINGS
@given(value=integers_near(UNSIGNED_128))
def test_unsigned_echo_matches_its_range(value: int) -> None:
    assert abs(value) <= 2**129 + 2

    if inside(value, UNSIGNED_128):
        assert interop.unsigned_echo(value) == value
    else:
        with pytest.raises(OverflowError):
            interop.unsigned_echo(value)


@SETTINGS
@given(
    day=st.dates(),
    clock=st.times(),
    moment=st.datetimes(timezones=st.none() | offsets()),
    span=st.timedeltas(),
)
def test_calendar_round_trips(
    day: dt.date,
    clock: dt.time,
    moment: dt.datetime,
    span: dt.timedelta,
) -> None:
    assert clock.tzinfo is None
    assert isinstance(moment, dt.datetime)
    assert isinstance(day, dt.date)
    assert isinstance(span, dt.timedelta)

    microseconds = microseconds_of(span)

    if not inside(microseconds, SIGNED_64):
        with pytest.raises(OverflowError):
            interop.moments(day, clock, moment, span)

        return

    result = interop.moments(day, clock, moment, span)

    assert result[0] == day
    assert result[1] == clock.replace(fold=0)
    assert result[2].replace(tzinfo=None) == moment.replace(tzinfo=None, fold=0)
    assert result[2].utcoffset() == moment.utcoffset()
    assert result[3] == span

    if inside(microseconds * 2, SIGNED_64):
        assert interop.doubled_span(span) == span * 2
    else:
        with pytest.raises(OverflowError):
            interop.doubled_span(span)


@SETTINGS
@given(text=st.text(max_size=24))
def test_text_paths_match_fspath(text: str) -> None:
    assert len(text) <= 24

    if '\0' in text:
        with pytest.raises(ValueError, match='embedded null'):
            interop.path_echo(text)
    elif surrogate(text):
        with pytest.raises(UnicodeEncodeError):
            interop.path_echo(text)
    else:
        assert interop.path_echo(text) == pathlib.Path(text)
        assert interop.extension(text) == extension_reference(text)


@SETTINGS
@given(raw=st.binary(max_size=24))
@example(raw=b'\x80')
def test_byte_paths_match_fspath(raw: bytes) -> None:
    assert len(raw) <= 24

    if b'\0' in raw:
        with pytest.raises(ValueError, match='embedded null'):
            interop.path_echo(raw)
    else:
        decoded = fsdecode_reference(raw)

        if decoded is None:
            with pytest.raises(UnicodeDecodeError):
                interop.path_echo(raw)
        else:
            assert interop.path_echo(raw) == pathlib.Path(decoded)

        assert interop.extension(raw) == extension_reference(raw)


@SETTINGS
@given(words=st.frozensets(texts(4), max_size=20))
def test_word_count_matches_length(words: frozenset[str]) -> None:
    assert len(words) <= 20

    if len(words) > WORDS_COUNT_MAX:
        with pytest.raises(ValueError, match='at most 16'):
            interop.word_count(set(words))
    else:
        assert interop.word_count(set(words)) == len(words)


@SETTINGS
@given(text=st.text(st.characters(codec='utf-8') | st.just('\ud800'), max_size=80))
def test_letters_match_encoded_bytes(text: str) -> None:
    assert len(text) <= 80

    expected = set(text.encode('utf-8', 'surrogatepass'))

    if surrogate(text):
        with pytest.raises(UnicodeEncodeError):
            interop.letters(text)
    elif len(expected) > LETTERS_COUNT_MAX:
        with pytest.raises(interop.ListFull):
            interop.letters(text)
    else:
        assert interop.letters(text) == expected


@SETTINGS
@given(scores=st.dictionaries(texts(6), integers_near(SIGNED_64), max_size=10))
def test_invert_matches_python(scores: dict[str, int]) -> None:
    assert len(scores) <= 10

    inverted = {value: key for key, value in scores.items()}

    if len(scores) > SCORES_COUNT_MAX:
        with pytest.raises(ValueError, match='at most 8'):
            interop.invert(scores)
    elif all(inside(value, SIGNED_64) for value in scores.values()):
        assert interop.invert(scores) == inverted
    else:
        with pytest.raises(OverflowError):
            interop.invert(scores)


@SETTINGS
@given(text=texts(40), times=st.integers(min_value=0, max_value=255))
def test_owned_text_respects_capacity(text: str, times: int) -> None:
    assert '\0' not in text
    assert 0 <= times <= 255

    size = len(text.encode())

    if size > LABEL_BYTES_MAX:
        with pytest.raises(ValueError, match='at most 32 bytes'):
            interop.repeat(text, times)
    elif size * times > LABEL_BYTES_MAX:
        with pytest.raises(interop.TextFull):
            interop.repeat(text, times)
    else:
        assert interop.repeat(text, times) == text * times


@SETTINGS
@given(
    first=integers_near(SIGNED_64),
    rest=st.lists(integers_near(SIGNED_64), max_size=10),
    scale=integers_near(SIGNED_64),
    options=st.dictionaries(
        st.from_regex(r'[a-z]{1,5}', fullmatch=True).filter(
            lambda name: name not in KEYWORDS_RESERVED,
        ),
        integers_near(SIGNED_64),
        max_size=6,
    ),
)
def test_combine_matches_reference(
    *,
    first: int,
    rest: list[int],
    scale: int,
    options: dict[str, int],
) -> None:
    assert len(rest) <= 10
    assert len(options) <= 6
    assert abs(first) <= 2**64 + 2
    assert abs(scale) <= 2**64 + 2

    call = functools.partial(interop.combine, first, *rest, scale=scale, **options)

    if len(rest) > REST_COUNT_MAX:
        with pytest.raises(TypeError, match='at most 8 extra positional'):
            call()
    elif len(options) > OPTIONS_COUNT_MAX:
        with pytest.raises(TypeError, match='at most 4 extra keyword'):
            call()
    else:
        combine_bounded(first=first, rest=rest, scale=scale, options=options)


def combine_bounded(*, first: int, rest: list[int], scale: int, options: dict[str, int]) -> None:
    assert len(rest) <= REST_COUNT_MAX
    assert len(options) <= OPTIONS_COUNT_MAX
    assert isinstance(first, int)
    assert isinstance(scale, int)

    values = [first, scale, *rest, *options.values()]
    call = functools.partial(interop.combine, first, *rest, scale=scale, **options)

    if not all(inside(value, SIGNED_64) for value in values):
        with pytest.raises(OverflowError):
            call()

        return

    try:
        expected = combine_reference(first=first, rest=rest, scale=scale, options=options)
    except OverflowError:
        with pytest.raises(OverflowError):
            call()
    else:
        assert call() == expected


@SETTINGS
@given(
    value=st.floats(allow_nan=False),
    low=st.floats(allow_nan=False),
    high=st.floats(allow_nan=False),
)
def test_clamp_matches_python(*, value: float, low: float, high: float) -> None:
    assert isinstance(value, float)
    assert isinstance(low, float)
    assert isinstance(high, float)

    if low > high:
        with pytest.raises(ValueError, match=r'^$'):
            interop.clamp(value, low=low, high=high)
    else:
        assert interop.clamp(value, low=low, high=high) == max(low, min(value, high))


@SETTINGS
@given(item=st.integers(min_value=SIGNED_64[0], max_value=SIGNED_64[1]) | texts(8) | st.none())
def test_unions_match_their_variants(item: object) -> None:
    assert item is None or isinstance(item, int | str)

    if item is None:
        assert interop.measure(item) == -1
    elif isinstance(item, str):
        assert interop.measure(item) == len(item.encode())
    else:
        expected = item // 2 if item % 2 == 0 else 'odd'

        assert interop.measure(item) == item
        assert interop.parity(item) == expected


@SETTINGS
@given(
    width=st.floats(allow_nan=False),
    height=st.floats(allow_nan=False),
    name=texts(20),
)
def test_shape_pickle_round_trips(*, width: float, height: float, name: str) -> None:
    assert isinstance(width, float)
    assert isinstance(height, float)
    assert '\0' not in name

    if len(name.encode()) > NAME_BYTES_MAX:
        with pytest.raises(ValueError, match='at most 16 bytes'):
            interop.Shape(width, height, name)

        return

    shape = interop.Shape(width, height, name)
    restored = pickle.loads(pickle.dumps(shape))

    assert restored == shape
    assert restored.name == name
    assert type(restored) is interop.Shape


@HOSTILE_SETTINGS
@given(data=st.data())
def test_hostile_arguments_raise_cleanly(data: st.DataObject) -> None:
    assert isinstance(data, st.DataObject)

    instances = [interop.Node('node'), interop.Shape(1.0, 2.0)]
    targets = hostile_targets(interop, instances)
    pool = hostile_values()
    values = st.integers(min_value=0, max_value=len(pool) - 1).map(pool.__getitem__)
    target_index = data.draw(st.integers(min_value=0, max_value=len(targets) - 1))
    arguments = data.draw(st.lists(values, max_size=HOSTILE_ARGUMENT_COUNT_MAX))
    names = st.sampled_from(['text', 'function', 'item', 'path', 'low', 'scale', 'bogus'])
    keywords = data.draw(st.dictionaries(names, values, max_size=2))
    call = functools.partial(targets[target_index], *arguments, **keywords)

    hostile_check(call)
