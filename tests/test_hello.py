import inspect

import pytest

import hello


def test_add() -> None:
    assert hello.add(2, 40) == 42
    assert hello.add(41) == 42
    assert hello.add(left=1, right=2) == 3


def test_overflow() -> None:
    with pytest.raises(hello.Overflow):
        hello.add(2**63 - 1, 1)


def test_signature() -> None:
    assert str(inspect.signature(hello.add)) == '(left, right=1)'
    assert hello.add.__doc__ == 'Add two integers.'
    assert hello.__doc__ == 'Greets from Zig.'
