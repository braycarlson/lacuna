import importlib
import importlib.machinery
import importlib.util
import shutil
import subprocess
import sys
import sysconfig

from pathlib import Path
from types import ModuleType


BUILD_TIMEOUT_SECONDS = 3600
BUILD_ZIG = """const std = @import("std");

const lacuna = @import("lacuna");

pub fn build(builder: *std.Build) void {
    const extension = lacuna.add_extension(builder, .{
        .free_threaded = &lacuna.free_threaded_default,
        .module = builder.createModule(.{ .root_source_file = builder.path("src/root.zig") }),
        .name = "NAME",
        .optimize = builder.standardOptimizeOption(.{ .preferred_optimize_mode = null }),
        .package = .{ .name = "NAME", .version = "0.1.0" },
        .platforms = &lacuna.platforms,
        .strip = false,
        .target = builder.standardTargetOptions(.{ .whitelist = null, .default_target = .{} }),
    });

    _ = extension;
}
"""
ERROR_TAIL_BYTES = 20000
MANIFEST = """.{
    .name = .greeter,
    .version = "0.1.0",
    .minimum_zig_version = "0.17.1",
    .fingerprint = 0x3dc4b1addfd22072,
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .dependencies = .{ .lacuna = .{ .path = "../../.." } },
}
"""
STUBTEST_TIMEOUT_SECONDS = 600


def build_variant() -> tuple[str, str]:
    assert sys.version_info >= (3, 11)
    assert sys.implementation.name == 'cpython'

    if sysconfig.get_config_var('Py_GIL_DISABLED') != 1:
        return ('develop', 'python')

    if sys.version_info >= (3, 15):
        return ('develop-abi3t', 'python-abi3t')

    major, minor = sys.version_info[:2]

    return (f'develop-{major}.{minor}t', f'python-{major}.{minor}t')


def project_built(*, name: str, source: str) -> Path:
    assert name.isidentifier()
    assert 'pub const module: lacuna.Module' in source

    root = Path(__file__).resolve().parent.parent
    project = root / '.zig-cache' / 'generated' / name
    zig = sys._xoptions.get('lacuna_zig') or shutil.which('zig')

    assert zig is not None, 'a generated project needs zig on PATH or -X lacuna_zig'
    assert (root / 'build.zig').is_file()

    if project.exists():
        shutil.rmtree(project)

    (project / 'src').mkdir(parents=True)
    (project / 'src' / 'root.zig').write_text(source)
    (project / 'build.zig').write_text(BUILD_ZIG.replace('NAME', name))
    (project / 'build.zig.zon').write_text(MANIFEST)

    step, directory = build_variant()
    command = [str(zig), 'build', f'{step}:{name}']
    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=project,
        text=True,
        timeout=BUILD_TIMEOUT_SECONDS,
    )

    failure = f'{project} did not build:\n{completed.stderr[-ERROR_TAIL_BYTES:]}'

    assert completed.returncode == 0, failure

    result = project / 'zig-out' / directory

    assert (result / name / '__init__.pyi').is_file()

    return result


def module_imported(*, name: str, output: Path) -> ModuleType:
    assert name.isidentifier()
    assert output.is_dir()

    if str(output) not in sys.path:
        sys.path.insert(0, str(output))

    result = importlib.import_module(name)

    assert result.__name__ == name

    return result


def stub_namespace(*, name: str, output: Path) -> dict[str, object]:
    assert name.isidentifier()
    assert output.is_dir()

    stub = output / name / '__init__.pyi'
    loader = importlib.machinery.SourceFileLoader(name + '_stub', str(stub))
    specification = importlib.util.spec_from_loader(loader.name, loader)
    stubbed = importlib.util.module_from_spec(specification)

    loader.exec_module(stubbed)

    result = vars(stubbed)

    assert '__builtins__' in result

    return result


def stubtest_report(*, name: str, output: Path) -> str:
    assert name.isidentifier()
    assert (output / name / '__init__.pyi').is_file()

    null_device = 'nul' if sys.platform == 'win32' else '/dev/null'
    configuration = output / 'mypy.ini'

    configuration.write_text(f'[mypy]\ncache_dir = {null_device}\n')

    command = [
        sys.executable,
        '-B',
        '-m',
        'mypy.stubtest',
        '--concise',
        '--mypy-config-file',
        str(configuration),
        name,
    ]
    completed = subprocess.run(
        command,
        capture_output=True,
        check=False,
        cwd=output,
        text=True,
        timeout=STUBTEST_TIMEOUT_SECONDS,
    )

    if completed.returncode == 0:
        return ''

    return completed.stdout + completed.stderr
