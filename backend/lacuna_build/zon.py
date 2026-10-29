from dataclasses import dataclass, field


CODE_POINT_MAX = 0x10FFFF
DELIMITERS = '{},='
DEPTH_MAX = 64
SOURCE_BYTES_MAX = 1 << 20
SURROGATES = range(0xD800, 0xE000)
TOKEN_COUNT_MAX = 1 << 16


class ZonError(ValueError):
    pass


@dataclass
class Frame:
    key: str | None
    fields: dict[str, object] = field(default_factory=dict)
    items: list[object] = field(default_factory=list)


@dataclass
class Parser:
    tokens: list[str]
    key: str | None = None
    position: int = 0
    result: object = None
    stack: list[Frame] = field(default_factory=list)


def tokens_of(source: str) -> list[str]:
    if len(source) > SOURCE_BYTES_MAX:
        message = f'build.zig.zon is longer than {SOURCE_BYTES_MAX} bytes'
        raise ZonError(message)

    result: list[str] = []
    index = 0

    for _ in range(len(source) + 1):
        if index >= len(source):
            break

        index, token = token_next(source, index)

        if token is not None:
            result.append(token)

        if len(result) > TOKEN_COUNT_MAX:
            message = 'build.zig.zon holds too many tokens'
            raise ZonError(message)

    return result


def token_next(source: str, index: int) -> tuple[int, str | None]:
    character = source[index]

    if character.isspace():
        return index + 1, None

    if source.startswith('//', index):
        end = source.find('\n', index)
        return (len(source) if end < 0 else end), None

    if character == '"':
        end = string_end(source, index)
        return end, source[index:end]

    if source.startswith('.{', index):
        return index + 2, '.{'

    end = word_end(source, index)
    return end, source[index:end]


def string_end(source: str, start: int) -> int:
    index = start + 1

    for _ in range(len(source)):
        if index >= len(source):
            break

        if source[index] == '\\':
            index += 2
        elif source[index] == '"':
            return index + 1
        else:
            index += 1

    message = 'build.zig.zon holds an unterminated string'
    raise ZonError(message)


def word_end(source: str, start: int) -> int:
    if source[start] in DELIMITERS:
        return start + 1

    index = start

    for _ in range(len(source)):
        if index >= len(source):
            break

        character = source[index]

        if character.isspace():
            break

        if character in DELIMITERS:
            break

        index += 1

    if index == start:
        message = f'build.zig.zon holds an unexpected character {source[start]!r}'
        raise ZonError(message)

    return index


def string_value(lexeme: str) -> str:
    if not lexeme.startswith('"'):
        message = f'build.zig.zon expected a string, not {lexeme!r}'
        raise ZonError(message)

    body = lexeme[1:-1]
    pieces: list[str] = []
    index = 0

    for _ in range(len(body) + 1):
        if index >= len(body):
            break

        if body[index] == '\\':
            index, piece = escape_decode(body, index)
        else:
            piece = body[index]
            index += 1

        pieces.append(piece)

    return ''.join(pieces)


def escape_simple(kind: str) -> str | None:
    match kind:
        case '"' | "'" | '\\':
            return kind
        case 'n':
            return '\n'
        case 'r':
            return '\r'
        case 't':
            return '\t'
        case _:
            return None


def escape_decode(body: str, start: int) -> tuple[int, str]:
    kind = body[start + 1 : start + 2]
    simple = escape_simple(kind)

    if simple is not None:
        return start + 2, simple

    if kind == 'x':
        return start + 4, chr(escape_number(body[start + 2 : start + 4], 2))

    if body.startswith('u{', start + 1):
        end = body.find('}', start + 3)

        if end < 0:
            message = 'build.zig.zon holds an unterminated \\u{} escape'
            raise ZonError(message)

        return end + 1, chr(escape_number(body[start + 3 : end], end - start - 3))

    message = f'build.zig.zon holds an unknown escape {body[start : start + 2]!r}'
    raise ZonError(message)


def escape_number(digits: str, length: int) -> int:
    if len(digits) != length:
        message = f'build.zig.zon holds a truncated escape {digits!r}'
        raise ZonError(message)

    if not digits:
        message = 'build.zig.zon holds an empty \\u{} escape'
        raise ZonError(message)

    if not all(character in '0123456789abcdefABCDEF' for character in digits):
        message = f'build.zig.zon holds a non-hexadecimal escape {digits!r}'
        raise ZonError(message)

    value = int(digits, 16)

    if value > CODE_POINT_MAX:
        message = f'build.zig.zon holds an escape past the last code point: {digits!r}'
        raise ZonError(message)

    if value in SURROGATES:
        message = f'build.zig.zon holds an escape for a surrogate: {digits!r}'
        raise ZonError(message)

    return value


def scalar_value(lexeme: str) -> object:
    if lexeme.startswith('"'):
        return string_value(lexeme)

    if lexeme.startswith('.'):
        return lexeme[1:]

    if lexeme in ('true', 'false'):
        return lexeme == 'true'

    try:
        number = int(lexeme, 0)
    except ValueError:
        message = f'build.zig.zon holds an unsupported value {lexeme!r}'
        raise ZonError(message) from None
    else:
        return number


def frame_close(stack: list[Frame]) -> Frame:
    if not stack:
        message = 'build.zig.zon closes a literal it never opened'
        raise ZonError(message)

    frame = stack.pop()

    if not frame.fields:
        return frame

    if frame.items:
        message = 'build.zig.zon mixes fields and items in one literal'
        raise ZonError(message)

    return frame


def frame_store(stack: list[Frame], key: str | None, item: object) -> None:
    if not stack:
        message = 'build.zig.zon holds a value outside the top literal'
        raise ZonError(message)

    parent = stack[-1]

    if key is None:
        parent.items.append(item)
    else:
        parent.fields[key] = item


def parser_open(parser: Parser) -> None:
    if len(parser.stack) == DEPTH_MAX:
        message = 'build.zig.zon nests too deeply'
        raise ZonError(message)

    if parser.result is not None:
        message = 'build.zig.zon holds more than one top literal'
        raise ZonError(message)

    frame = Frame(key=parser.key)

    parser.stack.append(frame)
    parser.key = None


def parser_close(parser: Parser) -> None:
    frame = frame_close(parser.stack)
    closed = frame.fields or frame.items

    if parser.stack:
        frame_store(parser.stack, frame.key, closed)
    else:
        parser.result = closed


def parser_key(parser: Parser, lexeme: str) -> bool:
    if not lexeme.startswith('.'):
        return False

    if parser.position >= len(parser.tokens):
        return False

    if parser.tokens[parser.position] != '=':
        return False

    parser.key = lexeme[1:]
    parser.position += 1

    return True


def parser_step(parser: Parser) -> None:
    lexeme = parser.tokens[parser.position]
    parser.position += 1

    if lexeme == '.{':
        parser_open(parser)

        return

    if lexeme == '}':
        parser_close(parser)

        return

    if lexeme == ',':
        parser.key = None

        return

    if parser_key(parser, lexeme):
        return

    frame_store(parser.stack, parser.key, scalar_value(lexeme))
    parser.key = None


def parse(source: str) -> dict[str, object]:
    parser = Parser(tokens=tokens_of(source))

    for _ in range(len(parser.tokens) + 1):
        if parser.position >= len(parser.tokens):
            break

        parser_step(parser)

    if parser.stack:
        message = 'build.zig.zon leaves a literal unclosed'
        raise ZonError(message)

    if not isinstance(parser.result, dict):
        message = 'build.zig.zon is not a single struct literal'
        raise ZonError(message)

    return parser.result
