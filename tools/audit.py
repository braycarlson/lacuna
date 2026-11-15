import re
import subprocess
import sys

from pathlib import Path


ABI3_TAG = '-abi3-'
ARGUMENT_COUNT = 3
CONSISTENT = re.compile(r'consistent with the following platform tag: "([^"]+)"')
POLICY = re.compile(r'(manylinux|musllinux)_(\d+)_(\d+)_(\w+)')


def main() -> None:
    if len(sys.argv) != ARGUMENT_COUNT:
        message = f'usage: {sys.argv[0]} <wheel> <platform tag>'
        raise SystemExit(message)

    wheel = Path(sys.argv[1])
    claimed = sys.argv[2].split('.')[0]
    audited = audited_tag(wheel)

    if not admits(claimed=claimed, audited=audited):
        message = f'{wheel.name} claims {claimed}, but auditwheel only admits {audited}'
        raise SystemExit(message)

    if ABI3_TAG in wheel.name:
        abi3_check(wheel)


def abi3_check(wheel: Path) -> None:
    if not wheel.is_file():
        message = f'{wheel} is not a file'
        raise SystemExit(message)

    command = [sys.executable, '-m', 'abi3audit', '--strict', '--verbose', str(wheel)]
    completed = subprocess.run(command, capture_output=True, check=False, text=True)

    if completed.returncode != 0:
        message = f'abi3audit rejected {wheel.name}:\n{completed.stdout}{completed.stderr}'
        raise SystemExit(message)


def admits(*, claimed: str, audited: str) -> bool:
    if not claimed:
        message = 'admits needs the platform tag the wheel claims'
        raise SystemExit(message)

    if not audited:
        message = 'admits needs the platform tag auditwheel reported'
        raise SystemExit(message)

    claimed_family, claimed_version, claimed_architecture = policy_of(claimed)
    audited_family, audited_version, audited_architecture = policy_of(audited)

    if claimed_family != audited_family:
        return False

    if claimed_architecture != audited_architecture:
        return False

    return audited_version <= claimed_version


def audited_tag(wheel: Path) -> str:
    if not wheel.is_file():
        message = f'{wheel} is not a file'
        raise SystemExit(message)

    command = [sys.executable, '-m', 'auditwheel', 'show', str(wheel)]
    completed = subprocess.run(command, capture_output=True, check=False, text=True)

    if completed.returncode != 0:
        message = f'auditwheel could not read {wheel.name}:\n{completed.stderr}'
        raise SystemExit(message)

    output = ' '.join(completed.stdout.split())
    matched = CONSISTENT.search(output)

    if matched is None:
        message = f'auditwheel reported no platform tag for {wheel.name}:\n{completed.stdout}'
        raise SystemExit(message)

    return matched.group(1)


def policy_of(tag: str) -> tuple[str, tuple[int, int], str]:
    if not tag:
        message = 'policy_of needs a platform tag'
        raise SystemExit(message)

    matched = POLICY.fullmatch(tag)

    if matched is None:
        message = f'{tag} is not a manylinux or musllinux platform tag'
        raise SystemExit(message)

    family, major, minor, architecture = matched.groups()

    return family, (int(major), int(minor)), architecture


if __name__ == '__main__':
    main()
