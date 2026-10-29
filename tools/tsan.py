import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

from pathlib import Path


ARGUMENT_COUNT = 2
CPYTHON_SHA256 = 'a65b20a728f169f4e66ae143f40b1bd3d33c38d770251663f627c9767b79b210'
CPYTHON_VERSION = '3.14.8'
CPYTHON_URL = f'https://www.python.org/ftp/python/{CPYTHON_VERSION}/Python-{CPYTHON_VERSION}.tgz'
INTERPRETER_NAME = 'python3.14t'


def main() -> None:
    if len(sys.argv) != ARGUMENT_COUNT:
        message = f'usage: {sys.argv[0]} <directory>'
        raise SystemExit(message)

    root = Path(sys.argv[1]).resolve()
    prefix = root / 'prefix'
    interpreter = prefix / 'bin' / INTERPRETER_NAME
    environment = root / 'venv'

    root.mkdir(parents=True, exist_ok=True)

    if not interpreter.is_file():
        interpreter_build(prefix)

    if not interpreter.is_file():
        message = f'the build finished without producing {interpreter}'
        raise SystemExit(message)

    venv = [
        'uv',
        'venv',
        '--allow-existing',
        '--quiet',
        str(environment),
        '--python',
        str(interpreter),
    ]

    install = [
        'uv',
        'pip',
        'install',
        '--quiet',
        '--python',
        str(environment / 'bin' / 'python'),
        'pytest',
    ]

    step_run(venv, source=root, environment=os.environ.copy())
    step_run(install, source=root, environment=os.environ.copy())


def archive_fetch(target: Path) -> None:
    with urllib.request.urlopen(CPYTHON_URL) as response:
        content = response.read()

    digest = hashlib.sha256(content).hexdigest()

    if digest != CPYTHON_SHA256:
        message = f'{CPYTHON_URL} has sha256 {digest}, expected {CPYTHON_SHA256}'
        raise SystemExit(message)

    target.write_bytes(content)


def interpreter_build(prefix: Path) -> None:
    compiler = shutil.which('clang')

    if compiler is None:
        message = 'building a ThreadSanitizer CPython needs clang on PATH'
        raise SystemExit(message)

    with tempfile.TemporaryDirectory() as directory:
        workspace = Path(directory)
        archive = workspace / 'cpython.tgz'

        archive_fetch(archive)

        with tarfile.open(archive) as bundle:
            bundle.extractall(workspace, filter='data')

        source = workspace / f'Python-{CPYTHON_VERSION}'
        environment = os.environ | {'CC': compiler}

        configure = [
            './configure',
            '--disable-gil',
            '--with-thread-sanitizer',
            '--without-ensurepip',
            f'--prefix={prefix}',
        ]

        jobs = str(os.cpu_count() or 1)

        step_run(configure, source=source, environment=environment)
        step_run(['make', f'-j{jobs}'], source=source, environment=environment)
        step_run(['make', 'install'], source=source, environment=environment)


def step_run(command: list[str], *, source: Path, environment: dict[str, str]) -> None:
    completed = subprocess.run(command, cwd=source, env=environment, check=False)

    if completed.returncode != 0:
        message = f'{" ".join(command)} exited with {completed.returncode}'
        raise SystemExit(message)


if __name__ == '__main__':
    main()
