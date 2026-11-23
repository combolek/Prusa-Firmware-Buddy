# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Coding style, commit message format and review rules live in `.claude/CLAUDE.md` and `doc/contributing.md` (both loaded automatically); they are not repeated here.

## This fork

This is a personal fork (`origin`) of `prusa3d/Prusa-Firmware-Buddy` (`upstream`). The upstream rule "main branch is called `private`" from `.claude/CLAUDE.md` does not apply here: `master` tracks `upstream/master`, and work happens on `coreone-ht*` branches (CORE One tweaks, mostly chamber temperature / filtration / safety timer limits) rebased on top of upstream releases.

## Local environment

- One CORE One+ printer, hostname `prusa`.
- It is connected to a self-hosted Prusa Connect server on `vapor`: `https://vapor:6443/` serves the web UI and API (used by `upload.sh`), and `https://vapor:6444/` is the printer connection endpoint. Everything stays on the LAN; nothing goes to the public Prusa Connect.
- Source of that Prusa Connect server: `/scratch/bolek/src/prusa-connect`. Check it for the API (endpoints, payloads, command verbs such as `core.command.flash`) instead of guessing from public docs.

## Building firmware

- `./build.sh`: builds the CORE One release firmware without a bootloader (`--preset coreone --bootloader empty`), with the version suffix taken from `git describe`. Extra args are passed to `utils/build.py`. Output: `build/products/coreone_release_emptyboot.bbf`. Re-running it is incremental (build dir `build/coreone_release_emptyboot/`, which also holds `compile_commands.json`).
- `./build.sh --upload`: builds, then runs `upload.sh` to push the `.bbf` through a Prusa Connect instance and trigger flashing on the printer. That has a real effect on a physical printer, so only run it when asked to.
- General form: `python utils/build.py --preset <name>[,<name>...] --build-type debug|release [--bootloader empty|yes|no] [-D VAR=VALUE]`. Presets are defined in `utils/presets/presets.json` (`CMakePresets.json` is generated from it by a pre-commit hook; don't edit it by hand). The toolchain, CMake and Ninja are downloaded by `utils/bootstrap.py` into `.dependencies/`.
- Python tools from `requirements.txt` (`prek`, `tree-sitter`, ...) live in the project venv `.venv/`, which `utils/bootstrap.py` creates with the Python it runs under and `utils/build.py` switches into. `.venv/bin` is not on `PATH`, so call its tools by path (`.venv/bin/prek`, `.venv/bin/python`). `build.sh` creates the venv by running `python3 utils/bootstrap.py` when `.venv` is missing. Every `utils/build.py` run also runs bootstrap (unless `--skip-bootstrap`), which installs `requirements.txt` and any dependency whose directory is missing, but never replaces an existing venv or SDK.
- The ESP8266 SDK (used to build the Wi-Fi firmware in a from-scratch build) has its own Python env per Python version, `.dependencies/esp8266-rtos-sdk-*/.idf-tools/python_env/rtos3.4_py<X.Y>_env`, created by bootstrap when it installs the SDK. Without one for the Python of `.venv`, the SDK falls back to `.venv` and fails with "Python requirements are not satisfied". After changing the Python of `.venv`, create it by running the SDK's `./install.sh` in its directory with `IDF_TOOLS_PATH=$PWD/.idf-tools`, `PIP_CONSTRAINT=$PWD/pip-constraint.txt` and `.venv/bin` first on `PATH`, as bootstrap does; don't install the SDK requirements into `.venv`.

## Unit tests

Unit tests are host-compiled (GCC recommended) with Catch2 and CTest, in `build/tests/`:

```bash
.venv/bin/python utils/build_tests.py --run -- -LE slow  # build + run fast tests
.venv/bin/python utils/build_tests.py <target>...        # build specific test targets (--list to see them)
.venv/bin/python utils/build_tests.py -t -- -R <regex>   # run only (no build), filter by test name
.venv/bin/python utils/build_tests.py --debug            # -Og for gdb
```

Tests live in `tests/unit/`, mirroring the `src/` paths. A new test directory needs a `CMakeLists.txt` and an `add_subdirectory` in its parent. See `tests/unit/README.md` for details. Integration tests (`tests/integration/`, pytest plus a QEMU simulator via `utils/simulator`) currently support only MK4 noboot builds.

## Lint / formatting

`.venv/bin/prek run -c .pre-commit-config.yaml`: clang-format, yapf, cmake-format, CMakePresets generation, and a check that forbids libc `assert` (use the project's own assert).

## Architecture

**One codebase, many printers.** The printer is chosen at configure time through the CMake cache variables `PRINTER` (MINI, MK4, MK3.5, XL, iX, COREONE, COREONEL, ...) and `BOARD` (BUDDY, XBUDDY, XLBUDDY, DWARF, MODULARBED, ...). Variant code is selected by:
- Feature options: `ProjectOptions.cmake` calls `define_boolean_option(NAME value)` (see `cmake/Options.cmake`), which generates `build/<dir>/include/option/<name>.h` defining `NAME()`. Code does `#include <option/has_foo.h>` and then `#if HAS_FOO()`. Forgetting the include is an error, not a silent false, because these are function-like macros.
- Printer macros in `include/printers.h` (`PRINTER_IS_PRUSA_COREONE()` etc.) and `BOARD_IS_*()`.
- Per-printer directories: `include/marlin/Configuration_<PRINTER>[_adv].h` (Marlin config), `src/gui/include_<PRINTER>/`, `src/marlin_stubs/<PRINTER>/`, and per-printer branches in `src/*/CMakeLists.txt`.

**Marlin is vendored and modified** in `lib/Marlin/`. Prusa-specific G-codes go in `src/marlin_stubs/` (`PrusaGcodeSuite`, dispatched from Marlin's gcode parser), not in Marlin itself.

**FreeRTOS tasks** are created in `src/buddy/main.cpp` (startup ordering via `TaskDeps` in `include/tasks.hpp`). The important ones:
- `marlin` (default task, `src/common/appmain.cpp`): runs the Marlin loop through `marlin_server` (`src/common/marlin_server.cpp`), which owns print state, media streaming, and the FSM dialogs that block a gcode while waiting for user input.
- `display` (`src/gui/guimain.cpp`): the GUI, built on the `src/guiapi/` window toolkit; screens and menus are in `src/gui/`.
- `network` / `connect`: PrusaLink web UI (`lib/WUI`) and the Prusa Connect client (`src/connect/`).
- `puppies` (XL / xBuddy extension): talks Modbus/CAN to secondary boards in `src/puppies/`; their own firmware is in `src/puppy/`.

The other tasks never touch Marlin globals directly. They talk to the server through `marlin_client` (requests/gcode injection) and read state from `marlin_vars` (`src/common/marlin_vars.hpp`, atomically readable mirrored variables).

**Features** (chamber, filtration, xbuddy_extension, safety_timer, filament sensors, ...) are self-contained modules in `src/feature/<name>/`.

**Persistent settings** go through `config_store` (`src/persistent_stores/store_instances/config_store/store_definition.hpp`), a journaled EEPROM store. Adding an item there is a persistent format change; removing or retyping one needs a migration (`migrations.cpp`).

**Other notes**
- The firmware build uses `-fno-exceptions -fno-rtti`.
- Logging: `LOG_COMPONENT_DEF` / `log_info(...)` (`doc/logging.md`). Metrics: `doc/metrics.md`. Debugging and profiling: `doc/debugging_profiling.md`.
