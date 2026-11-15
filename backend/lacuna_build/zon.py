from dataclasses import dataclass, field


CODE_POINT_MAX = 0x10FFFF
DELIMITERS = '{},='
DEPENDENCY_PATH_DEPTH = 3
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
class Walk:
    keys: list[str | None] = field(default_factory=list)
    pending: str | None = None


@dataclass
class Parser:
    tokens: list[str]
    key: str | None = None
    position: int = 0
    result: object = None
    stack: list[Frame] = field(default_factory=list)


def tokens_of(source: str) -> list[str]:
    if not isinstance(source, str):
        message = f'build.zig.zon is tokenized from text, not {type(source).__name__}'
        raise TypeError(message)

    return [lexeme for _, _, lexeme in token_spans(source)]


def token_spans(source: str) -> list[tuple[int, int, str]]:
    if len(source) > SOURCE_BYTES_MAX:
        message = f'build.zig.zon is longer than {SOURCE_BYTES_MAX} bytes'
        raise ZonError(message)

    result: list[tuple[int, int, str]] = []
    index = 0

    for _ in range(len(source) + 1):
        if index >= len(source):
            break

        end, token = token_next(source, index)

        if token is not None:
            span = (index, end, token)
            result.append(span)

        index = end

        if len(result) > TOKEN_COUNT_MAX:
            message = 'build.zig.zon holds too many tokens'
            raise ZonError(message)

    return result


def dependency_paths_rewrite(source: str, replacements: dict[str, str]) -> str:
    if not isinstance(source, str):
        message = f'build.zig.zon is rewritten from text, not {type(source).__name__}'
        raise TypeError(message)

    if not replacements:
        message = 'a dependency path rewrite needs at least one replacement'
        raise ValueError(message)

    if not isinstance(replacements, dict):
        message = f'replacements map dependency names to paths, not {type(replacements).__name__}'
        raise TypeError(message)

    spans = token_spans(source)
    edits = dependency_path_edits(spans, replacements)
    result = source

    for start, end, literal in reversed(edits):
        result = f'{result[:start]}{literal}{result[end:]}'

    dependencies = parse(result).get('dependencies')

    for name, target in replacements.items():
        if not isinstance(dependencies, dict):
            message = 'the rewritten build.zig.zon lost its .dependencies'
            raise ZonError(message)

        if dependencies.get(name, {}).get('path') != target:
            message = f'the rewritten build.zig.zon does not point .{name} at {target}'
            raise ZonError(message)

    return result


def dependency_path_edits(
    spans: list[tuple[int, int, str]],
    replacements: dict[str, str],
) -> list[tuple[int, int, str]]:
    if len(spans) > TOKEN_COUNT_MAX:
        message = f'build.zig.zon holds more than {TOKEN_COUNT_MAX} tokens'
        raise ValueError(message)

    if not replacements:
        message = 'a dependency path rewrite needs at least one replacement'
        raise ValueError(message)

    walk = Walk()
    edits: list[tuple[int, int, str]] = []

    for position, (start, end, lexeme) in enumerate(spans):
        if walk_step(walk, spans=spans, position=position):
            continue

        target = dependency_target(keys=walk.keys, key=walk.pending, replacements=replacements)
        walk.pending = None

        if target is not None:
            edit = (start, end, literal_of(lexeme=lexeme, target=target))
            edits.append(edit)

    if len(edits) != len(replacements):
        message = f'build.zig.zon declares {len(edits)} of {len(replacements)} path dependencies'
        raise ZonError(message)

    return edits


def walk_step(walk: Walk, *, spans: list[tuple[int, int, str]], position: int) -> bool:
    if not isinstance(walk, Walk):
        message = f'walk_step advances a Walk, not {type(walk).__name__}'
        raise TypeError(message)

    if not 0 <= position < len(spans):
        message = f'position {position} lies outside the {len(spans)} tokens of build.zig.zon'
        raise ValueError(message)

    lexeme = spans[position][2]

    if lexeme == '.{':
        walk.keys.append(walk.pending)
        walk.pending = None

        return True

    if lexeme == '}':
        if not walk.keys:
            message = 'build.zig.zon closes a literal it never opened'
            raise ZonError(message)

        del walk.keys[-1]
        walk.pending = None

        return True

    if lexeme == '=':
        return True

    if lexeme.startswith('.'):
        following = spans[position + 1][2] if position + 1 < len(spans) else None

        if following == '=':
            walk.pending = lexeme[1:]

            return True

    return False


def dependency_target(
    *,
    keys: list[str | None],
    key: str | None,
    replacements: dict[str, str],
) -> str | None:
    if len(keys) > DEPTH_MAX:
        message = f'build.zig.zon nests deeper than {DEPTH_MAX} literals'
        raise ValueError(message)

    if not isinstance(replacements, dict):
        message = f'replacements map dependency names to paths, not {type(replacements).__name__}'
        raise TypeError(message)

    if not isinstance(key, str | None):
        message = f'a build.zig.zon key is a str or None, not {type(key).__name__}'
        raise TypeError(message)

    if key != 'path':
        return None

    if len(keys) != DEPENDENCY_PATH_DEPTH:
        return None

    if keys[1] != 'dependencies':
        return None

    return replacements.get(str(keys[2]))


def literal_of(*, lexeme: str, target: str) -> str:
    if not target:
        message = 'a dependency path is never empty'
        raise ValueError(message)

    if not lexeme.startswith('"'):
        message = f'build.zig.zon gives a dependency .path as {lexeme!r}, not a string'
        raise ZonError(message)

    escaped = target.replace('\\', '\\\\').replace('"', '\\"')

    return f'"{escaped}"'


def token_next(source: str, index: int) -> tuple[int, str | None]:
    if not 0 <= index < len(source):
        message = f'index {index} lies outside the {len(source)} characters of build.zig.zon'
        raise ValueError(message)

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
    if not source.startswith('"', start):
        message = f'a string starts at a quote, and index {start} of build.zig.zon holds none'
        raise ValueError(message)

    index = start + 1

    for _ in range(len(source)):
        if index >= len(source):
            break

        if source[index] == '\\':
            index += 2
        elif source[index] == '"':
            break
        else:
            index += 1

    if not source.startswith('"', index):
        message = 'build.zig.zon holds an unterminated string'
        raise ZonError(message)

    return index + 1


def word_end(source: str, start: int) -> int:
    if not 0 <= start < len(source):
        message = f'index {start} lies outside the {len(source)} characters of build.zig.zon'
        raise ValueError(message)

    index = start

    if source[start] in DELIMITERS:
        index += 1
    else:
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
    if len(kind) > 1:
        message = f'an escape kind is the one character after a backslash, not {kind!r}'
        raise ValueError(message)

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
    if not body.startswith('\\', start):
        message = f'an escape starts at a backslash, and index {start} of the string holds none'
        raise ValueError(message)

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
    if not lexeme:
        message = 'a scalar value is read from a token, and the lexeme is empty'
        raise ValueError(message)

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

    if key in stack[-1].fields:
        message = f'build.zig.zon declares .{key} twice in one literal'
        raise ZonError(message)

    if item is None:
        message = 'a build.zig.zon value is never None'
        raise ValueError(message)

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
    if parser.tokens[parser.position - 1] != '}':
        message = f'the parser closes a literal at a closing brace, not at {parser.position}'
        raise ValueError(message)

    frame = frame_close(parser.stack)
    closed = frame.fields or frame.items

    if parser.stack:
        frame_store(parser.stack, frame.key, closed)
    else:
        parser.result = closed


def parser_key(parser: Parser, lexeme: str) -> bool:
    if parser.tokens[parser.position - 1] != lexeme:
        message = f'{lexeme!r} is not the token the parser read last'
        raise ValueError(message)

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
    if parser.position >= len(parser.tokens):
        message = f'the parser has read all {len(parser.tokens)} tokens of build.zig.zon'
        raise ValueError(message)

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
    if not isinstance(source, str):
        message = f'build.zig.zon is parsed from text, not {type(source).__name__}'
        raise TypeError(message)

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
