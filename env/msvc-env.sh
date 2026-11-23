#!/usr/bin/env bash
#
# Source (do not execute) this to enter a shell configured for cross-compiling
# to Windows with MSVC:
#
#     . ~/projects/msvc-cross/env/msvc-env.sh
#
# It puts the msvc-wine wrappers on PATH, exports INCLUDE/LIB for native
# clang-cl, and -- the part that matters most for build times -- makes sure a
# persistent wineserver is running. Without one, every single cl.exe invocation
# pays a full Wine server startup and teardown, which dominates the wall clock
# of any real build.

export MSVC_WINE_ROOT="${MSVC_WINE_ROOT:-/opt/msvc}"
export MSVC_CROSS_ROOT="${MSVC_CROSS_ROOT:-$HOME/projects/msvc-cross}"
export WINEDEBUG="${WINEDEBUG:--all}"

# A build runs thousands of Windows processes. Anything that puts a window on
# the desktop turns one crashing tool into a wall of dialogs, and
# winemenubuilder would file a desktop entry for each executable it sees.
# msvc-cross-init-wine writes the same settings into the prefix permanently,
# which also covers builds started without sourcing this script.
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}winemenubuilder.exe=;werfault.exe=d;winedbg.exe=d"

# A prefix of its own, so that using Wine for actual Windows applications is not
# affected by the settings a build wants. See env/msvc-cross-init-wine.
export WINEPREFIX="${WINEPREFIX:-${MSVC_CROSS_WINEPREFIX:-$HOME/.wine-msvc}}"

if [ ! -x "$MSVC_WINE_ROOT/bin/x64/cl" ]; then
    echo "msvc-env: no toolchain at $MSVC_WINE_ROOT/bin/x64" >&2
    return 1 2>/dev/null || exit 1
fi

case ":$PATH:" in
    *":$MSVC_WINE_ROOT/bin/x64:"*) ;;
    *) export PATH="$MSVC_WINE_ROOT/bin/x64:$PATH" ;;
esac

# INCLUDE/LIB for clang-cl and lld-link. The CMake toolchain files bake these
# into the build tree themselves, so this is for ad-hoc command-line use.
BIN="$MSVC_WINE_ROOT/bin/x64" . "$MSVC_WINE_ROOT/msvcenv-native.sh"

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    "$MSVC_CROSS_ROOT/env/msvc-cross-init-wine"
fi

# Persistent wineserver, so cl.exe invocations do not each pay a full Wine server
# startup and teardown -- the single biggest factor in cross build times.
#
# Started with no display on purpose. The wineserver is what actually holds the
# X or Wayland connection, and every client of it inherits the ability to put a
# window on screen; a build tool that decides to show usage text or an error then
# interrupts whoever is at the keyboard. A server with no display connection
# cannot, no matter what its clients ask for.
#
# `wineserver -w` waits for the server to *exit* -- it is not a readiness probe --
# so detection looks for a process of that name started for this WINEPREFIX.
_msvc_env_runs_in_prefix() {
    local pid
    for pid in $(pgrep -u "$(id -u)" -x "$1" 2>/dev/null); do
        tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$WINEPREFIX" && return 0
    done
    return 1
}

if ! _msvc_env_runs_in_prefix wineserver; then
    env -u DISPLAY -u WAYLAND_DISPLAY wineserver -p
fi

# Boot the prefix's services (services.exe, winedevice, plugplay, rpcss, ...) now,
# from a process that holds nothing. Otherwise the first Wine program a build
# starts boots them, they inherit every descriptor that program had open and,
# kept alive by the persistent server, hold them forever: vcpkg then waits on its
# own lock file, and CMake waits for EOF on an execute_process pipe that never
# comes. So: stdio on /dev/null, every other descriptor closed, own session.
# /proc/self is the subshell here, as the glob is expanded without a fork; the
# {fd}>&- form closes descriptors above 9 in both bash and zsh.
if ! _msvc_env_runs_in_prefix services.exe; then
    if ! (
        for fd_path in /proc/self/fd/*; do
            fd="${fd_path##*/}"
            if [ "$fd" -gt 2 ]; then
                eval 'exec {fd}>&-' 2>/dev/null || :
            fi
        done
        exec env -u DISPLAY -u WAYLAND_DISPLAY setsid wine wineboot </dev/null >/dev/null 2>&1
    ); then
        echo "msvc-env: wineboot failed; the first build step will boot the Wine services instead" >&2
    fi
fi
unset -f _msvc_env_runs_in_prefix

echo "msvc-env: MSVC $(sed -n 's/^MSVCVER=//p' "$MSVC_WINE_ROOT/bin/x64/msvcenv.sh")" \
     "/ SDK $(sed -n 's/^SDKVER=//p' "$MSVC_WINE_ROOT/bin/x64/msvcenv.sh")" \
     "/ $(wine --version)"
