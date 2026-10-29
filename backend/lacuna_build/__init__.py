import json
import shutil

from pathlib import Path

from lacuna_build import archive, project


__all__ = (
    'build_editable',
    'build_sdist',
    'build_wheel',
    'get_requires_for_build_editable',
    'get_requires_for_build_sdist',
    'get_requires_for_build_wheel',
    'prepare_metadata_for_build_editable',
    'prepare_metadata_for_build_wheel',
)

EDITABLE_TAG = 'py3-none-any'
GENERATOR = 'lacuna_build 0.1.0'
SDIST_REQUIRED = ('build.zig', 'build.zig.zon', 'pyproject.toml')


def project_current(config_settings: dict | None) -> project.Project:
    return project.project_load(Path.cwd(), config_settings)


def get_requires_for_build_wheel(config_settings: dict | None = None) -> list[str]:
    project.build_arguments_of(config_settings)

    return project.zig_requirements(Path.cwd())


def get_requires_for_build_sdist(config_settings: dict | None = None) -> list[str]:
    project.build_arguments_of(config_settings)

    return []


def get_requires_for_build_editable(config_settings: dict | None = None) -> list[str]:
    project.build_arguments_of(config_settings)

    return project.zig_requirements(Path.cwd())


def prepare_metadata_for_build_wheel(
    metadata_directory: str,
    config_settings: dict | None = None,
) -> str:
    built = project.metadata_build(project_current(config_settings))
    target = Path(metadata_directory) / built.name

    shutil.copytree(built, target, dirs_exist_ok=True)

    return built.name


def prepare_metadata_for_build_editable(
    metadata_directory: str,
    config_settings: dict | None = None,
) -> str:
    return prepare_metadata_for_build_wheel(metadata_directory, config_settings)


def build_wheel(
    wheel_directory: str,
    config_settings: dict | None = None,
    metadata_directory: str | None = None,
) -> str:
    del metadata_directory

    current = project_current(config_settings)
    suffix = project.interpreter_suffix()
    step = f'wheel-host{suffix}:{current.extension}'

    project.step_require(current, step=step, suffix=suffix)
    project.metadata_build(current)

    output = project.step_output(current, step=step, directory='dist')
    wheel = project.single_entry(output, '*.whl')
    target = Path(wheel_directory) / wheel.name

    shutil.copyfile(wheel, target)

    return wheel.name


def build_sdist(sdist_directory: str, config_settings: dict | None = None) -> str:
    current = project_current(config_settings)
    outside = current.dependencies_outside()

    if outside:
        message = (
            'a source distribution cannot carry path dependencies outside the project: '
            f'{", ".join(outside)}; depend on them by URL in build.zig.zon'
        )

        raise project.ProjectError(message)

    metadata = project.metadata_build(current) / 'METADATA'
    fields = project.metadata_fields(metadata.read_text(encoding='utf-8'))
    distribution = project.NAME_PATTERN.sub('_', fields['Name']).lower()
    prefix = f'{distribution}-{fields["Version"]}'
    listed = ['build.zig', 'build.zig.zon', 'pyproject.toml', *current.paths()]

    selected = archive.files_under(
        current.root,
        listed,
        include=current.sdist_include,
        exclude=current.sdist_exclude,
    )

    files = [(path.relative_to(current.root).as_posix(), path.read_bytes()) for path in selected]
    missing = sorted(set(SDIST_REQUIRED) - {name for name, _ in files})

    if missing:
        message = f'[tool.lacuna] sdist-exclude removes {", ".join(missing)} from the sdist'
        raise project.ProjectError(message)

    files.append(('PKG-INFO', metadata.read_bytes()))

    target = Path(sdist_directory) / f'{prefix}.tar.gz'

    archive.sdist_write(target, prefix, files)

    return target.name


def build_editable(
    wheel_directory: str,
    config_settings: dict | None = None,
    metadata_directory: str | None = None,
) -> str:
    del metadata_directory

    current = project_current(config_settings)
    suffix = project.interpreter_suffix()
    step = f'develop{suffix}:{current.extension}'

    project.step_require(current, step=step, suffix=suffix)

    metadata = project.metadata_build(current)
    directory = f'python{suffix}' if suffix else 'python'

    project.zig_run(current.root, [step, *current.build_arguments])

    tree = (current.root / 'zig-out' / directory).resolve()
    stem = metadata.name.removesuffix('.dist-info')
    distribution = stem.partition('-')[0]
    wheel_name = f'{stem}-{EDITABLE_TAG}.whl'

    wheel_text = (
        f'Wheel-Version: 1.0\nGenerator: {GENERATOR}\nRoot-Is-Purelib: true\nTag: {EDITABLE_TAG}\n'
    )

    record = {
        'build_arguments': list(current.build_arguments),
        'root': str(current.root.resolve()),
        'step': step,
        'tree': str(tree),
    }

    files = [
        (f'{distribution}_editable.pth', f'{tree}\n'.encode()),
        (f'{distribution}_editable.json', json.dumps(record, sort_keys=True).encode()),
    ]

    files.extend(
        (f'{metadata.name}/{path.name}', path.read_bytes()) for path in sorted(metadata.iterdir())
    )

    files.append((f'{metadata.name}/WHEEL', wheel_text.encode()))

    archive.wheel_write(Path(wheel_directory) / wheel_name, metadata.name, files)

    return wheel_name
