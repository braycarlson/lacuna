import os
import sys

import pytest

from pathlib import Path


ARGUMENT_COUNT = 4


def main() -> None:
    if len(sys.argv) != ARGUMENT_COUNT:
        message = f'usage: {sys.argv[0]} <lacuna root> <backend wheel> <test script>'
        raise SystemExit(message)

    os.environ['LACUNA_ROOT'] = str(Path(sys.argv[1]).resolve())
    os.environ['LACUNA_BACKEND_WHEEL'] = str(Path(sys.argv[2]).resolve())
    arguments = ['-p', 'no:cacheprovider', '-q', sys.argv[3]]
    status = pytest.main(arguments)

    raise SystemExit(status)


if __name__ == '__main__':
    main()
