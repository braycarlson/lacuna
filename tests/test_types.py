import collections
import collections.abc
import contextlib
import dataclasses
import enum
import functools
import math
import pickle
import reprlib
import sys
import threading
import types
import typing

import pytest
import typing_extensions

from collections.abc import Callable
from hypothesis import HealthCheck, Phase, given, settings
from hypothesis import strategies as st
from pathlib import Path
from types import ModuleType

import typefuzz
import zig_project

from conftest import hostile_values, imbalance


CONTAINER_ORIGINS = (collections.abc.Sequence, collections.abc.Set, frozenset, list, set)
COUNT = int(sys._xoptions.get('lacuna_types_count', '48'))
LEAK_SETTINGS = settings(
    database=None,
    deadline=None,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.shrink],
    max_examples=2,
    suppress_health_check=[HealthCheck.too_slow],
)
REJECTIONS = (BufferError, KeyError, OverflowError, TypeError, ValueError)
SEED = int(sys._xoptions.get('lacuna_types_seed', '1'))
SETTINGS = settings(database=None, deadline=None, max_examples=200)
ROUND_COUNT = 2000
SHOWN_LEVEL_MAX = 4
SHOWN_TEXT_MAX = 64
STEP_MAX = 1 << 16
SWITCH_INTERVAL_SECONDS = 1e-6
NAME = f'typefuzz_{SEED}'
GENERATED = typefuzz.generated_module(seed=SEED, count=COUNT, name=NAME)

debug_only = pytest.mark.skipif(
    not hasattr(sys, 'gettotalrefcount'),
    reason='counts references with sys.gettotalrefcount, which only a debug CPython provides',
)


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


@dataclasses.dataclass(frozen=True)
class Verdict:
    expected: object
    raised: type[BaseException] | None


def shown(value: object) -> str:
    assert SHOWN_LEVEL_MAX > 0
    assert not isinstance(value, typefuzz.RefusedError)

    formatter = reprlib.Repr()
    formatter.maxlevel = SHOWN_LEVEL_MAX
    formatter.maxlong = SHOWN_TEXT_MAX
    formatter.maxother = SHOWN_TEXT_MAX
    formatter.maxstring = SHOWN_TEXT_MAX

    return formatter.repr(value)


def admits(*, annotation: object, value: object, module: ModuleType) -> bool:
    assert isinstance(module, ModuleType)
    assert not isinstance(value, typefuzz.RefusedError)
    assert not isinstance(annotation, str)

    worlds: list[list[tuple[object, object]]] = [[(annotation, value)]]

    for _ in range(STEP_MAX):
        if not worlds:
            return False

        pending = worlds.pop()

        if not pending:
            return True

        current, item = pending.pop()
        alternatives = obligations(annotation=current, value=item, module=module)

        if alternatives is not None:
            worlds.extend(pending + alternative for alternative in alternatives)

    message = f'the stub check took more than {STEP_MAX} steps'
    raise AssertionError(message)


def obligations(
    *,
    annotation: object,
    value: object,
    module: ModuleType,
) -> list[list[tuple[object, object]]] | None:
    assert isinstance(module, ModuleType)
    assert not isinstance(value, typefuzz.RefusedError)
    assert not isinstance(annotation, str)

    if annotation is None:
        return [[]] if value is None else None

    if annotation is type(None):
        return [[]] if value is None else None

    if typing_extensions.is_typeddict(annotation):
        return record_obligations(annotation, value)

    if isinstance(annotation, type):
        return [[]] if leaf_admitted(annotation=annotation, value=value, module=module) else None

    return generic_obligations(annotation=annotation, value=value)


def leaf_admitted(*, annotation: type, value: object, module: ModuleType) -> bool:
    assert isinstance(annotation, type)
    assert isinstance(module, ModuleType)
    assert not isinstance(value, typefuzz.RefusedError)

    if annotation is object:
        return True

    if annotation is float:
        return isinstance(value, float | int)

    if annotation is complex:
        return isinstance(value, complex | float | int)

    if annotation is typing_extensions.Buffer:
        return buffer_admitted(value)

    if issubclass(annotation, enum.Enum):
        return isinstance(value, getattr(module, annotation.__name__))

    return isinstance(value, annotation)


def buffer_admitted(value: object) -> bool:
    assert not isinstance(value, typefuzz.RefusedError)

    try:
        view = memoryview(value)
    except TypeError:
        return False

    view.release()

    return True


def generic_obligations(
    *,
    annotation: object,
    value: object,
) -> list[list[tuple[object, object]]] | None:
    assert annotation is not None
    assert not isinstance(annotation, str)
    assert not isinstance(value, typefuzz.RefusedError)

    origin = typing.get_origin(annotation)
    arguments = typing.get_args(annotation)

    if origin in {types.UnionType, typing.Union}:
        return [[(argument, value)] for argument in arguments]

    if origin is tuple:
        return tuple_obligations(arguments, value)

    if origin in CONTAINER_ORIGINS:
        if not isinstance(value, origin):
            return None

        return [[(arguments[0], item) for item in value]]

    if origin in {dict, collections.abc.Mapping}:
        if not isinstance(value, origin):
            return None

        key_annotation, item_annotation = arguments
        pairs = [((key_annotation, key), (item_annotation, item)) for key, item in value.items()]

        return [[obligation for pair in pairs for obligation in pair]]

    message = f'the checker does not know the annotation {annotation!r}'
    raise AssertionError(message)


def record_obligations(
    annotation: type,
    value: object,
) -> list[list[tuple[object, object]]] | None:
    assert typing_extensions.is_typeddict(annotation)
    assert not isinstance(value, typefuzz.RefusedError)

    if not isinstance(value, dict):
        return None

    hints = typing_extensions.get_type_hints(annotation)

    if not annotation.__required_keys__ <= value.keys():
        return None

    if not value.keys() <= hints.keys():
        return None

    return [[(hints[key], item) for key, item in value.items()]]


def tuple_obligations(
    arguments: tuple[object, ...],
    value: object,
) -> list[list[tuple[object, object]]] | None:
    assert isinstance(arguments, tuple)
    assert not isinstance(value, typefuzz.RefusedError)

    if not isinstance(value, tuple):
        return None

    if arguments == ((),):
        return [[]] if value == () else None

    if len(arguments) == 2:
        if arguments[1] is Ellipsis:
            return [[(arguments[0], item) for item in value]]

    if len(arguments) != len(value):
        return None

    return [list(zip(arguments, value, strict=True))]


def same(*, expected: object, actual: object) -> bool:
    assert not isinstance(expected, typefuzz.RefusedError)
    assert not isinstance(actual, typefuzz.RefusedError)

    pending: list[tuple[object, object]] = [(expected, actual)]

    for _ in range(STEP_MAX):
        if not pending:
            return True

        left, right = pending.pop()
        children = same_children(expected=left, actual=right)

        if children is None:
            return False

        pending.extend(children)

    message = f'the comparison took more than {STEP_MAX} steps'
    raise AssertionError(message)


def same_children(*, expected: object, actual: object) -> list[tuple[object, object]] | None:
    assert not isinstance(expected, typefuzz.RefusedError)
    assert not isinstance(actual, typefuzz.RefusedError)

    if isinstance(expected, enum.Enum):
        return [] if expected is actual else None

    if type(expected) is not type(actual):
        return None

    comparers = (
        (complex, same_complexes),
        (dict, same_entries),
        (float, same_floats),
        (list | tuple, same_sequences),
        (set | frozenset, same_sets),
    )

    for kind, comparer in comparers:
        if isinstance(expected, kind):
            return comparer(expected=expected, actual=actual)

    return [] if expected == actual else None


def same_entries(
    *,
    expected: dict[object, object],
    actual: dict[object, object],
) -> list[tuple[object, object]] | None:
    assert isinstance(expected, dict)
    assert isinstance(actual, dict)

    left = {(type(key), key): item for key, item in expected.items()}
    right = {(type(key), key): item for key, item in actual.items()}

    if left.keys() != right.keys():
        return None

    return [(left[key], right[key]) for key in left]


def same_complexes(*, expected: complex, actual: complex) -> list[tuple[object, object]] | None:
    assert isinstance(expected, complex)
    assert isinstance(actual, complex)

    return [(expected.real, actual.real), (expected.imag, actual.imag)]


def same_floats(*, expected: float, actual: float) -> list[tuple[object, object]] | None:
    assert isinstance(expected, float)
    assert isinstance(actual, float)

    if math.isnan(expected):
        return [] if math.isnan(actual) else None

    if expected != actual:
        return None

    return [] if math.copysign(1.0, expected) == math.copysign(1.0, actual) else None


def same_sequences(
    *,
    expected: list[object] | tuple[object, ...],
    actual: list[object] | tuple[object, ...],
) -> list[tuple[object, object]] | None:
    assert isinstance(expected, list | tuple)
    assert type(expected) is type(actual)

    if len(expected) != len(actual):
        return None

    return list(zip(expected, actual, strict=True))


def same_sets(
    *,
    expected: set[object] | frozenset[object],
    actual: set[object] | frozenset[object],
) -> list[tuple[object, object]] | None:
    assert isinstance(expected, set | frozenset)
    assert type(expected) is type(actual)

    left = {(type(item), item) for item in expected}
    right = {(type(item), item) for item in actual}

    return [] if left == right else None


def verdict(*, node: object, value: object, module: ModuleType) -> Verdict:
    assert hasattr(node, 'spelled')
    assert isinstance(module, ModuleType)
    assert not isinstance(value, typefuzz.RefusedError)

    try:
        expected = node.convert(value, module)
    except typefuzz.RefusedError:
        return Verdict(None, typefuzz.RefusedError)
    except RuntimeError as error:
        return Verdict(None, type(error))

    return Verdict(expected, None)


def call_check(function: typefuzz.Function, value: object, module: ModuleType) -> None:
    assert isinstance(function, typefuzz.Function)
    assert isinstance(module, ModuleType)
    assert not isinstance(value, typefuzz.RefusedError)

    judged = verdict(node=function.node, value=value, module=module)
    echo = getattr(module, function.name)

    if judged.raised is typefuzz.RefusedError:
        with pytest.raises(REJECTIONS):
            echo(value)

        return

    if judged.raised is not None:
        with pytest.raises(judged.raised):
            echo(value)

        return

    actual = echo(value)

    if not same(expected=judged.expected, actual=actual):
        parts = (shown(value), shown(actual), shown(judged.expected))
        message = '{}({}) returned {}, not {}'.format(function.name, *parts)
        raise AssertionError(message)


def field_check(*, instance: object, field: typefuzz.Field, value: object) -> None:
    assert hasattr(instance, field.name)
    assert not isinstance(value, typefuzz.RefusedError)

    module = sys.modules[type(instance).__module__]
    before = getattr(instance, field.name)
    judged = verdict(node=field.node, value=value, module=module)

    if judged.raised is None:
        setattr(instance, field.name, value)

        actual = getattr(instance, field.name)
        parts = (field.name, shown(value), shown(actual))

        assert same(expected=judged.expected, actual=actual), '{} = {} reads {}'.format(*parts)

        return

    expected = REJECTIONS if judged.raised is typefuzz.RefusedError else judged.raised

    with pytest.raises(expected):
        setattr(instance, field.name, value)

    assert same(expected=before, actual=getattr(instance, field.name)), f'{field.name} changed'


def field_assigned(instance: object, field: typefuzz.Field, value: object) -> None:
    assert hasattr(instance, field.name)
    assert not isinstance(value, typefuzz.RefusedError)

    with contextlib.suppress(REJECTIONS):
        setattr(instance, field.name, value)


def instance_pickled(instance: object) -> None:
    assert instance is not None
    assert not isinstance(instance, type)

    restored = pickle.loads(pickle.dumps(instance))

    assert type(restored) is type(instance)


def instance_built(built: Built, klass: typefuzz.Klass, data: st.DataObject) -> object:
    assert isinstance(built, Built)
    assert isinstance(klass, typefuzz.Klass)
    assert isinstance(data, st.DataObject)

    module = built.module
    initial = {}

    for field in klass.fields:
        initial[field.name] = data.draw(field.node.strategy(module, canonical=True))

    result = getattr(module, klass.spelled)(**initial)

    for field in klass.fields:
        expected = field.node.convert(initial[field.name], module)

        assert same(expected=expected, actual=getattr(result, field.name)), field.name

    return result


def field_written(
    *,
    instance: object,
    field: typefuzz.Field,
    value: object,
    barrier: threading.Barrier,
) -> None:
    assert hasattr(instance, field.name)
    assert barrier.parties > 1
    assert not isinstance(value, typefuzz.RefusedError)

    _ = barrier.wait()

    for _ in range(ROUND_COUNT):
        setattr(instance, field.name, value)


def field_read(
    *,
    instance: object,
    field: typefuzz.Field,
    expected: tuple[object, object],
    barrier: threading.Barrier,
    torn: list[object],
) -> None:
    assert hasattr(instance, field.name)
    assert len(expected) == 2
    assert barrier.parties > 1
    assert isinstance(torn, list)

    _ = barrier.wait()

    for _ in range(ROUND_COUNT):
        actual = getattr(instance, field.name)

        if not any(same(expected=item, actual=actual) for item in expected):
            torn.append(actual)


def fault_parts(value: object) -> list[object] | None:
    assert not isinstance(value, typefuzz.RefusedError)
    assert value is not typefuzz.RefusedError

    if isinstance(value, types.MappingProxyType):
        return None

    if isinstance(value, collections.UserDict | collections.UserList):
        return [value.data]

    if isinstance(value, dict):
        return [*value.keys(), *value.values()]

    if isinstance(value, list | tuple | set | frozenset):
        return list(value)

    return []


def fault_safe(value: object) -> bool:
    assert not isinstance(value, typefuzz.RefusedError)
    assert STEP_MAX > 0

    pending = [value]

    for _ in range(STEP_MAX):
        if not pending:
            return True

        parts = fault_parts(pending.pop())

        if parts is None:
            return False

        pending.extend(parts)

    message = f'the value holds more than {STEP_MAX} parts'
    raise AssertionError(message)


def refusal(value: object, echo: Callable[[object], object]) -> None:
    assert callable(echo)
    assert not isinstance(value, typefuzz.RefusedError)

    try:
        echo(value)
    except REJECTIONS:
        return

    message = f'{echo.__name__} accepted a value the model refuses'
    raise AssertionError(message)


@pytest.fixture(scope='session')
def built() -> Built:
    output = zig_project.project_built(name=NAME, source=GENERATED.source)
    module = zig_project.module_imported(name=NAME, output=output)
    namespace = zig_project.stub_namespace(name=NAME, output=output)

    assert all(hasattr(module, function.name) for function in GENERATED.functions)
    assert all(function.name in namespace for function in GENERATED.functions)

    return Built(module, namespace)


@pytest.mark.parametrize('function', GENERATED.functions, ids=lambda function: function.name)
@SETTINGS
@given(data=st.data())
def test_round_trip_matches_the_model(
    *,
    built: Built,
    function: typefuzz.Function,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(function, typefuzz.Function)
    assert isinstance(data, st.DataObject)

    valid = function.node.strategy(built.module, canonical=False)
    value = data.draw(valid | function.node.mutants(built.module))

    call_check(function, value, built.module)


@pytest.mark.parametrize('function', GENERATED.functions, ids=lambda function: function.name)
def test_hostile_values_follow_the_model(*, built: Built, function: typefuzz.Function) -> None:
    assert isinstance(built, Built)
    assert isinstance(function, typefuzz.Function)

    for value in (*typefuzz.HOSTILE, *hostile_values()):
        call_check(function, value, built.module)


@pytest.mark.parametrize('function', GENERATED.functions, ids=lambda function: function.name)
@SETTINGS
@given(data=st.data())
def test_stub_admits_every_canonical_value_and_result(
    *,
    built: Built,
    function: typefuzz.Function,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(function, typefuzz.Function)
    assert isinstance(data, st.DataObject)

    hints = typing_extensions.get_type_hints(built.namespace[function.name])
    value = data.draw(function.node.strategy(built.module, canonical=True))
    judged = verdict(node=function.node, value=value, module=built.module)

    assert judged.raised is None, f'the canonical value {shown(value)} is refused'
    assert admits(annotation=hints['value'], value=value, module=built.module)

    result = getattr(built.module, function.name)(value)

    assert admits(annotation=hints['return'], value=result, module=built.module)


@debug_only
@pytest.mark.parametrize('function', GENERATED.functions, ids=lambda function: function.name)
@LEAK_SETTINGS
@given(data=st.data())
def test_conversions_balance_references(
    *,
    built: Built,
    function: typefuzz.Function,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(function, typefuzz.Function)
    assert isinstance(data, st.DataObject)

    valid = function.node.strategy(built.module, canonical=False)
    value = data.draw(valid | function.node.mutants(built.module))
    judged = verdict(node=function.node, value=value, module=built.module)
    echo = getattr(built.module, function.name)
    run = functools.partial(echo, value)

    if judged.raised is not None:
        run = functools.partial(refusal, value, echo)

    leaking = imbalance(run, faults=fault_safe(value))

    assert not leaking, f'{function.name}({shown(value)}) leaks references'


@pytest.mark.parametrize('klass', GENERATED.classes, ids=lambda klass: klass.spelled)
@SETTINGS
@given(data=st.data())
def test_class_fields_follow_the_model(
    *,
    built: Built,
    klass: typefuzz.Klass,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(klass, typefuzz.Klass)
    assert isinstance(data, st.DataObject)

    instance = instance_built(built, klass, data)

    for field in klass.fields:
        valid = field.node.strategy(built.module, canonical=False)
        value = data.draw(valid | field.node.mutants(built.module))

        field_check(instance=instance, field=field, value=value)

    restored = pickle.loads(pickle.dumps(instance))

    for field in klass.fields:
        original = getattr(instance, field.name)

        assert same(expected=original, actual=getattr(restored, field.name)), field.name


@pytest.mark.parametrize('klass', GENERATED.classes, ids=lambda klass: klass.spelled)
@LEAK_SETTINGS
@given(data=st.data())
def test_class_fields_refuse_hostile_values(
    *,
    built: Built,
    klass: typefuzz.Klass,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(klass, typefuzz.Klass)
    assert isinstance(data, st.DataObject)

    instance = instance_built(built, klass, data)

    for field in klass.fields:
        for value in (*typefuzz.HOSTILE, *hostile_values()):
            field_check(instance=instance, field=field, value=value)


@pytest.mark.parametrize('klass', GENERATED.classes, ids=lambda klass: klass.spelled)
@LEAK_SETTINGS
@given(data=st.data())
def test_class_fields_are_never_read_torn(
    *,
    built: Built,
    klass: typefuzz.Klass,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(klass, typefuzz.Klass)
    assert isinstance(data, st.DataObject)

    instance = instance_built(built, klass, data)
    field = data.draw(st.sampled_from(klass.fields))
    canonical = field.node.strategy(built.module, canonical=True)
    values = (data.draw(canonical), data.draw(canonical))
    expected = tuple(field.node.convert(value, built.module) for value in values)
    barrier = threading.Barrier(4)
    torn: list[object] = []

    setattr(instance, field.name, values[0])

    writers = [
        threading.Thread(
            target=field_written,
            kwargs={'instance': instance, 'field': field, 'value': value, 'barrier': barrier},
        )
        for value in values
    ]
    readers = [
        threading.Thread(
            target=field_read,
            kwargs={
                'instance': instance,
                'field': field,
                'expected': expected,
                'barrier': barrier,
                'torn': torn,
            },
        )
        for _ in range(2)
    ]

    interval = sys.getswitchinterval()

    sys.setswitchinterval(SWITCH_INTERVAL_SECONDS)

    try:
        for thread in (*writers, *readers):
            thread.start()

        for thread in (*writers, *readers):
            thread.join()
    finally:
        sys.setswitchinterval(interval)

    assert not torn, f'{klass.spelled}.{field.name} read {shown(torn[0])}'


@debug_only
@pytest.mark.parametrize('klass', GENERATED.classes, ids=lambda klass: klass.spelled)
@LEAK_SETTINGS
@given(data=st.data())
def test_class_fields_balance_references(
    *,
    built: Built,
    klass: typefuzz.Klass,
    data: st.DataObject,
) -> None:
    assert isinstance(built, Built)
    assert isinstance(klass, typefuzz.Klass)
    assert isinstance(data, st.DataObject)

    instance = instance_built(built, klass, data)

    for field in klass.fields:
        valid = field.node.strategy(built.module, canonical=False)
        value = data.draw(valid | field.node.mutants(built.module))
        run = functools.partial(field_assigned, instance, field, value)
        leaking = imbalance(run, faults=fault_safe(value))

        assert not leaking, f'{klass.spelled}.{field.name} leaks references'

    pickled = functools.partial(instance_pickled, instance)

    assert not imbalance(pickled, faults=False), f'pickling {klass.spelled} leaks references'


def test_generated_source_names_every_function() -> None:
    assert len(GENERATED.functions) == COUNT
    assert all(f'pub fn {function.name}(' in GENERATED.source for function in GENERATED.functions)


def test_stubtest_accepts_the_generated_stub(*, built: Built) -> None:
    assert isinstance(built, Built)
    assert built.module.__file__ is not None

    output = Path(built.module.__file__).parent.parent
    report = zig_project.stubtest_report(name=NAME, output=output)

    assert not report, report
