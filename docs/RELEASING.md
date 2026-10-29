# Releasing

Releases are built on a Mac that has the signing certificate and the
notarization profile. A release is one GitHub release in this repo plus one
small change to the website.

## One-time setup

1. **Developer ID certificate.** `Developer ID Application: Khushwant Parihar
   (TVQX6QVQ7N)` in the login keychain. The first signed build asks for
   keychain access; choose Always Allow.
2. **Notarization profile** (needs an app-specific password from
   appleid.apple.com, typed by you):

   ```sh
   xcrun notarytool store-credentials AB_NOTARY --apple-id <Apple ID> --team-id TVQX6QVQ7N
   ```

3. **Sparkle key.** The EdDSA private key is in the login keychain (account
   `build.accessibility.desktop`) and exported to
   `~/.config/accessibility-build/sparkle-ed25519-private.key` (mode 600).
   Keep a copy in a password manager. Losing it means installed copies can
   never verify another update. The public key is `SUPublicEDKey` in
   `project.yml`.
4. `brew install xcodegen`, and `gh auth login` with access to
   `Accessibility-build/accessibility-build-desktop`.

## Every release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   The build number must always increase; Sparkle compares it.
2. Add `## <version> - <date>` to `CHANGELOG.md`.
3. Run the accessibility checklist in `docs/ACCESSIBILITY.md` on a Debug build.
4. `scripts/release.sh`. It runs the tests, archives a universal build,
   exports it with Developer ID, notarizes and staples the app, builds and
   signs the DMG, notarizes and staples the DMG, runs Gatekeeper checks, signs
   the DMG for Sparkle, and prints the entry for the website.
5. Publish:

   ```sh
   gh release create v<version> build/release/Accessibility-Build-<version>.dmg build/release/SHA256SUMS.txt \
     --repo Accessibility-build/accessibility-build-desktop --title "Accessibility Build <version>" --notes-file <notes>
   ```

6. Website, on a branch: add the printed entry at the top of
   `lib/desktop-release.ts` with the changelog notes. `npm run build`, then
   `next start` on port 3100 and check `/desktop`, `/desktop/appcast.xml`
   (valid XML; the signature and length match) and `/api/desktop/download`
   (302 to the new DMG). Merge with `--no-ff` into main and push.
7. Live check: `curl -IL https://accessibility.build/api/desktop/download`
   ends in a 200 with the DMG's length; download it in a browser, open it on a
   clean macOS user account with no Gatekeeper warning; an installed earlier
   version offers the update.
8. `npm run assistant:index` on the website and commit the index; ping
   IndexNow for `/desktop`.

Released files are never replaced. A fix ships as a new version.
