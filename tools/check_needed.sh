#!/usr/bin/env bash
# check_needed.sh KEY STAGE [EXTRA_GLOB] - does the package carry every library its program needs?
#
# The rule (autobleem-main docs/decisions.md, "Third-party App ports"): a package brings its own libraries in
# lib/<key>/, except what every machine of the platform has - the C library family, the compiler's runtime,
# the graphics stack - and the SDL2 family (the launcher's own on the console and on Windows, the system's on
# the Pis and the PC stick). So each library the program or a bundled library names must be one of those, or
# be in lib/<key>/. Exit 1 on anything else.
#
# EXTRA_GLOB (optional, non-win only) is a further set of binaries to check besides the program's own stage
# and lib/<key>/ - e.g. a port that ships plugin .so files outside lib/<key>/ passes its plugins directory
# glob, such as "$stage/plugins/*.so*".
set -euo pipefail
key="$1"
stage="$2"
extra="${3:-}"
libdir="$stage/lib/$key"

status=0
if [ "$key" = win ]; then
    objdump=x86_64-w64-mingw32-objdump
    # the system DLLs a MinGW program may import, and the launcher's SDL2 family (SDL2, SDL2_image, _mixer, _ttf)
    allowed='^(kernel32|user32|gdi32|winmm|imm32|ole32|oleaut32|shell32|shlwapi|comctl32|comdlg32|uxtheme|xinput1_[34]|xinput9_1_0|version|setupapi|advapi32|msvcrt|ucrtbase|ws2_32|iphlpapi|cfgmgr32|api-ms-win-.*|sdl2(_image|_mixer|_ttf)?)\.dll$'
    for f in "$stage"/bin/win/*.exe "$libdir"/*.dll; do
        [ -f "$f" ] || continue
        for dll in $("$objdump" -p "$f" | sed -n 's/^\s*DLL Name: //p' | tr -d '\r'); do
            lower=$(echo "$dll" | tr 'A-Z' 'a-z')
            if echo "$lower" | grep -qE "$allowed"; then continue; fi
            if [ -f "$libdir/$dll" ]; then continue; fi
            echo "    ERROR: $(basename "$f") needs $dll, which is neither the system's, SDL2 nor in lib/win/"
            status=1
        done
    done
else
    allowed='^(libc|libm|libdl|libpthread|librt|libresolv|libutil|ld-linux[-a-z0-9_.]*|libgcc_s|libstdc\+\+|libSDL2-2\.0|libSDL2_image-2\.0|libSDL2_mixer-2\.0|libSDL2_ttf-2\.0|libasound|libEGL|libGLESv2|libGL|libwayland-[a-z]+|libdrm)\.so'
    for f in "$stage"/bin/"$key"/* "$libdir"/*.so* ${extra:+$extra}; do
        [ -f "$f" ] || continue
        for lib in $(readelf -d "$f" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
            if echo "$lib" | grep -qE "$allowed"; then continue; fi
            if [ -f "$libdir/$lib" ]; then continue; fi
            echo "    ERROR: $(basename "$f") needs $lib, which is neither the system's, SDL2 nor in lib/$key/"
            status=1
        done
    done
fi
[ "$status" -eq 0 ] && echo "    $key: every library is the system's, SDL2 or in lib/$key/"
exit $status
