import pickle
import sys

from pathlib import Path
from types import MappingProxyType

import pytest

import mixed
import mixed._native

from mixed.helpers import Registered


SHARED_NAMES = MappingProxyType(
    {'darwin': 'libcounter-mixed.dylib', 'win32': 'counter-mixed.dll'},
)


def test_python_layer_wraps_native() -> None:
    assert mixed.greet('Zig') == 'Hello, Zig!'
    assert mixed.shout('zig') == 'HELLO, ZIG!'
    assert mixed.greet is mixed._native.greet


def test_native_module_is_nested() -> None:
    assert mixed._native.__name__ == 'mixed._native'
    assert mixed.Error.__module__ == 'mixed._native'
    assert mixed._native.__file__ is not None

    package = Path(mixed.__file__).parent

    assert (package / 'py.typed').exists()
    assert (package / '_native.pyi').exists()
    assert (package / 'helpers.py').exists()


def test_module_name_places_a_class_in_the_package() -> None:
    badge = mixed.Badge(3)

    assert mixed.Badge is mixed._native.Badge
    assert mixed.Badge.__module__ == 'mixed'
    assert mixed.Badge.__qualname__ == 'Badge'
    assert repr(mixed.Badge) == "<class 'mixed.Badge'>"
    assert pickle.loads(pickle.dumps(mixed.Badge)) is mixed.Badge
    assert badge.rank == 3
    assert type(badge).__module__ == 'mixed'


def test_bundled_library_loads_beside_the_extension() -> None:
    first = mixed._native.counter_next()
    directory = Path(mixed._native.__file__).parent
    expected = SHARED_NAMES.get(sys.platform, 'libcounter-mixed.so')

    assert mixed._native.counter_next() == first + 1
    assert [path.name for path in directory.iterdir() if 'counter' in path.name] == [expected]


def test_native_errors() -> None:
    with pytest.raises(mixed.TextFull):
        mixed.greet('x' * 200)


def test_python_metaclass() -> None:
    native = mixed._native

    assert hasattr(native, 'Plugin') is native.metaclasses

    if sys.version_info < (3, 12):
        assert not native.metaclasses

    if native.metaclasses:
        plugin_check()


def plugin_check() -> None:
    plugin = mixed._native.Plugin

    assert type(plugin) is Registered
    assert plugin in Registered.registry
    assert repr(plugin) == '<registered Plugin>'
    assert plugin(4).level == 4
    assert plugin().level == 0

    class Extension(plugin):
        pass

    assert Registered.registry[-1] is Extension
