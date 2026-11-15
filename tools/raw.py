import re
import subprocess
import sys
import tomllib

from pathlib import Path
from types import MappingProxyType


ALIAS_DEPTH_MAX = 8
ARGUMENT_COUNTS = MappingProxyType({'coverage': 4, 'generate': 6})
COLUMN_COUNT_MAX = 100
C_HANDLES = MappingProxyType(
    {
        'PyInterpreterState': 'c.PyInterpreterState',
        'PyThreadState': 'c.PyThreadState',
    },
)
C_STRUCTS = frozenset(
    {
        'PyCriticalSection',
        'PyCriticalSection2',
        'PyGetSetDef',
        'PyMemberDef',
        'PyMethodDef',
        'PyModuleDef',
        'PyType_Spec',
        'Py_buffer',
    },
)
C_TYPES = MappingProxyType(
    {
        'PyGILState_STATE': 'c.PyGILState_STATE',
        'Py_hash_t': 'c.Py_hash_t',
        'Py_ssize_t': 'c.Py_ssize_t',
        'wchar_t': 'wchar_t',
    },
)
EXCLUDED_IFDEFS = MappingProxyType(
    {
        'MS_WINDOWS': 'windows',
        'Py_REF_DEBUG': 'debug',
        'USE_STACKCHECK': 'windows',
    },
)
EXCLUSION_REASONS = ('abi_only', 'debug', 'va_list', 'windows')
FUNCTION_COUNT_MAX = 2048
FUNCTION_POINTER = '?*const fn'
GATE_KEYS = frozenset({'abi_only', 'added', 'ifdef'})
LAYER_COUNT_MAX = 4
MANIFEST_VERSION = (3, 15)
OBJECT_BASES = frozenset(
    {
        'PyCodeObject',
        'PyFrameObject',
        'PyObject',
        'PyTypeObject',
        'PyVarObject',
    },
)
OBJECT_SHAPES = MappingProxyType(
    {
        ('?*',): '?*c.PyObject',
        ('[*c]',): '?*c.PyObject',
        ('[*c]', '?*'): '?*?*c.PyObject',
        ('[*c]', '[*c]'): '?*?*c.PyObject',
        ('[*c]const ', '[*c]'): '?[*]const ?*c.PyObject',
    },
)
OPAQUE = 'opaque {}'
PATTERN_ADDED = re.compile(r'3\.\d+')
PATTERN_ALIAS = re.compile(r'^pub const ([A-Za-z_][A-Za-z0-9_]*) = (.*);$')
PATTERN_FUNCTION = re.compile(r'^pub extern fn (_?Py[A-Za-z0-9_]*)\((.*)\) (.*);$')
PATTERN_LAYER = re.compile(r'^(\[\*c\]|\?\*|\*|\[\*\])(const )?')
PATTERN_NAME = re.compile(r'^(?:[A-Za-z_][A-Za-z0-9_]*|@"[^"]*"): (.*)$')
PATTERN_OPAQUE = re.compile(r'^pub const ([A-Za-z_][A-Za-z0-9_]*) = opaque \{')
PATTERN_SIZE_T = re.compile(r'^_(Py[A-Za-z0-9_]*)_SizeT$')
PATTERN_STRUCT = re.compile(r'^pub const ([A-Za-z_][A-Za-z0-9_]*) = extern (struct|union) \{')
PATTERN_VA_LIST = re.compile(r'__va_list_tag|va_list')
PATTERN_VERSION = re.compile(r'^pub const PY_(MAJOR|MINOR)_VERSION = @as\(c_int, (\d+)\);$')
PLATFORM_IFDEFS = MappingProxyType(
    {'HAVE_FORK': 'fork', 'PY_HAVE_THREAD_NATIVE_ID': 'thread_native_id'},
)
POINTER_CATEGORIES = frozenset({'c_struct', 'handle', 'opaque', 'struct'})
SCALARS = frozenset(
    {
        'anyopaque',
        'c_int',
        'c_long',
        'c_longlong',
        'c_uint',
        'c_ulong',
        'c_ulonglong',
        'f64',
        'i32',
        'i64',
        'isize',
        'noreturn',
        'u32',
        'u64',
        'u8',
        'usize',
        'void',
    },
)
UNEXPORTED_FUNCTIONS = frozenset({'_Py_CheckPython3'})


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else ''

    if mode not in ARGUMENT_COUNTS:
        message = f'usage: {sys.argv[0]} coverage|generate <arguments>'
        raise SystemExit(message)

    if len(sys.argv) != ARGUMENT_COUNTS[mode]:
        message = f'{mode} takes {ARGUMENT_COUNTS[mode] - 2} arguments'
        raise SystemExit(message)

    paths = [Path(argument) for argument in sys.argv[2:]]
    manifest = manifest_load(paths[1])
    translation = translation_load(paths[0])

    coverage_check(manifest, translation, paths[0])

    if mode == 'generate':
        generate(manifest, translation, zig=paths[2], output_path=paths[3])


def alias_resolve(name: str, aliases: dict[str, str]) -> str:
    if not name:
        message = 'an alias needs a name'
        raise SystemExit(message)

    if not aliases:
        message = f'there are no aliases to resolve {name} against'
        raise SystemExit(message)

    current = name

    for _ in range(ALIAS_DEPTH_MAX):
        if current not in aliases:
            return current

        current = aliases[current]

    message = f'the alias chain of {name} is deeper than {ALIAS_DEPTH_MAX}'
    raise SystemExit(message)


def coverage_check(
    manifest: dict[str, dict[str, object]],
    translation: dict[str, object],
    translation_path: Path,
) -> None:
    if not manifest:
        message = 'the manifest has no functions'
        raise SystemExit(message)

    if not translation['functions']:
        message = f'{translation_path} declares no functions'
        raise SystemExit(message)

    if not translation_path.name:
        message = 'the translation path names no file'
        raise SystemExit(message)

    unlisted = sorted(set(translation['functions']) - set(manifest) - UNEXPORTED_FUNCTIONS)

    if unlisted:
        names = ', '.join(unlisted)
        message = (
            f'{translation_path} declares functions the vendored manifest lacks: {names}. '
            'Vendor the stable_abi.toml of the CPython release these headers come from, '
            'then regenerate src/raw.zig with zig build raw.'
        )

        raise SystemExit(message)


def declaration_render(*, name: str, parameters: list[str], result: str) -> list[str]:
    if not name:
        message = 'a declaration needs a name'
        raise SystemExit(message)

    if not isinstance(parameters, list):
        message = f'{name} needs a parameter list'
        raise SystemExit(message)

    if not result:
        message = f'{name} needs a result type'
        raise SystemExit(message)

    single = f'*const fn ({", ".join(parameters)}) callconv(.c) {result}'
    line = f'pub const {name} = c.Gate.declare({single}, "{name}");'

    if len(line) <= COLUMN_COUNT_MAX:
        return [line]

    lines = [f'pub const {name} = c.Gate.declare(']

    if len(f'    {single},') > COLUMN_COUNT_MAX:
        lines.append('    *const fn (')
        lines.extend(f'        {parameter},' for parameter in parameters)
        lines.append(f'    ) callconv(.c) {result},')
    else:
        lines.append(f'    {single},')

    lines.append(f'    "{name}",')
    lines.append(');')

    return lines


def exclusion_of(entry: dict[str, object], parameters: list[str]) -> str:
    if 'minor' not in entry:
        message = f'the manifest entry {entry} has no minor version'
        raise SystemExit(message)

    if not isinstance(parameters, list):
        message = f'parameters must be a list, not {type(parameters).__name__}'
        raise SystemExit(message)

    if entry['ifdef'] in EXCLUDED_IFDEFS:
        return EXCLUDED_IFDEFS[entry['ifdef']]

    if entry['abi_only']:
        return 'abi_only'

    if any(PATTERN_VA_LIST.search(parameter) for parameter in parameters):
        return 'va_list'

    return ''


def gate_render(name: str, entry: dict[str, object], *, link_name: str) -> list[str]:
    if not name:
        message = 'a gate needs a name'
        raise SystemExit(message)

    if 'minor' not in entry:
        message = f'{name} has no minor version'
        raise SystemExit(message)

    if link_name == name:
        message = f'{name} links to itself, so it needs no link name'
        raise SystemExit(message)

    platform = PLATFORM_IFDEFS.get(entry['ifdef'], 'any')
    fields = [f'.minor = {entry["minor"]}']

    if platform != 'any':
        fields.append(f'.platform = .{platform}')

    if link_name:
        fields.append(f'.link_name = "{link_name}"')

    line = f'    pub const {name}: c.Gate = .{{ {", ".join(fields)} }};'

    if len(line) <= COLUMN_COUNT_MAX:
        return [line]

    body = [f'        {field},' for field in fields]

    return [f'    pub const {name}: c.Gate = .{{', *body, '    };']


def generate(
    manifest: dict[str, dict[str, object]],
    translation: dict[str, object],
    *,
    zig: Path,
    output_path: Path,
) -> None:
    if not manifest:
        message = 'the manifest has no functions'
        raise SystemExit(message)

    if not zig.is_file():
        message = f'{zig} is not the zig executable'
        raise SystemExit(message)

    if output_path.suffix != '.zig':
        message = f'{output_path} must name a .zig file'
        raise SystemExit(message)

    if translation['version'] != MANIFEST_VERSION:
        message = (
            f'the translated headers are Python {translation["version"]}, but the '
            f'vendored manifest is from Python {MANIFEST_VERSION}'
        )

        raise SystemExit(message)

    source = source_render(manifest, translation)
    formatted = zig_format(zig, source)

    output_path.write_text(formatted, encoding='utf-8')


def lines_matching(pattern: re.Pattern[str], lines: list[str]) -> list[re.Match[str]]:
    if not pattern.pattern.startswith('^'):
        message = f'the pattern {pattern.pattern} must anchor at the start of a line'
        raise SystemExit(message)

    if not lines:
        message = 'there are no lines to match'
        raise SystemExit(message)

    return [match for match in map(pattern.match, lines) if match is not None]


def manifest_entry(name: str, table: dict[str, object]) -> dict[str, object]:
    if not name:
        message = 'a manifest entry needs a name'
        raise SystemExit(message)

    if not isinstance(table, dict):
        message = f'the manifest entry for {name} is not a table'
        raise SystemExit(message)

    unknown = set(table) - GATE_KEYS

    if unknown:
        message = f'the manifest gives {name} keys this generator does not know: {unknown}'
        raise SystemExit(message)

    added = table.get('added')

    if not isinstance(added, str):
        message = f'{name} has no added version: {added!r}'
        raise SystemExit(message)

    if PATTERN_ADDED.fullmatch(added) is None:
        message = f'{name} has an added version this generator cannot read: {added}'
        raise SystemExit(message)

    ifdef = table.get('ifdef')
    known = ifdef is None or ifdef in EXCLUDED_IFDEFS or ifdef in PLATFORM_IFDEFS

    if not known:
        message = f'{name} has an ifdef this generator does not know: {ifdef}'
        raise SystemExit(message)

    return {
        'abi_only': table.get('abi_only') is True,
        'ifdef': ifdef,
        'minor': int(added.split('.')[1]),
    }


def manifest_load(path: Path) -> dict[str, dict[str, object]]:
    if not path.is_file():
        message = f'{path} is not a file'
        raise SystemExit(message)

    document = tomllib.loads(path.read_text(encoding='utf-8'))
    functions = document.get('function')

    if not isinstance(functions, dict):
        message = f'{path} has no [function.*] tables'
        raise SystemExit(message)

    if len(functions) > FUNCTION_COUNT_MAX:
        message = f'{path} lists {len(functions)} functions, more than {FUNCTION_COUNT_MAX}'
        raise SystemExit(message)

    return {name: manifest_entry(name, table) for name, table in functions.items()}


def parameter_type(text: str) -> str:
    if not text:
        message = 'a parameter needs a type'
        raise SystemExit(message)

    match = PATTERN_NAME.match(text)

    return text if match is None else match.group(1)


def parameters_split(text: str) -> list[str]:
    if '\n' in text:
        message = f'a parameter list spans lines: {text}'
        raise SystemExit(message)

    pieces = []
    depth = 0
    start = 0

    for index, character in enumerate(text):
        depth += (character == '(') - (character == ')')

        if character != ',':
            continue

        if depth == 0:
            pieces.append(text[start:index])
            start = index + 1

    pieces.append(text[start:])

    return [parameter_type(piece.strip()) for piece in pieces if piece.strip()]


def source_join(
    *,
    opaques: list[str],
    gates: list[str],
    blocks: list[list[str]],
    exclusions: dict[str, list[str]],
) -> str:
    if not gates:
        message = 'there are no functions to declare'
        raise SystemExit(message)

    if len(gates) != len(blocks):
        message = f'{len(gates)} gates for {len(blocks)} declarations'
        raise SystemExit(message)

    if set(exclusions) != set(EXCLUSION_REASONS):
        message = f'the exclusions must be grouped by {EXCLUSION_REASONS}'
        raise SystemExit(message)

    if len(set(opaques)) != len(opaques):
        message = 'an opaque type is listed twice'
        raise SystemExit(message)

    lines = [
        'const std = @import("std");',
        '',
        'const builtin = @import("builtin");',
        'const c = @import("c.zig");',
        '',
    ]

    platform = [
        'pub const fork_available = builtin.target.os.tag != .windows;',
        '',
        'pub const thread_native_id_available = switch (builtin.target.os.tag) {',
        '    .dragonfly, .freebsd, .linux, .netbsd, .openbsd, .windows => true,',
        '    else => builtin.target.os.tag.isDarwin(),',
        '};',
        '',
        'pub const wchar_t = std.c.wchar_t;',
        '',
        'pub const gates = struct {',
    ]

    lines.extend(f'pub const {name} = opaque {{}};' for name in opaques)
    lines.extend(platform)
    lines.extend(blocks_fence(gates, count_previous=0))
    lines.append('};')

    for reason in EXCLUSION_REASONS:
        opening = f'pub const excluded_{reason} = [_][]const u8{{'

        lines.extend(('', opening))
        lines.extend(f'    "{name}",' for name in exclusions[reason])
        lines.append('};')

    lines.extend(blocks_fence(blocks, count_previous=2))

    return '\n'.join(lines) + '\n'


def blocks_fence(blocks: list[list[str]], *, count_previous: int) -> list[str]:
    if not blocks:
        message = 'there are no blocks to fence'
        raise SystemExit(message)

    if count_previous < 0:
        message = f'the previous block cannot have {count_previous} lines'
        raise SystemExit(message)

    lines = []

    for block in blocks:
        if max(len(block), count_previous) > 1:
            lines.append('')

        lines.extend(block)
        count_previous = len(block)

    return lines


def size_t_links(manifest: dict[str, dict[str, object]]) -> dict[str, str]:
    if not manifest:
        message = 'the manifest has no functions'
        raise SystemExit(message)

    links = {}

    for name in manifest:
        match = PATTERN_SIZE_T.match(name)

        if match is None:
            continue

        if match.group(1) in manifest:
            links[match.group(1)] = name

    return links


def source_render(manifest: dict[str, dict[str, object]], translation: dict[str, object]) -> str:
    if not manifest:
        message = 'the manifest has no functions'
        raise SystemExit(message)

    if not translation['functions']:
        message = 'the translation has no functions'
        raise SystemExit(message)

    exclusions = {reason: [] for reason in EXCLUSION_REASONS}
    gates = []
    blocks = []
    opaques = set()
    link_names = size_t_links(manifest)

    for name in sorted(manifest):
        entry = manifest[name]
        signature = translation['functions'].get(name)
        parameters = [] if signature is None else signature[0]
        reason = exclusion_of(entry, parameters)

        if reason:
            exclusions[reason].append(name)
            continue

        if signature is None:
            message = f'the manifest lists {name}, but the translated headers do not declare it'
            raise SystemExit(message)

        mapped = [type_map(parameter, translation, opaques) for parameter in parameters]
        returned = type_map(signature[1], translation, opaques)

        gates.append(gate_render(name, entry, link_name=link_names.get(name, '')))
        blocks.append(declaration_render(name=name, parameters=mapped, result=returned))

    return source_join(opaques=sorted(opaques), gates=gates, blocks=blocks, exclusions=exclusions)


def translation_load(path: Path) -> dict[str, object]:
    if not path.is_file():
        message = f'{path} is not a file'
        raise SystemExit(message)

    lines = path.read_text(encoding='utf-8').splitlines()
    version = {
        match.group(1): int(match.group(2)) for match in lines_matching(PATTERN_VERSION, lines)
    }
    aliases = {match.group(1): match.group(2) for match in lines_matching(PATTERN_ALIAS, lines)}
    opaques = {match.group(1): OPAQUE for match in lines_matching(PATTERN_OPAQUE, lines)}

    functions = {
        match.group(1): (parameters_split(match.group(2)), match.group(3))
        for match in lines_matching(PATTERN_FUNCTION, lines)
    }

    if set(version) != {'MAJOR', 'MINOR'}:
        message = f'{path} does not define PY_MAJOR_VERSION and PY_MINOR_VERSION'
        raise SystemExit(message)

    return {
        'aliases': aliases | opaques,
        'functions': functions,
        'structs': {match.group(1) for match in lines_matching(PATTERN_STRUCT, lines)},
        'version': (version['MAJOR'], version['MINOR']),
    }


def type_category(*, base: str, resolved: str, structs: set[str]) -> str:
    if not base:
        message = 'a type needs a base'
        raise SystemExit(message)

    if not resolved:
        message = f'{base} resolved to nothing'
        raise SystemExit(message)

    if not isinstance(structs, set):
        message = f'structs must be a set, not {type(structs).__name__}'
        raise SystemExit(message)

    checks = (
        ('object', base in OBJECT_BASES),
        ('handle', base in C_HANDLES),
        ('c_type', base in C_TYPES),
        ('c_struct', base in C_STRUCTS),
        ('opaque', resolved == OPAQUE),
        ('struct', resolved in structs),
        ('struct', base in structs),
        ('function', resolved.startswith(FUNCTION_POINTER)),
        ('scalar', resolved in SCALARS),
    )

    return next((category for category, matched in checks if matched), '')


def type_compose(*, layers: list[str], base: str, resolved: str, structs: set[str]) -> str:
    if len(layers) > LAYER_COUNT_MAX:
        message = f'{base} nests more than {LAYER_COUNT_MAX} pointers'
        raise SystemExit(message)

    if not base:
        message = 'a type needs a base'
        raise SystemExit(message)

    if not resolved:
        message = f'{base} resolved to nothing'
        raise SystemExit(message)

    if not isinstance(structs, set):
        message = f'structs must be a set, not {type(structs).__name__}'
        raise SystemExit(message)

    prefix = ''.join(layers)
    category = type_category(base=base, resolved=resolved, structs=structs)

    if category == 'object':
        return type_object(layers, base)

    if not prefix:
        if category in POINTER_CATEGORIES:
            message = f'{base} is passed by value, which the raw layer cannot express'
            raise SystemExit(message)

    renders = {
        'c_struct': f'{prefix}c.{base}',
        'c_type': prefix + C_TYPES.get(base, ''),
        'function': '?*const anyopaque',
        'handle': prefix.replace('[*c]', '?*') + C_HANDLES.get(base, ''),
        'opaque': prefix + base,
        'scalar': prefix + resolved,
        'struct': '?*const anyopaque' if prefix.endswith('const ') else '?*anyopaque',
    }

    if category not in renders:
        message = f'no raw-layer mapping for the type {prefix}{base}'
        raise SystemExit(message)

    return renders[category]


def type_layers(text: str) -> tuple[list[str], str]:
    if not text:
        message = 'a type needs text'
        raise SystemExit(message)

    layers = []
    rest = text

    for _ in range(LAYER_COUNT_MAX + 1):
        match = PATTERN_LAYER.match(rest)

        if match is None:
            return layers, rest

        layers.append(match.group(0))
        rest = rest[match.end() :]

    message = f'{text} nests more than {LAYER_COUNT_MAX} pointers'
    raise SystemExit(message)


def type_map(text: str, translation: dict[str, object], opaques: set[str]) -> str:
    if not text:
        message = 'a type needs text'
        raise SystemExit(message)

    if 'aliases' not in translation:
        message = 'the translation has no aliases'
        raise SystemExit(message)

    if not isinstance(opaques, set):
        message = f'opaques must be a set, not {type(opaques).__name__}'
        raise SystemExit(message)

    if text == '...':
        return text

    current = text

    for _ in range(ALIAS_DEPTH_MAX):
        if current.startswith(FUNCTION_POINTER):
            return '?*const anyopaque'

        layers, base = type_layers(current)
        fixed = base in OBJECT_BASES or base in C_HANDLES or base in C_TYPES
        resolved = base if fixed else alias_resolve(base, translation['aliases'])

        if PATTERN_LAYER.match(resolved) is None:
            if resolved == OPAQUE:
                opaques.add(base)

            return type_compose(
                layers=layers,
                base=base,
                resolved=resolved,
                structs=translation['structs'],
            )

        current = ''.join(layers) + resolved

    message = f'the type {text} does not resolve within {ALIAS_DEPTH_MAX} aliases'
    raise SystemExit(message)


def type_object(layers: list[str], base: str) -> str:
    if not isinstance(layers, list):
        message = f'layers must be a list, not {type(layers).__name__}'
        raise SystemExit(message)

    if base not in OBJECT_BASES:
        message = f'{base} is not an object type'
        raise SystemExit(message)

    shape = tuple(layers)

    if shape not in OBJECT_SHAPES:
        message = f'no raw-layer mapping for {"".join(layers)}{base}'
        raise SystemExit(message)

    return OBJECT_SHAPES[shape]


def zig_format(zig: Path, source: str) -> str:
    if not zig.is_file():
        message = f'{zig} is not the zig executable'
        raise SystemExit(message)

    if not source.endswith('\n'):
        message = 'the generated source must end with a newline'
        raise SystemExit(message)

    command = [str(zig), 'fmt', '--stdin']
    completed = subprocess.run(command, input=source, capture_output=True, text=True, check=False)

    if completed.returncode != 0:
        message = f'zig fmt rejected the generated source:\n{completed.stderr}'
        raise SystemExit(message)

    return completed.stdout


if __name__ == '__main__':
    main()
