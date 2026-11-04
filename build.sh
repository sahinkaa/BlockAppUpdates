#!/bin/sh
set -eu
cd "$(dirname "$0")"
make clean package THEOS_PACKAGE_SCHEME=rootless
make clean package THEOS_PACKAGE_SCHEME=roothide
make clean
