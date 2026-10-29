import sys

from pathlib import Path

import pytest

import mixed
import mixed._native

from mixed.helpers import Registered


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
