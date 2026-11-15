# lacuna

A library for CPython extension modules in Zig. A module is a plain Zig declaration of functions, classes, and enums, and the conversions to and from Python are derived at compile time. The library builds on Python's limited API, so one abi3 wheel covers each Python version from 3.11 onward, with free-threaded wheels alongside it. The `lacuna` command creates, builds, and publishes a project, and the `lacuna_build` PEP 517 backend generates `.pyi` stubs and builds wheels for Linux, macOS, Windows, and Android. The library fills the role that PyO3 and maturin fill for Rust.
