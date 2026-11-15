import inspect
import pathlib

import pytest

import hello

from conftest import subinterpreter_run, subinterpreters


def test_add() -> None:
    assert hello.add(2, 40) == 42
    assert hello.add(41) == 42
    assert hello.add(left=1, right=2) == 3


def test_overflow() -> None:
    assert issubclass(hello.Overflow, hello.Error)
    assert issubclass(hello.Overflow, OverflowError)

    with pytest.raises(hello.Overflow):
        hello.add(2**63 - 1, 1)


def test_signature() -> None:
    assert str(inspect.signature(hello.add)) == '(left, right=1)'
    assert hello.add.__doc__ == 'Add two integers.'
    assert hello.__doc__ == 'Greets from Zig.'


@subinterpreters
def test_subinterpreters_are_refused_by_default() -> None:
    directory = str(pathlib.Path(hello.__file__).parent.parent)

    assert pathlib.Path(directory).is_dir()

    source = f'import sys\nsys.path.insert(0, {directory!r})\nimport hello\n'

    with pytest.raises(Exception, match='does not support'):
        subinterpreter_run(source)
