#!/bin/bash
# Notepad4-mac 构建脚本
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-Release}
cmake -S . -B build -DCMAKE_BUILD_TYPE="$CONFIG"
cmake --build build -j"$(sysctl -n hw.ncpu)"

APP="build/Notepad4.app"
if [ -d "$APP" ]; then
	SIZE=$(du -sh "$APP" | cut -f1)
	ARCH=$(lipo -info "$APP/Contents/MacOS/Notepad4" | sed 's/.*: //')
	echo "✓ 构建完成: $APP ($SIZE, $ARCH)"
	echo "  运行: open $APP"
fi
