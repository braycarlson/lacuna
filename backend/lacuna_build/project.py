import functools
import importlib.util
import os
import posixpath
import re
import shlex
import shutil
import subprocess
import sys
import sysconfig
import tomllib

from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from types import MappingProxyType

from lacuna_build import archive, zon


ABI3T_VERSION = (3, 15)
BUILD_ARGUMENTS_KEY = 'build-args'
CROSS_SYSTEMS = frozenset({'android', 'ios'})
DEPENDENCY_DIRECTORY_PATTERN = re.compile(r'[A-Za-z0-9_][A-Za-z0-9_.-]*')
ENTRY_POINT_GROUP_KEYS = MappingProxyType(
    {'console_scripts': 'scripts', 'gui_scripts': 'gui-scripts'},
)
ENTRY_POINT_SECTION_PATTERN = re.compile(r'^\[([^\]]+)\]$', re.MULTILINE)
EXTENSION_PATTERN = re.compile(r'^  wheel-host:(\S+)', re.MULTILINE)
EXTRA_MARKER_PATTERN = re.compile(r'\bextra\s*==')
METADATA_FIELD_KEYS = MappingProxyType(
    {
        'Author': 'authors',
        'Author-email': 'authors',
        'Classifier': 'classifiers',
        'Description-Content-Type': 'readme',
        'Keywords': 'keywords',
        'License': 'license',
        'License-Expression': 'license',
        'License-File': 'license-files',
        'Maintainer': 'maintainers',
        'Maintainer-email': 'maintainers',
        'Project-URL': 'urls',
        'Provides-Extra': 'optional-dependencies',
        'Requires-Python': 'requires-python',
        'Summary': 'description',
        'Version': 'version',
    },
)
HOST_PREFIXES = frozenset({'develop', 'wheel-host'})
NAME_PATTERN = re.compile(r'[-_.]+')
OUTPUT_LINE_COUNT_MAX = 4096
PLATFORM_SEPARATOR_PATTERN = re.compile(r'[-. ]')
PROJECT_KEYS_ALLOWED = frozenset({'dynamic', 'name', 'version'})
PROJECT_KEYS_DYNAMIC = frozenset(
    {
        'authors',
        'classifiers',
        'dependencies',
        'description',
        'entry-points',
        'gui-scripts',
        'import-names',
        'import-namespaces',
        'keywords',
        'license',
        'license-files',
        'maintainers',
        'optional-dependencies',
        'readme',
        'requires-python',
        'scripts',
        'urls',
        'version',
    },
)
SDIST_EXCLUDE_KEY = 'sdist-exclude'
SDIST_INCLUDE_KEY = 'sdist-include'
STEP_PATTERN = re.compile(r'^  (\S+)', re.MULTILINE)
VENDOR_COUNT_MAX = 32
VENDOR_DEPTH_MAX = 8
VENDOR_DIRECTORY = 'vendor'
VENDOR_PATH_PARTS_MIN = 3
WHEEL_PLATFORM_FLAG = '-Dwheel-platform='
ZIG_VARIABLE = 'LACUNA_ZIG'


class ProjectError(RuntimeError):
    pass


@dataclass(frozen=True)
class Edge:
    location: str
    name: str
    source: Path
    target: Path


@dataclass(frozen=True)
class SdistLayout:
    files: tuple[tuple[str, bytes], ...]
    manifests: tuple[tuple[str, str], ...]


@dataclass(frozen=True)
class Project:
    build_arguments: tuple[str, ...]
    dynamic: tuple[str, ...]
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

    def zig_version(self) -> str:
        version = self.manifest.get('minimum_zig_version')

        if not isinstance(version, str):
            message = 'build.zig.zon must declare .minimum_zig_version'
            raise ProjectError(message)

        return version


def name_normalize(name: str) -> str:
    if not isinstance(name, str):
        message = f'a project name must be a string, not {name!r}'
        raise ProjectError(message)

    return NAME_PATTERN.sub('-', name).lower()


def build_arguments_of(config_settings: dict | None) -> tuple[str, ...]:
    if not isinstance(config_settings, dict | None):
        message = f'config_settings must be a dict or None, not {type(config_settings).__name__}'
        raise TypeError(message)

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


def cross_arguments(build_arguments: tuple[str, ...]) -> tuple[str, ...]:
    if not isinstance(build_arguments, tuple):
        message = f'the build arguments are a tuple, not {type(build_arguments).__name__}'
        raise TypeError(message)

    return cross_arguments_chosen(
        build_arguments=build_arguments,
        platform=sysconfig.get_platform(),
        system=sys.platform,
    )


def cross_arguments_chosen(
    *,
    build_arguments: tuple[str, ...],
    platform: str,
    system: str,
) -> tuple[str, ...]:
    if not isinstance(build_arguments, tuple):
        message = f'the build arguments are a tuple, not {type(build_arguments).__name__}'
        raise TypeError(message)

    if not platform:
        message = 'sysconfig reports no platform to build the wheel for'
        raise ProjectError(message)

    if not system:
        message = 'sys.platform names no system to build the wheel for'
        raise ProjectError(message)

    if system not in CROSS_SYSTEMS:
        return ()

    if any(argument.startswith(WHEEL_PLATFORM_FLAG) for argument in build_arguments):
        return ()

    tag = PLATFORM_SEPARATOR_PATTERN.sub('_', platform)

    return (f'{WHEEL_PLATFORM_FLAG}{tag}',)


def project_table_check(table: dict[str, object]) -> None:
    if not isinstance(table, dict):
        message = 'pyproject.toml [project] must be a table'
        raise ProjectError(message)

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

    project_dynamic_check(table, dynamic)


def project_dynamic_check(table: dict[str, object], dynamic: list[str]) -> None:
    if not isinstance(table, dict):
        message = 'pyproject.toml [project] must be a table'
        raise ProjectError(message)

    if 'name' in dynamic:
        message = 'pyproject.toml [project] dynamic lists name, which must be static'
        raise ProjectError(message)

    unknown = sorted(set(dynamic) - PROJECT_KEYS_DYNAMIC)

    if unknown:
        hint = '; the summary is [project] description' if 'summary' in unknown else ''

        message = (
            f'pyproject.toml [project] dynamic lists {", ".join(unknown)}, which [project] '
            f'does not define{hint}'
        )

        raise ProjectError(message)

    duplicated = sorted(set(dynamic) & set(table))

    if duplicated:
        message = (
            f'pyproject.toml declares [project] {", ".join(duplicated)} and also lists it in '
            'dynamic'
        )

        raise ProjectError(message)


def project_load(root: Path, config_settings: dict | None = None) -> Project:
    if not (root / 'pyproject.toml').is_file():
        message = f'{root} holds no pyproject.toml'
        raise ProjectError(message)

    if not isinstance(config_settings, dict | None):
        message = f'config_settings must be a dict or None, not {type(config_settings).__name__}'
        raise TypeError(message)

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

    configured = build_arguments_of(config_settings)
    build_arguments = configured + cross_arguments(configured)
    extension = tool.get('extension') or extension_detect(root, build_arguments)

    return Project(
        build_arguments=build_arguments,
        dynamic=tuple(table.get('dynamic', [])),
        extension=extension,
        manifest=manifest,
        name=table['name'],
        root=root,
        sdist_exclude=globs_of(tool, SDIST_EXCLUDE_KEY),
        sdist_include=globs_of(tool, SDIST_INCLUDE_KEY),
        version=table.get('version'),
    )


def globs_of(tool: dict[str, object], key: str) -> tuple[str, ...]:
    if not isinstance(tool, dict):
        message = 'pyproject.toml [tool.lacuna] must be a table'
        raise ProjectError(message)

    if key not in (SDIST_EXCLUDE_KEY, SDIST_INCLUDE_KEY):
        message = f'{key!r} is not a [tool.lacuna] glob setting'
        raise ValueError(message)

    value = tool.get(key, [])
    message = f'pyproject.toml [tool.lacuna] {key} must be a list of glob strings'

    if not isinstance(value, list):
        raise ProjectError(message)

    if not all(isinstance(pattern, str) for pattern in value):
        raise ProjectError(message)

    return tuple(value)


def extension_detect(root: Path, build_arguments: tuple[str, ...]) -> str:
    if not root.is_dir():
        message = f'{root} is not a directory to run zig build in'
        raise ValueError(message)

    if not isinstance(build_arguments, tuple):
        message = f'build_arguments must be a tuple, not {type(build_arguments).__name__}'
        raise TypeError(message)

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
    if not (root / 'build.zig.zon').is_file():
        message = f'{root / "build.zig.zon"} is missing; lacuna_build builds Zig packages'
        raise ProjectError(message)

    if zig_command() is not None:
        return []

    manifest = zon.parse((root / 'build.zig.zon').read_text(encoding='utf-8'))
    version = manifest.get('minimum_zig_version')

    if not isinstance(version, str):
        message = 'build.zig.zon must declare .minimum_zig_version'
        raise ProjectError(message)

    return [f'ziglang=={version}']


def zig_invocation(arguments: list[str]) -> list[str]:
    if not arguments:
        message = 'zig build needs a step or a flag from lacuna_build'
        raise ValueError(message)

    command = zig_command()

    if command is None:
        message = f'no Zig compiler found; install ziglang or set {ZIG_VARIABLE}'
        raise ProjectError(message)

    return [*command, 'build', *arguments]


def zig_check(invocation: list[str], completed: subprocess.CompletedProcess[str]) -> None:
    if completed.args != invocation:
        message = f'{completed.args} is not the result of {invocation}'
        raise ValueError(message)

    if completed.returncode == 0:
        return

    detail = completed.stderr or ''
    message = f'{" ".join(invocation)} failed with status {completed.returncode}\n{detail}'

    raise ProjectError(message)


def zig_output(root: Path, arguments: list[str]) -> str:
    if not root.is_dir():
        message = f'{root} is not a directory to run zig build in'
        raise ValueError(message)

    if not arguments:
        message = 'zig build needs a step or a flag from lacuna_build'
        raise ValueError(message)

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
    if not root.is_dir():
        message = f'{root} is not a directory to run zig build in'
        raise ValueError(message)

    if not arguments:
        message = 'zig build needs a step or a flag from lacuna_build'
        raise ValueError(message)

    invocation = zig_invocation(arguments)
    completed = subprocess.run(invocation, check=False, cwd=root, text=True)

    zig_check(invocation, completed)


def interpreter_suffix() -> str:
    major, minor = sys.version_info[:2]

    if sys.implementation.name == 'pypy':
        return f'-pypy{major}.{minor}'

    if sys.implementation.name == 'graalpy':
        return f'-graalpy{major}.{minor}'

    if not sysconfig.get_config_var('Py_GIL_DISABLED'):
        return ''

    return f'-{major}.{minor}t'


def graalpy_abi_of(cache_tag: str) -> str:
    if not isinstance(cache_tag, str):
        message = f'a cache tag is a string, not {type(cache_tag).__name__}'
        raise TypeError(message)

    name, _, _ = cache_tag.partition('-')
    abi = name.removeprefix('graalpy')
    message = f'GraalPy reports the cache tag {cache_tag!r}, not graalpy<abi>-<version>'

    if not name.startswith('graalpy'):
        raise ProjectError(message)

    if not abi.isdigit():
        raise ProjectError(message)

    return abi


def host_suffix(project: Project, *, prefix: str) -> str:
    if not isinstance(project, Project):
        message = f'host_suffix reads a Project, not {type(project).__name__}'
        raise TypeError(message)

    if prefix not in HOST_PREFIXES:
        message = f'{prefix!r} is not a host step prefix of the lacuna build'
        raise ValueError(message)

    return host_suffix_chosen(
        extension=project.extension,
        prefix=prefix,
        steps=steps_listed(project.root, project.build_arguments),
        suffix=interpreter_suffix(),
        version=(sys.version_info.major, sys.version_info.minor),
    )


def host_suffix_chosen(
    *,
    extension: str,
    prefix: str,
    steps: frozenset[str],
    suffix: str,
    version: tuple[int, int],
) -> str:
    if prefix not in HOST_PREFIXES:
        message = f'{prefix!r} is not a host step prefix of the lacuna build'
        raise ValueError(message)

    if not extension:
        message = 'a host step builds a named extension'
        raise ValueError(message)

    if not isinstance(steps, frozenset):
        message = f'the listed steps are a frozenset, not {type(steps).__name__}'
        raise TypeError(message)

    if suffix[:1] not in ('', '-'):
        message = f'an interpreter suffix starts with a hyphen, not {suffix!r}'
        raise ValueError(message)

    if len(version) != len(ABI3T_VERSION):
        message = f'a Python version is a (major, minor) pair, not {version!r}'
        raise ValueError(message)

    if not suffix.endswith('t'):
        return suffix

    if version < ABI3T_VERSION:
        return suffix

    if f'{prefix}{suffix}:{extension}' in steps:
        return suffix

    if f'{prefix}-abi3t:{extension}' in steps:
        return '-abi3t'

    return suffix


@functools.cache
def steps_listed(root: Path, build_arguments: tuple[str, ...]) -> frozenset[str]:
    if not root.is_dir():
        message = f'{root} is not a project directory to list build steps from'
        raise ValueError(message)

    if not isinstance(build_arguments, tuple):
        message = f'the build arguments are a tuple, not {type(build_arguments).__name__}'
        raise TypeError(message)

    listing = zig_output(root, ['-l', *build_arguments])

    return frozenset(STEP_PATTERN.findall(listing))


def step_require(project: Project, *, step: str, suffix: str) -> None:
    if not step.endswith(f':{project.extension}'):
        message = f'the step {step} does not build the extension {project.extension}'
        raise ValueError(message)

    if suffix not in step:
        message = f'the step {step} does not carry the interpreter suffix {suffix}'
        raise ValueError(message)

    if step in steps_listed(project.root, project.build_arguments):
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

    if suffix.startswith('-graalpy'):
        version = suffix.removeprefix('-graalpy')
        major, _, minor = version.partition('.')
        abi = graalpy_abi_of(sys.implementation.cache_tag or '')

        message = (
            f'GraalPy {version} needs a GraalPy build, but build.zig builds none for it; add '
            f'.{{ .abi = "{abi}", .version = .{{ .major = {major}, .minor = {minor} }} }} to '
            'the graalpy option of add_extension, or build with CPython'
        )

        raise ProjectError(message)

    version = suffix.removeprefix('-').removesuffix('t')
    major, _, minor = version.partition('.')

    message = (
        f'Python {version}t is free-threaded but build.zig builds no free-threaded extension '
        f'for it; add .{{ .major = {major}, .minor = {minor} }} to the free_threaded option '
        'of add_extension, keep .abi3t = true there for Python 3.15 and later, or build with '
        'a Python that has the GIL'
    )

    raise ProjectError(message)


def step_output(project: Project, *, step: str, directory: str) -> Path:
    if not step.endswith(f':{project.extension}'):
        message = f'the step {step} does not build the extension {project.extension}'
        raise ValueError(message)

    if directory not in ('dist', 'metadata'):
        message = f'{directory!r} is not an install directory of the lacuna build steps'
        raise ValueError(message)

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
    if not directory.is_dir():
        message = f'{directory} is not a directory to look for {pattern} in'
        raise ValueError(message)

    if Path(pattern).name != pattern:
        message = f'{pattern} must match entries directly inside {directory}'
        raise ValueError(message)

    found = sorted(directory.glob(pattern))

    if len(found) != 1:
        message = f'expected one {pattern} in {directory}, found {len(found)}'
        raise ProjectError(message)

    return found[0]


def metadata_build(project: Project) -> Path:
    if not project.extension:
        message = f'the project {project.name} names no extension to build the metadata of'
        raise ValueError(message)

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

    if project.version is not None:
        if fields.get('Version') != project.version:
            message = (
                f'pyproject.toml gives version {project.version} but build.zig gives '
                f'{fields.get("Version")}'
            )

            raise ProjectError(message)

    undeclared = metadata_undeclared(project, directory)

    if undeclared:
        message = (
            f'build.zig fills [project] {", ".join(undeclared)}, so pyproject.toml must list '
            f'{"it" if len(undeclared) == 1 else "them"} in [project] dynamic'
        )

        raise ProjectError(message)

    return directory


def metadata_undeclared(project: Project, directory: Path) -> list[str]:
    if not isinstance(project, Project):
        message = f'project must be a Project, not {type(project).__name__}'
        raise TypeError(message)

    if not (directory / 'METADATA').is_file():
        message = f'{directory} holds no METADATA'
        raise ValueError(message)

    declared = set(project.dynamic)

    if project.version is not None:
        declared.add('version')

    return sorted(project_keys_filled(directory) - declared)


def project_keys_filled(directory: Path) -> set[str]:
    if not (directory / 'METADATA').is_file():
        message = f'{directory} holds no METADATA'
        raise ValueError(message)

    metadata = (directory / 'METADATA').read_text(encoding='utf-8')
    header, _, body = metadata.partition('\n\n')
    result = {'readme'} if body.strip() else set()

    for line in header.splitlines()[:OUTPUT_LINE_COUNT_MAX]:
        field, _, value = line.partition(': ')
        key = project_key_of(field=field, value=value)

        if key is not None:
            result.add(key)

    entry_points = directory / 'entry_points.txt'

    if entry_points.is_file():
        text = entry_points.read_text(encoding='utf-8')
        groups = ENTRY_POINT_SECTION_PATTERN.findall(text)

        result.update(ENTRY_POINT_GROUP_KEYS.get(group, 'entry-points') for group in groups)

    return result


def project_key_of(*, field: str, value: str) -> str | None:
    if not isinstance(field, str):
        message = f'a METADATA field name must be a string, not {field!r}'
        raise TypeError(message)

    if not isinstance(value, str):
        message = f'a METADATA field value must be a string, not {value!r}'
        raise TypeError(message)

    if field != 'Requires-Dist':
        return METADATA_FIELD_KEYS.get(field)

    marker = value.partition(';')[2]

    if EXTRA_MARKER_PATTERN.search(marker):
        return 'optional-dependencies'

    return 'dependencies'


def metadata_fields(metadata: str) -> dict[str, str]:
    if not metadata.startswith('Metadata-Version: '):
        message = 'a METADATA file starts with its Metadata-Version field'
        raise ValueError(message)

    result: dict[str, str] = {}

    for line in metadata.splitlines()[:OUTPUT_LINE_COUNT_MAX]:
        if not line:
            break

        key, _, value = line.partition(': ')

        if key not in result:
            result[key] = value

    return result


def path_dependencies(manifest: dict[str, object]) -> list[tuple[str, str]]:
    if not isinstance(manifest, dict):
        message = f'a build.zig.zon manifest is a struct, not {type(manifest).__name__}'
        raise TypeError(message)

    dependencies = manifest.get('dependencies', {})

    if not dependencies:
        return []

    if not isinstance(dependencies, dict):
        message = 'build.zig.zon gives .dependencies as something other than a struct'
        raise ProjectError(message)

    result: list[tuple[str, str]] = []

    for name, dependency in sorted(dependencies.items()):
        if not isinstance(dependency, dict):
            continue

        location = dependency.get('path')

        if location is None:
            continue

        if not isinstance(location, str):
            message = f'build.zig.zon gives the .path of .{name} as something other than a string'
            raise ProjectError(message)

        pair = (name, location)
        result.append(pair)

    return result


def manifest_of(root: Path) -> dict[str, object]:
    if not root.is_dir():
        message = f'the path dependency at {root} is not a directory'
        raise ProjectError(message)

    manifest = root / 'build.zig.zon'

    if not manifest.is_file():
        message = f'the path dependency at {root} holds no build.zig.zon'
        raise ProjectError(message)

    return zon.parse(manifest.read_text(encoding='utf-8'))


def edges_reached(root: Path, manifest: dict[str, object]) -> list[Edge]:
    if not root.is_absolute():
        message = f'the project root {root} must be resolved before its dependencies are walked'
        raise ValueError(message)

    if not isinstance(manifest, dict):
        message = f'a build.zig.zon manifest is a struct, not {type(manifest).__name__}'
        raise TypeError(message)

    edges: list[Edge] = []
    visited = {root}
    pending = [(root, manifest, 0)]

    for _ in range(VENDOR_COUNT_MAX + 1):
        if not pending:
            break

        package, current, depth = pending.pop(0)

        for name, location in path_dependencies(current):
            target = (package / location).resolve()
            edge = Edge(location=location, name=name, source=package, target=target)
            edges.append(edge)

            if target in visited:
                continue

            if depth == VENDOR_DEPTH_MAX:
                message = f'the path dependencies nest deeper than {VENDOR_DEPTH_MAX} packages'
                raise ProjectError(message)

            visited.add(target)
            pending.append((target, manifest_of(target), depth + 1))

    if pending:
        message = f'the project reaches more than {VENDOR_COUNT_MAX} path dependencies'
        raise ProjectError(message)

    return edges


def vendor_directories(root: Path, edges: list[Edge]) -> dict[Path, str]:
    if not root.is_absolute():
        message = f'the project root {root} must be resolved before packages are vendored'
        raise ValueError(message)

    if len(edges) > VENDOR_COUNT_MAX * VENDOR_COUNT_MAX:
        message = f'the project reaches more than {VENDOR_COUNT_MAX} path dependencies'
        raise ProjectError(message)

    result: dict[Path, str] = {}

    for edge in edges:
        if edge.target.is_relative_to(root):
            continue

        if edge.target in result:
            continue

        bare = edge.name.removeprefix('@"').removesuffix('"')

        if not DEPENDENCY_DIRECTORY_PATTERN.fullmatch(bare):
            message = f'the path dependency .{edge.name} has no name usable as a directory'
            raise ProjectError(message)

        if bare in result.values():
            message = (
                f'two path dependencies outside the project are named .{edge.name}; '
                'rename one in build.zig.zon so each gets its own vendor directory'
            )

            raise ProjectError(message)

        result[edge.target] = bare

    return result


def sdist_location(*, directories: dict[Path, str], package: Path, root: Path) -> PurePosixPath:
    if not package.is_absolute():
        message = f'a package location is computed from a resolved path, not {package}'
        raise ValueError(message)

    if not root.is_absolute():
        message = f'the project root {root} must be resolved before packages are placed'
        raise ValueError(message)

    if len(directories) > VENDOR_COUNT_MAX:
        message = f'the project vendors more than {VENDOR_COUNT_MAX} path dependencies'
        raise ValueError(message)

    if package in directories:
        return PurePosixPath(VENDOR_DIRECTORY, directories[package])

    if not package.is_relative_to(root):
        message = f'{package} lies outside the project and was never vendored'
        raise ValueError(message)

    return PurePosixPath(package.relative_to(root).as_posix())


def sdist_layout(current: Project) -> SdistLayout:
    if not isinstance(current, Project):
        message = f'sdist_layout lays out a Project, not {type(current).__name__}'
        raise TypeError(message)

    root = current.root.resolve()
    edges = edges_reached(root, current.manifest)
    directories = vendor_directories(root, edges)
    replacements: dict[Path, dict[str, str]] = {}

    for edge in edges:
        if edge.source not in directories:
            if edge.target not in directories:
                continue

        source = sdist_location(directories=directories, package=edge.source, root=root)
        target = sdist_location(directories=directories, package=edge.target, root=root)
        relative = posixpath.relpath(target.as_posix(), source.as_posix())

        replacements.setdefault(edge.source, {})[edge.name] = relative

    manifests: list[tuple[str, str]] = []

    for package, replaced in sorted(replacements.items()):
        source = (package / 'build.zig.zon').read_text(encoding='utf-8')
        location = sdist_location(directories=directories, package=package, root=root)
        rewritten = zon.dependency_paths_rewrite(source, replaced)
        entry = ((location / 'build.zig.zon').as_posix(), rewritten)
        manifests.append(entry)

    files: list[tuple[str, bytes]] = []

    for package, directory in sorted(directories.items()):
        files.extend(vendored_files(package=package, directory=directory))

    return SdistLayout(files=tuple(files), manifests=tuple(manifests))


def vendored_files(*, directory: str, package: Path) -> list[tuple[str, bytes]]:
    if not DEPENDENCY_DIRECTORY_PATTERN.fullmatch(directory):
        message = f'{directory!r} is not a vendor directory name'
        raise ValueError(message)

    if not package.is_absolute():
        message = f'a vendored package is read from a resolved path, not {package}'
        raise ValueError(message)

    listed = ['build.zig.zon', *manifest_paths(manifest_of(package))]
    selected = archive.files_under(package, listed)
    prefix = PurePosixPath(VENDOR_DIRECTORY, directory)

    return [
        ((prefix / path.relative_to(package).as_posix()).as_posix(), path.read_bytes())
        for path in selected
    ]


def manifest_paths(manifest: dict[str, object]) -> list[str]:
    if not isinstance(manifest, dict):
        message = f'a build.zig.zon manifest is a struct, not {type(manifest).__name__}'
        raise TypeError(message)

    listed = manifest.get('paths', [])

    if not isinstance(listed, list):
        message = 'a path dependency lists the files of its package in .paths'
        raise ProjectError(message)

    return [str(path) for path in listed]


def sdist_files(
    files: list[tuple[str, bytes]],
    layout: SdistLayout,
) -> list[tuple[str, bytes]]:
    if not isinstance(layout, SdistLayout):
        message = f'sdist_files applies an SdistLayout, not {type(layout).__name__}'
        raise TypeError(message)

    if not isinstance(files, list):
        message = f'sdist_files takes the project files as a list, not {type(files).__name__}'
        raise TypeError(message)

    vendored = {vendor_directory_of(name) for name, _ in layout.files}

    for name, _ in files:
        directory = vendor_directory_of(name)

        if directory is not None:
            if directory in vendored:
                message = (
                    f'the sdist vendors a path dependency at {VENDOR_DIRECTORY}/{directory}, '
                    f'where the project already keeps {name}'
                )

                raise ProjectError(message)

    result = dict(files)
    result.update(layout.files)

    for name, text in layout.manifests:
        if name not in result:
            message = f'the sdist rewrites {name}, which it does not carry'
            raise ProjectError(message)

        result[name] = text.encode('utf-8')

    return sorted(result.items())


def vendor_directory_of(name: str) -> str | None:
    if not name:
        message = 'an sdist entry always has a name'
        raise ValueError(message)

    parts = name.split('/')

    if len(parts) < VENDOR_PATH_PARTS_MIN:
        return None

    if parts[0] != VENDOR_DIRECTORY:
        return None

    return parts[1]
