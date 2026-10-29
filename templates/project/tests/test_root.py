import example


def test_double() -> None:
    assert example.double(21) == 42
    assert example.double(value=-3) == -6
