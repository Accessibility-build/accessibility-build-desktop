#!/bin/zsh
# Builds, signs, notarizes and packages a release DMG, then prints what the
# website's lib/desktop-release.ts needs. See docs/RELEASING.md.
#
# Needs, on this Mac:
#   - the "Developer ID Application" certificate in the login keychain
#   - a notarytool profile:  xcrun notarytool store-credentials AB_NOTARY ...
#   - the Sparkle private key: ~/.config/accessibility-build/sparkle-ed25519-private.key
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-AB_NOTARY}"
# SKIP_NOTARIZE=1 rehearses everything else (archive, export, DMG, signatures)
# when the notarization profile is not set up yet. Its output must not ship.
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SPARKLE_KEY="${SPARKLE_KEY:-$HOME/.config/accessibility-build/sparkle-ed25519-private.key}"
IDENTITY="Developer ID Application: Khushwant Parihar (TVQX6QVQ7N)"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"

VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *//p' project.yml)
grep -q "^## $VERSION " CHANGELOG.md || { echo "CHANGELOG.md has no '## $VERSION - date' entry" >&2; exit 1; }
test -f "$SPARKLE_KEY" || { echo "missing Sparkle key at $SPARKLE_KEY" >&2; exit 1; }

echo "==> Tests"
(cd Packages/ColorCore && swift test --quiet)
(cd Packages/AuditCore && swift test --quiet)

echo "==> Archive $VERSION ($BUILD), universal"
rm -rf build/release
mkdir -p build/release
xcodegen generate --quiet
xcodebuild \
  -project AccessibilityBuild.xcodeproj -scheme AccessibilityBuild -configuration Release \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -packageAuthorizationProvider netrc \
  -archivePath build/release/AccessibilityBuild.xcarchive archive -quiet
cat > build/release/export.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>TVQX6QVQ7N</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/release/AccessibilityBuild.xcarchive \
  -exportOptionsPlist build/release/export.plist -exportPath build/release/export -quiet
APP="build/release/export/Accessibility Build.app"

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/Accessibility Build"

if [[ "$SKIP_NOTARIZE" != 1 ]]; then
  echo "==> Notarize and staple the app"
  ditto -c -k --keepParent "$APP" build/release/app.zip
  xcrun notarytool submit build/release/app.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
fi

echo "==> DMG"
DMG="build/release/Accessibility-Build-$VERSION.dmg"
STAGE=build/release/dmg
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Accessibility Build.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Accessibility Build" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ "$SKIP_NOTARIZE" != 1 ]]; then
  echo "==> Notarize and staple the DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"

  echo "==> Gatekeeper checks"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "==> DRY RUN: not notarized. Do not publish these files."
  codesign --verify --verbose=2 "$DMG"
fi

echo "==> Sparkle signature"
SIG_LINE=$("$SPARKLE_BIN/sign_update" --ed-key-file "$SPARKLE_KEY" "$DMG")
ED_SIG=$(echo "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(stat -f%z "$DMG")
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
(cd build/release && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)

cat <<EOF

Release artifacts:
  $DMG
  build/release/SHA256SUMS.txt

Entry for lib/desktop-release.ts on the website (newest first):
  {
    version: "$VERSION",
    build: "$BUILD",
    date: "$(date +%Y-%m-%d)",
    minimumSystemVersion: "14.0",
    length: $LENGTH,
    edSignature: "$ED_SIG",
    sha256: "$SHA",
    notes: [ /* from CHANGELOG.md */ ],
  },
EOF
