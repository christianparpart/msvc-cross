# msvc-cross

Build genuine Windows binaries with the Microsoft C++ compiler, from Linux,
without a Windows machine or VM anywhere in the loop.

This repository is the thin glue layer on top of
[mstorsjo/msvc-wine](https://github.com/mstorsjo/msvc-wine): CMake toolchain
files, an environment script, a shared CMake preset fragment, a vcpkg overlay
triplet, and a smoke-test project that proves the whole thing works.

The output is a real `PE32+ executable ... x86-64` built by `cl.exe` against the
Microsoft STL and the Windows SDK — not a MinGW binary, not an approximation.

```console
$ file build/hello.exe
build/hello.exe: PE32+ executable for MS Windows 6.00 (console), x86-64, 6 sections
$ wine build/hello.exe
hello, windows
_MSC_VER=1951 __cplusplus=199711
MSVC ABI OK
```

## Two toolchains, one MSVC installation

| | `msvc-wine-x64.cmake` | `clang-cl-x64.cmake` |
|---|---|---|
| Compiler | Microsoft `cl.exe`, run under Wine | `clang-cl`, running natively on Linux |
| Linker | Microsoft `link.exe`, under Wine | `lld-link`, native |
| Headers / import libs | MSVC + Windows SDK | the same MSVC + Windows SDK |
| ABI | MSVC | MSVC |
| Wine used at build time | yes | **no** |
| Use it for | fidelity — this is the real compiler | iteration — no Wine in the compile path |

Both come out of a single `vsdownload.py` download. They produce
interchangeable binaries and can be pointed at the same source tree from
different build directories.

The `clang-cl` toolchain is not a fallback. Some projects only ever exercise
clang-cl on Windows in CI, and for those it is the *better-tested* path.

## Requirements

- Wine (`wine64`)
- `msitools` ≥ 0.98 and `libgcab` ≥ 1.2 — `vsdownload.py` extracts MSI payloads
- `lld` — provides `lld-link`, for the clang-cl toolchain
- CMake ≥ 3.25, Ninja
- Python 3

On Fedora:

```sh
sudo dnf install -y wine msitools lld cmake ninja-build
```

`samba-winbind` is worth having as a backstop: `mspdbsrv.exe` needs it if a
build ever falls back to `/Zi`. The toolchain files avoid that by default.

## Setup

```sh
# 1. Get msvc-wine and prepare a Wine prefix dedicated to building
git clone https://github.com/mstorsjo/msvc-wine ~/projects/msvc-wine
~/projects/msvc-cross/env/msvc-cross-init-wine

# 2. Download MSVC + the Windows SDK from Microsoft, and install
sudo mkdir -p /opt/msvc && sudo chown "$USER:$USER" /opt/msvc
cd ~/projects/msvc-wine
./vsdownload.py --accept-license --dest /opt/msvc --architecture x64 \
                --cache ~/.cache/msvc-wine-pkgs
./install.sh /opt/msvc
cp msvcenv-native.sh /opt/msvc/

# 3. Enter a cross shell
. ~/projects/msvc-cross/env/msvc-env.sh
```

`--architecture x64` trims the download to a single target. `--cache` is worth
setting: adding a second toolset later (see *Pinning a toolset* below) then
becomes a partial download instead of a full one.

You are accepting Microsoft's Visual Studio Build Tools licence when you pass
`--accept-license`. The resulting toolchain is **not redistributable**.

## Using it

Point CMake at one of the toolchain files:

```sh
cmake -S . -B build -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=$MSVC_CROSS_ROOT/toolchains/msvc-wine-x64.cmake \
      -DCMAKE_BUILD_TYPE=Release
cmake --build build
ctest --test-dir build          # tests run under Wine automatically
```

Or, in a project that uses CMake presets, drop a `CMakeUserPresets.json` next to
its `CMakePresets.json`:

```json
{
  "version": 7,
  "include": ["$penv{HOME}/projects/msvc-cross/presets/windows-cross.json"],
  "configurePresets": [
    {
      "name": "msvc-cross-location",
      "hidden": true,
      "environment": { "MSVC_CROSS_ROOT": "$penv{HOME}/projects/msvc-cross" }
    },
    {
      "name": "cross-cl-release",
      "inherits": ["msvc-cross-location", "msvc-wine-x64", "base"],
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Release" }
    }
  ]
}
```

Inheriting the project's own hidden base preset keeps its generator, build
directory layout and options; the fragment here contributes only the toolchain
and two cross-cutting cache variables. Note the inheritance order --
`msvc-cross-location` must come before `msvc-wine-x64`, because the latter's
`toolchainFile` reads `$env{MSVC_CROSS_ROOT}`.

Two details are worth copying rather than simplifying:

- **`$penv{...}`, not `$env{...}`, in `include`.** CMake only expands
  `$penv{}` there. `${fileDir}` is no help either: it resolves against the file
  doing the *including*, not the fragment, so a fragment cannot locate itself.
- **Resolve the location from `$penv{HOME}` rather than requiring
  `MSVC_CROSS_ROOT` to be exported.** An unresolvable `include` is a hard error
  that takes down the *whole* preset file, so a missing environment variable
  would break the project's ordinary Linux presets too, not just the cross ones.

## What the toolchain files do that a hand-written one would miss

**`CMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded`** (`/Z7`, not `/Zi`). `/Zi`
routes every compilation through a single `mspdbsrv.exe`, which serialises the
build under Wine and additionally requires winbind. Embedded debug info keeps
each `cl.exe` independent, which is what makes parallel builds worth anything.

**`CMAKE_CROSSCOMPILING_EMULATOR=wine`**, so `ctest`, `catch_discover_tests` and
`POST_BUILD` commands can run the binaries they just produced.

**`CMAKE_POLICY_VERSION_MINIMUM=3.5`** in the preset fragment. CMake 4 rejects
`cmake_minimum_required(VERSION <3.5)`, which plenty of vendored dependencies
still declare.

**`CMAKE_CATCH_DISCOVER_TESTS_DISCOVERY_MODE=PRE_TEST`**. Catch2's default
`POST_BUILD` mode executes every test binary during the *build* just to
enumerate test cases.

**`-imsvc` rather than `-I`** for the MSVC and SDK headers on the clang-cl side,
so `/W4` — and `/WX`, where a project enables it — never fires on Microsoft's
own headers.

**No pinned `CMAKE_<LANG>_COMPILER_ID`.** CMake identifies the wrappers as MSVC
on its own. Pinning it makes `Windows-MSVC.cmake` read
`CMAKE_C_COMPILER_VERSION` even in projects that never enable C, which is empty,
and the configure aborts with *"MSVC compiler version not detected properly"*.

## Pinning a toolset

`vsdownload.py` defaults to the newest Visual Studio. To install an older
toolset alongside it rather than instead of it:

```sh
./vsdownload.py --accept-license --dest /opt/msvc-14.44 \
                --msvc-version 14.44 --architecture x64 \
                --cache ~/.cache/msvc-wine-pkgs
./install.sh /opt/msvc-14.44
```

Then select it per build tree with `-DMSVC_WINE_ROOT=/opt/msvc-14.44`. The
`clang-cl` toolchain reads the toolset version out of the installation and sets
`-fms-compatibility-version` to match, so `_MSC_VER` stays consistent between
the two compilers.

## vcpkg

`vcpkg-triplets/x64-windows.cmake` is an overlay triplet that chainloads the
`cl.exe` toolchain:

```sh
vcpkg install ms-gsl:x64-windows --overlay-triplets=$MSVC_CROSS_ROOT/vcpkg-triplets
```

`vcpkg-triplets/x64-windows-clangcl.cmake` is the same thing for the clang-cl
toolchain. It is a separate triplet rather than a switch because vcpkg keys its
binary cache on the triplet name, and sharing one name between two compilers
would let a `cl.exe`-built package satisfy a `clang-cl` build from cache. The two
are ABI-compatible, so it would usually work — which is what makes it a bad
thing to leave to chance.

Neither file sets `VCPKG_CMAKE_SYSTEM_NAME`, and that is deliberate rather than an
oversight. vcpkg spells "the target is Windows" as an *empty*
`VCPKG_CMAKE_SYSTEM_NAME`; setting it to `Windows` matches none of its branches
and leaves `VCPKG_TARGET_IS_WINDOWS` off, so ports take their Unix path while the
compiler underneath is still MSVC. openssl then runs its `./Configure` for a Unix
target and fails in a way that says nothing about the cause. What makes the build
target Windows is the chainloaded toolchain, which sets `CMAKE_SYSTEM_NAME`
itself.

Two things to expect when building ports this way:

- **`mspdbsrv.exe` can wedge vcpkg.** The MSVC PDB server outlives the compiler
  that spawned it and inherits its file descriptors, vcpkg's lock file among
  them, so a later `vcpkg install` fails with *"another vcpkg may be running
  against the same directory"* and no vcpkg is running at all. Kill the stray
  `mspdbsrv.exe` and remove the `vcpkg-running.lock` files. The toolchains ask
  for `/Z7` precisely to keep it out of the picture, but a port that sets its own
  debug information format can still bring it back.
- Ports that need a Windows-hosted build tool of their own — anything reaching
  for `nasm`, `perl` or a prebuilt `.exe` — are where this stops being routine.

## Keeping a build off the desktop

A build starts thousands of short-lived Windows processes, and Wine's defaults
assume you are running an application rather than a toolchain. Anything that
decides to show something puts it on screen: Qt's `QCommandLineParser` reports
usage through a `MessageBox` when the process has no console, Wine allocates a
console window for a console program with output to show, and a crash becomes a
dialog that blocks its process until dismissed. During a parallel build that is
a stream of windows over whatever you were doing.

`env/msvc-cross-init-wine` creates a prefix at `~/.wine-msvc`, separate from
`~/.wine` so ordinary Wine use is unaffected, and `env/msvc-env.sh` starts its
`wineserver` **with no display connection at all**. That is the part that holds:
the wineserver owns the X or Wayland connection and every client inherits its
ability to create a window, so unsetting `DISPLAY` for one client changes
nothing once a display-capable server is already running. Test binaries still
run; they run headless, which is what Qt's `offscreen` platform plugin is for.

What this deliberately does *not* do is force Wine's null graphics driver
(`HKCU\Software\Wine\Drivers\Graphics = ""`). That looks like a stronger form
of the same thing and is worse: a test probing for a native rendering backend
gets far enough to enumerate Vulkan devices through `winevulkan` and then fails,
where against a displayless wineserver it finds no backend and skips cleanly. A
false failure is worse than an honest skip.


## Notes and gotchas

- **Keep a `wineserver` alive.** Without a persistent one, every `cl.exe`
  invocation pays a full Wine server startup and teardown — the single biggest
  factor in cross build times. `env/msvc-env.sh` starts one. Beware that
  `wineserver -w` *waits for the server to exit*; it is not a readiness probe,
  and using it as one hangs.
- **`CMAKE_CROSSCOMPILING_EMULATOR` is `bin/wine-exec`, not `wine`.** CTest and
  the test frameworks it drives pass absolute host paths to the binary under
  test, and a Windows command line parser reads a leading `/` as the start of an
  option. Catch2 receives `--out /home/you/build/listing.json` as "`--out` with
  no argument", fails discovery, and reports a perfectly good binary as broken.
  `wine-exec` rewrites such arguments to `Z:\...` first, conservatively enough
  that `/nologo` and `/W4` are left alone.
- **Qt applications need a `qt.conf`.** Qt's plugins and QML modules are loaded
  by path rather than linked, so nothing copies them next to the executable and
  nothing points at them. Qt then reports "no Qt platform plugin could be
  initialized" through a message box and calls `qFatal`, which is `abort()`,
  which MSVC raises as `__fastfail` — so a headless run shows no output
  whatsoever and exits `0xC0000409`, which reads like memory corruption and is
  nothing of the sort. A two-line `qt.conf` naming the Qt prefix settles it,
  along with the Qt kit's `bin` on `WINEPATH` for the plugins' own DLLs.
- **CMake has no C++26 for MSVC.** `CMAKE_CXX26_STANDARD_COMPILE_OPTION` is unset
  for MSVC at every version, so requesting the dialect is a hard generation error
  rather than a failed feature probe. `CMAKE_CXX_STANDARD_LATEST` — 23 for MSVC,
  26 for GCC and Clang — is the variable to branch on.
- **Path length.** MSVC still enforces roughly 260 characters, and Wine's `z:\`
  prefix eats into that budget. Short install and build paths help.
- **`__cplusplus` reports `199711` under `cl.exe`** unless the project passes
  `/Zc:__cplusplus`. That is real MSVC behaviour faithfully reproduced, not an
  artifact of this setup.
- `binfmt_misc` with `windowsPE` registered (Fedora's `wine` package does this)
  lets Windows `.exe` files run by path, which is what allows a Windows Qt kit's
  `moc.exe` and `rcc.exe` to serve as build tools directly. They need the execute
  bit, which `aqt` does not set.

## Smoke test

```sh
cd test/hello
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=../../toolchains/msvc-wine-x64.cmake
cmake --build build && ctest --test-dir build --output-on-failure
```

It exercises a static library, a `.rc` resource, a Win32 import library
(`ws2_32`) and `std::format`, then runs the result under Wine.

## Licence

The contents of this repository are provided as-is. The MSVC toolchain it
downloads is Microsoft's, is covered by their licence, and is not
redistributable.
