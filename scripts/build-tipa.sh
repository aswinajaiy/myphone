#!/usr/bin/env bash
# Builds an unsigned Release .app, fakesigns it with the private entitlements via ldid,
# and packages it as build/DeviceHealth.tipa for TrollStore.
# Requires: Xcode, xcodegen, ldid  (brew install xcodegen ldid)
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate

xcodebuild \
  -project DeviceHealth.xcodeproj \
  -scheme DeviceHealth \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP=build/DerivedData/Build/Products/Release-iphoneos/DeviceHealth.app
ldid -SResources/TrollStore.entitlements "$APP/DeviceHealth"

rm -rf build/Payload build/DeviceHealth.tipa
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry DeviceHealth.tipa Payload)
echo "Built $(pwd)/build/DeviceHealth.tipa"
