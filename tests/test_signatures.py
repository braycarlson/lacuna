import dataclasses
import functools
import inspect
import random
import sys

import pytest

from collections.abc import Callable
from hypothesis import HealthCheck, Phase, given, settings
from hypothesis import strategies as st
from pathlib import Path
from types import ModuleType

import zig_project

from conftest import imbalance


CAPACITY_MAX = 3
COUNT = int(sys._xoptions.get('lacuna_signatures_count', '32'))
DEFAULT_CHANCE = 0.4
FIELD_COUNT_MAX = 5
FIELD_NAMES = ('alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot')
KEYWORD_COUNT_MAX = 6
KEYWORDS_CHANCE = 0.4
KEYWORDS_NAME = 'extra'
LEAK_SETTINGS = settings(
    database=None,
    deadline=None,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.shrink],
    max_examples=3,
    suppress_health_check=[HealthCheck.too_slow],
)
RENAME_CHANCE = 0.25
STRANGE_NAMES = ('zulu', 'not valid', '\ud800', '', 'café')
SEED = int(sys._xoptions.get('lacuna_signatures_seed', '1'))
SETTINGS = settings(database=None, deadline=None, max_examples=300)
REJECTIONS = (TypeError, ValueError)
SPELLED_KEYWORD_CHANCE = 0.3
VALUE_MAX = 1 << 40
VARIADIC_CHANCE = 0.4
VARIADIC_NAME = 'rest'
NAME = f'signatures_{SEED}'

KIND_KEYWORD_ONLY = inspect.Parameter.KEYWORD_ONLY
KIND_POSITIONAL = inspect.Parameter.POSITIONAL_OR_KEYWORD
KIND_POSITIONAL_ONLY = inspect.Parameter.POSITIONAL_ONLY
KIND_VARIADIC = inspect.Parameter.VAR_POSITIONAL
KIND_KEYWORDS = inspect.Parameter.VAR_KEYWORD


class Spelled(str):
    __slots__ = ()


@dataclasses.dataclass(frozen=True)
class Field:
    capacity: int
    default: int | None
    kind: inspect._ParameterKind
    python_name: str
    zig_name: str


@dataclasses.dataclass(frozen=True)
class Shape:
    declared_keyword_only: bool
    fields: tuple[Field, ...]
    name: str

    def regular(self) -> tuple[Field, ...]:
        assert self.fields
        assert self.name.isidentifier()

        return tuple(field for field in self.fields if field.capacity == 0)

    def signature(self) -> inspect.Signature:
        assert self.fields
        assert self.name.isidentifier()

        parameters = []

        for field in self.fields:
            default = inspect.Parameter.empty if field.default is None else field.default
            parameter = inspect.Parameter(field.python_name, field.kind, default=default)
            parameters.append(parameter)

        result = inspect.Signature(parameters)

        assert len(result.parameters) == len(self.fields)

        return result


def field_spelled(field: Field) -> str:
    assert field.zig_name.isidentifier()
    assert field.capacity >= 0

    if field.kind is KIND_VARIADIC:
        kind = f'lacuna.ListType(i64, {field.capacity})'
    elif field.kind is KIND_KEYWORDS:
        kind = f'lacuna.MapType([]const u8, i64, {field.capacity})'
    else:
        kind = 'i64'

    return kind


def shape_source(shape: Shape) -> str:
    assert shape.fields
    assert shape.name.isidentifier()

    lines = [f'    pub fn {shape.name}(arguments: struct {{']

    for field in shape.fields:
        default = '' if field.default is None else f' = {field.default}'
        lines.append(f'        {field.zig_name}: {field_spelled(field)}{default},')

    lines.extend(shape_declarations(shape))

    returned = ', '.join(field_spelled(field) for field in shape.fields)
    values = ', '.join(f'arguments.{field.zig_name}' for field in shape.fields)

    lines.append(f'    }}) struct {{ {returned} }} {{')
    lines.append(f'        return .{{ {values} }};')
    lines.append('    }')

    return '\n'.join(lines)


def shape_declarations(shape: Shape) -> list[str]:
    assert shape.fields
    assert shape.name.isidentifier()

    by_kind = {kind: [] for kind in inspect._ParameterKind}

    for field in shape.fields:
        by_kind[field.kind].append(field)

    declarations = []
    positional_only = by_kind[KIND_POSITIONAL_ONLY]
    keyword_only = by_kind[KIND_KEYWORD_ONLY]

    if positional_only:
        listed = ', '.join('.' + field.zig_name for field in positional_only)
        declarations.append(f'pub const positional_only = .{{ {listed} }};')

    declared = shape.declared_keyword_only

    if not by_kind[KIND_VARIADIC]:
        declared = True

    if keyword_only:
        if declared:
            listed = ', '.join('.' + field.zig_name for field in keyword_only)
            declarations.append(f'pub const keyword_only = .{{ {listed} }};')

    for field in (*by_kind[KIND_VARIADIC], *by_kind[KIND_KEYWORDS]):
        marker = 'variadic' if field.kind is KIND_VARIADIC else 'keywords'
        declarations.append(f'pub const {marker} = .{field.zig_name};')

    renamed = [field for field in shape.fields if field.python_name != field.zig_name]

    if renamed:
        listed = ', '.join(f'.{field.zig_name} = "{field.python_name}"' for field in renamed)
        declarations.append(f'pub const names = .{{ {listed} }};')

    result = [''] + ['        ' + declaration for declaration in declarations]

    assert len(result) == len(declarations) + 1

    return result


def shape_generated(generator: random.Random, index: int) -> Shape:
    assert isinstance(generator, random.Random)
    assert index >= 0

    count = generator.randint(1, FIELD_COUNT_MAX)
    names = generator.sample(FIELD_NAMES, count)
    positional_end = generator.randint(0, count)
    positional_only_count = generator.randint(0, positional_end)
    defaulted_count = generator.randint(0, positional_end)
    fields = []

    for position, name in enumerate(names):
        kind = KIND_KEYWORD_ONLY

        if position < positional_end:
            kind = KIND_POSITIONAL_ONLY if position < positional_only_count else KIND_POSITIONAL

        defaulted = position >= positional_end - defaulted_count

        if kind is KIND_KEYWORD_ONLY:
            defaulted = generator.random() < DEFAULT_CHANCE

        default = generator.randint(-VALUE_MAX, VALUE_MAX) if defaulted else None
        python_name = 'py_' + name if generator.random() < RENAME_CHANCE else name
        fields.append(Field(0, default, kind, python_name, name))

    if generator.random() < VARIADIC_CHANCE:
        capacity = generator.randint(1, CAPACITY_MAX)
        variadic = Field(capacity, None, KIND_VARIADIC, VARIADIC_NAME, VARIADIC_NAME)
        fields.insert(positional_end, variadic)

    if generator.random() < KEYWORDS_CHANCE:
        capacity = generator.randint(1, CAPACITY_MAX)
        keywords = Field(capacity, None, KIND_KEYWORDS, KEYWORDS_NAME, KEYWORDS_NAME)
        fields.append(keywords)

    result = Shape(generator.random() < 0.5, tuple(fields), f'bind_{index}')

    assert result.signature() is not None

    return result


def shapes_generated(*, seed: int, count: int) -> tuple[Shape, ...]:
    assert seed >= 0
    assert count > 0

    generator = random.Random(seed)
    result = tuple(shape_generated(generator, index) for index in range(count))

    assert len({shape.name for shape in result}) == count

    return result


def module_source(shapes: tuple[Shape, ...]) -> str:
    assert shapes
    assert all(isinstance(shape, Shape) for shape in shapes)

    header = [
        'const lacuna = @import("lacuna");',
        '',
        'pub const module: lacuna.Module = .{',
        f'    .name = "{NAME}",',
        '    .functions = Functions,',
        '    .thread_safe = true,',
        '};',
        '',
        'const Functions = struct {',
    ]
    bodies = '\n\n'.join(shape_source(shape) for shape in shapes)

    return '\n'.join(header) + '\n' + bodies + '\n};\n'


SHAPES = shapes_generated(seed=SEED, count=COUNT)


@dataclasses.dataclass(frozen=True)
class Call:
    keywords: dict[str, int]
    positional: tuple[int, ...]
    split: int


def call_strategy(shape: Shape) -> st.SearchStrategy[Call]:
    assert isinstance(shape, Shape)
    assert shape.fields

    spelled = {field.python_name for field in shape.fields}
    names = sorted(spelled | {field.zig_name for field in shape.fields})
    candidates = st.sampled_from([*names, *STRANGE_NAMES])
    keys = candidates | candidates.map(Spelled)
    values = st.integers(-VALUE_MAX, VALUE_MAX)
    positional_max = len(shape.regular()) + CAPACITY_MAX + 2
    positional = st.lists(values, max_size=positional_max).map(tuple)
    keywords = st.dictionaries(keys, values, max_size=KEYWORD_COUNT_MAX)

    return st.builds(Call, keywords, positional, st.integers(0, positional_max))


def expected_values(shape: Shape, call: Call) -> tuple[object, ...] | type[BaseException]:
    assert isinstance(shape, Shape)
    assert isinstance(call, Call)

    bound = expected_bound(shape, call)

    if isinstance(bound, type):
        return bound

    values = []

    for field in shape.fields:
        value = collected_value(field, bound.arguments[field.python_name])

        if value is ValueError:
            return ValueError

        values.append(value)

    return tuple(values)


def expected_bound(shape: Shape, call: Call) -> inspect.BoundArguments | type[BaseException]:
    assert isinstance(shape, Shape)
    assert isinstance(call, Call)

    positional_only = {
        field.python_name for field in shape.fields if field.kind is KIND_POSITIONAL_ONLY
    }
    diverted = {key: call.keywords[key] for key in call.keywords if str(key) in positional_only}
    named = {key: item for key, item in call.keywords.items() if key not in diverted}
    refused = ValueError if overflowing(shape, call) else TypeError

    if diverted:
        if not any(field.kind is KIND_KEYWORDS for field in shape.fields):
            return refused

    try:
        bound = shape.signature().bind(*call.positional, **named)
    except TypeError:
        return refused

    bound.apply_defaults()

    for field in shape.fields:
        if field.kind is KIND_KEYWORDS:
            extras = bound.arguments[field.python_name]
            bound.arguments[field.python_name] = {**extras, **diverted}

    assert all(key in call.keywords for key in diverted)

    return bound


def collected_value(field: Field, value: object) -> object:
    assert isinstance(field, Field)
    assert field.capacity >= 0
    assert value is not None

    if field.kind is KIND_VARIADIC:
        result = list(value)
    elif field.kind is KIND_KEYWORDS:
        result = {str(key): item for key, item in value.items()}
    else:
        return value

    if len(result) > field.capacity:
        return ValueError

    if not all(encodable(key) for key in result if isinstance(key, str)):
        return ValueError

    return result


def overflowing(shape: Shape, call: Call) -> bool:
    assert isinstance(shape, Shape)
    assert isinstance(call, Call)

    nameable = {
        field.python_name for field in shape.fields if field.kind is not KIND_POSITIONAL_ONLY
    }
    positional_count = sum(
        field.kind in {KIND_POSITIONAL, KIND_POSITIONAL_ONLY} for field in shape.fields
    )
    extras = [str(key) for key in call.keywords if str(key) not in nameable]

    for field in shape.fields:
        if field.kind is KIND_KEYWORDS:
            if len(extras) > field.capacity:
                return True

            if not all(encodable(key) for key in extras):
                return True

        if field.kind is KIND_VARIADIC:
            if len(call.positional) - positional_count > field.capacity:
                return True

    return False


def encodable(text: str) -> bool:
    assert isinstance(text, str)
    assert len(text) < 1 << 10

    try:
        _ = text.encode()
    except UnicodeEncodeError:
        return False

    return True


def called(call: Call, function: Callable[..., object]) -> object:
    assert callable(function)
    assert isinstance(call, Call)

    split = min(call.split, len(call.positional))

    if split == 0:
        return function(*call.positional, **call.keywords)

    partial = functools.partial(function, *call.positional[:split])

    return partial(*call.positional[split:], **call.keywords)


def exactly(*, expected: tuple[object, ...], actual: object) -> bool:
    assert isinstance(expected, tuple)
    assert all(not isinstance(item, Spelled) for item in expected)
    assert not isinstance(actual, Spelled)

    if type(actual) is not tuple:
        return False

    if len(actual) != len(expected):
        return False

    pairs = zip(expected, actual, strict=True)
    types_match = all(type(left) is type(right) for left, right in pairs)

    return types_match and actual == expected


def parameters_summary(signature: inspect.Signature) -> list[tuple[str, str, object]]:
    assert isinstance(signature, inspect.Signature)
    assert len(signature.parameters) <= FIELD_COUNT_MAX + 2

    parameters = signature.parameters.values()
    result = [(parameter.name, parameter.kind.name, parameter.default) for parameter in parameters]

    assert len(result) == len(signature.parameters)

    return result


class Built:
    __slots__ = ('module', 'namespace')

    def __init__(self, module: ModuleType, namespace: dict[str, object]) -> None:
        assert isinstance(module, ModuleType)
        assert '__builtins__' in namespace

        self.module = module
        self.namespace = namespace

    def __repr__(self) -> str:
        assert isinstance(self.module, ModuleType)
        assert '__builtins__' in self.namespace

        return f'Built({self.module.__name__})'


def refusal(call: Call, function: Callable[..., object]) -> None:
    assert isinstance(call, Call)
    assert callable(function)

    try:
        _ = called(call, function)
    except REJECTIONS:
        return

    message = f'{function.__name__} accepted a call that Python binding refuses'
    raise AssertionError(message)


debug_only = pytest.mark.skipif(
    not hasattr(sys, 'gettotalrefcount'),
    reason='counts references with sys.gettotalrefcount, which only a debug CPython provides',
)


@pytest.fixture(scope='session')
def built() -> Built:
    output = zig_project.project_built(name=NAME, source=module_source(SHAPES))
    module = zig_project.module_imported(name=NAME, output=output)
    namespace = zig_project.stub_namespace(name=NAME, output=output)

    assert all(hasattr(module, shape.name) for shape in SHAPES)
    assert all(shape.name in namespace for shape in SHAPES)

    return Built(module, namespace)


@pytest.mark.parametrize('shape', SHAPES, ids=lambda shape: shape.name)
@SETTINGS
@given(data=st.data())
def test_calls_bind_like_python(*, built: Built, shape: Shape, data: st.DataObject) -> None:
    assert isinstance(built, Built)
    assert isinstance(shape, Shape)
    assert isinstance(data, st.DataObject)

    call = data.draw(call_strategy(shape))
    expected = expected_values(shape, call)
    function = getattr(built.module, shape.name)

    if expected is TypeError:
        with pytest.raises(TypeError):
            _ = called(call, function)
    elif expected is ValueError:
        with pytest.raises((TypeError, ValueError)):
            _ = called(call, function)
    else:
        actual = called(call, function)

        message = f'{shape.name} bound {actual!r}, not {expected!r}'

        assert exactly(expected=expected, actual=actual), message


@pytest.mark.parametrize('shape', SHAPES, ids=lambda shape: shape.name)
def test_runtime_signature_matches_python(*, built: Built, shape: Shape) -> None:
    assert isinstance(built, Built)
    assert isinstance(shape, Shape)

    actual = inspect.signature(getattr(built.module, shape.name))

    assert parameters_summary(actual) == parameters_summary(shape.signature())


@pytest.mark.parametrize('shape', SHAPES, ids=lambda shape: shape.name)
def test_stub_signature_matches_python(*, built: Built, shape: Shape) -> None:
    assert isinstance(built, Built)
    assert isinstance(shape, Shape)

    actual = inspect.signature(built.namespace[shape.name])

    assert parameters_summary(actual) == parameters_summary(shape.signature())


@debug_only
@pytest.mark.parametrize('shape', SHAPES, ids=lambda shape: shape.name)
@LEAK_SETTINGS
@given(data=st.data())
def test_binding_balances_references(*, built: Built, shape: Shape, data: st.DataObject) -> None:
    assert isinstance(built, Built)
    assert isinstance(shape, Shape)
    assert isinstance(data, st.DataObject)

    call = data.draw(call_strategy(shape))
    function = getattr(built.module, shape.name)
    expected = expected_values(shape, call)
    run = functools.partial(called, call, function)

    if isinstance(expected, type):
        run = functools.partial(refusal, call, function)

    assert not imbalance(run), f'{shape.name} leaks references for {call!r}'


def test_stubtest_accepts_the_generated_stub(*, built: Built) -> None:
    assert isinstance(built, Built)
    assert built.module.__file__ is not None

    output = Path(built.module.__file__).parent.parent
    report = zig_project.stubtest_report(name=NAME, output=output)

    assert not report, report
