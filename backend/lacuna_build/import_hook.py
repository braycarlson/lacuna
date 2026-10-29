import importlib.abc
import importlib.machinery
import json
import os
import sys

from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from lacuna_build import archive, project, zon


EDITABLE_PATTERN = '*_editable.json'
EDITABLE_COUNT_MAX = 256
SEARCH_PATH_COUNT_MAX = 4096
TREE_ENTRY_COUNT_MAX = 1 << 16


class ImportHookError(RuntimeError):
    pass


@dataclass(frozen=True)
class Editable:
    build_arguments: tuple[str, ...]
    names: frozenset[str]
    root: Path
    step: str
    tree: Path


class Finder(importlib.abc.MetaPathFinder):
    def __init__(self, editables: list[Editable]) -> None:
        self.checked: set[Path] = set()
        self.editables = editables

    def find_spec(
        self,
        fullname: str,
        path: Sequence[str] | None = None,
        target: ModuleType | None = None,
    ) -> None:
        del target

        if path is not None:
            return

        editable = editable_of(self.editables, fullname)

        if editable is None:
            return

        if editable.tree in self.checked:
            return

        self.checked.add(editable.tree)

        if stale(editable):
            rebuild(editable, fullname)


def install() -> Finder:
    uninstall()

    finder = Finder(editables_found(sys.path))
    sys.meta_path.insert(0, finder)

    return finder


def uninstall() -> None:
    sys.meta_path[:] = [entry for entry in sys.meta_path if not isinstance(entry, Finder)]


def editables_found(search_path: list[str]) -> list[Editable]:
    if len(search_path) > SEARCH_PATH_COUNT_MAX:
        message = f'sys.path holds more than {SEARCH_PATH_COUNT_MAX} entries'
        raise ImportHookError(message)

    result: list[Editable] = []

    for entry in search_path:
        directory = Path(entry or '.')

        if not directory.is_dir():
            continue

        result.extend(editable_load(record) for record in sorted(directory.glob(EDITABLE_PATTERN)))

    if len(result) > EDITABLE_COUNT_MAX:
        message = f'sys.path holds more than {EDITABLE_COUNT_MAX} lacuna editable installs'
        raise ImportHookError(message)

    return result


def editable_load(record: Path) -> Editable:
    fields = json.loads(record.read_text(encoding='utf-8'))
    expected = {'build_arguments', 'root', 'step', 'tree'}

    message = f'{record} is not a lacuna editable record'

    if not isinstance(fields, dict):
        raise ImportHookError(message)

    if set(fields) != expected:
        raise ImportHookError(message)

    texts = [fields['root'], fields['step'], fields['tree'], *fields['build_arguments']]

    if not all(isinstance(text, str) for text in texts):
        message = f'{record} holds a field that is not text'
        raise ImportHookError(message)

    tree = Path(fields['tree'])
    names = frozenset(name_of(child) for child in tree.iterdir()) if tree.is_dir() else frozenset()

    return Editable(
        build_arguments=tuple(fields['build_arguments']),
        names=names,
        root=Path(fields['root']),
        step=fields['step'],
        tree=tree,
    )


def name_of(child: Path) -> str:
    return child.name.partition('.')[0]


def editable_of(editables: list[Editable], fullname: str) -> Editable | None:
    for editable in editables:
        if fullname in editable.names:
            return editable

    return None


def stale(editable: Editable) -> bool:
    artifacts = artifacts_of(editable.tree)

    if not artifacts:
        return True

    built = min(artifact.stat().st_mtime_ns for artifact in artifacts)
    edited = max(source.stat().st_mtime_ns for source in sources_of(editable.root))

    return edited > built


def artifacts_of(tree: Path) -> list[Path]:
    suffixes = tuple(importlib.machinery.EXTENSION_SUFFIXES)
    result: list[Path] = []

    for count, (directory, _, files) in enumerate(os.walk(tree)):
        if count == TREE_ENTRY_COUNT_MAX:
            message = f'{tree} holds more than {TREE_ENTRY_COUNT_MAX} directories'
            raise ImportHookError(message)

        result.extend(Path(directory) / name for name in files if name.endswith(suffixes))

    return result


def sources_of(root: Path) -> list[Path]:
    manifest = zon.parse((root / 'build.zig.zon').read_text(encoding='utf-8'))
    listed = manifest.get('paths', [])

    if not isinstance(listed, list):
        message = f'{root / "build.zig.zon"} must list the files of the package in .paths'
        raise ImportHookError(message)

    names = ['build.zig', 'build.zig.zon', *map(str, listed)]

    return archive.files_under(root, names)


def rebuild(editable: Editable, fullname: str) -> None:
    try:
        arguments = [editable.step, *editable.build_arguments]
        project.zig_output(editable.root, arguments)
    except project.ProjectError as error:
        message = f'rebuilding {fullname} failed:\n{error}'
        raise ImportError(message, name=fullname) from error

    for artifact in artifacts_of(editable.tree):
        os.utime(artifact)
