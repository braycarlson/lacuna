import importlib.util

import pytest

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
