import array
import collections
import collections.abc
import ctypes
import dataclasses
import enum
import functools
import ipaddress
import math
import operator
import random
import struct
import types
import uuid

from types import ModuleType

from hypothesis import strategies as st


ARRAY_LENGTH_MAX = 3
BIG_INTEGER_BITS_MAX = 1 << 14
BIG_INTEGER_EDGE_COUNT = 7
BYTE_BITS = 8
CAPACITY_MAX = 4
CLASS_COUNT = 6
CLASS_FIELD_COUNT_MAX = 3
COMPOSITE_KINDS = ('array', 'list', 'map', 'optional', 'record', 'set', 'tuple', 'variant')
DEFAULT_CHANCE = 0.4
DEPTH_MAX = 3
ENUM_MEMBER_COUNT_MAX = 4
ENUM_TAG_BITS = (0, 1, 2, 3, 8, 16, 32, 63, 64, 65, 128)
FIELD_COUNT_MAX = 4
FIELD_NAMES = ('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot', 'golf', 'hotel')
FLOAT_BITS = (16, 32, 64, 80, 128)
FLOAT_DEFAULTS = (0.0, 0.5, -2.0, 1024.0)
FLOAT_EDGES = (
    0.0,
    -0.0,
    1.0,
    -1.5,
    5e-324,
    2.2250738585072014e-308,
    1.401298464324817e-45,
    5.960464477539063e-08,
    65504.0,
    65519.99,
    65520.0,
    3.4028234663852886e38,
    3.4028235677973366e38,
    1.7976931348623157e308,
    math.inf,
    -math.inf,
    math.nan,
)
FUNCTION_ATTEMPT_MAX = 64
HASHABLE_KINDS = ('address', 'blob', 'boolean', 'enumeration', 'integer', 'integer', 'text', 'uuid')
HEAP_TYPE_FLAG = 1 << 9
HOLDER_BUDGET = 512
INTEGER_BITS = (1, 2, 7, 8, 9, 15, 16, 17, 31, 32, 33, 53, 63, 64, 65, 100, 127, 128, 129, 256)
INTEGER_BITS_WIDEST = 1024
LAYER_WIDTH = 12
LEAF_KINDS = (
    'address',
    'blob',
    'boolean',
    'complex',
    'enumeration',
    'float',
    'float',
    'integer',
    'integer',
    'text',
    'uuid',
)
LEAF_KINDS_TOP = (*LEAF_KINDS, 'big')
PAYLOAD_COUNT_MAX = 4
SEQUENCE_TYPES = (
    array.array,
    bytearray,
    bytes,
    collections.deque,
    list,
    memoryview,
    range,
    tuple,
)
TEXT_CAPACITY_MAX = 12
TEXT_DEFAULTS = ('', 'zig', 'café')
TEXT_SIZE_MAX = 24
TUPLE_WIDTH_MAX = 3
WALK_STEP_MAX = 1 << 12
VOID_CHANCE = 0.15


class RefusedError(Exception):
    pass


@dataclasses.dataclass(frozen=True)
class Indexed:
    number: int

    def __index__(self) -> int:
        assert isinstance(self.number, int)
        assert not isinstance(self.number, bool)

        return self.number


@dataclasses.dataclass(frozen=True)
class Floating:
    number: float

    def __float__(self) -> float:
        assert isinstance(self.number, float)
        assert type(self.number) is float

        return self.number


class Spelled(str):
    __slots__ = ()


class Keyed(dict):
    pass


HOSTILE = (
    None,
    True,
    0,
    -1,
    2**64,
    1.5,
    math.nan,
    1j,
    '',
    '\ud800',
    'text',
    b'bytes',
    (),
    [],
    {},
    frozenset(),
    object(),
    Indexed(3),
)


@dataclasses.dataclass(frozen=True)
class Default:
    enumeration: str | None
    python: object
    zig: str


def big_integer_edge(index: int) -> int:
    assert 0 <= index < BIG_INTEGER_EDGE_COUNT
    assert BIG_INTEGER_BITS_MAX > 64

    limit = 1 << BIG_INTEGER_BITS_MAX
    edges = (0, 1, -1, 2**64, -(2**64), limit - 1, -(limit - 1))

    assert len(edges) == BIG_INTEGER_EDGE_COUNT

    return edges[index]


def big_integer_outside(index: int) -> object:
    assert 0 <= index < 3
    assert BIG_INTEGER_BITS_MAX > 64

    outside = (1 << BIG_INTEGER_BITS_MAX, -(1 << BIG_INTEGER_BITS_MAX), 1.5)

    return outside[index]


def float_rounded(*, number: float, bits: int) -> float:
    assert isinstance(number, float)
    assert bits in FLOAT_BITS

    if bits == 16:
        try:
            packed = struct.pack('<e', number)
        except OverflowError:
            return math.copysign(math.inf, number)

        return struct.unpack('<e', packed)[0]

    if bits == 32:
        return ctypes.c_float(number).value

    return number


def float_value(value: object) -> float:
    assert not isinstance(value, RefusedError)

    if isinstance(value, float):
        return float.__float__(value)

    if hasattr(type(value), '__float__'):
        return float_called(value)

    if not hasattr(type(value), '__index__'):
        raise RefusedError

    try:
        result = float(operator.index(value))
    except (OverflowError, TypeError):
        raise RefusedError from None

    assert type(result) is float

    return result


def float_called(value: object) -> float:
    assert not isinstance(value, RefusedError)
    assert hasattr(type(value), '__float__')

    try:
        result = type(value).__float__(value)
    except (OverflowError, TypeError):
        raise RefusedError from None

    if type(result) is not float:
        raise RefusedError

    return result


def hashable(value: object) -> bool:
    assert not isinstance(value, RefusedError)
    assert not isinstance(value, Default)

    try:
        hash(value)
    except TypeError:
        return False

    return True


def items_extended(items: tuple[object, ...]) -> tuple[object, ...]:
    assert isinstance(items, tuple)

    result = (*items, 0)

    assert len(result) == len(items) + 1

    return result


def items_miscounted(items: list[object], *, length: int) -> bool:
    assert isinstance(items, list)
    assert length >= 0

    return len(items) != length


def items_repeated(items: list[object], *, count: int) -> list[object]:
    assert isinstance(items, list)
    assert count >= 0

    result = items * count

    assert len(result) == len(items) * count

    return result


def items_shortened(items: tuple[object, ...]) -> tuple[object, ...]:
    assert isinstance(items, tuple)
    assert items

    result = items[:-1]

    assert len(result) == len(items) - 1

    return result


def keys_view(members: set[object]) -> collections.abc.KeysView:
    assert isinstance(members, set)
    assert all(hashable(member) for member in members)

    result = dict.fromkeys(members).keys()

    assert len(result) == len(members)

    return result


def mapping_proxy(contents: dict[object, object]) -> types.MappingProxyType:
    assert isinstance(contents, dict)
    assert len(contents) <= CAPACITY_MAX + 2

    result = types.MappingProxyType(contents)

    assert len(result) == len(contents)

    return result


def record_extended(items: dict[str, object]) -> dict[object, object]:
    assert isinstance(items, dict)
    assert 'zulu' not in items

    result: dict[object, object] = {**items, 'zulu': 1}

    assert len(result) == len(items) + 1

    return result


def record_keyed(items: dict[str, object]) -> dict[object, object]:
    assert isinstance(items, dict)
    assert all(isinstance(key, str) for key in items)

    result: dict[object, object] = {**items, 7: 1}

    assert len(result) == len(items) + 1

    return result


def record_with(items: dict[str, object], replaced: object, *, name: str) -> dict[str, object]:
    assert isinstance(items, dict)
    assert name.isidentifier()
    assert not isinstance(replaced, RefusedError)

    result = {**items, name: replaced}

    assert result[name] is replaced

    return result


def record_without(items: dict[str, object], *, name: str) -> dict[str, object]:
    assert isinstance(items, dict)
    assert name.isidentifier()

    result = {key: item for key, item in items.items() if key != name}

    assert name not in result

    return result


def sequence_items(value: object) -> list[object]:
    assert not isinstance(value, RefusedError)

    if isinstance(value, str | dict):
        raise RefusedError

    if not isinstance(value, SEQUENCE_TYPES):
        if not type(value).__flags__ & HEAP_TYPE_FLAG:
            raise RefusedError

        if not hasattr(type(value), '__getitem__'):
            raise RefusedError

    try:
        result = list(value)
    except TypeError:
        raise RefusedError from None

    assert isinstance(result, list)

    return result


def sequence_wrapped(items: list[object]) -> collections.UserList:
    assert isinstance(items, list)
    assert len(items) <= CAPACITY_MAX + 2

    result = collections.UserList(items)

    assert len(result) == len(items)

    return result


def singleton_set(item: object) -> set[object]:
    assert hashable(item)

    result = {item}

    assert len(result) == 1

    return result


def text_exact(text: str) -> str:
    assert isinstance(text, str)

    result = text.encode().decode()

    assert type(result) is str

    return result


def text_fits(text: str, *, capacity: int) -> bool:
    assert isinstance(text, str)
    assert capacity > 0

    return len(text.encode()) <= capacity


def text_unterminated(text: str) -> bool:
    assert isinstance(text, str)
    assert TEXT_SIZE_MAX > 0

    return '\0' not in text


def user_dictionary(contents: dict[object, object]) -> collections.UserDict:
    assert isinstance(contents, dict)
    assert len(contents) <= CAPACITY_MAX + 2

    result = collections.UserDict(contents)

    assert result.data == contents

    return result


def zig_float(number: float) -> str:
    assert math.isfinite(number)

    text = repr(number)
    result = text if '.' in text else text + '.0'

    assert float(result) == number

    return result


@dataclasses.dataclass(frozen=True, kw_only=True)
class Boolean:
    holders: int = 0
    spelled: str = 'bool'

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if value is True:
            return value

        if value is False:
            return value

        raise RefusedError

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)

        chosen = generator.random() < 0.5
        result = Default(None, chosen, 'true' if chosen else 'false')

        assert result.python is chosen

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        result = st.sampled_from([0, 1, None, 'true', 1.0])

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        return st.booleans()


@dataclasses.dataclass(frozen=True, kw_only=True)
class Integer:
    bits: int
    holders: int = 0
    signed: bool
    spelled: str

    def bounds(self) -> tuple[int, int]:
        assert 0 <= self.bits <= INTEGER_BITS_WIDEST
        assert self.bits > 0 or not self.signed

        if self.signed:
            return (-(1 << (self.bits - 1)), (1 << (self.bits - 1)) - 1)

        return (0, (1 << self.bits) - 1)

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        try:
            number = operator.index(value)
        except TypeError:
            raise RefusedError from None

        minimum, maximum = self.bounds()

        if number < minimum:
            raise RefusedError

        if number > maximum:
            raise RefusedError

        return number

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)

        minimum, maximum = self.bounds()
        chosen = generator.choice([minimum, maximum, max(minimum, min(maximum, 1))])
        result = Default(None, chosen, str(chosen))

        assert minimum <= chosen <= maximum

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        minimum, maximum = self.bounds()
        outside = [minimum - 1, maximum + 1, minimum - 2**70, maximum + 2**70, 1.0, '1', None]
        result = st.sampled_from(outside) | st.builds(Indexed, st.sampled_from(outside[:2]))

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        minimum, maximum = self.bounds()
        middle = (minimum + maximum) // 2
        edges = sorted({minimum, maximum, max(minimum, min(maximum, 0)), middle})
        numbers = st.integers(minimum, maximum) | st.sampled_from(edges)

        if canonical:
            return numbers

        forms = numbers | st.builds(Indexed, numbers)

        if minimum > 0:
            return forms

        if maximum < 1:
            return forms

        return forms | st.booleans()


@dataclasses.dataclass(frozen=True, kw_only=True)
class BigInteger:
    holders: int = 0
    spelled: str = 'std.math.big.int.Const'

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        try:
            number = operator.index(value)
        except TypeError:
            raise RefusedError from None

        if number.bit_length() > BIG_INTEGER_BITS_MAX:
            raise RefusedError

        return number

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        result = st.integers(0, 2).map(big_integer_outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        edges = st.integers(0, BIG_INTEGER_EDGE_COUNT - 1).map(big_integer_edge)

        return st.integers(-(2**300), 2**300) | edges


@dataclasses.dataclass(frozen=True, kw_only=True)
class Float:
    bits: int
    holders: int = 0
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        result = float_rounded(number=float_value(value), bits=self.bits)

        assert type(result) is float

        return result

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)

        chosen = generator.choice(FLOAT_DEFAULTS)
        result = Default(None, chosen, zig_float(chosen))

        assert float_rounded(number=chosen, bits=self.bits) == chosen

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        result = st.sampled_from([2**1024, '1.5', None, 1j, b'1'])

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        numbers = st.floats() | st.sampled_from(FLOAT_EDGES)
        forms = numbers | st.integers(-(2**60), 2**60)

        if canonical:
            return forms

        return forms | st.builds(Floating, numbers)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Complex:
    bits: int
    holders: int = 0
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if isinstance(value, complex):
            number = complex.__complex__(value)
        elif isinstance(value, str):
            raise RefusedError
        elif hasattr(value, '__complex__'):
            number = complex(value)
        else:
            number = complex(float_value(value), 0.0)

        real = float_rounded(number=number.real, bits=self.bits)
        imaginary = float_rounded(number=number.imag, bits=self.bits)

        return complex(real, imaginary)

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        result = st.sampled_from(['1+2j', None, b'1', [1.0, 2.0]])

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        numbers = st.complex_numbers()

        if canonical:
            return numbers

        return numbers | st.floats() | st.integers(-(2**60), 2**60)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Identifier:
    holders: int = 0
    spelled: str = 'lacuna.UUID'

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if not isinstance(value, uuid.UUID):
            raise RefusedError

        result = uuid.UUID(bytes=value.bytes)

        assert result == value

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        outside = [str(uuid.UUID(int=7)), uuid.UUID(int=7).bytes, 7, None]
        result = st.sampled_from(outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        return st.uuids()


@dataclasses.dataclass(frozen=True, kw_only=True)
class Address:
    holders: int = 0
    spelled: str = 'lacuna.IPAddress'

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if isinstance(value, ipaddress.IPv4Address):
            return ipaddress.IPv4Address(value.packed)

        if isinstance(value, ipaddress.IPv6Address):
            return ipaddress.IPv6Address(value.packed)

        raise RefusedError

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        outside = ['127.0.0.1', b'\x7f\x00\x00\x01', 2130706433, ipaddress.ip_network('10.0.0.0/8')]
        result = st.sampled_from(outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        return st.ip_addresses()


@dataclasses.dataclass(frozen=True, kw_only=True)
class Text:
    capacity: int | None
    holders: int = 0
    spelled: str
    terminated: bool

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if not isinstance(value, str):
            raise RefusedError

        try:
            encoded = value.encode()
        except UnicodeEncodeError:
            raise RefusedError from None

        if self.terminated:
            if '\0' in value:
                raise RefusedError

        if self.capacity is not None:
            if len(encoded) > self.capacity:
                raise RefusedError

        return encoded.decode()

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)
        assert self.capacity is None

        chosen = generator.choice(TEXT_DEFAULTS)
        result = Default(None, chosen, '"' + chosen + '"')

        assert '"' not in chosen

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        outside = ['\ud800', 'a\0b', b'text', None, 7]

        if self.capacity is not None:
            outside.append('x' * (self.capacity + 1))
            outside.append('é' * self.capacity)

        result = st.sampled_from(outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        size_max = TEXT_SIZE_MAX if self.capacity is None else self.capacity
        texts = st.text(max_size=size_max)

        if self.terminated:
            texts = texts.filter(text_unterminated)

        if self.capacity is not None:
            texts = texts.filter(functools.partial(text_fits, capacity=self.capacity))

        if canonical:
            return texts.map(text_exact)

        return texts | texts.map(Spelled)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Blob:
    capacity: int
    holders: int = 0
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if isinstance(value, str):
            raise RefusedError

        try:
            view = memoryview(value)
        except TypeError:
            raise RefusedError from None

        with view:
            if not view.c_contiguous:
                raise RefusedError

            content = view.tobytes()

        if len(content) > self.capacity:
            raise RefusedError

        return content

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)

        outside = [b'x' * (self.capacity + 1), 'text', memoryview(b'abcdef')[::2], [1, 2], None]
        result = st.sampled_from(outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        content = st.binary(max_size=self.capacity)

        if canonical:
            return content

        return content | content.map(bytearray) | content.map(memoryview)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Enumeration:
    holders: int = 0
    members: tuple[tuple[str, int], ...]
    spelled: str
    tag: Integer

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if isinstance(value, getattr(module, self.spelled)):
            return value

        raise RefusedError

    def declaration(self) -> str:
        assert self.members
        assert self.spelled.isidentifier()

        members = ', '.join(f'{name} = {number}' for name, number in self.members)
        result = f'pub const {self.spelled} = enum({self.tag.spelled}) {{ {members} }};'

        assert result.endswith('};')

        return result

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)
        assert self.members

        chosen = generator.choice(self.members)[0]
        result = Default(self.spelled, chosen, '.' + chosen)

        assert result.zig[1:] == chosen

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert self.members

        foreign = enum.Enum(self.spelled, [(name, number) for name, number in self.members])
        outside = [self.members[0][1], self.members[0][0], None, next(iter(foreign))]
        result = st.sampled_from(outside)

        assert isinstance(result, st.SearchStrategy)

        return result

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        members = list(getattr(module, self.spelled))

        assert len(members) == len(self.members)

        return st.sampled_from(members)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Optional:
    child: object
    holders: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if value is None:
            return None

        return self.child.convert(value, module)

    def default(self, generator: random.Random) -> Default:
        assert isinstance(generator, random.Random)
        assert not isinstance(self.child, Optional)

        return Default(None, None, 'null')

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert not isinstance(self.child, Optional)

        return self.child.mutants(module)

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        return st.none() | self.child.strategy(module, canonical=canonical)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Array:
    child: object
    holders: int
    length: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        items = sequence_items(value)

        if len(items) != self.length:
            raise RefusedError

        return tuple(self.child.convert(item, module) for item in items)

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert 0 <= self.length <= ARRAY_LENGTH_MAX

        valid = self.child.strategy(module, canonical=False)
        miscounted = functools.partial(items_miscounted, length=self.length)
        shorter = st.lists(valid, max_size=self.length + 2).filter(miscounted)
        broken = st.lists(self.child.mutants(module), min_size=1, max_size=1)
        padded = broken.map(functools.partial(items_repeated, count=max(1, self.length)))

        return shorter | padded | st.sampled_from(['ab', {0: 1}, frozenset({1, 2})])

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        child = self.child.strategy(module, canonical=canonical)
        items = st.lists(child, min_size=self.length, max_size=self.length)

        if canonical:
            return items.map(tuple)

        return items | items.map(tuple) | items.map(sequence_wrapped)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Tuple:
    children: tuple[object, ...]
    holders: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        items = sequence_items(value)

        if len(items) != len(self.children):
            raise RefusedError

        pairs = zip(self.children, items, strict=True)

        return tuple(child.convert(item, module) for child, item in pairs)

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert self.children

        valid = st.tuples(*(child.strategy(module, canonical=False) for child in self.children))
        broken = st.tuples(*(child.mutants(module) for child in self.children))

        return valid.map(items_extended) | valid.map(items_shortened) | broken

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        items = st.tuples(*(child.strategy(module, canonical=canonical) for child in self.children))

        if canonical:
            return items

        return items | items.map(list)


@dataclasses.dataclass(frozen=True)
class Field:
    default: Default | None
    name: str
    node: object


@dataclasses.dataclass(frozen=True, kw_only=True)
class Record:
    fields: tuple[Field, ...]
    holders: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if not isinstance(value, dict):
            raise RefusedError

        names = {field.name for field in self.fields}

        for key in value:
            if not isinstance(key, str):
                raise RefusedError

            if key not in names:
                raise RefusedError

        result = {field.name: self.field_value(field, value, module) for field in self.fields}

        assert result.keys() == names

        return result

    def declaration(self) -> str:
        assert self.spelled.isidentifier()
        assert len(self.fields) <= FIELD_COUNT_MAX

        fields = []

        for field in self.fields:
            default = '' if field.default is None else ' = ' + field.default.zig
            fields.append(f'{field.name}: {field.node.spelled}{default}')

        return f'pub const {self.spelled} = struct {{ {", ".join(fields)} }};'

    def field_value(self, field: Field, value: dict[str, object], module: ModuleType) -> object:
        assert field in self.fields
        assert isinstance(value, dict)
        assert isinstance(module, ModuleType)

        if field.name in value:
            return field.node.convert(value[field.name], module)

        if field.default is None:
            raise RefusedError

        if field.default.enumeration is None:
            return field.default.python

        return getattr(getattr(module, field.default.enumeration), field.default.python)

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert len(self.fields) <= FIELD_COUNT_MAX

        valid = self.strategy(module, canonical=False)
        broken = [
            valid.map(record_extended),
            valid.map(record_keyed),
            st.sampled_from([[], 'text', None]),
        ]

        for field in self.fields:
            without = functools.partial(record_without, name=field.name)
            replaced = functools.partial(record_with, name=field.name)
            broken.append(valid.map(without))
            broken.append(st.builds(replaced, valid, field.node.mutants(module)))

        return st.one_of(broken)

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        required = {}
        optional = {}

        for field in self.fields:
            target = required if field.default is None else optional
            target[field.name] = field.node.strategy(module, canonical=canonical)

        items = st.fixed_dictionaries(required, optional=optional)

        if canonical:
            return items

        return items | items.map(Keyed)


@dataclasses.dataclass(frozen=True, kw_only=True)
class List:
    capacity: int
    child: object
    holders: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        items = sequence_items(value)

        if len(items) > self.capacity:
            raise RefusedError

        return [self.child.convert(item, module) for item in items]

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert 0 < self.capacity <= CAPACITY_MAX

        valid = self.child.strategy(module, canonical=False)
        longer = st.lists(valid, min_size=self.capacity + 1, max_size=self.capacity + 2)
        broken = st.lists(self.child.mutants(module), min_size=1, max_size=1)

        return longer | broken | st.sampled_from(['ab', frozenset({1}), None])

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        items = st.lists(self.child.strategy(module, canonical=canonical), max_size=self.capacity)

        if canonical:
            return items

        return items | items.map(tuple) | items.map(sequence_wrapped)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Set:
    capacity: int
    child: object
    frozen: bool
    holders: int
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if not isinstance(value, collections.abc.Set):
            raise RefusedError

        if len(value) > self.capacity:
            raise RefusedError

        converted = []

        for item in value:
            element = self.child.convert(item, module)

            if element not in converted:
                converted.append(element)

        return frozenset(converted) if self.frozen else set(converted)

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert 0 < self.capacity <= CAPACITY_MAX

        valid = self.child.strategy(module, canonical=False).filter(hashable)
        longer = st.lists(valid, min_size=self.capacity + 1, max_size=self.capacity + 2).map(set)
        broken = self.child.mutants(module).filter(hashable).map(singleton_set)

        return longer | broken | st.sampled_from([[1], (1,), {1: 2}, None])

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        child = self.child.strategy(module, canonical=canonical).filter(hashable)
        items = st.sets(child, max_size=self.capacity)

        if canonical:
            return items.map(frozenset) if self.frozen else items

        return items | items.map(frozenset) | items.map(keys_view)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Map:
    capacity: int
    holders: int
    key: object
    spelled: str
    value: object

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        if not isinstance(value, collections.abc.Mapping):
            raise RefusedError

        if len(value) > self.capacity:
            raise RefusedError

        result = {}

        for key, item in list(value.items()):
            result[self.key.convert(key, module)] = self.value.convert(item, module)

        return result

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert 0 < self.capacity <= CAPACITY_MAX

        keys = self.key.strategy(module, canonical=False).filter(hashable)
        values = self.value.strategy(module, canonical=False)
        pairs = st.tuples(keys, values)
        longer = st.lists(pairs, min_size=self.capacity + 1, max_size=self.capacity + 2).map(dict)
        foreign = self.key.mutants(module).filter(hashable)
        bad_keys = st.dictionaries(foreign, values, min_size=1, max_size=1)
        bad_values = st.dictionaries(keys, self.value.mutants(module), min_size=1, max_size=1)

        return longer | bad_keys | bad_values | st.sampled_from([[(1, 2)], 'ab', None])

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        keys = self.key.strategy(module, canonical=canonical).filter(hashable)
        values = self.value.strategy(module, canonical=canonical)
        items = st.dictionaries(keys, values, max_size=self.capacity)

        if canonical:
            return items

        return items | items.map(mapping_proxy) | items.map(user_dictionary)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Variant:
    holders: int
    payloads: tuple[tuple[str, object | None], ...]
    spelled: str

    def convert(self, value: object, module: ModuleType) -> object:
        assert isinstance(module, ModuleType)
        assert not isinstance(value, RefusedError)

        for _name, node in self.payloads:
            if node is None:
                if value is None:
                    return None
            else:
                try:
                    result = node.convert(value, module)
                except RefusedError:
                    continue
                else:
                    return result

        raise RefusedError

    def declaration(self) -> str:
        assert self.payloads
        assert self.spelled.isidentifier()

        written = [(name, 'void' if node is None else node.spelled) for name, node in self.payloads]
        payloads = ', '.join(f'{name}: {text}' for name, text in written)

        return f'pub const {self.spelled} = union(enum) {{ {payloads} }};'

    def mutants(self, module: ModuleType) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert self.payloads

        nodes = [node for _name, node in self.payloads if node is not None]

        if not nodes:
            return st.sampled_from([1, 'text'])

        return st.one_of([node.mutants(module) for node in nodes])

    def strategy(self, module: ModuleType, *, canonical: bool) -> st.SearchStrategy[object]:
        assert isinstance(module, ModuleType)
        assert isinstance(canonical, bool)

        options = [
            st.none() if node is None else node.strategy(module, canonical=canonical)
            for _name, node in self.payloads
        ]

        return st.one_of(options)


@dataclasses.dataclass(frozen=True, kw_only=True)
class Klass:
    fields: tuple[Field, ...]
    spelled: str

    def declaration(self) -> str:
        assert self.fields
        assert self.spelled.isidentifier()

        names = [field.name for field in self.fields]
        declared = '\n'.join(f'    {field.name}: {field.node.spelled},' for field in self.fields)
        access = ', '.join(f'.{name} = .read_write' for name in names)
        arguments = ', '.join(f'{field.name}: {field.node.spelled}' for field in self.fields)
        stored = ', '.join(f'.{name} = arguments.{name}' for name in names)
        lines = [
            f'pub const {self.spelled} = struct {{',
            declared,
            '',
            f'    pub const fields = .{{ {access} }};',
            '    pub const pickle = true;',
            '',
            f'    pub fn init(self: *{self.spelled}, arguments: struct {{ {arguments} }}) void {{',
            f'        self.* = .{{ {stored} }};',
            '    }',
            '};',
        ]

        return '\n'.join(lines)


def alignment_one(node: object) -> bool:
    assert node is not None
    assert hasattr(node, 'spelled')

    pending = [node]

    for _ in range(WALK_STEP_MAX):
        if not pending:
            return True

        parts = alignment_parts(pending.pop())

        if parts is None:
            return False

        pending.extend(parts)

    message = f'{node.spelled} has more than {WALK_STEP_MAX} parts'
    raise AssertionError(message)


def alignment_parts(node: object) -> list[object] | None:
    assert node is not None
    assert hasattr(node, 'spelled')

    if isinstance(node, Integer):
        return [] if node.bits <= BYTE_BITS else None

    if isinstance(node, Array | Boolean | Enumeration | Klass | Record | Tuple):
        return layout_children(node)

    return None


def node_children(node: object) -> list[object]:
    assert node is not None
    assert not isinstance(node, Field)

    if isinstance(node, Record):
        return [field.node for field in node.fields]

    if isinstance(node, Variant):
        return [payload for _name, payload in node.payloads if payload is not None]

    if isinstance(node, Map):
        return [node.key, node.value]

    if isinstance(node, Tuple):
        return list(node.children)

    return [node.child] if hasattr(node, 'child') else []


def owned(node: object) -> bool:
    assert node is not None
    assert hasattr(node, 'spelled')

    pending = [node]

    for _ in range(WALK_STEP_MAX):
        if not pending:
            return True

        current = pending.pop()

        if isinstance(current, BigInteger):
            return False

        if isinstance(current, Text):
            if current.capacity is None:
                return False

        pending.extend(node_children(current))

    message = f'{node.spelled} has more than {WALK_STEP_MAX} parts'
    raise AssertionError(message)


def size_parts(node: object) -> list[object] | None:
    assert node is not None
    assert hasattr(node, 'spelled')

    if isinstance(node, Integer):
        return [] if node.bits == 0 else None

    if isinstance(node, Array):
        return [node.child] if node.length > 0 else []

    if isinstance(node, Variant):
        return node_children(node) if len(node.payloads) == 1 else None

    if isinstance(node, Enumeration | Klass | Record | Tuple):
        return layout_children(node)

    return None


def zero_size(node: object) -> bool:
    assert node is not None
    assert hasattr(node, 'spelled')

    pending = [node]

    for _ in range(WALK_STEP_MAX):
        if not pending:
            return True

        parts = size_parts(pending.pop())

        if parts is None:
            return False

        pending.extend(parts)

    message = f'{node.spelled} has more than {WALK_STEP_MAX} parts'
    raise AssertionError(message)


def zero_size_aligned(node: object) -> bool:
    assert node is not None
    assert hasattr(node, 'spelled')

    if not zero_size(node):
        return False

    return not alignment_one(node)


class Generator:
    def __init__(self, seed: int) -> None:
        assert isinstance(seed, int)
        assert seed >= 0

        self.random = random.Random(seed)
        self.classes: list[Klass] = []
        self.declared: list[object] = []
        self.enums: list[Enumeration] = []

    def _name(self, prefix: str) -> str:
        assert prefix.isidentifier()

        result = f'{prefix}{len(self.declared)}'

        assert result.isidentifier()

        return result

    def address(self) -> Address:
        assert self.random is not None

        result = Address()

        assert result.holders == 0

        return result

    def array(self, *, nested: list[object], top: list[object]) -> Array:
        assert nested
        assert top

        child = self.random.choice(nested)
        length = self.random.randint(0, ARRAY_LENGTH_MAX)
        holders = 1 + length * child.holders
        result = Array(
            child=child,
            holders=holders,
            length=length,
            spelled=f'[{length}]{child.spelled}',
        )

        assert result.holders >= 1

        return result

    def big(self) -> BigInteger:
        assert BIG_INTEGER_BITS_MAX > 64

        result = BigInteger()

        assert result.holders == 0

        return result

    def blob(self) -> Blob:
        assert TEXT_CAPACITY_MAX > 0

        capacity = self.random.randint(1, TEXT_CAPACITY_MAX)
        result = Blob(capacity=capacity, spelled=f'lacuna.BlobType({capacity})')

        assert result.holders == 0

        return result

    def boolean(self) -> Boolean:
        assert self.random is not None

        result = Boolean()

        assert result.holders == 0

        return result

    def klass(self, nested: list[object]) -> Klass:
        assert nested
        assert CLASS_FIELD_COUNT_MAX > 0

        candidates = [node for node in nested if owned(node)]
        count = self.random.randint(1, CLASS_FIELD_COUNT_MAX)
        names = self.random.sample(FIELD_NAMES, count)
        fields = tuple(Field(None, name, self.random.choice(candidates)) for name in names)
        result = Klass(fields=fields, spelled=self._name('Klass'))

        self.declared.append(result)
        self.classes.append(result)

        return result

    def complex_node(self) -> Complex:
        assert FLOAT_BITS

        bits = self.random.choice((32, 64))
        result = Complex(bits=bits, spelled=f'std.math.Complex(f{bits})')

        assert result.holders == 0

        return result

    def composite(self, *, nested: list[object], top: list[object]) -> object:
        assert nested
        assert top

        builders = {
            'array': self.array,
            'list': self.list_node,
            'map': self.map_node,
            'optional': self.optional,
            'record': self.record,
            'set': self.set_node,
            'tuple': self.tuple_node,
            'variant': self.variant,
        }

        assert builders.keys() == set(COMPOSITE_KINDS)

        return builders[self.random.choice(COMPOSITE_KINDS)](nested=nested, top=top)

    def enumeration(self) -> Enumeration:
        assert ENUM_MEMBER_COUNT_MAX > 0

        signed = self.random.random() < 0.4
        widths = [bits for bits in ENUM_TAG_BITS if bits > 0] if signed else list(ENUM_TAG_BITS)
        bits = self.random.choice(widths)
        tag = Integer(bits=bits, signed=signed, spelled=('i' if signed else 'u') + str(bits))
        minimum, maximum = tag.bounds()
        count = min(maximum - minimum + 1, self.random.randint(1, ENUM_MEMBER_COUNT_MAX))
        numbers = self.enumeration_values(count=count, minimum=minimum, maximum=maximum)
        members = tuple((f'm{index}', number) for index, number in enumerate(numbers))
        result = Enumeration(members=members, spelled=self._name('Choice'), tag=tag)

        self.declared.append(result)
        self.enums.append(result)

        return result

    def enumeration_values(self, *, count: int, minimum: int, maximum: int) -> list[int]:
        assert 0 < count <= ENUM_MEMBER_COUNT_MAX
        assert minimum <= maximum

        edges = [minimum, maximum, max(minimum, min(maximum, 0))]
        result: list[int] = []

        for _ in range(FUNCTION_ATTEMPT_MAX):
            if len(result) == count:
                break

            edge = self.random.choice(edges)
            drawn = self.random.randint(minimum, maximum)
            candidate = edge if self.random.random() < 0.5 else drawn

            if candidate not in result:
                result.append(candidate)

        assert 0 < len(result) <= count

        return result

    def field_default(self, node: object) -> Default | None:
        assert node is not None
        assert DEFAULT_CHANCE < 1

        defaultable = isinstance(node, Boolean | Integer | Float | Optional | Enumeration)

        if isinstance(node, Text):
            defaultable = node.capacity is None

        if not defaultable:
            return None

        if self.random.random() > DEFAULT_CHANCE:
            return None

        return node.default(self.random)

    def float_node(self) -> Float:
        assert FLOAT_BITS

        bits = self.random.choice(FLOAT_BITS)
        result = Float(bits=bits, spelled='f' + str(bits))

        assert result.bits in FLOAT_BITS

        return result

    def hashable_leaf(self) -> object:
        assert HASHABLE_KINDS

        result = self.leaf_of(self.random.choice(HASHABLE_KINDS))

        assert result.holders == 0

        return result

    def identifier(self) -> Identifier:
        assert self.random is not None

        result = Identifier()

        assert result.holders == 0

        return result

    def integer(self) -> Integer:
        assert INTEGER_BITS

        signed = self.random.random() < 0.5
        widths = (*INTEGER_BITS, INTEGER_BITS_WIDEST) if signed else (0, *INTEGER_BITS)
        bits = self.random.choice(widths)
        result = Integer(bits=bits, signed=signed, spelled=('i' if signed else 'u') + str(bits))

        assert result.bits <= INTEGER_BITS_WIDEST

        return result

    def leaf(self, *, top: bool) -> object:
        assert isinstance(top, bool)

        kinds = LEAF_KINDS_TOP if top else LEAF_KINDS
        result = self.leaf_of(self.random.choice(kinds))

        assert result.holders == 0

        return result

    def leaf_of(self, kind: str) -> object:
        assert kind in LEAF_KINDS_TOP

        builders = {
            'address': self.address,
            'big': self.big,
            'blob': self.blob,
            'boolean': self.boolean,
            'complex': self.complex_node,
            'enumeration': self.enumeration,
            'float': self.float_node,
            'integer': self.integer,
            'text': self.text,
            'uuid': self.identifier,
        }

        assert builders.keys() == set(LEAF_KINDS_TOP)

        return builders[kind]()

    def list_node(self, *, nested: list[object], top: list[object]) -> List:
        assert nested
        assert top

        capacity = self.random.randint(1, CAPACITY_MAX)
        child = self.random.choice(nested)
        spelled = f'lacuna.ListType({child.spelled}, {capacity})'

        return List(
            capacity=capacity,
            child=child,
            holders=1 + capacity * child.holders,
            spelled=spelled,
        )

    def map_node(self, *, nested: list[object], top: list[object]) -> Map:
        assert nested
        assert top

        capacity = self.random.randint(1, CAPACITY_MAX)
        key = self.hashable_leaf()
        value = self.random.choice(nested)
        spelled = f'lacuna.MapType({key.spelled}, {value.spelled}, {capacity})'
        holders = 1 + capacity * (key.holders + value.holders)

        return Map(capacity=capacity, holders=holders, key=key, spelled=spelled, value=value)

    def optional(self, *, nested: list[object], top: list[object]) -> Optional:
        assert nested
        assert top

        child = self.random.choice(top)

        if isinstance(child, Optional):
            return child

        if zero_size_aligned(child):
            return child

        return Optional(child=child, holders=child.holders, spelled='?' + child.spelled)

    def pools(self) -> list[object]:
        assert LAYER_WIDTH > 0

        nested = [self.leaf(top=False) for _ in range(LAYER_WIDTH)]
        top = [self.leaf(top=True) for _ in range(LAYER_WIDTH)]

        for _ in range(DEPTH_MAX):
            nested_layer = [self.composite(nested=nested, top=nested) for _ in range(LAYER_WIDTH)]
            whole = top + nested
            top_layer = [self.composite(nested=nested, top=whole) for _ in range(LAYER_WIDTH)]
            nested = nested + nested_layer
            top = top + top_layer

        result = top + nested

        assert len(result) == 2 * LAYER_WIDTH * (DEPTH_MAX + 1)

        return result

    def record(self, *, nested: list[object], top: list[object]) -> Record:
        assert nested
        assert top

        count = self.random.randint(0, FIELD_COUNT_MAX)
        fields = []

        for name in self.random.sample(FIELD_NAMES, count):
            node = self.random.choice(nested)
            fields.append(Field(self.field_default(node), name, node))

        holders = 1 + sum(1 + field.node.holders for field in fields)
        result = Record(fields=tuple(fields), holders=holders, spelled=self._name('Record'))

        self.declared.append(result)

        return result

    def set_node(self, *, nested: list[object], top: list[object]) -> Set:
        assert nested
        assert top

        capacity = self.random.randint(1, CAPACITY_MAX)
        child = self.hashable_leaf()
        frozen = self.random.random() < 0.3
        kind = 'FrozenSetType' if frozen else 'SetType'
        spelled = f'lacuna.{kind}({child.spelled}, {capacity})'
        holders = 1 + capacity * (1 + child.holders)

        return Set(capacity=capacity, child=child, frozen=frozen, holders=holders, spelled=spelled)

    def text(self) -> Text:
        assert TEXT_CAPACITY_MAX > 0

        shape = self.random.choice(['owned', 'slice', 'terminated'])

        if shape == 'owned':
            capacity = self.random.randint(1, TEXT_CAPACITY_MAX)
            spelled = f'lacuna.TextType({capacity})'

            return Text(capacity=capacity, spelled=spelled, terminated=False)

        terminated = shape == 'terminated'
        spelled = '[:0]const u8' if terminated else '[]const u8'

        return Text(capacity=None, spelled=spelled, terminated=terminated)

    def tuple_node(self, *, nested: list[object], top: list[object]) -> Tuple:
        assert nested
        assert top

        children = tuple(self.random.choice(nested) for _ in range(self.random.randint(1, 3)))
        spelled = 'struct { ' + ', '.join(child.spelled for child in children) + ' }'
        holders = 1 + sum(1 + child.holders for child in children)

        return Tuple(children=children, holders=holders, spelled=spelled)

    def variant(self, *, nested: list[object], top: list[object]) -> Variant:
        assert nested
        assert top

        count = self.random.randint(1, PAYLOAD_COUNT_MAX)
        payloads: list[tuple[str, object | None]] = []
        written: set[str] = set()

        for index in range(count):
            void = self.random.random() < VOID_CHANCE
            node = None if void else self.random.choice(top)

            if node is not None:
                if zero_size_aligned(node):
                    node = None

            text = 'void' if node is None else node.spelled

            if text not in written:
                payloads.append((f'p{index}', node))
                written.add(text)

        holders = sum(node.holders for _name, node in payloads if node is not None)
        result = Variant(holders=holders, payloads=tuple(payloads), spelled=self._name('Variant'))

        self.declared.append(result)

        return result


@dataclasses.dataclass(frozen=True)
class Function:
    name: str
    node: object


@dataclasses.dataclass(frozen=True)
class Generated:
    classes: tuple[Klass, ...]
    functions: tuple[Function, ...]
    name: str
    source: str


def generated_functions(generator: Generator, count: int) -> tuple[Function, ...]:
    assert isinstance(generator, Generator)
    assert count > 0

    pool = generator.pools()
    functions = []
    nested = [node for node in pool if owned(node)]

    for _ in range(CLASS_COUNT):
        generator.klass(nested)

    for index in range(count * FUNCTION_ATTEMPT_MAX):
        if len(functions) == count:
            break

        node = generator.random.choice(pool)

        if node.holders <= HOLDER_BUDGET:
            functions.append(Function(f'echo_{index}', node))

    assert len(functions) == count

    return tuple(functions)


def generated_module(*, seed: int, count: int, name: str) -> Generated:
    assert seed >= 0
    assert count > 0
    assert name.isidentifier()

    generator = Generator(seed)
    functions = generated_functions(generator, count)
    enums = ', '.join(node.spelled for node in generator.enums)
    classes = ', '.join(klass.spelled for klass in generator.classes)
    lines = [
        'const std = @import("std");',
        '',
        'const lacuna = @import("lacuna");',
        '',
        'pub const module: lacuna.Module = .{',
        f'    .name = "{name}",',
        f'    .classes = &.{{ {classes} }},',
        f'    .enums = &.{{ {enums} }},',
        '    .functions = Functions,',
        '    .thread_safe = true,',
        '};',
        '',
    ]

    lines.extend(node.declaration() for node in generator.declared)
    lines.append('')
    lines.append('const Functions = struct {')

    for function in functions:
        spelled = function.node.spelled
        signature = (
            f'    pub fn {function.name}(arguments: struct {{ value: {spelled} }}) {spelled} {{'
        )
        lines.extend([signature, '        return arguments.value;', '    }', ''])

    lines[-1] = '};'
    lines.extend(['', 'comptime {'])

    for node in layout_nodes(functions=functions, classes=generator.classes):
        lines.extend(layout_lines(node))

    lines.extend(['}', ''])

    result = Generated(tuple(generator.classes), functions, name, '\n'.join(lines))

    assert result.source.count('pub fn ') == count + len(generator.classes)

    return result


def layout_children(node: object) -> list[object]:
    assert node is not None
    assert hasattr(node, 'spelled')

    if isinstance(node, Enumeration):
        return [node.tag]

    if isinstance(node, Klass):
        return [field.node for field in node.fields]

    return node_children(node)


def layout_lines(node: object) -> list[str]:
    assert node is not None
    assert hasattr(node, 'spelled')

    spelled = node.spelled
    relation = '>' if zero_size(node) else '=='
    lines = [f'    if (@sizeOf({spelled}) {relation} 0) @compileError("typefuzz: {spelled} size");']

    if alignment_one(node):
        lines.append(
            f'    if (@alignOf({spelled}) > 1) @compileError("typefuzz: {spelled} align");'
        )

    return lines


def layout_nodes(*, functions: tuple[Function, ...], classes: list[Klass]) -> list[object]:
    assert functions
    assert all(isinstance(klass, Klass) for klass in classes)

    pending: list[object] = [function.node for function in functions]
    seen: dict[str, object] = {}

    pending.extend(classes)

    for _ in range(WALK_STEP_MAX):
        if not pending:
            return list(seen.values())

        current = pending.pop()

        if current.spelled not in seen:
            seen[current.spelled] = current
            pending.extend(layout_children(current))

    message = f'the generated functions hold more than {WALK_STEP_MAX} parts'
    raise AssertionError(message)
