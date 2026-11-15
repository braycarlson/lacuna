import contextlib
import importlib
import os
import sys
import zipfile

from pathlib import Path
from types import ModuleType


def backend() -> ModuleType:
    wheel = Path(os.environ['LACUNA_BACKEND_WHEEL'])
    location = str(wheel)

    assert wheel.suffix == '.whl'

    if location not in sys.path:
        sys.path.insert(0, location)

    with zipfile.ZipFile(wheel) as archive:
        assert 'lacuna_build/__init__.py' in archive.namelist()

    module = importlib.import_module('lacuna_build')

    assert module.__file__ is not None
    assert module.__file__.startswith(location)

    return module


def hook(
    project: Path,
    name: str,
    *arguments: str,
    config_settings: dict[str, object] | None = None,
) -> object:
    assert project.is_dir()
    assert not name.startswith('_')
    assert all(isinstance(argument, str) for argument in arguments)
    assert config_settings is None or all(isinstance(key, str) for key in config_settings)

    with contextlib.chdir(project):
        module = backend()

        assert name in module.__all__

        if config_settings is None:
            return getattr(module, name)(*arguments)

        return getattr(module, name)(*arguments, config_settings=config_settings)
