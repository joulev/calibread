#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

xcodebuild build \
  -project CalibreRead.xcodeproj \
  -scheme CalibreRead \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""

xattr -cr build/Build/Products/Release/Calibread.app

echo "Built: $(cd build/Build/Products/Release && pwd)/Calibread.app"
