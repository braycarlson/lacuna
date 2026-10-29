import pytest

import wide


GROUPS = ('North', 'South', 'East', 'West')
WORDS = (
    'alpha',
    'bravo',
    'charlie',
    'delta',
    'echo',
    'foxtrot',
    'golf',
    'hotel',
    'india',
    'juliett',
    'kilo',
    'lima',
    'mike',
    'november',
    'oscar',
    'papa',
)
NAMES = frozenset(group + word.capitalize() for group in GROUPS for word in WORDS)


def test_every_error_raises_its_class() -> None:
    raised = set()

    for index in range(len(NAMES)):
        with pytest.raises(wide.Error) as information:
            wide.fail(index)

        name = type(information.value).__name__
        message = f'the {name} fault stopped the wide module'

        assert str(information.value) == message
        assert type(information.value).__doc__ == message
        assert getattr(wide, name) is type(information.value)

        raised.add(name)

    assert raised == NAMES

    with pytest.raises(IndexError):
        wide.fail(len(NAMES))


def test_long_docs() -> None:
    sentence = 'sixty-four errors and sixteen documented fields'
    docs = wide.__doc__ or ''

    assert docs.count(sentence) == 4
    assert docs.startswith('The wide fixture holds')
    assert (wide.fail.__doc__ or '').endswith(docs)


def test_panel_fields_and_properties() -> None:
    panel = wide.Panel()

    for word in WORDS:
        assert getattr(panel, word) == 0
        assert getattr(wide.Panel, word).__doc__.startswith(f'The {word} slot')

        setattr(panel, word, 2**62)

        assert getattr(panel, f'{word}_doubled') == 2**63 - 1
