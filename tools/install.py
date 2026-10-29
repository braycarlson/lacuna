import os
import subprocess
import sys
import tempfile

from pathlib import Path


ARGUMENT_COUNT = 3


def main() -> None:
    if len(sys.argv) != ARGUMENT_COUNT:
        message = f'usage: {sys.argv[0]} <wheel> <test script>'
        raise SystemExit(message)

    with tempfile.TemporaryDirectory() as directory:
        wheel = Path(sys.argv[1]).resolve()
        script = Path(sys.argv[2]).resolve()
        target = Path(directory) / 'site'

        install = [
            sys.executable,
            '-m',
            'pip',
            'install',
            '--no-index',
            '--no-deps',
            '--quiet',
            '--disable-pip-version-check',
            '--target',
            target,
            wheel,
        ]

        installed = subprocess.run(install, check=False)

        if installed.returncode != 0:
            message = f'pip could not install {wheel}'
            raise SystemExit(message)

        run = [
            sys.executable,
            '-B',
            '-X',
            'dev',
            '-W',
            'error',
            '-m',
            'pytest',
            '-p',
            'no:cacheprovider',
            '-q',
            script,
        ]

        environment = os.environ | {'LACUNA_WHEEL': str(wheel), 'PYTHONPATH': str(target)}
        tested = subprocess.run(run, check=False, cwd=directory, env=environment)

    raise SystemExit(tested.returncode)


if __name__ == '__main__':
    main()
