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

# Persistent wineserver, so cl.exe invocations do not each pay a full Wine
# server startup and teardown. Note that `wineserver -w` *waits for the server
# to exit* -- it is not a readiness probe -- so detection goes via pgrep.
if ! pgrep -u "$(id -u)" -x wineserver >/dev/null 2>&1; then
    wineserver -p
fi

echo "msvc-env: MSVC $(sed -n 's/^MSVCVER=//p' "$MSVC_WINE_ROOT/bin/x64/msvcenv.sh")" \
     "/ SDK $(sed -n 's/^SDKVER=//p' "$MSVC_WINE_ROOT/bin/x64/msvcenv.sh")" \
     "/ $(wine --version)"
