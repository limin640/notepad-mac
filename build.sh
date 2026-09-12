#!/bin/bash
# Notepad Mac 构建脚本
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${1:-Release}
cmake -S . -B build -DCMAKE_BUILD_TYPE="$CONFIG"
cmake --build build -j"$(sysctl -n hw.ncpu)"

APP="build/Notepad Mac.app"
if [ -d "$APP" ]; then
	if [ -f docs/donate/wechat.png ]; then
		cp -f docs/donate/wechat.png "$APP/Contents/Resources/wechat-donate.png"
	fi
	# 给 bundle 做 ad-hoc 签名，绑定 Info.plist；对外分发请用 scripts/package.sh
	codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
	SIZE=$(du -sh "$APP" | cut -f1)
	ARCH=$(lipo -info "$APP/Contents/MacOS/Notepad Mac" | sed 's/.*: //')
	echo "✓ 构建完成: $APP ($SIZE, $ARCH)"
	echo "  运行: open \"$APP\""
	echo "  打 DMG: ./scripts/package.sh"
fi
