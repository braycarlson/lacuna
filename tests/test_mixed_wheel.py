import importlib.metadata
import io
import json
import os
import struct
import subprocess
import sys
import zipfile

import pytest

import mixed

from pathlib import Path
from types import MappingProxyType


ELF_DYNAMIC = 2
ELF_LOAD = 1
ELF_NEEDED_TAGS = frozenset({1})
ELF_RUNPATH_TAGS = frozenset({15, 29})
ELF_STRING_TABLE = 5
SHARED_NAMES = MappingProxyType(
    {'darwin': 'libcounter-mixed.dylib', 'win32': 'counter-mixed.dll'},
)
SHARED_NAME = SHARED_NAMES.get(sys.platform, 'libcounter-mixed.so')


def test_metadata() -> None:
    metadata = importlib.metadata.metadata('mixed')
    requirements = importlib.metadata.requires('mixed') or []

    assert metadata['Name'] == 'mixed'
    assert metadata['Requires-Python'] == '>=3.11'
    assert 'typing-extensions>=4.6' in requirements
    assert 'pytest>=8; extra == "test"' in requirements
    assert metadata.get_all('Provides-Extra') == ['test']


def test_console_script() -> None:
    scripts = importlib.metadata.entry_points(group='console_scripts', name='mixed-greet')
    output = io.StringIO()

    assert len(scripts) == 1

    with pytest.MonkeyPatch.context() as patch:
        (script,) = scripts
        main = script.load()
        arguments = ['mixed-greet', 'pip']

        patch.setattr('sys.argv', arguments)
        patch.setattr('sys.stdout', output)

        main()

    assert output.getvalue() == 'Hello, pip!\n'
    assert mixed.greet('pip') == 'Hello, pip!'


def test_data_files_shipped() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        notes = archive.read('mixed-0.1.0.data/data/share/mixed/notes.txt')
        header = archive.read('mixed-0.1.0.data/headers/mixed/mixed.h')
        record = archive.read('mixed-0.1.0.dist-info/RECORD').decode()

    assert notes == b'Notes installed beside the mixed package.\n'
    assert header == b'#define MIXED_VERSION 1\n'
    assert 'mixed-0.1.0.data/data/share/mixed/notes.txt,sha256=' in record


def test_bundled_library_ships_beside_the_extension() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        names = archive.namelist()
        record = archive.read('mixed-0.1.0.dist-info/RECORD').decode()

    first = mixed._native.counter_next()

    assert f'mixed/{SHARED_NAME}' in names
    assert f'mixed/{SHARED_NAME},sha256=' in record
    assert mixed._native.counter_next() == first + 1
    assert (Path(mixed._native.__file__).parent / SHARED_NAME).is_file()


def elf_dynamic_strings(data: bytes, *, tags: frozenset[int]) -> list[str]:
    assert tags

    if data[:6] != b'\x7fELF\x02\x01':
        message = 'expected a 64-bit little-endian ELF file'
        raise ValueError(message)

    program_offset = struct.unpack_from('<Q', data, 0x20)[0]
    entry_size, entry_count = struct.unpack_from('<HH', data, 0x36)
    segments = [
        struct.unpack_from('<IIQQQQQQ', data, program_offset + index * entry_size)
        for index in range(entry_count)
    ]

    loads = [segment for segment in segments if segment[0] == ELF_LOAD]
    dynamic = next(segment for segment in segments if segment[0] == ELF_DYNAMIC)
    entries = [
        struct.unpack_from('<qQ', data, dynamic[2] + index * 16)
        for index in range(dynamic[5] // 16)
    ]

    table_address = next(value for tag, value in entries if tag == ELF_STRING_TABLE)
    load = next(load for load in loads if load[3] <= table_address < load[3] + load[5])
    table = table_address - load[3] + load[2]
    result = []

    for tag, value in entries:
        if tag in tags:
            end = data.index(b'\0', table + value)
            result.append(data[table + value : end].decode())

    return result


def test_extension_finds_its_library_through_origin_alone() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        binaries = {
            name: archive.read(name)
            for name in archive.namelist()
            if name.endswith(('.so', '.dylib', '.dll', '.pyd'))
        }

    assert f'mixed/{SHARED_NAME}' in binaries

    if sys.platform != 'linux':
        return

    for name, data in binaries.items():
        runpaths = elf_dynamic_strings(data, tags=ELF_RUNPATH_TAGS)
        needed = elf_dynamic_strings(data, tags=ELF_NEEDED_TAGS)

        assert runpaths == (['$ORIGIN'] if '_native' in name else []), name
        assert (SHARED_NAME in needed) == ('_native' in name), name


def test_bytecode_not_shipped() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        names = archive.namelist()

    assert 'mixed/helpers.py' in names
    assert not [name for name in names if name.endswith(('.pyc', '.pyo'))]
    assert not [name for name in names if '__pycache__' in name]


def test_sbom_describes_the_wheel() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        document = json.loads(archive.read('mixed-0.1.0.dist-info/sboms/mixed.cdx.json'))
        record = archive.read('mixed-0.1.0.dist-info/RECORD').decode()

    component = document['metadata']['component']
    tools = document['metadata']['tools']['components']

    assert document['bomFormat'] == 'CycloneDX'
    assert document['specVersion'] == '1.6'
    assert component['purl'] == 'pkg:pypi/mixed@0.1.0'
    assert [tool['name'] for tool in tools] == ['zig']
    assert document['components'] == []
    assert 'mixed-0.1.0.dist-info/sboms/mixed.cdx.json,sha256=' in record


def test_executable_runs_from_the_installed_scripts() -> None:
    root = Path(mixed.__file__).resolve().parent.parent
    name = 'mixed-shout.exe' if os.name == 'nt' else 'mixed-shout'
    found = [directory / name for directory in (root / 'bin', root / 'Scripts')]
    installed = [path for path in found if path.is_file()]

    assert len(installed) == 1, found

    command = [str(installed[0]), 'hello', 'zig']
    completed = subprocess.run(command, capture_output=True, check=False, text=True)

    assert completed.returncode == 0, completed.stderr
    assert completed.stdout == 'HELLO ZIG\n'


def test_executable_is_marked_executable_in_the_wheel() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        scripts = [member for member in archive.infolist() if '.data/scripts/' in member.filename]
        record = archive.read('mixed-0.1.0.dist-info/RECORD').decode()

    assert [member.filename.rpartition('/')[2] for member in scripts] in (
        ['mixed-shout'],
        ['mixed-shout.exe'],
    )

    assert (scripts[0].external_attr >> 16) & 0o777 == 0o755
    assert f'{scripts[0].filename},sha256=' in record
