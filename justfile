set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-c"]

[doc('Check the extern declarations against the Python.h of the uv-selected interpreter')]
abi:
    zig build test:abi "-Dpython-include={{ shell('uv run --no-project python -c "import sysconfig; print(sysconfig.get_paths()[\"include\"])"') }}"

[doc('Compile every example for every release and local-only platform')]
check:
    zig build check

[doc('Run the continuous integration pipeline')]
ci:
    zig build ci
    zig build test:unit -Doptimize=safe

[doc('Test every example under a debug Python and check each leak script for reference leaks')]
debug:
    zig build test:debug

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

[doc('Test every example under each PyPy and check the extern declarations against its headers')]
pypy:
    zig build test:pypy
    zig build test:abi "-Dpython-include={{ shell('uv run --no-project --python pypy@3.11 python -c "import sysconfig; print(sysconfig.get_paths()[\"include\"])"') }}" -Dpython-pypy=3.11
    zig build test:abi "-Dpython-include={{ shell('uv run --no-project --python pypy@3.12 python -c "import sysconfig; print(sysconfig.get_paths()[\"include\"])"') }}" -Dpython-pypy=3.12

[doc('Run the pytest suites against the package trees and the installed wheels')]
python:
    zig build test:python test:property test:wheel test:stub

[doc('Run every test suite and the format check')]
test:
    zig build test

[doc('Test every example under a ThreadSanitizer free-threaded CPython built into .zig-cache/tsan')]
[linux]
tsan:
    uv run --no-project python tools/tsan.py .zig-cache/tsan
    zig build test:tsan "-Dpython-tsan={{ justfile_directory() }}/.zig-cache/tsan/venv/bin/python"

[doc('Run the unit tests and the tidy check: just unit [filter]')]
unit filter="":
    zig build test:unit {{ if filter == "" { "" } else { "-Dtest-filter=" + filter } }}

[doc('Run every example suite under valgrind memcheck against a ReleaseSafe x86_64_v3 build')]
[linux]
valgrind:
    uv venv --allow-existing --quiet .zig-cache/valgrind --python 3.14+gil
    uv pip install --quiet --python .zig-cache/valgrind/bin/python pytest
    PYTHONMALLOC=malloc zig build test:python -Doptimize=safe -Dcpu=x86_64_v3 -Dpython=valgrind -Dpython=--error-exitcode=99 -Dpython=-q -Dpython=--track-origins=yes "-Dpython={{ justfile_directory() }}/.zig-cache/valgrind/bin/python"

[doc('Build a wheel of both examples for every release platform')]
wheel:
    zig build wheel
