import importlib.util
import os
import re
import shlex
import shutil
import subprocess
import sys
import sysconfig
import tomllib

from dataclasses import dataclass
from pathlib import Path

from lacuna_build import zon


BUILD_ARGUMENTS_KEY = 'build-args'
EXTENSION_PATTERN = re.compile(r'^  wheel-host:(\S+)', re.MULTILINE)
NAME_PATTERN = re.compile(r'[-_.]+')
OUTPUT_LINE_COUNT_MAX = 4096
PROJECT_KEYS_ALLOWED = frozenset({'dynamic', 'name', 'version'})
SDIST_EXCLUDE_KEY = 'sdist-exclude'
SDIST_INCLUDE_KEY = 'sdist-include'
STEP_PATTERN = re.compile(r'^  (\S+)', re.MULTILINE)
ZIG_VARIABLE = 'LACUNA_ZIG'


class ProjectError(RuntimeError):
    pass


@dataclass(frozen=True)
class Project:
    build_arguments: tuple[str, ...]
    extension: str
    manifest: dict[str, object]
    name: str
    root: Path
    sdist_exclude: tuple[str, ...]
    sdist_include: tuple[str, ...]
    version: str | None

    def paths(self) -> list[str]:
        listed = self.manifest.get('paths', [])
        message = 'build.zig.zon must list the files of the package in .paths'

        if not isinstance(listed, list):
            raise ProjectError(message)

        if not listed:
            raise ProjectError(message)

        return [str(path) for path in listed]

    def dependencies_outside(self) -> list[str]:
        dependencies = self.manifest.get('dependencies', {})

        if not isinstance(dependencies, dict):
            return []

        result: list[str] = []

        for name, dependency in dependencies.items():
            if not isinstance(dependency, dict):
                continue

            location = dependency.get('path')

            if location is None:
                continue

            resolved = (self.root / str(location)).resolve()

            if not resolved.is_relative_to(self.root.resolve()):
                result.append(f'{name} at {location}')

        return result

    def zig_version(self) -> str:
        version = self.manifest.get('minimum_zig_version')

        if not isinstance(version, str):
            message = 'build.zig.zon must declare .minimum_zig_version'
            raise ProjectError(message)

        return version


def name_normalize(name: str) -> str:
    return NAME_PATTERN.sub('-', name).lower()


def build_arguments_of(config_settings: dict | None) -> tuple[str, ...]:
    if not config_settings:
        return ()

    unknown = sorted(set(config_settings) - {BUILD_ARGUMENTS_KEY})

    if unknown:
        message = (
            f'lacuna_build accepts only the {BUILD_ARGUMENTS_KEY!r} config setting, '
            f'not {", ".join(map(repr, unknown))}'
        )

        raise ProjectError(message)

    value = config_settings.get(BUILD_ARGUMENTS_KEY, [])

    if isinstance(value, str):
        return tuple(shlex.split(value))

    message = f'the {BUILD_ARGUMENTS_KEY!r} config setting must be a string or a list of strings'

    if not isinstance(value, list):
        raise ProjectError(message)

    if not all(isinstance(item, str) for item in value):
        raise ProjectError(message)

    return tuple(argument for item in value for argument in shlex.split(item))


def project_table_check(table: dict[str, object]) -> None:
    unknown = sorted(set(table) - PROJECT_KEYS_ALLOWED)

    if unknown:
        message = (
            f'pyproject.toml declares [project] {", ".join(unknown)}, which lacuna_build takes '
            'from the Package of add_extension in build.zig; move them there and list them in '
            '[project] dynamic'
        )

        raise ProjectError(message)

    dynamic = table.get('dynamic', [])

    message = 'pyproject.toml [project] dynamic must be a list of strings'

    if not isinstance(dynamic, list):
        raise ProjectError(message)

    if not all(isinstance(item, str) for item in dynamic):
        raise ProjectError(message)

    if 'version' not in dynamic:
        return

    if 'version' in table:
        message = 'pyproject.toml declares [project] version and also lists it in dynamic'
        raise ProjectError(message)


def project_load(root: Path, config_settings: dict | None = None) -> Project:
    pyproject = root / 'pyproject.toml'
    manifest_path = root / 'build.zig.zon'

    if not manifest_path.is_file():
        message = f'{manifest_path} is missing; lacuna_build builds Zig packages'
        raise ProjectError(message)

    configuration = tomllib.loads(pyproject.read_text(encoding='utf-8'))
    table = configuration.get('project', {})
    tool = configuration.get('tool', {}).get('lacuna', {})
    manifest = zon.parse(manifest_path.read_text(encoding='utf-8'))

    if 'name' not in table:
        message = 'pyproject.toml must declare [project] name'
        raise ProjectError(message)

    project_table_check(table)

    build_arguments = build_arguments_of(config_settings)
    extension = tool.get('extension') or extension_detect(root, build_arguments)

    return Project(
        build_arguments=build_arguments,
        extension=extension,
        manifest=manifest,
        name=table['name'],
        root=root,
        sdist_exclude=globs_of(tool, SDIST_EXCLUDE_KEY),
        sdist_include=globs_of(tool, SDIST_INCLUDE_KEY),
        version=table.get('version'),
    )


def globs_of(tool: dict[str, object], key: str) -> tuple[str, ...]:
    value = tool.get(key, [])
    message = f'pyproject.toml [tool.lacuna] {key} must be a list of glob strings'

    if not isinstance(value, list):
        raise ProjectError(message)

    if not all(isinstance(pattern, str) for pattern in value):
        raise ProjectError(message)

    return tuple(value)


def extension_detect(root: Path, build_arguments: tuple[str, ...]) -> str:
    listing = zig_output(root, ['-l', *build_arguments])
    found = EXTENSION_PATTERN.findall(listing)

    if len(found) == 1:
        return found[0]

    message = (
        'set [tool.lacuna] extension in pyproject.toml; build.zig declares '
        f'{len(found)} extensions: {", ".join(found) or "none"}'
    )

    raise ProjectError(message)


def zig_command() -> list[str] | None:
    explicit = os.environ.get(ZIG_VARIABLE)

    if explicit:
        return [explicit]

    found = shutil.which('zig')

    if found is not None:
        return [found]

    if importlib.util.find_spec('ziglang') is not None:
        return [sys.executable, '-m', 'ziglang']

    return None


def zig_requirements(root: Path) -> list[str]:
    if zig_command() is not None:
        return []

    manifest = zon.parse((root / 'build.zig.zon').read_text(encoding='utf-8'))
    version = manifest.get('minimum_zig_version')

    if not isinstance(version, str):
        message = 'build.zig.zon must declare .minimum_zig_version'
        raise ProjectError(message)

    return [f'ziglang=={version}']


def zig_invocation(arguments: list[str]) -> list[str]:
    command = zig_command()

    if command is None:
        message = f'no Zig compiler found; install ziglang or set {ZIG_VARIABLE}'
        raise ProjectError(message)

    return [*command, 'build', *arguments]


def zig_check(invocation: list[str], completed: subprocess.CompletedProcess[str]) -> None:
    if completed.returncode == 0:
        return

    detail = completed.stderr or ''
    message = f'{" ".join(invocation)} failed with status {completed.returncode}\n{detail}'

    raise ProjectError(message)


def zig_output(root: Path, arguments: list[str]) -> str:
    invocation = zig_invocation(arguments)

    completed = subprocess.run(
        invocation,
        check=False,
        cwd=root,
        capture_output=True,
        text=True,
    )

    zig_check(invocation, completed)

    return completed.stdout


def zig_run(root: Path, arguments: list[str]) -> None:
    invocation = zig_invocation(arguments)
    completed = subprocess.run(invocation, check=False, cwd=root, text=True)

    zig_check(invocation, completed)


def interpreter_suffix() -> str:
    major, minor = sys.version_info[:2]

    if sys.implementation.name == 'pypy':
        return f'-pypy{major}.{minor}'

    if not sysconfig.get_config_var('Py_GIL_DISABLED'):
        return ''

    return f'-{major}.{minor}t'


def step_require(project: Project, *, step: str, suffix: str) -> None:
    listing = zig_output(project.root, ['-l', *project.build_arguments])

    if step in STEP_PATTERN.findall(listing):
        return

    if not suffix:
        message = f'build.zig declares no {step} step'
        raise ProjectError(message)

    if suffix.startswith('-pypy'):
        version = suffix.removeprefix('-pypy')
        major, _, minor = version.partition('.')

        message = (
            f'PyPy {version} needs a PyPy build, but build.zig builds none for it; add '
            f'.{{ .abi = "pp80", .version = .{{ .major = {major}, .minor = {minor} }} }} to the '
            'pypy option of add_extension, or build with CPython'
        )

        raise ProjectError(message)

    version = suffix.removeprefix('-').removesuffix('t')
    major, _, minor = version.partition('.')

    message = (
        f'Python {version}t is free-threaded but build.zig builds no free-threaded extension '
        f'for it; add .{{ .major = {major}, .minor = {minor} }} to the free_threaded option '
        'of add_extension, or build with a Python that has the GIL'
    )

    raise ProjectError(message)


def step_output(project: Project, *, step: str, directory: str) -> Path:
    name = NAME_PATTERN.sub('_', step).replace(':', '_')
    prefix = project.root / 'zig-out' / 'lacuna-backend' / name

    if prefix.exists():
        shutil.rmtree(prefix)

    zig_run(project.root, [step, '--prefix', str(prefix), *project.build_arguments])

    output = prefix / directory

    if not output.is_dir():
        message = f'zig build {step} produced no {directory} directory'
        raise ProjectError(message)

    return output


def single_entry(directory: Path, pattern: str) -> Path:
    found = sorted(directory.glob(pattern))

    if len(found) != 1:
        message = f'expected one {pattern} in {directory}, found {len(found)}'
        raise ProjectError(message)

    return found[0]


def metadata_build(project: Project) -> Path:
    step = f'metadata:{project.extension}'
    output = step_output(project, step=step, directory='metadata')
    directory = single_entry(output, '*.dist-info')
    metadata = (directory / 'METADATA').read_text(encoding='utf-8')
    fields = metadata_fields(metadata)

    if name_normalize(fields.get('Name', '')) != name_normalize(project.name):
        message = (
            f'pyproject.toml names the project {project.name} but build.zig names it '
            f'{fields.get("Name")}'
        )

        raise ProjectError(message)

    if project.version is None:
        return directory

    if fields.get('Version') != project.version:
        message = (
            f'pyproject.toml gives version {project.version} but build.zig gives '
            f'{fields.get("Version")}'
        )

        raise ProjectError(message)

    return directory


def metadata_fields(metadata: str) -> dict[str, str]:
    result: dict[str, str] = {}

    for line in metadata.splitlines()[:OUTPUT_LINE_COUNT_MAX]:
        if not line:
            break

        key, _, value = line.partition(': ')

        if key not in result:
            result[key] = value

    return result
