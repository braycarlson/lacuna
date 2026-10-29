import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
import zlib

import pytest

from collections.abc import Iterator
from pathlib import Path

import lacuna_build_paths


LACUNA_FILES = ('LICENSE', 'build.zig', 'build.zig.zon', 'src', 'tools')
FINGERPRINT = '0x3dc4b1addfd22072'
FINGERPRINT_SUGGESTED = re.compile(r'use this value: (0x[0-9a-f]+)')
PUBLISH_URL = 'http://127.0.0.1:9/legacy/'
PYTHON_REFERENCE = '3.14+gil'
PYTHON_WHEEL_MIN = (3, 12)
ZIG_KEYWORD = re.compile(r'\.\{ "(\w+)", \.keyword_\w+ \}')
ZIG_STD_DIRECTORY = re.compile(r'\.std_dir = "([^"]+)"')

BUILD_ZIG = """const std = @import("std");

const lacuna = @import("lacuna");

pub fn build(builder: *std.Build) void {
    const license_files = [_]lacuna.LicenseFile{
        .{ .name = "LICENSE", .path = builder.path("LICENSE") },
    };
    const scripts = [_]lacuna.EntryPoint{.{ .name = "greet", .target = "greeter:cli" }};
    const extension = lacuna.add_extension(builder, .{
        .free_threaded = &.{},
        .module = builder.createModule(.{ .root_source_file = builder.path("src/greeter.zig") }),
        .name = "greeter",
        .optimize = builder.standardOptimizeOption(.{ .preferred_optimize_mode = null }),
        .package = .{
            .license = .{ .expression = "MIT", .files = &license_files },
            .name = "greeter",
            .scripts = &scripts,
            .summary = "A greeter built by lacuna_build.",
            .version = "0.2.0",
        },
        .platforms = &lacuna.platforms,
        .strip = false,
        .target = builder.standardTargetOptions(.{ .whitelist = null, .default_target = .{} }),
    });

    _ = extension;
}
"""

FAILED_PROBE = """
from lacuna_build import import_hook

import_hook.install()

try:
    import greeter
except ImportError as error:
    print(error)
"""

GREETER_ZIG = """const lacuna = @import("lacuna");

pub const module: lacuna.Module = .{
    .name = "greeter",
    .functions = Functions,
    .thread_safe = true,
};

const Functions = struct {
    pub fn word() []const u8 {
        return "WORD";
    }
};
"""

GREETER_NATIVE_ZIG = """const lacuna = @import("lacuna");

pub const module: lacuna.Module = .{
    .name = "greeter",
    .classes = &.{Registry},
    .functions = Functions,
    .thread_safe = true,
};

const Functions = struct {
    pub fn word() []const u8 {
        return "native";
    }
};

const Registry = struct {
    size: u32,

    pub const extends = lacuna.Native.dictionary;

    pub fn init(registry: *Registry) void {
        registry.* = .{ .size = 0 };
    }
};
"""

HOOKED_PROBE = """
from lacuna_build import import_hook

finder = import_hook.install()

import email.message
import greeter

print(greeter.word())
print(finder.find_spec('json'))
"""

METADATA_FIELDS = (
    'Maintainer-email: Lin <lin@example.com>',
    'Requires-Python: >=3.12',
    'Provides-Dist: greeter',
    'Obsoletes-Dist: greeter-c',
    'Description-Content-Type: text/markdown',
    'Dynamic: Requires-Dist',
)

METADATA_PACKAGE = """.summary = "A greeter built by lacuna_build.",
            .description = .{ .path = builder.path("README.md") },
            .dynamic = &.{"Requires-Dist"},
            .maintainers = &.{.{ .email = "lin@example.com", .name = "Lin" }},
            .obsoletes = &.{"greeter-c"},
            .provides = &.{"greeter"},
            .requires_python = "REQUIRES","""

MANIFEST = """.{
    .name = .greeter,
    .version = "0.2.0",
    .minimum_zig_version = "0.17.0",
    .fingerprint = FINGERPRINT,
    .paths = .{ "LICENSE", "src", "vendor" },
    .dependencies = .{ .lacuna = .{ .path = "vendor/lacuna" } },
}
"""

PYPROJECT = """[build-system]
requires = ["lacuna-build"]
build-backend = "lacuna_build"

[project]
name = "greeter"
dynamic = ["version", "summary", "license", "scripts"]
"""


SDIST_GLOBS = """
[tool.lacuna]
sdist-include = ["README.md", "notes/*.txt"]
sdist-exclude = ["src/scratch/*"]
"""


@pytest.fixture
def workspace() -> Iterator[Path]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)

        assert root.is_dir()

        yield root


@pytest.fixture
def project(*, workspace: Path) -> Path:
    assert workspace.is_dir()

    root = workspace / 'greeter'

    lacuna_vendor(root)

    (root / 'src').mkdir()
    (root / 'src' / 'greeter.zig').write_text(GREETER_ZIG.replace('WORD', 'hello'))
    (root / 'build.zig').write_text(BUILD_ZIG)
    (root / 'build.zig.zon').write_text(MANIFEST.replace('FINGERPRINT', FINGERPRINT))
    (root / 'pyproject.toml').write_text(PYPROJECT)
    (root / 'LICENSE').write_text('MIT License\n')

    return root


def lacuna_vendor(root: Path) -> None:
    assert root.parent.is_dir()

    source = Path(os.environ['LACUNA_ROOT'])
    vendor = root / 'vendor' / 'lacuna'

    assert (source / 'build.zig').is_file()
    assert not vendor.exists()

    vendor.mkdir(parents=True)

    for name in LACUNA_FILES:
        origin = source / name

        if origin.is_dir():
            shutil.copytree(origin, vendor / name)
        else:
            shutil.copyfile(origin, vendor / name)


def command_failure(command: list[str], completed: subprocess.CompletedProcess[str]) -> str:
    assert command
    assert completed.returncode != 0

    return f'{" ".join(command)} failed:\n{completed.stdout}\n{completed.stderr}'


def command_output(command: list[str], *, cwd: Path, environment: dict[str, str]) -> str:
    assert command
    assert cwd.is_dir()
    assert all(isinstance(value, str) for value in environment.values())

    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=cwd,
        env=environment,
        text=True,
    )

    assert completed.returncode == 0, command_failure(command, completed)

    return completed.stdout


def command_run(command: list[str], *, cwd: Path, environment: dict[str, str]) -> None:
    assert command
    assert cwd.is_dir()
    assert all(isinstance(value, str) for value in environment.values())

    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=cwd,
        env=environment,
        text=True,
    )

    assert completed.returncode == 0, command_failure(command, completed)


def uv_run(*arguments: str | Path, cwd: Path) -> None:
    assert arguments
    assert cwd.is_dir()

    wheel = Path(os.environ['LACUNA_BACKEND_WHEEL'])
    command = ['uv', *map(str, arguments)]
    environment = os.environ | {'UV_FIND_LINKS': str(wheel.parent), 'UV_NO_INDEX': '1'}

    command_run(command, cwd=cwd, environment=environment)


def test_build_sdist_then_wheel(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    output = workspace / 'dist'

    uv_run('build', '--out-dir', output, project, cwd=workspace)

    sdists = sorted(output.glob('*.tar.gz'))
    wheels = sorted(output.glob('*.whl'))

    assert [path.name for path in sdists] == ['greeter-0.2.0.tar.gz']
    assert len(wheels) == 1
    assert wheels[0].name.startswith('greeter-0.2.0-cp311-abi3-')

    with tarfile.open(sdists[0]) as archive:
        names = set(archive.getnames())

    assert 'greeter-0.2.0/PKG-INFO' in names
    assert 'greeter-0.2.0/pyproject.toml' in names
    assert 'greeter-0.2.0/vendor/lacuna/src/lacuna.zig' in names
    assert not any('zig-out' in name or '.zig-cache' in name for name in names)

    with zipfile.ZipFile(wheels[0]) as archive:
        listing = set(archive.namelist())
        entry_points = archive.read('greeter-0.2.0.dist-info/entry_points.txt').decode()

    assert 'greeter/py.typed' in listing
    assert 'greet = greeter:cli' in entry_points

    target = workspace / 'site'

    install = [
        sys.executable,
        '-m',
        'pip',
        'install',
        '--no-deps',
        '--target',
        str(target),
        str(wheels[0]),
    ]

    command_run(install, cwd=workspace, environment=dict(os.environ))

    probe = [sys.executable, '-c', 'import greeter; print(greeter.word())']
    environment = os.environ | {'PYTHONPATH': str(target)}

    assert command_output(probe, cwd=workspace, environment=environment) == 'hello\n'


def test_sdist_is_reproducible(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    first = workspace / 'first'
    second = workspace / 'second'

    uv_run('build', '--sdist', '--out-dir', first, project, cwd=workspace)
    uv_run('build', '--sdist', '--out-dir', second, project, cwd=workspace)

    name = 'greeter-0.2.0.tar.gz'

    assert (first / name).read_bytes() == (second / name).read_bytes()


def test_editable_install_follows_rebuilds(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    environment = workspace / 'venv'
    python = environment / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    probe = [str(python), '-c', 'import greeter; print(greeter.word())']
    inherited = dict(os.environ)

    uv_run('venv', '--python', sys.executable, environment, cwd=workspace)
    uv_run('pip', 'install', '--python', python, '--editable', project, cwd=workspace)

    before = command_output(probe, cwd=workspace, environment=inherited)

    (project / 'src' / 'greeter.zig').write_text(GREETER_ZIG.replace('WORD', 'rebuilt'))
    zig = shutil.which('zig')

    assert zig is not None

    rebuild = [zig, 'build', 'develop:greeter']

    command_run(rebuild, cwd=project, environment=inherited)

    after = command_output(probe, cwd=workspace, environment=inherited)

    assert before == 'hello\n'
    assert after == 'rebuilt\n'


def test_import_hook_rebuilds_stale_editables(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    environment = workspace / 'venv'
    python = environment / ('Scripts/python.exe' if os.name == 'nt' else 'bin/python')
    inherited = dict(os.environ)
    absent = inherited | {'LACUNA_ZIG': str(workspace / 'absent' / 'zig')}

    uv_run('venv', '--python', sys.executable, environment, cwd=workspace)
    uv_run('pip', 'install', '--python', python, 'lacuna-build', cwd=workspace)
    uv_run('pip', 'install', '--python', python, '--editable', project, cwd=workspace)

    hooked = [str(python), '-c', HOOKED_PROBE]
    plain = [str(python), '-c', 'import greeter; print(greeter.word())']

    assert command_output(hooked, cwd=workspace, environment=absent) == 'hello\nNone\n'

    (project / 'src' / 'greeter.zig').write_text(GREETER_ZIG.replace('WORD', 'rebuilt'))

    assert command_output(plain, cwd=workspace, environment=inherited) == 'hello\n'
    assert command_output(hooked, cwd=workspace, environment=inherited) == 'rebuilt\nNone\n'
    assert command_output(hooked, cwd=workspace, environment=absent) == 'rebuilt\nNone\n'

    (project / 'src' / 'greeter.zig').write_text(GREETER_ZIG.replace('"WORD"', 'WORD'))

    failed = [str(python), '-c', FAILED_PROBE]
    failure = command_output(failed, cwd=workspace, environment=inherited)

    assert failure.startswith('rebuilding greeter failed:')
    assert 'error' in failure.removeprefix('rebuilding greeter failed:')


def test_project_template_builds_and_passes_its_tests(*, workspace: Path) -> None:
    assert workspace.is_dir()

    source = Path(os.environ['LACUNA_ROOT']) / 'templates' / 'project'
    root = workspace / 'example'
    output = workspace / 'dist'
    target = workspace / 'site'

    assert (source / 'build.zig').is_file()

    shutil.copytree(source, root)
    lacuna_vendor(root)
    uv_run('build', '--out-dir', output, root, cwd=workspace)

    sdists = sorted(output.glob('*.tar.gz'))
    wheels = sorted(output.glob('*.whl'))

    assert [path.name for path in sdists] == ['example-0.1.0.tar.gz']
    assert len(wheels) == 1
    assert wheels[0].name.startswith('example-0.1.0-cp311-abi3-')

    install = [
        sys.executable,
        '-m',
        'pip',
        'install',
        '--no-deps',
        '--target',
        str(target),
        str(wheels[0]),
    ]

    command_run(install, cwd=workspace, environment=dict(os.environ))

    tested = [
        sys.executable,
        '-m',
        'pytest',
        '-p',
        'no:cacheprovider',
        '-q',
        str(root / 'tests' / 'test_root.py'),
    ]

    environment = os.environ | {'PYTHONPATH': str(target)}

    assert 'passed' in command_output(tested, cwd=workspace, environment=environment)


def metadata_interpreter(workspace: Path) -> str:
    assert workspace.is_dir()

    if sys.version_info >= PYTHON_WHEEL_MIN:
        return sys.executable

    command = ['uv', 'python', 'find', PYTHON_REFERENCE]
    interpreter = command_output(command, cwd=workspace, environment=dict(os.environ)).strip()

    assert Path(interpreter).is_file()

    return interpreter


def metadata_project(project: Path, requires_python: str) -> None:
    assert project.is_dir()
    assert requires_python.startswith('>=')

    summary = '.summary = "A greeter built by lacuna_build.",'
    platforms = '.platforms = &lacuna.platforms,'
    minimum = f'{platforms}\n        .python_version_min = .{{ .major = 3, .minor = 12 }},'
    package = METADATA_PACKAGE.replace('REQUIRES', requires_python)

    assert summary in BUILD_ZIG
    assert platforms in BUILD_ZIG

    build = BUILD_ZIG.replace(summary, package).replace(platforms, minimum)

    (project / 'build.zig').write_text(build)
    (project / 'src' / 'greeter.zig').write_text(GREETER_NATIVE_ZIG)
    (project / 'src' / 'scratch').mkdir()
    (project / 'src' / 'scratch' / 'draft.zig').write_text('const draft = 1;\n')
    (project / 'notes').mkdir()
    (project / 'notes' / 'todo.txt').write_text('ship it\n')
    (project / 'README.md').write_text('# greeter\n')

    pyproject = project / 'pyproject.toml'
    pyproject.write_text(pyproject.read_text() + SDIST_GLOBS)


def test_package_metadata_and_sdist_globs(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    output = workspace / 'dist'
    target = workspace / 'site'

    metadata_project(project, '>=3.12')
    uv_run('build', '--out-dir', output, project, cwd=workspace)

    sdists = sorted(output.glob('*.tar.gz'))
    wheels = sorted(output.glob('*.whl'))

    assert [path.name for path in sdists] == ['greeter-0.2.0.tar.gz']
    assert len(wheels) == 1
    assert wheels[0].name.startswith('greeter-0.2.0-cp312-abi3-')

    with tarfile.open(sdists[0]) as archive:
        names = set(archive.getnames())

    assert 'greeter-0.2.0/notes/todo.txt' in names
    assert 'greeter-0.2.0/README.md' in names
    assert 'greeter-0.2.0/src/greeter.zig' in names
    assert 'greeter-0.2.0/src/scratch/draft.zig' not in names

    with zipfile.ZipFile(wheels[0]) as archive:
        metadata = archive.read('greeter-0.2.0.dist-info/METADATA').decode().splitlines()
        wheel = archive.read('greeter-0.2.0.dist-info/WHEEL').decode()

    assert all(field in metadata for field in METADATA_FIELDS)
    assert 'Generator: lacuna 0.1.0 (zig ' in wheel

    checked = [
        'uv',
        'run',
        '--no-project',
        '--with',
        'twine',
        'python',
        '-m',
        'twine',
        'check',
        '--strict',
        str(sdists[0]),
        str(wheels[0]),
    ]

    command_run(checked, cwd=workspace, environment=dict(os.environ))

    interpreter = metadata_interpreter(workspace)

    install = [
        interpreter,
        '-m',
        'pip',
        'install',
        '--no-deps',
        '--target',
        str(target),
        str(wheels[0]),
    ]

    command_run(install, cwd=workspace, environment=dict(os.environ))

    probe = [interpreter, '-c', 'import greeter; print(issubclass(greeter.Registry, dict))']
    environment = os.environ | {'PYTHONPATH': str(target)}

    assert command_output(probe, cwd=workspace, environment=environment) == 'True\n'


def test_requires_python_below_the_minimum_is_refused(*, project: Path) -> None:
    assert project.is_dir()

    expected = r"requires Python '>=3\.11', which admits versions below the 3\.12"
    module = lacuna_build_paths.backend()

    metadata_project(project, '>=3.11')

    with pytest.raises(module.project.ProjectError, match=expected):
        lacuna_build_paths.hook(project, 'prepare_metadata_for_build_wheel', str(project))


def test_name_mismatch_is_reported(*, project: Path) -> None:
    assert project.is_dir()

    pyproject = project / 'pyproject.toml'

    assert pyproject.is_file()

    pyproject.write_text(PYPROJECT.replace('name = "greeter"', 'name = "other"'))

    with pytest.raises(lacuna_build_paths.backend().project.ProjectError, match='names it'):
        lacuna_build_paths.hook(project, 'prepare_metadata_for_build_wheel', str(project))


def test_project_fields_owned_by_build_zig_are_refused(*, project: Path) -> None:
    assert project.is_dir()

    pyproject = project / 'pyproject.toml'
    declared = PYPROJECT + 'dependencies = ["requests"]\nrequires-python = ">=3.12"\n'
    module = lacuna_build_paths.backend()

    pyproject.write_text(declared)

    with pytest.raises(module.project.ProjectError, match='dependencies, requires-python'):
        lacuna_build_paths.hook(project, 'prepare_metadata_for_build_wheel', str(project))


def test_dynamic_version_and_static_version_conflict(*, project: Path) -> None:
    assert project.is_dir()

    pyproject = project / 'pyproject.toml'
    declared = PYPROJECT.replace('name = "greeter"', 'name = "greeter"\nversion = "0.2.0"')
    module = lacuna_build_paths.backend()

    pyproject.write_text(declared)

    with pytest.raises(module.project.ProjectError, match='also lists it in dynamic'):
        lacuna_build_paths.hook(project, 'prepare_metadata_for_build_wheel', str(project))


def test_build_arguments_are_forwarded(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    module = lacuna_build_paths.backend()
    refused = {'build-args': '-Dbogus-option=1'}
    accepted = {'build-args': ['-Doptimize=fast']}

    with pytest.raises(module.project.ProjectError, match='bogus-option'):
        lacuna_build_paths.hook(
            project,
            'prepare_metadata_for_build_wheel',
            str(workspace),
            config_settings=refused,
        )

    name = lacuna_build_paths.hook(
        project,
        'prepare_metadata_for_build_wheel',
        str(workspace),
        config_settings=accepted,
    )

    assert (workspace / str(name) / 'METADATA').is_file()


def test_unknown_config_settings_are_refused(*, project: Path) -> None:
    assert project.is_dir()

    module = lacuna_build_paths.backend()
    settings = {'features': 'fast'}

    with pytest.raises(module.project.ProjectError, match="not 'features'"):
        lacuna_build_paths.hook(project, 'get_requires_for_build_wheel', config_settings=settings)

    with pytest.raises(module.project.ProjectError, match='string or a list'):
        lacuna_build_paths.hook(
            project,
            'get_requires_for_build_wheel',
            config_settings={'build-args': 3},
        )


def test_unsupported_free_threaded_version_is_reported(*, project: Path) -> None:
    assert project.is_dir()

    listed = '.free_threaded = &.{.{ .major = 3, .minor = 12 }},'
    expected = r'lists free-threaded 3\.12; lacuna builds 3\.13 to 3\.15'
    module = lacuna_build_paths.backend()

    assert '.free_threaded = &.{},' in BUILD_ZIG

    (project / 'build.zig').write_text(BUILD_ZIG.replace('.free_threaded = &.{},', listed))

    with pytest.raises(module.project.ProjectError, match=expected):
        lacuna_build_paths.hook(project, 'prepare_metadata_for_build_wheel', str(project))


def test_outside_path_dependency_is_refused(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    manifest = project / 'build.zig.zon'
    moved = workspace / 'lacuna'

    shutil.move(project / 'vendor' / 'lacuna', moved)
    manifest.write_text(manifest.read_text().replace('vendor/lacuna', '../lacuna'))

    with pytest.raises(lacuna_build_paths.backend().project.ProjectError, match='outside'):
        lacuna_build_paths.hook(project, 'build_sdist', str(workspace))


def test_ziglang_is_requested_without_a_compiler(*, project: Path) -> None:
    assert project.is_dir()
    assert 'minimum_zig_version = "0.17.0"' in MANIFEST

    with pytest.MonkeyPatch.context() as patch:
        patch.setenv('PATH', '')
        patch.delenv('LACUNA_ZIG', raising=False)

        requirements = lacuna_build_paths.hook(project, 'get_requires_for_build_wheel')
        sdist = lacuna_build_paths.hook(project, 'get_requires_for_build_sdist')

    assert requirements == ['ziglang==0.17.0']
    assert sdist == []


def test_explicit_compiler_wins(*, project: Path) -> None:
    assert project.is_dir()

    with pytest.MonkeyPatch.context() as patch:
        patch.setenv('PATH', '')
        patch.setenv('LACUNA_ZIG', '/opt/zig/zig')

        requirements = lacuna_build_paths.hook(project, 'get_requires_for_build_wheel')

    assert requirements == []


def test_free_threaded_interpreter_without_a_build_is_reported(
    *,
    project: Path,
    workspace: Path,
) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    with pytest.MonkeyPatch.context() as patch:
        module = lacuna_build_paths.backend()
        expected = r'Python 3\.15t is free-threaded .* \.\{ \.major = 3, \.minor = 15 \}'

        patch.setattr(module.project, 'interpreter_suffix', lambda: '-3.15t')

        with pytest.raises(module.project.ProjectError, match=expected):
            lacuna_build_paths.hook(project, 'build_wheel', str(workspace))

        with pytest.raises(module.project.ProjectError, match=expected):
            lacuna_build_paths.hook(project, 'build_editable', str(workspace))

    assert not (project / 'zig-out' / 'lacuna-backend').exists()


def test_pypy_interpreter_without_a_build_is_reported(
    *,
    project: Path,
    workspace: Path,
) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    with pytest.MonkeyPatch.context() as patch:
        module = lacuna_build_paths.backend()
        expected = r'PyPy 3\.11 needs a PyPy build.*\.minor = 11'

        patch.setattr(module.project, 'interpreter_suffix', lambda: '-pypy3.11')

        with pytest.raises(module.project.ProjectError, match=expected):
            lacuna_build_paths.hook(project, 'build_wheel', str(workspace))


def test_pypy_frontend_builds_a_pypy_wheel(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()
    assert '.free_threaded = &.{},' in BUILD_ZIG

    listed = '.free_threaded = &.{},\n        .pypy = &lacuna.pypy_all,'
    output = workspace / 'dist'

    (project / 'build.zig').write_text(BUILD_ZIG.replace('.free_threaded = &.{},', listed))

    uv_run('build', '--wheel', '--python', 'pypy@3.11', '--out-dir', output, project, cwd=workspace)

    wheels = sorted(path.name for path in output.glob('*.whl'))

    assert len(wheels) == 1
    assert wheels[0].startswith('greeter-0.2.0-pp311-pypy311_pp80-')

    target = workspace / 'site'
    environment = dict(os.environ)

    uv_run(
        'pip',
        'install',
        '--python',
        'pypy@3.11',
        '--target',
        target,
        output / wheels[0],
        cwd=workspace,
    )

    probe = ['uv', 'run', '--no-project', '--python', 'pypy@3.11', 'python', '-c']
    probe.append('import greeter; print(greeter.word())')
    environment['PYTHONPATH'] = str(target)

    assert command_output(probe, cwd=workspace, environment=environment) == 'hello\n'


def test_wheel_follows_edits_to_python_sources(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()
    assert '.strip = false,' in BUILD_ZIG

    sourced = '.python_source = builder.path("python"),\n        .strip = false,'
    extra = project / 'python' / 'greeter' / 'extra.py'
    listed = '.paths = .{ "LICENSE", "src", "vendor" },'
    paths = '.paths = .{ "LICENSE", "src", "vendor", "python" },'
    manifest = project / 'build.zig.zon'

    (project / 'build.zig').write_text(BUILD_ZIG.replace('.strip = false,', sourced))
    manifest.write_text(manifest.read_text().replace(listed, paths))
    extra.parent.mkdir(parents=True)

    contents = []

    for value in ('first', 'second'):
        output = workspace / value

        output.mkdir()
        source = f"VALUE = '{value}'\n".encode()

        extra.write_bytes(source)

        name = lacuna_build_paths.hook(project, 'build_wheel', str(output))

        with zipfile.ZipFile(output / str(name)) as archive:
            contents.append(archive.read('greeter/extra.py'))

    assert contents == [b"VALUE = 'first'\n", b"VALUE = 'second'\n"]


def test_pip_builds_the_wheel(*, project: Path, workspace: Path) -> None:
    assert project.is_dir()
    assert workspace.is_dir()

    wheel = Path(os.environ['LACUNA_BACKEND_WHEEL'])
    output = workspace / 'pip'

    command = [
        sys.executable,
        '-m',
        'pip',
        'wheel',
        '--no-index',
        '--find-links',
        str(wheel.parent),
        '--wheel-dir',
        str(output),
        str(project),
    ]

    command_run(command, cwd=workspace, environment=dict(os.environ))

    built = sorted(path.name for path in output.glob('greeter-*.whl'))

    assert len(built) == 1
    assert built[0].startswith('greeter-0.2.0-cp311-abi3-')


@pytest.fixture
def cli(*, workspace: Path) -> Path:
    assert workspace.is_dir()

    environment = workspace / 'cli'

    uv_run('venv', '--python', sys.executable, environment, cwd=workspace)
    uv_run('pip', 'install', '--python', interpreter_of(environment), 'lacuna-build', cwd=workspace)

    lacuna = script_of(environment, 'lacuna')

    assert lacuna.is_file()

    return lacuna


def script_of(environment: Path, name: str) -> Path:
    assert environment.name
    assert name
    assert not name.endswith('.exe')

    directory = environment / ('Scripts' if os.name == 'nt' else 'bin')
    suffix = '.exe' if os.name == 'nt' else ''

    return directory / f'{name}{suffix}'


def interpreter_of(environment: Path) -> Path:
    assert environment.name

    return script_of(environment, 'python')


def cli_completed(
    lacuna: Path,
    *arguments: str | Path,
    cwd: Path,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    assert lacuna.is_file()
    assert arguments
    assert cwd.is_dir()
    assert environment is None or 'PATH' in environment

    command = [str(lacuna), *map(str, arguments)]
    inherited = dict(os.environ) if environment is None else environment

    return subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=cwd,
        env=inherited,
        text=True,
    )


def cli_output(lacuna: Path, *arguments: str | Path, cwd: Path) -> str:
    assert lacuna.is_file()
    assert arguments
    assert cwd.is_dir()

    completed = cli_completed(lacuna, *arguments, cwd=cwd)

    assert completed.returncode == 0, f'{arguments} failed:\n{completed.stdout}\n{completed.stderr}'

    return completed.stdout


def cli_run(lacuna: Path, *arguments: str | Path, cwd: Path) -> None:
    assert lacuna.is_file()
    assert arguments
    assert cwd.is_dir()

    completed = cli_completed(lacuna, *arguments, cwd=cwd)

    assert completed.returncode == 0, f'{arguments} failed:\n{completed.stdout}\n{completed.stderr}'


def cli_failure(
    lacuna: Path,
    *arguments: str | Path,
    cwd: Path,
    environment: dict[str, str] | None = None,
) -> str:
    assert lacuna.is_file()
    assert arguments
    assert cwd.is_dir()
    assert environment is None or 'PATH' in environment

    completed = cli_completed(lacuna, *arguments, cwd=cwd, environment=environment)

    assert completed.returncode == 1, f'{arguments} exited {completed.returncode}'
    assert completed.stdout == ''
    assert completed.stderr.count('\n') == 1, completed.stderr
    assert completed.stderr.startswith('lacuna: ')

    return completed.stderr


def template_leftovers(root: Path) -> list[Path]:
    assert (root / 'build.zig.zon').is_file()

    files = [path for path in root.rglob('*') if path.is_file()]
    owned = [path for path in files if 'vendor' not in path.relative_to(root).parts]

    assert len(owned) >= 6

    return [path for path in owned if 'example' in path.read_text(encoding='utf-8')]


def tree_contents(root: Path, listed: list[str]) -> dict[str, bytes]:
    assert root.is_dir()
    assert listed
    assert all(not name.startswith('/') for name in listed)

    result: dict[str, bytes] = {}

    for name in listed:
        origin = root / name
        found = sorted(origin.rglob('*')) if origin.is_dir() else [origin]

        for path in found:
            if path.is_dir():
                continue

            if '__pycache__' in path.parts:
                continue

            result[path.relative_to(root).as_posix()] = path.read_bytes()

    return result


def fingerprint_suggested(root: Path, fingerprint: int) -> int:
    assert (root / 'build.zig.zon').is_file()
    assert fingerprint >> 32 > 0
    assert fingerprint & 0xFFFFFFFF > 0

    manifest = root / 'build.zig.zon'
    original = manifest.read_text(encoding='utf-8')
    written = f'0x{fingerprint:016x}'
    zeroed = f'0x{fingerprint >> 32:08x}00000000'
    zig = shutil.which('zig')
    command = [str(zig), 'build', '-l']

    assert written in original
    assert zig is not None

    manifest.write_text(original.replace(written, zeroed), encoding='utf-8')

    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=root,
        text=True,
    )

    manifest.write_text(original, encoding='utf-8')

    found = FINGERPRINT_SUGGESTED.search(completed.stderr)

    assert completed.returncode != 0
    assert found is not None, completed.stderr

    return int(found.group(1), 16)


def test_cli_new_build_and_install(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'demo_app'
    output = workspace / 'dist'
    fresh = workspace / 'fresh'

    assert cli_output(cli, 'new', root, cwd=workspace) == f'{root.resolve()}\n'
    assert template_leftovers(root) == []
    assert 'import demo_app' in (root / 'tests' / 'test_root.py').read_text()
    assert 'EXTENSION: demo_app' in (root / '.github' / 'workflows' / 'release.yml').read_text()

    printed = cli_output(cli, 'build', '--project', root, '--sdist', '--out', output, cwd=workspace)
    wheels = sorted(output.glob('*.whl'))
    sdist = output.resolve() / 'demo_app-0.1.0.tar.gz'

    assert len(wheels) == 1
    assert printed.splitlines() == [str(wheels[0].resolve()), str(sdist)]
    assert wheels[0].name.startswith('demo_app-0.1.0-cp311-abi3-')
    assert sdist.is_file()

    uv_run('venv', '--python', sys.executable, fresh, cwd=workspace)
    uv_run('pip', 'install', '--python', interpreter_of(fresh), wheels[0], cwd=workspace)

    probe = [str(interpreter_of(fresh)), '-c', 'import demo_app; print(demo_app.double(21))']

    assert command_output(probe, cwd=workspace, environment=dict(os.environ)) == '42\n'


def test_cli_new_vendors_lacuna_with_a_fingerprint_zig_accepts(
    *,
    cli: Path,
    workspace: Path,
) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    first = workspace / 'first'
    second = workspace / 'second'
    source = Path(os.environ['LACUNA_ROOT'])
    zon = lacuna_build_paths.backend().zon
    listed = zon.parse((source / 'build.zig.zon').read_text())['paths']
    vendor = first / 'vendor' / 'lacuna'
    zig = shutil.which('zig')

    assert zig is not None

    cli_run(cli, 'new', first, cwd=workspace)
    cli_run(cli, 'new', second, '--name', 'first', cwd=workspace)

    assert sorted(path.name for path in vendor.iterdir()) == sorted(listed)
    assert tree_contents(vendor, listed) == tree_contents(source, listed)

    manifests = [zon.parse((root / 'build.zig.zon').read_text()) for root in (first, second)]
    fingerprints = [manifest['fingerprint'] for manifest in manifests]

    assert [manifest['name'] for manifest in manifests] == ['first', 'first']
    assert fingerprints[0] >> 32 == zlib.crc32(b'first')
    assert fingerprints[1] >> 32 == zlib.crc32(b'first')
    assert fingerprints[0] & 0xFFFFFFFF != fingerprints[1] & 0xFFFFFFFF
    assert fingerprint_suggested(first, fingerprints[0]) >> 32 == fingerprints[0] >> 32

    listing = command_output([zig, 'build', '-l'], cwd=first, environment=dict(os.environ))

    assert 'wheel-host:first' in listing


def test_cli_new_refuses_every_keyword_of_the_compiler(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    zig = shutil.which('zig')
    target = workspace / 'keyword'
    source = Path(os.environ['LACUNA_ROOT'])

    assert zig is not None

    environment = command_output([zig, 'env'], cwd=source, environment=dict(os.environ))
    std = ZIG_STD_DIRECTORY.search(environment)

    assert std is not None

    tokenizer = Path(std.group(1)) / 'zig' / 'tokenizer.zig'
    keywords = sorted(ZIG_KEYWORD.findall(tokenizer.read_text()))

    assert len(keywords) > 40

    for word in keywords:
        refused = cli_failure(cli, 'new', target, '--name', word, cwd=workspace)

        assert f'{word!r} is a ' in refused
        assert ' keyword, so it cannot name a ' in refused

    assert not target.exists()


def test_cli_develop_installs_an_editable_build(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'develop_app'
    python = interpreter_of(cli.parent.parent)
    code = 'import develop_app; print(develop_app.double(4)); print(develop_app.__file__)'
    probe = [str(python), '-c', code]
    inherited = dict(os.environ)

    cli_run(cli, 'new', root, cwd=workspace)
    cli_run(cli, 'develop', '--project', root, cwd=workspace)

    first = command_output(probe, cwd=workspace, environment=inherited).splitlines()

    cli_run(cli, 'develop', '--project', root, cwd=workspace)

    second = command_output(probe, cwd=workspace, environment=inherited).splitlines()

    assert first[0] == '8'
    assert Path(first[1]).resolve().is_relative_to(root.resolve() / 'zig-out')
    assert second == first


def test_cli_develop_falls_back_to_pip(*, workspace: Path) -> None:
    assert workspace.is_dir()

    environment = workspace / 'pip'
    python = interpreter_of(environment)
    wheel = Path(os.environ['LACUNA_BACKEND_WHEEL'])
    root = workspace / 'pip_app'
    inherited = dict(os.environ)
    created = [sys.executable, '-m', 'venv', str(environment)]
    install = [str(python), '-m', 'pip', 'install', '--no-index', str(wheel)]
    probe = [str(python), '-c', 'import pip_app; print(pip_app.double(5))']
    zig = shutil.which('zig')

    assert zig is not None

    command_run(created, cwd=workspace, environment=inherited)
    command_run(install, cwd=workspace, environment=inherited)

    lacuna = script_of(environment, 'lacuna')
    isolated = inherited | {'LACUNA_ZIG': zig, 'PATH': str(lacuna.parent)}

    cli_run(lacuna, 'new', root, cwd=workspace)

    completed = cli_completed(
        lacuna,
        'develop',
        '--project',
        root,
        cwd=workspace,
        environment=isolated,
    )

    assert completed.returncode == 0, completed.stderr
    assert command_output(probe, cwd=workspace, environment=inherited) == '10\n'


def test_cli_sdist_defaults_to_the_current_project(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'sdist_app'
    sdist = root.resolve() / 'dist' / 'sdist_app-0.1.0.tar.gz'

    cli_run(cli, 'new', root, cwd=workspace)

    assert cli_output(cli, 'sdist', cwd=root) == f'{sdist}\n'

    with tarfile.open(sdist) as archive:
        names = set(archive.getnames())
        pyproject = archive.extractfile('sdist_app-0.1.0/pyproject.toml')

        assert pyproject is not None

        declared = pyproject.read().decode()

    assert 'sdist_app-0.1.0/build.zig.zon' in names
    assert 'sdist_app-0.1.0/vendor/lacuna/src/lacuna.zig' in names
    assert 'name = "sdist_app"' in declared


def test_cli_publish_hands_only_the_new_distributions_to_uv(
    *,
    cli: Path,
    workspace: Path,
) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'publish_app'
    output = workspace / 'upload'
    stale = output / 'publish_app-0.0.1.tar.gz'
    sdist = output.resolve() / 'publish_app-0.1.0.tar.gz'
    environment = {key: value for key, value in os.environ.items() if 'PUBLISH' not in key}

    cli_run(cli, 'new', root, cwd=workspace)
    output.mkdir()
    stale.write_bytes(b'stale')

    completed = cli_completed(
        cli,
        'publish',
        '--project',
        root,
        '--out',
        output,
        '--dry-run',
        '--trusted-publishing',
        'never',
        '--publish-url',
        PUBLISH_URL,
        cwd=workspace,
        environment=environment,
    )

    wheels = sorted(output.glob('*.whl'))

    assert completed.returncode == 0, completed.stderr
    assert len(wheels) == 1
    assert completed.stdout.splitlines() == [str(wheels[0].resolve()), str(sdist)]
    assert f'Checking 2 files against {PUBLISH_URL}' in completed.stderr
    assert f'Checking {wheels[0].name} ' in completed.stderr
    assert f'Checking {sdist.name} ' in completed.stderr
    assert stale.name not in completed.stderr


def test_cli_new_refuses_occupied_targets_and_invalid_names(
    *,
    cli: Path,
    workspace: Path,
) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    occupied = workspace / 'occupied'
    kept = occupied / 'keep.txt'
    fresh = workspace / 'fresh'
    hyphenated = workspace / 'my-project'
    empty = workspace / 'empty'
    longest = workspace / ('a' * 32)
    invalid = ('9lives', '_leading', 'a' * 33, 'class', 'naïve', 'struct', 'trailing_')

    occupied.mkdir()
    empty.mkdir()
    kept.write_text('keep\n')

    for target in (occupied, kept):
        refused = cli_failure(cli, 'new', target, '--name', 'kept', cwd=workspace)
        expected = f'lacuna: {target.resolve()} already exists and is not an empty directory\n'

        assert refused == expected

    for name in invalid:
        assert repr(name) in cli_failure(cli, 'new', fresh, '--name', name, cwd=workspace)

    assert repr('my-project') in cli_failure(cli, 'new', hyphenated, cwd=workspace)
    assert [path.name for path in occupied.iterdir()] == ['keep.txt']
    assert not fresh.exists()
    assert not hyphenated.exists()
    assert cli_output(cli, 'new', empty, cwd=workspace) == f'{empty.resolve()}\n'
    assert cli_output(cli, 'new', longest, cwd=workspace) == f'{longest.resolve()}\n'
    assert cli_completed(cli, 'build', '--dry-run', cwd=workspace).returncode == 2


def test_cli_refuses_develop_and_publish_without_uv(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'bare_app'
    isolated = os.environ | {'PATH': str(cli.parent)}
    expected = 'lacuna: lacuna develop needs uv on PATH or pip installed in '

    cli_run(cli, 'new', root, cwd=workspace)

    develop = cli_failure(cli, 'develop', '--project', root, cwd=workspace, environment=isolated)
    publish = cli_failure(cli, 'publish', '--project', root, cwd=workspace, environment=isolated)

    assert develop.startswith(expected)
    assert publish == 'lacuna: lacuna publish needs uv on PATH\n'
    assert not (root / 'zig-out').exists()
    assert not (root / 'dist').exists()


def test_cli_reports_failures_without_a_traceback(*, cli: Path, workspace: Path) -> None:
    assert cli.is_file()
    assert workspace.is_dir()

    root = workspace / 'broken_app'

    cli_run(cli, 'new', root, cwd=workspace)
    (root / 'src' / 'root.zig').write_text('const broken = ;\n')

    completed = cli_completed(cli, 'build', '--project', root, cwd=workspace)
    lines = completed.stderr.splitlines()
    missing = cli_failure(cli, 'sdist', '--project', workspace, cwd=workspace)

    assert completed.returncode == 1
    assert completed.stdout == ''
    assert 'Traceback' not in completed.stderr
    assert lines[-1].startswith('lacuna: ')
    assert ' build wheel-host:broken_app --prefix ' in lines[-1]
    assert lines[-1].endswith(' failed with status 1')
    assert missing.startswith(f'lacuna: {workspace.resolve()} holds no pyproject.toml')
