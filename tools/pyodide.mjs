import { basename, dirname, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [, , package_directory, wheel, tests, ...pytest_arguments] = process.argv;

if (pytest_arguments.length === 0) {
    throw new Error("usage: pyodide.mjs <pyodide package> <wheel> <tests> <pytest arguments>");
}

const entry = pathToFileURL(resolve(package_directory, "pyodide.mjs"));
const loaded = await import(entry.href);
const pyodide = await loaded.loadPyodide();

pyodide.mountNodeFS("/lacuna/wheel", resolve(dirname(wheel)));
pyodide.mountNodeFS("/lacuna/tests", resolve(tests));

await pyodide.loadPackage(["micropip", "pytest"]);

const micropip = pyodide.pyimport("micropip");

await micropip.install(`emfs:/lacuna/wheel/${basename(wheel)}`);

pyodide.globals.set("pytest_arguments", pyodide.toPy(pytest_arguments));

const status = await pyodide.runPythonAsync(`
import os
import sys

sys.dont_write_bytecode = True
os.chdir('/lacuna/tests')

import pytest

int(pytest.main(['-p', 'no:cacheprovider', *pytest_arguments]))
`);

process.exit(status);
