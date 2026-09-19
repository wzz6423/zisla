# yyjson 0.12.0

- Upstream: https://github.com/ibireme/yyjson
- Release: https://github.com/ibireme/yyjson/releases/tag/0.12.0
- Commit: `8b4a38dc994a110abaec8a400615567bd996105f`
- Imported files: `src/yyjson.c`, `src/yyjson.h`, and `LICENSE`
- License: MIT

The imported files are unmodified. Zisla disables the writer, incremental reader,
JSON Pointer/Patch utilities, and non-standard JSON at compile time because the
Windows activity detectors only read standard JSONL records.
The amalgamated source is compiled as C++20 so the CMake and MSVC builds use the
same language mode; upstream's public declarations preserve C linkage.
