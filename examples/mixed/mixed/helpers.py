import sys

from mixed._native import greet


ARGUMENT_COUNT_MAX = 2


class Registered(type):
    registry = tuple[type, ...]()

    def __init__(cls, name: str, bases: tuple[type, ...], namespace: dict[str, object]) -> None:
        if name != cls.__name__:
            message = f'{name!r} does not name the class {cls.__name__!r}'
            raise ValueError(message)

        if not isinstance(bases, tuple):
            message = f'bases must be a tuple, not {type(bases).__name__}'
            raise TypeError(message)

        if not isinstance(namespace, dict):
            message = f'namespace must be a dict, not {type(namespace).__name__}'
            raise TypeError(message)

        super().__init__(name, bases, namespace)
        Registered.registry = (*Registered.registry, cls)

    def __repr__(cls) -> str:
        return f'<registered {cls.__name__}>'


def main() -> None:
    if len(sys.argv) > ARGUMENT_COUNT_MAX:
        message = f'usage: {sys.argv[0]} [name]'
        raise SystemExit(message)

    name = sys.argv[1] if len(sys.argv) == ARGUMENT_COUNT_MAX else 'world'
    line = greet(name) + '\n'
    written = sys.stdout.write(line)

    if written != len(line):
        message = f'wrote {written} of {len(line)} characters'
        raise OSError(message)


def shout(name: str) -> str:
    if not name:
        message = 'shout needs a non-empty name'
        raise ValueError(message)

    return greet(name).upper()
