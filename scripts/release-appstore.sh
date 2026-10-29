#!/bin/zsh
# Archives the Mac App Store build and exports or uploads it.
# Usage: scripts/release-appstore.sh [export|upload]   (default: export)
#
# Uses Xcode's automatic signing with the Apple ID signed in to Xcode. The
# first run may register this Mac and the bundle ID and create the Mac App
# Store profile in the developer account; see docs/APP_STORE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

DESTINATION="${1:-export}"
[[ "$DESTINATION" == export || "$DESTINATION" == upload ]] || { echo "usage: $0 [export|upload]" >&2; exit 1; }

echo "==> Tests"
(cd Packages/ColorCore && swift test --quiet)
(cd Packages/AuditCore && swift test --quiet)

echo "==> Archive (App Store target, universal)"
rm -rf build/appstore
mkdir -p build/appstore
xcodegen generate --quiet
xcodebuild \
  -project AccessibilityBuild.xcodeproj -scheme AccessibilityBuildAppStore -configuration Release \
  -derivedDataPath build/DerivedData-appstore -clonedSourcePackagesDirPath build/SourcePackages \
  -packageAuthorizationProvider netrc -allowProvisioningUpdates \
  -archivePath build/appstore/AccessibilityBuild.xcarchive archive -quiet

# The App Store build must never carry Sparkle or a network entitlement.
ARCHIVED="build/appstore/AccessibilityBuild.xcarchive/Products/Applications/Accessibility Build.app"
if [[ -d "$ARCHIVED/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Sparkle found in the App Store build" >&2; exit 1
fi
if codesign -d --entitlements - "$ARCHIVED" 2>/dev/null | grep -q "network.client\|temporary-exception"; then
  echo "unexpected entitlement in the App Store build" >&2; exit 1
fi

cat > build/appstore/export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>teamID</key><string>TVQX6QVQ7N</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

echo "==> ${DESTINATION:u}"
xcodebuild -exportArchive -archivePath build/appstore/AccessibilityBuild.xcarchive \
  -exportOptionsPlist build/appstore/export.plist -exportPath build/appstore/export \
  -allowProvisioningUpdates -quiet

if [[ "$DESTINATION" == export ]]; then
  ls -la build/appstore/export
else
  echo "Uploaded. App Store Connect processes the build in about 10 to 30 minutes; then pick it on the version page."
fi
