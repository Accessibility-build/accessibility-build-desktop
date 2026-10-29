#!/bin/zsh
# Renders every window, light and dark, and audits each one's accessibility
# tree. Usage: scripts/snapshots.sh [output dir]   (default: build/snapshots)
#
# The snapshot build is Debug, ad-hoc signed and unsandboxed so it can write
# anywhere. It is launched with `open` so it runs under its own (absent)
# Screen Recording permission instead of inheriting the terminal's.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$PWD/build/snapshots}"
mkdir -p "$OUT"
xcodegen generate --quiet
xcodebuild -project AccessibilityBuild.xcodeproj -scheme AccessibilityBuild -configuration Debug \
  -derivedDataPath build/DerivedData-snap -clonedSourcePackagesDirPath build/SourcePackages \
  -packageAuthorizationProvider netrc \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= OTHER_CODE_SIGN_FLAGS= CODE_SIGN_ENTITLEMENTS= -quiet build
APP="$PWD/build/DerivedData-snap/Build/Products/Debug/Accessibility Build.app"
rm -f "$OUT/ax-findings.txt"
for mode in light dark; do
  open -n -W "$APP" --args -snapshotDir "$OUT" -snapshotAppearance "$mode"
done
echo "Screenshots and accessibility outlines in $OUT"
cat "$OUT/ax-findings.txt"
