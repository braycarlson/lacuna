set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

[doc('Compile every example for every release and local-only platform')]
check:
    zig build check

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Install both example packages into zig-out/python')]
example:
    zig build example

[doc('Format every Zig source file and every Python file')]
fmt:
    zig fmt build.zig examples src templates tests/compile_fail
    uvx ruff format backend templates tests tools

[doc('Lint every Zig and Python file with tigerstyle-lsp, and the Python files with ruff')]
lint:
    tigerstyle-lsp check backend build.zig examples src templates tests tools --format concise
    uvx ruff check backend templates tests tools
    uvx ruff format --check backend templates tests tools

[default]
[doc('List every recipe')]
list:
    @just --list

[doc('Regenerate src/raw.zig from tools/stable_abi.toml and the Python 3.15 headers')]
raw:
    zig build raw "-Dpython-include={{ shell("uv run --no-project --python 3.15+gil python -c \"import sysconfig; print(sysconfig.get_paths()['include'])\"") }}"

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Check the extern declarations against the Python.h of the uv-selected interpreter')]
test-abi:
    zig build test:abi "-Dpython-include={{ shell("uv run --no-project python -c \"import sysconfig; print(sysconfig.get_paths()['include'])\"") }}"

[doc('Test every example under a debug Python and check each leak script for reference leaks')]
test-debug:
    zig build test:debug

[doc('Test every example under each PyPy and check the extern declarations against its headers')]
test-pypy:
    zig build test:pypy
    zig build test:abi "-Dpython-include={{ shell("uv run --no-project --python pypy@3.11 python -c \"import sysconfig; print(sysconfig.get_paths()['include'])\"") }}" -Dpython-pypy=3.11
    zig build test:abi "-Dpython-include={{ shell("uv run --no-project --python pypy@3.12 python -c \"import sysconfig; print(sysconfig.get_paths()['include'])\"") }}" -Dpython-pypy=3.12

[doc('Run the pytest suites against the package trees and the installed wheels')]
test-python:
    zig build test:python test:property test:wheel test:stub

[doc('Test every example under a ThreadSanitizer free-threaded CPython built into .zig-cache/tsan')]
[linux]
test-tsan:
    uv run --no-project python tools/tsan.py .zig-cache/tsan
    zig build test:tsan "-Dpython-tsan={{ justfile_directory() }}/.zig-cache/tsan/venv/bin/python"

[doc('Bind generated Zig types and signatures from a seed and check them against Python: just test-types [seed]')]
test-types seed="1":
    zig build test:types -Dtypes-seed={{ seed }}

[doc('Run the unit tests and the tidy check: just test-unit [filter]')]
test-unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run every example suite under valgrind memcheck against a ReleaseSafe x86_64_v3 build')]
[linux]
test-valgrind:
    uv venv --allow-existing --quiet .zig-cache/valgrind --python 3.14+gil
    uv pip install --quiet --python .zig-cache/valgrind/bin/python pytest
    PYTHONMALLOC=malloc zig build test:python -Doptimize=safe -Dcpu=x86_64_v3 -Dpython=valgrind -Dpython=--error-exitcode=99 -Dpython=--fair-sched=yes -Dpython=-q -Dpython=--track-origins=yes "-Dpython={{ justfile_directory() }}/.zig-cache/valgrind/bin/python"

[doc('Build a wheel of both examples for every release platform')]
wheel:
    zig build wheel
