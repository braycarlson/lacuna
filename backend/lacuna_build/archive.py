import base64
import fnmatch
import gzip
import hashlib
import io
import tarfile
import zipfile

from pathlib import Path


DATE_TIME = (1980, 1, 1, 0, 0, 0)
ENTRY_COUNT_MAX = 1 << 16
EXCLUDED_NAMES = frozenset({'.git', '.zig-cache', '__pycache__', 'zig-out'})
TIMESTAMP = 315532800


class ArchiveError(RuntimeError):
    pass


def files_under(
    root: Path,
    listed: list[str],
    *,
    include: tuple[str, ...] = (),
    exclude: tuple[str, ...] = (),
) -> list[Path]:
    if not root.is_dir():
        message = f'{root} is not a directory to collect files from'
        raise ValueError(message)

    if not listed:
        message = f'listed must name at least one path under {root}'
        raise ValueError(message)

    if not isinstance(include, tuple):
        message = f'include must be a tuple of glob patterns, not {type(include).__name__}'
        raise TypeError(message)

    if not isinstance(exclude, tuple):
        message = f'exclude must be a tuple of glob patterns, not {type(exclude).__name__}'
        raise TypeError(message)

    result: set[Path] = set()

    for name in listed:
        path = root / name

        if not path.exists():
            message = f'build.zig.zon lists {name} in .paths, but it does not exist'
            raise ArchiveError(message)

        if path.is_file():
            result.add(path)
        else:
            result.update(directory_files(path))

    for pattern in include:
        result.update(path for path in root.glob(pattern) if admitted(root=root, path=path))

    result = {path for path in result if not excluded(root=root, path=path, patterns=exclude)}

    if len(result) > ENTRY_COUNT_MAX:
        message = f'the source distribution holds more than {ENTRY_COUNT_MAX} files'
        raise ArchiveError(message)

    return sorted(result)


def admitted(*, root: Path, path: Path) -> bool:
    if not path.is_relative_to(root):
        message = f'{path} does not lie under {root}'
        raise ValueError(message)

    relative = path.relative_to(root)

    if not path.is_file():
        return False

    if path.suffix == '.pyc':
        return False

    return not any(part in EXCLUDED_NAMES for part in relative.parts)


def excluded(*, root: Path, path: Path, patterns: tuple[str, ...]) -> bool:
    if not path.is_relative_to(root):
        message = f'{path} does not lie under {root}'
        raise ValueError(message)

    if not isinstance(patterns, tuple):
        message = f'patterns must be a tuple of glob patterns, not {type(patterns).__name__}'
        raise TypeError(message)

    relative = path.relative_to(root).as_posix()

    return any(fnmatch.fnmatchcase(relative, pattern) for pattern in patterns)


def directory_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        message = f'{directory} is not a directory'
        raise ArchiveError(message)

    result: list[Path] = []
    pending = [directory]

    for _ in range(ENTRY_COUNT_MAX):
        if not pending:
            break

        current = pending.pop()

        for child in sorted(current.iterdir()):
            if child.name in EXCLUDED_NAMES:
                continue

            if child.suffix == '.pyc':
                continue

            if child.is_dir():
                pending.append(child)
            else:
                result.append(child)

    if pending:
        message = f'{directory} holds too many directories for a source distribution'
        raise ArchiveError(message)

    return result


def sdist_write(target: Path, prefix: str, files: list[tuple[str, bytes]]) -> None:
    if target.name != f'{prefix}.tar.gz':
        message = f'the source distribution {target.name} must be named {prefix}.tar.gz'
        raise ValueError(message)

    if 'PKG-INFO' not in dict(files):
        message = f'the source distribution {target.name} carries no PKG-INFO'
        raise ValueError(message)

    buffer = io.BytesIO()

    with tarfile.open(fileobj=buffer, mode='w', format=tarfile.PAX_FORMAT) as archive:
        for name, content in sorted(files):
            information = tarfile.TarInfo(f'{prefix}/{name}')
            information.size = len(content)
            information.mtime = TIMESTAMP
            information.mode = 0o644
            information.uid = 0
            information.gid = 0
            information.uname = ''
            information.gname = ''
            stream = io.BytesIO(content)

            archive.addfile(information, stream)

    compressed = gzip.compress(buffer.getvalue(), mtime=TIMESTAMP)

    target.write_bytes(compressed)


def record_hash(content: bytes) -> str:
    if not isinstance(content, bytes):
        message = f'a RECORD hash covers bytes, not {type(content).__name__}'
        raise TypeError(message)

    digest = hashlib.sha256(content).digest()
    encoded = base64.urlsafe_b64encode(digest).rstrip(b'=').decode('ascii')

    return f'sha256={encoded}'


def wheel_write(target: Path, metadata_directory: str, files: list[tuple[str, bytes]]) -> None:
    if target.suffix != '.whl':
        message = f'{target} is not named like a wheel'
        raise ValueError(message)

    if not metadata_directory.endswith('.dist-info'):
        message = f'{metadata_directory} is not a .dist-info directory'
        raise ValueError(message)

    if len(dict(files)) != len(files):
        message = f'the wheel {target.name} lists a file name twice'
        raise ValueError(message)

    record_name = f'{metadata_directory}/RECORD'
    lines = [f'{name},{record_hash(content)},{len(content)}' for name, content in files]

    lines.append(f'{record_name},,')

    with zipfile.ZipFile(target, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        record = ('\n'.join(lines) + '\n').encode('utf-8')

        for name, content in [*files, (record_name, record)]:
            information = zipfile.ZipInfo(name, date_time=DATE_TIME)
            information.compress_type = zipfile.ZIP_DEFLATED
            information.external_attr = 0o644 << 16

            archive.writestr(information, content)
