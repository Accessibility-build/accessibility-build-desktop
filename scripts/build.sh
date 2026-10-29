#!/bin/zsh
# Builds the app. Usage: scripts/build.sh [Debug|Release]
#
# Packages are resolved without the keychain: SwiftPM otherwise looks up
# GitHub credentials there and a background build hangs on the prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-Debug}"
xcodegen generate --quiet
xcodebuild \
  -project AccessibilityBuild.xcodeproj \
  -scheme AccessibilityBuild \
  -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -packageAuthorizationProvider netrc \
  -quiet build

APP="build/DerivedData/Build/Products/$CONFIG/Accessibility Build.app"
test -d "$APP" || { echo "build failed: $APP missing" >&2; exit 1; }
echo "$APP"
