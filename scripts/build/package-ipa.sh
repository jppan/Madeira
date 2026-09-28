#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DERIVED="$ROOT/app/DerivedData"
DIST="$ROOT/dist"
# docs/BUILDING.md records guest crashes with the Release configuration.
APP="$DERIVED/Build/Products/Debug-iphoneos/Madeira.app"

required=(
  "$ROOT/FEX/build-ios/FEXCore/Source/libFEXCore.a"
  "$ROOT/FEX/build-ios/FEXCore/Source/libFEXCore_Base.a"
  "$ROOT/FEX/build-ios/External/fmt/libfmt.a"
  "$ROOT/FEX/build-ios/External/cephes/libcephes_128bit.a"
  "$ROOT/FEX/build-ios/External/xxhash/cmake_unofficial/libxxhash.a"
  "$ROOT/FEX/build-ios/External/SoftFloat-3e/libsoftfloat_3e.a"
  "$ROOT/FEX/build-ios/FEXCore/Source/libJemallocLibs.a"
  "$ROOT/app/Madeira/libwineserver.a"
  "$ROOT/app/Madeira/libntdll_unix.a"
  "$ROOT/app/Madeira/libwin32u_unix.a"
  "$ROOT/app/Madeira/libdxmt_combined.a"
  "$ROOT/app/Madeira/libgnutls.a"
  "$ROOT/app/Madeira/libhogweed.a"
  "$ROOT/app/Madeira/libnettle.a"
  "$ROOT/app/Madeira/libgmp.a"
  "$ROOT/app/Madeira/x86_64-vcruntime/vcruntime140.dll"
)
for path in "${required[@]}"; do
  [[ -f "$path" ]] || { echo "ERROR: required build artifact missing: $path" >&2; exit 1; }
done

rm -rf "$DERIVED" "$DIST/Payload"
mkdir -p "$DIST"
"$ROOT/build/stage-licenses.sh"

xcodebuild \
  -project "$ROOT/app/Madeira.xcodeproj" \
  -scheme Madeira \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  IPHONEOS_DEPLOYMENT_TARGET=18.0 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  DEVELOPMENT_TEAM='' \
  build

[[ -d "$APP" ]] || { echo "ERROR: xcodebuild succeeded but Madeira.app is missing" >&2; exit 1; }

# Preserve the requested entitlements for later re-signing. An ad-hoc signature
# does not authorize installation or grant these entitlements on an iPhone.
codesign --force --sign - \
  --entitlements "$ROOT/app/Madeira/Madeira.entitlements" \
  "$APP"

bundle_required=(
  "$APP/Madeira"
  "$APP/prefix-template.tar.gz"
  "$APP/arm64ec-windows/xtajit64.dll"
  "$APP/x86_64-vcruntime/vcruntime140.dll"
  "$APP/d3d12/libmetalirconverter.dylib"
)
for path in "${bundle_required[@]}"; do
  [[ -e "$path" ]] || { echo "ERROR: required bundle resource missing: $path" >&2; exit 1; }
done
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q 'com.apple.security.cs.allow-jit' || {
  echo "ERROR: packaged app is missing the allow-jit entitlement" >&2
  exit 1
}

mkdir -p "$DIST/Payload"
ditto "$APP" "$DIST/Payload/Madeira.app"
rm -f "$DIST/Madeira.ipa"
(
  cd "$DIST"
  /usr/bin/zip -qry Madeira.ipa Payload
)
rm -rf "$DIST/Payload"
[[ -s "$DIST/Madeira.ipa" ]] || { echo "ERROR: failed to create IPA" >&2; exit 1; }
unzip -tq "$DIST/Madeira.ipa" >/dev/null
