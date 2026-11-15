import argparse
import contextlib
import importlib.resources
import importlib.util
import keyword
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import tomllib
import zlib

from importlib.resources.abc import Traversable
from pathlib import Path

from lacuna_build import archive, build_editable, build_sdist, build_wheel, project, zon


FINGERPRINT_IDENTIFIER_MAX = 0xFFFFFFFE
FINGERPRINT_PATTERN = re.compile(r'\.fingerprint = 0x[0-9a-fA-F]+,')
NAME_BYTES_MAX = 32
NAME_PATTERN = re.compile(r'[A-Za-z](?:[A-Za-z0-9_]*[A-Za-z0-9])?')
TEMPLATE_DIRECTORY = 'template'
TEMPLATE_MANIFEST = 'build.zig.zon'
TEMPLATE_NAME_PATTERN = re.compile(r'\bexample\b')
TREE_DIRECTORY_COUNT_MAX = 1 << 12
VENDOR_DIRECTORY = 'lacuna'

ZIG_KEYWORDS = frozenset(
    {
        'addrspace',
        'align',
        'allowzero',
        'and',
        'anyframe',
        'anytype',
        'asm',
        'break',
        'callconv',
        'catch',
        'comptime',
        'const',
        'continue',
        'defer',
        'else',
        'enum',
        'errdefer',
        'error',
        'export',
        'extern',
        'fn',
        'for',
        'if',
        'inline',
        'linksection',
        'noalias',
        'noinline',
        'nosuspend',
        'opaque',
        'or',
        'orelse',
        'packed',
        'pub',
        'resume',
        'return',
        'struct',
        'suspend',
        'switch',
        'test',
        'threadlocal',
        'try',
        'union',
        'unreachable',
        'var',
        'volatile',
        'while',
    }
)


class CommandError(RuntimeError):
    pass


def main(arguments: list[str] | None = None) -> int:
    if not isinstance(arguments, list | None):
        message = f'arguments must be a list of strings or None, not {type(arguments).__name__}'
        raise TypeError(message)

    parser = parser_build()
    namespace, extra = parser.parse_known_args(arguments)

    if namespace.command != 'publish':
        if extra:
            parser.error(f'unrecognized arguments: {" ".join(extra)}')

    namespace.arguments = extra[1:] if extra[:1] == ['--'] else extra

    try:
        namespace.handler(namespace)
    except (
        CommandError,
        archive.ArchiveError,
        project.ProjectError,
        tomllib.TOMLDecodeError,
        zon.ZonError,
    ) as error:
        failure_report(error)

        return 1
    else:
        return 0


def command_build(namespace: argparse.Namespace) -> None:
    if namespace.command != 'build':
        message = f'command_build runs the build command, not {namespace.command}'
        raise ValueError(message)

    root = project_root(namespace.project)
    output = output_of(namespace.out, root)
    produced = distributions_build(root=root, output=output, sdist=namespace.sdist)

    paths_report(produced)


def command_develop(namespace: argparse.Namespace) -> None:
    if namespace.command != 'develop':
        message = f'command_develop runs the develop command, not {namespace.command}'
        raise ValueError(message)

    with tempfile.TemporaryDirectory() as directory:
        root = project_root(namespace.project)
        installer = installer_check()

        with contextlib.chdir(root):
            name = build_editable(directory)

        wheel = str(Path(directory) / name)
        distribution = name.partition('-')[0]

        for command in installs_of(installer, wheel=wheel, distribution=distribution):
            command_run(command, label=f'installing {name}')


def command_new(namespace: argparse.Namespace) -> None:
    if namespace.command != 'new':
        message = f'command_new runs the new command, not {namespace.command}'
        raise ValueError(message)

    target = Path(namespace.path).resolve()
    name = namespace.name or target.name

    name_check(name)
    target_check(target)

    resources = importlib.resources.files('lacuna_build')
    template = tree_files(resources / TEMPLATE_DIRECTORY)
    vendored = tree_files(resources / VENDOR_DIRECTORY)
    fingerprint = fingerprint_of(name)

    for relative, resource in template:
        content = resource.read_text(encoding='utf-8')

        rendered = template_render(
            relative=relative,
            content=content,
            name=name,
            fingerprint=fingerprint,
        )

        file_write(target / relative, rendered.encode('utf-8'))

    for relative, resource in vendored:
        file_write(target / 'vendor' / 'lacuna' / relative, resource.read_bytes())

    created = [target]

    manifest_check(target / TEMPLATE_MANIFEST, name=name, fingerprint=fingerprint)
    paths_report(created)


def command_publish(namespace: argparse.Namespace) -> None:
    if namespace.command != 'publish':
        message = f'command_publish runs the publish command, not {namespace.command}'
        raise ValueError(message)

    root = project_root(namespace.project)
    publisher = shutil.which('uv')

    if publisher is None:
        message = 'lacuna publish needs uv on PATH'
        raise CommandError(message)

    output = output_of(namespace.out, root)
    produced = distributions_build(root=root, output=output, sdist=True)
    command = [publisher, 'publish', *namespace.arguments, *map(str, produced)]

    paths_report(produced)
    command_run(command, label='uv publish')


def command_run(command: list[str], *, label: str) -> None:
    if not command:
        message = f'{label} has no command to run'
        raise ValueError(message)

    if not label:
        message = f'running {command[0]} needs a label to name it in a failure'
        raise ValueError(message)

    completed = subprocess.run(command, check=False)

    if completed.returncode != 0:
        message = f'{label} failed with status {completed.returncode}'
        raise CommandError(message)


def command_sdist(namespace: argparse.Namespace) -> None:
    if namespace.command != 'sdist':
        message = f'command_sdist runs the sdist command, not {namespace.command}'
        raise ValueError(message)

    root = project_root(namespace.project)
    output = output_of(namespace.out, root)

    output.mkdir(parents=True, exist_ok=True)

    with contextlib.chdir(root):
        name = build_sdist(str(output))

    produced = [output / name]

    paths_report(produced)


def distributions_build(*, root: Path, output: Path, sdist: bool) -> list[Path]:
    if not (root / 'pyproject.toml').is_file():
        message = f'{root} holds no pyproject.toml to build'
        raise ValueError(message)

    if not output.is_absolute():
        message = f'{output} must be absolute, because the build runs inside {root}'
        raise ValueError(message)

    output.mkdir(parents=True, exist_ok=True)

    with contextlib.chdir(root):
        names = [build_wheel(str(output))]

        if sdist:
            names.append(build_sdist(str(output)))

    return [output / name for name in names]


def failure_report(error: Exception) -> None:
    if not isinstance(error, Exception):
        message = f'failure_report reports an exception, not {type(error).__name__}'
        raise TypeError(message)

    summary, _, detail = str(error).partition('\n')

    if detail.strip():
        _ = sys.stderr.write(detail.rstrip('\n') + '\n')

    _ = sys.stderr.write(f'lacuna: {summary}\n')


def file_write(path: Path, content: bytes) -> None:
    if path.exists():
        message = f'{path} already exists, and a new project writes each file once'
        raise ValueError(message)

    if not isinstance(content, bytes):
        message = f'{path} takes bytes, not {type(content).__name__}'
        raise TypeError(message)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def fingerprint_of(name: str) -> int:
    if not NAME_PATTERN.fullmatch(name):
        message = f'{name!r} is not a package name to fingerprint'
        raise ValueError(message)

    checksum = zlib.crc32(name.encode('ascii'))
    identifier = secrets.randbelow(FINGERPRINT_IDENTIFIER_MAX) + 1

    return checksum << 32 | identifier


def installer_check() -> str | None:
    installer = shutil.which('uv')

    if installer is not None:
        return installer

    if importlib.util.find_spec('pip') is None:
        message = f'lacuna develop needs uv on PATH or pip installed in {sys.executable}'
        raise CommandError(message)

    return None


def installs_of(installer: str | None, *, wheel: str, distribution: str) -> list[list[str]]:
    if installer is not None:
        if not Path(installer).is_file():
            message = f'the installer {installer} is not a file'
            raise ValueError(message)

    if not Path(wheel).is_file():
        message = f'the wheel {wheel} does not exist'
        raise ValueError(message)

    if not Path(wheel).name.startswith(f'{distribution}-'):
        message = f'the wheel {wheel} does not belong to the distribution {distribution}'
        raise ValueError(message)

    if installer is None:
        pip = [sys.executable, '-m', 'pip', 'install']

        return [[*pip, wheel], [*pip, '--force-reinstall', '--no-deps', wheel]]

    install = [installer, 'pip', 'install', '--python', sys.executable]

    return [[*install, '--reinstall-package', distribution, wheel]]


def manifest_check(manifest: Path, *, name: str, fingerprint: int) -> None:
    if not manifest.is_file():
        message = f'the lacuna_build template wrote no {manifest}'
        raise CommandError(message)

    fields = zon.parse(manifest.read_text(encoding='utf-8'))

    if fields.get('name') != name:
        message = f'{manifest} names the package {fields.get("name")}, not {name}'
        raise CommandError(message)

    if fields.get('fingerprint') != fingerprint:
        message = f'{manifest} holds the fingerprint {fields.get("fingerprint")}, not {fingerprint}'
        raise CommandError(message)


def name_check(name: str) -> None:
    if not NAME_PATTERN.fullmatch(name):
        message = (
            f'{name!r} is not a valid package name: it must start with an ASCII letter, '
            'end with a letter or digit, and hold only letters, digits, and underscores; '
            'pass another with --name'
        )

        raise CommandError(message)

    if len(name) > NAME_BYTES_MAX:
        message = f'{name!r} is longer than {NAME_BYTES_MAX} bytes, the most Zig allows'
        raise CommandError(message)

    if keyword.iskeyword(name):
        message = f'{name!r} is a Python keyword, so it cannot name a module'
        raise CommandError(message)

    if name in ZIG_KEYWORDS:
        message = f'{name!r} is a Zig keyword, so it cannot name a Zig package'
        raise CommandError(message)


def output_of(out: str | None, root: Path) -> Path:
    if not isinstance(out, str | None):
        message = f'out must be a str or None, not {type(out).__name__}'
        raise TypeError(message)

    if not root.is_absolute():
        message = f'{root} must be absolute so that its dist directory is too'
        raise ValueError(message)

    if out is None:
        return root / 'dist'

    return Path(out).resolve()


def parser_build() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='lacuna',
        description='Create, build, and publish Python extension modules written in Zig.',
        allow_abbrev=False,
    )

    commands = parser.add_subparsers(dest='command', required=True, metavar='command')
    build = commands.add_parser('build', help='build a wheel for this Python', allow_abbrev=False)
    develop = commands.add_parser('develop', help='install as editable', allow_abbrev=False)
    new = commands.add_parser('new', help='create a project', allow_abbrev=False)
    publish = commands.add_parser('publish', help='build and run uv publish', allow_abbrev=False)
    sdist = commands.add_parser('sdist', help='build the source distribution', allow_abbrev=False)

    build.add_argument('--sdist', action='store_true', help='also build the source distribution')
    new.add_argument('path', help='the directory to create')
    new.add_argument('--name', help='the package name; defaults to the directory name')

    for command in (build, develop, publish, sdist):
        command.add_argument('--project', default='.', help='the project directory')

    for command in (build, publish, sdist):
        command.add_argument('--out', help='the output directory; defaults to PROJECT/dist')

    build.set_defaults(handler=command_build)
    develop.set_defaults(handler=command_develop)
    new.set_defaults(handler=command_new)
    publish.set_defaults(handler=command_publish)
    sdist.set_defaults(handler=command_sdist)

    return parser


def paths_report(paths: list[Path]) -> None:
    if not paths:
        message = 'a lacuna command reports at least one path it produced'
        raise ValueError(message)

    for path in paths:
        _ = sys.stdout.write(f'{path}\n')


def project_root(location: str) -> Path:
    if not Path(location).is_dir():
        message = f'{location} is not a directory; pass the project directory with --project'
        raise CommandError(message)

    root = Path(location).resolve()

    if not (root / 'pyproject.toml').is_file():
        message = f'{root} holds no pyproject.toml; pass the project directory with --project'
        raise CommandError(message)

    return root


def target_check(target: Path) -> None:
    if target.exists():
        if not target.is_dir():
            message = f'{target} already exists and is not an empty directory'
            raise CommandError(message)

    if target.is_dir():
        if any(target.iterdir()):
            message = f'{target} already exists and is not an empty directory'
            raise CommandError(message)


def template_render(*, relative: str, content: str, name: str, fingerprint: int) -> str:
    if relative.startswith('/'):
        message = f'the template path {relative} must be relative to the template'
        raise ValueError(message)

    if not isinstance(content, str):
        message = f'the template {relative} renders text, not {type(content).__name__}'
        raise TypeError(message)

    if not NAME_PATTERN.fullmatch(name):
        message = f'{name!r} is not a package name to render the template with'
        raise ValueError(message)

    if fingerprint >> 32 != zlib.crc32(name.encode('ascii')):
        message = f'the fingerprint 0x{fingerprint:016x} does not carry the checksum of {name}'
        raise ValueError(message)

    renamed = TEMPLATE_NAME_PATTERN.sub(name, content)

    if relative != TEMPLATE_MANIFEST:
        return renamed

    replacement = f'.fingerprint = 0x{fingerprint:016x},'
    rendered, count = FINGERPRINT_PATTERN.subn(replacement, renamed)

    if count != 1:
        message = f'the template {TEMPLATE_MANIFEST} holds {count} fingerprints, not one'
        raise CommandError(message)

    return rendered


def tree_files(root: Traversable) -> list[tuple[str, Traversable]]:
    if not root.is_dir():
        message = f'lacuna_build carries no {root.name} directory; install it from its wheel'
        raise CommandError(message)

    result: list[tuple[str, Traversable]] = []
    pending = [('', root)]

    for _ in range(TREE_DIRECTORY_COUNT_MAX):
        if not pending:
            break

        prefix, current = pending.pop()

        for child in current.iterdir():
            relative = f'{prefix}{child.name}'

            if child.name in archive.EXCLUDED_NAMES:
                continue

            if child.name.endswith('.pyc'):
                continue

            if child.is_dir():
                directory = (f'{relative}/', child)
                pending.append(directory)
            else:
                file = (relative, child)
                result.append(file)

    if pending:
        message = f'lacuna_build {root.name} holds more than {TREE_DIRECTORY_COUNT_MAX} directories'
        raise CommandError(message)

    return result


if __name__ == '__main__':
    sys.exit(main())
