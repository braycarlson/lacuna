import importlib.util
import json
import shutil
import struct
import subprocess
import sys
import tempfile

import auditwheel
import pytest

from collections.abc import Iterator
from pathlib import Path
from types import ModuleType


ADMITTED = (
    ('manylinux_2_17_x86_64', 'manylinux_2_17_x86_64'),
    ('manylinux_2_17_x86_64', 'manylinux_2_5_x86_64'),
    ('manylinux_2_17_x86_64', 'manylinux_2_9_x86_64'),
    ('manylinux_2_31_armv7l', 'manylinux_2_28_armv7l'),
    ('musllinux_1_2_aarch64', 'musllinux_1_1_aarch64'),
    ('manylinux_2_36_loongarch64', 'manylinux_2_36_loongarch64'),
    ('musllinux_1_2_loongarch64', 'musllinux_1_2_loongarch64'),
)
IMPORT_SOURCE = """const imported = @extern(
    *const fn () callconv(.c) ?*anyopaque,
    .{{ .name = "{symbol}" }},
);

export fn PyInit_witness() ?*anyopaque {{
    return imported();
}}
"""
BINARY_SUFFIXES = ('.dll', '.dylib', '.so')
EXECUTABLE_SOURCE = """pub fn main() void {}
"""
FAT_ALIGNMENT_LOG2 = 14
FAT_MAGIC = 0xCAFEBABE
LINKED_SOURCE = """extern fn witness_value() i32;

export fn PyInit_witness() ?*anyopaque {
    return @ptrFromInt(@as(usize, @intCast(witness_value())));
}
"""
LIBRARY_SOURCE = """export fn witness_value() i32 {
    return 64;
}
"""
POLICED = (
    ('x86_64-linux-gnu', 'manylinux_2_17_x86_64.manylinux2014_x86_64', 'libwitness.so'),
    ('x86_64-linux-musl', 'musllinux_1_2_x86_64', 'libwitness.so'),
    ('aarch64-linux-android.29', 'android_29_arm64_v8a', 'libwitness.so'),
    ('aarch64-macos.11.0', 'macosx_11_0_arm64', 'libwitness.dylib'),
    ('x86_64-windows-gnu', 'win_amd64', 'witness.dll'),
    ('x86-windows-gnu', 'win32', 'witness.dll'),
)
POLICY_FILES = ('android-policy.json', 'manylinux-policy.json', 'musllinux-policy.json')
POLICY_PATH = Path(__file__).resolve().parent.parent / 'src' / 'policy.json'
STATIC_TARGETS = (
    ('aarch64-linux-android.29', 'android_29_arm64_v8a'),
    ('aarch64-macos.11.0', 'macosx_11_0_arm64'),
    ('x86_64-linux-gnu.2.17', 'manylinux_2_17_x86_64'),
    ('x86_64-linux-musl', 'musllinux_1_2_x86_64'),
    ('x86_64-windows-gnu', 'win_amd64'),
)
STATIC_SUFFIXES = ('', '.exe')
REFUSED = (
    ('manylinux_2_17_x86_64', 'manylinux_2_28_x86_64'),
    ('manylinux_2_9_x86_64', 'manylinux_2_17_x86_64'),
    ('manylinux_2_17_x86_64', 'manylinux_2_17_aarch64'),
    ('manylinux_2_17_x86_64', 'musllinux_1_2_x86_64'),
    ('musllinux_1_1_x86_64', 'musllinux_1_2_x86_64'),
    ('manylinux_2_36_loongarch64', 'manylinux_2_38_loongarch64'),
    ('manylinux_2_36_loongarch64', 'manylinux_2_36_riscv64'),
    ('musllinux_1_2_loongarch64', 'manylinux_2_36_loongarch64'),
)
UNLINKED_SOURCE = """export fn PyInit_witness() ?*anyopaque {
    return null;
}
"""


def audit_module() -> ModuleType:
    path = Path(__file__).resolve().parent.parent / 'tools' / 'audit.py'

    assert path.is_file()

    specification = importlib.util.spec_from_file_location('audit', path)

    assert specification is not None
    assert specification.loader is not None

    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)

    assert callable(module.admits)

    return module


@pytest.mark.parametrize(('claimed', 'audited'), ADMITTED)
def test_older_policies_are_admitted(*, claimed: str, audited: str) -> None:
    module = audit_module()

    assert module.admits(claimed=claimed, audited=audited)

    if claimed != audited:
        assert not module.admits(claimed=audited, audited=claimed)


@pytest.mark.parametrize(('claimed', 'audited'), REFUSED)
def test_newer_or_foreign_policies_are_refused(*, claimed: str, audited: str) -> None:
    assert not audit_module().admits(claimed=claimed, audited=audited)


def test_unaudited_wheel_is_refused() -> None:
    with pytest.raises(SystemExit, match='not a manylinux or musllinux') as raised:
        audit_module().admits(claimed='manylinux_2_17_x86_64', audited='linux_x86_64')

    assert 'linux_x86_64' in str(raised.value)


@pytest.fixture
def workspace() -> Iterator[Path]:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)

        assert root.is_dir()

        yield root


def abi3_wheel(directory: Path, symbol: str) -> Path:
    assert directory.is_dir()
    assert symbol.startswith('Py')

    zig = Path(sys._xoptions['lacuna_zig'])
    staging = directory / 'staging'
    source = directory / 'witness.zig'

    assert zig.is_file()

    staging.mkdir()
    source.write_text(IMPORT_SOURCE.format(symbol=symbol), encoding='utf-8')

    command = [
        str(zig),
        'build-lib',
        '-dynamic',
        '-fallow-shlib-undefined',
        '-target',
        'x86_64-linux-gnu',
        '-O',
        'small',
        f'-femit-bin={staging / "witness.abi3.so"}',
        str(source),
    ]

    completed = subprocess.run(command, capture_output=True, check=False, cwd=directory, text=True)

    assert completed.returncode == 0, completed.stderr

    archive = shutil.make_archive(str(directory / 'witness'), 'zip', staging)
    wheel = Path(archive).rename(directory / 'witness-0.1.0-cp311-abi3-manylinux_2_17_x86_64.whl')

    assert wheel.is_file()

    return wheel


def test_abi3_symbol_newer_than_the_tag_is_refused(*, workspace: Path) -> None:
    assert workspace.is_dir()

    wheel = abi3_wheel(workspace, 'PyErr_GetRaisedException')

    with pytest.raises(SystemExit, match='abi3audit rejected') as raised:
        audit_module().abi3_check(wheel)

    assert wheel.name in str(raised.value)
    assert 'PyErr_GetRaisedException' in str(raised.value)


def test_abi3_symbol_within_the_tag_is_admitted(*, workspace: Path) -> None:
    assert workspace.is_dir()

    wheel = abi3_wheel(workspace, 'PyErr_Occurred')

    assert audit_module().abi3_check(wheel) is None


def zig_run(*, arguments: list[str], directory: Path) -> None:
    assert arguments
    assert directory.is_dir()

    zig = Path(sys._xoptions['lacuna_zig'])
    command = [str(zig), *arguments]
    completed = subprocess.run(command, capture_output=True, check=False, cwd=directory, text=True)

    assert completed.returncode == 0, completed.stderr


def witness_extension(*, directory: Path, linked: bool, target: str) -> Path:
    assert target
    assert directory.is_dir()

    staging = directory / f'{target}-{"linked" if linked else "unlinked"}'
    source = staging / 'extension.zig'

    staging.mkdir()
    (staging / 'library.zig').write_text(LIBRARY_SOURCE, encoding='utf-8')
    source.write_text(LINKED_SOURCE if linked else UNLINKED_SOURCE, encoding='utf-8')

    common = ['-dynamic', '-target', target, '-O', 'small']
    library = ['build-lib', *common, '--name', 'witness', 'library.zig']
    extension = ['build-lib', *common, '--name', 'extension', 'extension.zig']

    if linked:
        zig_run(arguments=library, directory=staging)
        extension.extend(['-L.', '-lwitness'])

    zig_run(arguments=extension, directory=staging)

    built = [path for path in staging.glob('*extension.*') if path.suffix in BINARY_SUFFIXES]

    assert len(built) == 1, built

    return built[0]


def police(*, allowed: tuple[str, ...], binary: Path, tag: str) -> subprocess.CompletedProcess[str]:
    assert binary.is_file()
    assert tag
    assert isinstance(allowed, tuple)

    tool = Path(sys._xoptions['lacuna_policy'])
    output = binary.with_name(f'{binary.name}.checked')
    command = [str(tool), str(binary), str(output), "the extension 'witness'", tag, *allowed]

    output.unlink(missing_ok=True)

    return subprocess.run(command, capture_output=True, check=False, text=True)


def fat_merge(*, slices: tuple[Path, ...], target: Path) -> Path:
    assert len(slices) > 1
    assert not target.exists()

    alignment = 1 << FAT_ALIGNMENT_LOG2
    contents = [path.read_bytes() for path in slices]
    offsets = []
    position = alignment

    for content in contents:
        offsets.append(position)
        position += -(-len(content) // alignment) * alignment

    image = bytearray(position)
    header = struct.pack('>II', FAT_MAGIC, len(contents))
    image[: len(header)] = header

    for index, (content, offset) in enumerate(zip(contents, offsets, strict=True)):
        cpu = struct.unpack('<ii', content[4:12])
        entry = struct.pack('>iiIII', *cpu, offset, len(content), FAT_ALIGNMENT_LOG2)
        start = len(header) + index * len(entry)
        image[start : start + len(entry)] = entry
        image[offset : offset + len(content)] = content

    target.write_bytes(image)

    return target


def test_vendored_policy_matches_auditwheel() -> None:
    root = Path(auditwheel.__file__).resolve().parent / 'policy'
    expected = {}

    for name in POLICY_FILES:
        for policy in json.loads((root / name).read_text(encoding='utf-8')):
            if policy['name'] != 'linux':
                expected[policy['name']] = sorted(policy['lib_whitelist'])

    vendored = json.loads(POLICY_PATH.read_text(encoding='utf-8'))

    assert len(expected) > 20
    assert vendored == expected


@pytest.mark.parametrize(('target', 'tag', 'library'), POLICED)
def test_policy_names_the_library_a_platform_lacks(
    *,
    library: str,
    tag: str,
    target: str,
    workspace: Path,
) -> None:
    assert library
    assert tag
    assert target
    assert workspace.is_dir()

    extension = witness_extension(directory=workspace, linked=True, target=target)
    refused = police(allowed=(), binary=extension, tag=tag)

    assert refused.returncode == 1
    assert f"the extension 'witness' for {tag} needs {library}," in refused.stderr
    assert not extension.with_name(f'{extension.name}.checked').exists()

    admitted = police(allowed=(library,), binary=extension, tag=tag)
    checked = extension.with_name(f'{extension.name}.checked')

    assert admitted.returncode == 0, admitted.stderr
    assert checked.read_bytes() == extension.read_bytes()


@pytest.mark.parametrize(('target', 'tag', 'library'), POLICED)
def test_policy_passes_an_extension_that_needs_only_the_platform(
    *,
    library: str,
    tag: str,
    target: str,
    workspace: Path,
) -> None:
    assert library
    assert tag
    assert target
    assert workspace.is_dir()

    extension = witness_extension(directory=workspace, linked=False, target=target)
    completed = police(allowed=(), binary=extension, tag=tag)
    checked = extension.with_name(f'{extension.name}.checked')

    assert library not in completed.stderr
    assert completed.returncode == 0, completed.stderr
    assert checked.read_bytes() == extension.read_bytes()


def test_policy_reads_each_slice_of_a_universal_binary(*, workspace: Path) -> None:
    assert workspace.is_dir()

    clean = witness_extension(directory=workspace, linked=False, target='aarch64-macos.11.0')
    linked = witness_extension(directory=workspace, linked=True, target='x86_64-macos.11.0')
    other = witness_extension(directory=workspace, linked=False, target='x86_64-macos.11.0')
    mixed = fat_merge(slices=(clean, linked), target=workspace / 'mixed.so')
    plain = fat_merge(slices=(clean, other), target=workspace / 'plain.so')
    refused = police(allowed=(), binary=mixed, tag='macosx_11_0_universal2')
    admitted = police(allowed=(), binary=plain, tag='macosx_11_0_universal2')

    assert refused.returncode == 1
    assert 'needs libwitness.dylib,' in refused.stderr
    assert admitted.returncode == 0, admitted.stderr


@pytest.mark.parametrize(('target', 'tag'), STATIC_TARGETS)
def test_policy_admits_a_static_executable(*, tag: str, target: str, workspace: Path) -> None:
    assert tag
    assert target
    assert workspace.is_dir()

    staging = workspace / target
    staging.mkdir()
    (staging / 'main.zig').write_text(EXECUTABLE_SOURCE, encoding='utf-8')

    arguments = ['build-exe', '-target', target, '-O', 'small', 'main.zig']

    zig_run(arguments=arguments, directory=staging)

    built = sorted(staging.iterdir())
    names = {f'main{suffix}' for suffix in STATIC_SUFFIXES}
    binaries = [path for path in built if path.name in names]

    assert len(binaries) == 1, built

    completed = police(allowed=(), binary=binaries[0], tag=tag)

    assert completed.returncode == 0, completed.stderr


def test_policy_refuses_a_file_that_is_no_binary(*, workspace: Path) -> None:
    assert workspace.is_dir()

    garbage = workspace / 'garbage.so'
    garbage.write_bytes(b'\x7fELF' + bytes(60))

    completed = police(allowed=(), binary=garbage, tag='manylinux_2_17_x86_64')

    assert completed.returncode != 0
    assert 'ElfInvalid' in completed.stderr
