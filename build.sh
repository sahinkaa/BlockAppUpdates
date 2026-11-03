#!/bin/sh
set -eu
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build-cache/modules"
for scheme in rootless roothide; do
    make clean package THEOS_PACKAGE_SCHEME="$scheme"
    arch=iphoneos-arm64
    if [ "$scheme" = roothide ]; then arch=iphoneos-arm64e; fi
    python3 normalize_package.py "packages/com.sahinkaa.blockappupdates_1.0.4_${arch}.deb"
done
