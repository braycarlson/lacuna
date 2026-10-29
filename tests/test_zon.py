import random

import pytest

import lacuna_build_paths


CASE_COUNT = 400
ESCAPE_SOURCES = '\\"\n\t'
ESCAPE_TEXTS = ('\\\\', '\\"', '\\n', '\\t')
FUZZ_ALPHABET = '.{}=,"\\ \n\tabxu019_-/'
FUZZ_COUNT = 4000
FUZZ_LENGTH_MAX = 48
KEY_ALPHABET = 'abcdefghijklmnopqrstuvwxyz_'
SEED = 20261023
TEXT_ALPHABET = 'az09 "\\\n\té€\U0001f600'
WIDTH_MAX = 4


def key_draw(generator: random.Random) -> str:
    assert isinstance(generator, random.Random)

    length = generator.randint(1, 8)
    result = ''.join(generator.choice(KEY_ALPHABET) for _ in range(length))

    assert result.isidentifier()

    return result


def leaf_draw(generator: random.Random) -> object:
    assert isinstance(generator, random.Random)

    kind = generator.randrange(4)

    if kind == 0:
        return generator.choice((True, False))

    if kind == 1:
        return generator.randint(-(2**70), 2**70)

    length = generator.randint(0, 12)
    result = ''.join(generator.choice(TEXT_ALPHABET) for _ in range(length))

    assert len(result) == length

    return result


def container_draw(generator: random.Random) -> object:
    assert isinstance(generator, random.Random)

    width = generator.randint(1, WIDTH_MAX)

    if generator.random() < 0.5:
        return [leaf_draw(generator) for _ in range(width)]

    result = {key_draw(generator): leaf_draw(generator) for _ in range(width)}

    assert 0 < len(result) <= width

    return result


def document_draw(generator: random.Random) -> dict[str, object]:
    assert isinstance(generator, random.Random)

    width = generator.randint(1, WIDTH_MAX)
    result: dict[str, object] = {}

    for _ in range(width):
        nested = generator.random() < 0.5
        result[key_draw(generator)] = container_draw(generator) if nested else leaf_draw(generator)

    assert 0 < len(result) <= width

    return result


def character_escaped(character: str) -> str:
    assert len(character) == 1

    index = ESCAPE_SOURCES.find(character)

    if index >= 0:
        return ESCAPE_TEXTS[index]

    if character.isascii():
        return character

    return f'\\u{{{ord(character):x}}}'


def text_escaped(text: str) -> str:
    assert isinstance(text, str)

    result = '"' + ''.join(character_escaped(character) for character in text) + '"'

    assert len(result) >= len(text) + 2

    return result


def leaf_text(value: object) -> str:
    assert not isinstance(value, (list, dict))

    if isinstance(value, bool):
        return 'true' if value else 'false'

    if isinstance(value, int):
        return str(value)

    assert isinstance(value, str)

    return text_escaped(value)


def container_text(value: object) -> str:
    assert value is not None

    if isinstance(value, list):
        listed = ', '.join(leaf_text(item) for item in value)
    elif isinstance(value, dict):
        listed = ', '.join(f'.{key} = {leaf_text(item)}' for key, item in value.items())
    else:
        return leaf_text(value)

    return '.{ ' + listed + ' }'


def document_text(document: dict[str, object]) -> str:
    assert document

    fields = ',\n'.join(f'    .{key} = {container_text(value)}' for key, value in document.items())
    result = '// generated\n.{\n' + fields + ',\n}\n'

    assert result.count('\n') >= len(document) + 2

    return result


def test_parse_inverts_an_independent_serializer() -> None:
    zon = lacuna_build_paths.backend().zon
    generator = random.Random(SEED)
    coverage = {'escaped': 0, 'nested': 0}

    for _ in range(CASE_COUNT):
        document = document_draw(generator)
        source = document_text(document)

        assert zon.parse(source) == document, source

        coverage['escaped'] += '\\u{' in source
        coverage['nested'] += any(isinstance(value, (list, dict)) for value in document.values())

    assert coverage['escaped'] > CASE_COUNT // 4
    assert coverage['nested'] > CASE_COUNT // 4


def test_deep_nesting_round_trips_up_to_the_limit() -> None:
    zon = lacuna_build_paths.backend().zon
    depth = zon.DEPTH_MAX - 1
    source = '.{ .a = ' * depth + '.{ .leaf = 1 }' + ' }' * depth
    expected: object = {'leaf': 1}

    for _ in range(depth):
        expected = {'a': expected}

    assert source.count('.{') == zon.DEPTH_MAX
    assert zon.parse(source) == expected
    assert zon.parse('.{ .a = .{} }') == {'a': []}

    with pytest.raises(zon.ZonError, match='nests too deeply'):
        zon.parse('.{ .a = ' * zon.DEPTH_MAX + '.{}' + ' }' * zon.DEPTH_MAX)


@pytest.mark.parametrize(
    'source',
    [
        '}',
        '.{ .a = 1 } }',
        '.{ .a = 1 } .{ .b = 2 }',
        '.{ .a = "\\u{110000}" }',
        '.{ .a = "\\u{d800}" }',
        '.{ .a = "\\u{}" }',
        '.{ .a = "\\u{41" }',
        '.{ .a = "\\x4" }',
        '.{ .a = "\\q" }',
        '.{ .a = "open }',
        '.{ .a = 1, 2 }',
        '.{ .a = 010 }',
        '.{ .a = 1',
        '',
    ],
)
def test_malformed_source_raises_the_declared_error(source: str) -> None:
    assert len(source) < FUZZ_LENGTH_MAX

    zon = lacuna_build_paths.backend().zon

    with pytest.raises(zon.ZonError):
        zon.parse(source)


def test_random_text_finishes_and_raises_only_the_declared_error() -> None:
    zon = lacuna_build_paths.backend().zon
    generator = random.Random(SEED)
    outcomes = {'parsed': 0, 'rejected': 0}

    for _ in range(FUZZ_COUNT):
        length = generator.randint(0, FUZZ_LENGTH_MAX)
        source = ''.join(generator.choice(FUZZ_ALPHABET) for _ in range(length))

        try:
            parsed = zon.parse(source)
        except zon.ZonError:
            outcomes['rejected'] += 1
        else:
            assert isinstance(parsed, dict), source
            outcomes['parsed'] += 1

    assert outcomes['rejected'] > 0
    assert sum(outcomes.values()) == FUZZ_COUNT


def test_escapes_decode_to_their_characters() -> None:
    zon = lacuna_build_paths.backend().zon
    source = '.{ .text = "\\x41\\u{e9}\\u{1F600}\\n\\t\\\\\\"\\\'" }'

    assert zon.parse(source) == {'text': 'Aé\U0001f600\n\t\\"\''}
    assert zon.parse('.{ .a = "\\\\" }') == {'a': '\\'}
