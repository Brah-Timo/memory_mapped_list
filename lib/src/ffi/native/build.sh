#!/usr/bin/env bash
# build.sh — compile mml_native for the current POSIX platform.
#
# Usage:
#   chmod +x build.sh && ./build.sh
#
# On macOS the script produces mml_native.dylib; on Linux/Android it produces
# mml_native.so.  Windows users should use CMakeLists.txt with Visual Studio
# or MinGW.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/mml_native.c"

OS="$(uname -s)"

case "${OS}" in
  Darwin*)
    OUTPUT="${SCRIPT_DIR}/mml_native.dylib"
    gcc -O2 -shared -fPIC -o "${OUTPUT}" "${SOURCE}"
    echo "Built: ${OUTPUT}"
    ;;
  Linux*)
    OUTPUT="${SCRIPT_DIR}/mml_native.so"
    gcc -O2 -shared -fPIC -o "${OUTPUT}" "${SOURCE}"
    echo "Built: ${OUTPUT}"
    ;;
  *)
    echo "Unsupported OS: ${OS}. Use CMakeLists.txt on Windows."
    exit 1
    ;;
esac

# Optionally use cmake if available for a more reproducible build
if command -v cmake &>/dev/null; then
  echo ""
  echo "CMake is available.  For a cleaner build run:"
  echo "  mkdir -p ${SCRIPT_DIR}/cmake_build"
  echo "  cd ${SCRIPT_DIR}/cmake_build"
  echo "  cmake .. -DCMAKE_BUILD_TYPE=Release"
  echo "  cmake --build . --config Release"
fi
