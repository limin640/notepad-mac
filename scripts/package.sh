#!/bin/bash
# 构建 Notepad4.app，打 DMG。
# 有 Developer ID Application 证书时：hardened runtime 签名，并可公证。
# 否则：ad-hoc 签名，只适合本机或「右键打开」。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MACOSX_BUNDLE_SHORT_VERSION_STRING "\([^"]*\)".*/\1/p' CMakeLists.txt | head -1)
VERSION=${VERSION:-0.1.19}
APP_NAME="Notepad4"
BUNDLE_ID="com.limin640.notepad4mac"
ENTITLEMENTS="macapp/Notepad4.entitlements"
DIST="dist"
APP="$DIST/${APP_NAME}.app"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
notary_profile="${APP_PASSWORD_KEYCHAIN:-notarytool-password}"
require_notarization="${REQUIRE_NOTARIZATION:-0}"

./build.sh Release

mkdir -p "$DIST"
rm -rf "$APP" "$DMG"
ditto "build/${APP_NAME}.app" "$APP"

if [ -f docs/donate/wechat.png ]; then
	cp -f docs/donate/wechat.png "$APP/Contents/Resources/wechat-donate.png"
fi
cp -f LICENSE "$APP/Contents/Resources/LICENSE.txt"

sign_identity="-"
signing_mode="adhoc"
sign_extra=""

if [ "${FORCE_AD_HOC:-0}" != "1" ]; then
	dev_id=$(security find-identity -v -p codesigning 2>/dev/null \
		| grep -oE 'Developer ID Application: [^(]+' \
		| head -1 | sed 's/ *$//' || true)
	if [ -n "$dev_id" ]; then
		sign_identity="$dev_id"
		signing_mode="developer-id"
		sign_extra="--options runtime --timestamp --entitlements $ENTITLEMENTS"
		echo "🔐 Developer ID: $dev_id"
	else
		echo "⚠️  本机没有 Developer ID Application 证书，使用 ad-hoc 签名。"
		echo "    Apple ID / iCloud 登录不等于 Apple Developer Program（\$99/年）。"
		echo "    对外分发需要：加入开发者计划 → 创建 Developer ID Application 证书"
		echo "    → 本机钥匙串能看到该证书 → 再跑本脚本。"
	fi
fi

if [ "$require_notarization" = "1" ] && [ "$signing_mode" != "developer-id" ]; then
	echo "❌ REQUIRE_NOTARIZATION=1 但没有 Developer ID Application 证书。"
	exit 2
fi

echo "▶ codesign ($signing_mode)"
# sign_extra 可能为空；不使用空数组，兼容 bash 3.2 + set -u
# shellcheck disable=SC2086
codesign --force --deep --sign "$sign_identity" $sign_extra "$APP"
codesign --verify --verbose=2 "$APP"

STAGING=$(mktemp -d /tmp/notepad4-dmg.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
if [ -f docs/打开说明.txt ]; then
	cp -f docs/打开说明.txt "$STAGING/打开说明.txt"
fi
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [ "$signing_mode" = "developer-id" ]; then
	codesign --force --sign "$sign_identity" --timestamp "$DMG" || true
	if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ]; then
		ZIP=$(mktemp /tmp/notepad4-notarize.XXXXXX.zip)
		ditto -c -k --keepParent "$APP" "$ZIP"
		echo "▶ notarytool submit"
		xcrun notarytool submit "$ZIP" --keychain-profile "$notary_profile" --wait
		rm -f "$ZIP"
		xcrun stapler staple "$APP"
		xcrun stapler staple "$DMG"
	else
		echo "⚠️  已用 Developer ID 签名，但未设置 APPLE_ID / TEAM_ID，跳过公证。"
		echo "    先: xcrun notarytool store-credentials $notary_profile --apple-id ... --team-id ..."
	fi
fi

echo "✓ $APP"
echo "✓ $DMG"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier=|Signature=|TeamIdentifier=|Authority=' || true
echo "  上传 DMG 到 GitHub Releases，不要推进 git。"
