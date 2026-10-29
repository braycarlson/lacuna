import importlib.metadata
import io
import os
import zipfile

import pytest

import mixed


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


def test_bytecode_not_shipped() -> None:
    with zipfile.ZipFile(os.environ['LACUNA_WHEEL']) as archive:
        names = archive.namelist()

    assert 'mixed/helpers.py' in names
    assert not [name for name in names if name.endswith(('.pyc', '.pyo'))]
    assert not [name for name in names if '__pycache__' in name]
