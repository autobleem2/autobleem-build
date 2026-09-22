# CMake toolchain for the autobleem-build image's llvm-mingw (UCRT clang/mingw cross). Baked into the image
# at /opt/win-llvm.cmake; a Windows target uses it with -DCMAKE_TOOLCHAIN_FILE=/opt/win-llvm.cmake, which
# cross-compiles UCRT Windows binaries on a Linux runner (no windows-latest / setup-msys2 overhead).
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

set(_llvm /opt/llvm-mingw)
set(CMAKE_C_COMPILER   ${_llvm}/bin/x86_64-w64-mingw32-clang)
set(CMAKE_CXX_COMPILER ${_llvm}/bin/x86_64-w64-mingw32-clang++)
set(CMAKE_RC_COMPILER  ${_llvm}/bin/x86_64-w64-mingw32-windres)

set(CMAKE_FIND_ROOT_PATH ${_llvm}/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
