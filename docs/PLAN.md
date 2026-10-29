# Accessibility Build for Mac: plan

Status: approved 29 October 2026; this is the plan the app was built to.

## 0. Decisions needed from you

| # | Decision | Recommendation |
|---|---|---|
| D1 | Interim fix for the live /desktop page (it links to a 404 today) | Option A, "In development" page, ship today |
| D2 | Finish the old Tauri prototype, or rebuild as a native SwiftUI app | Rebuild natively (section 3) |
| D3 | v1.0 scope | Contrast picker, colour-vision lens, quick capture; annotate editor in v1.1 (section 4) |
| D4 | Where the source and the DMG live | New public GitHub repo, DMG on its Releases; appcast served by the website (section 8) |
| D5 | Minimum macOS | macOS 14 Sonoma or later, universal binary (section 5) |
| D6 | Notarization credential | You run one `xcrun notarytool store-credentials` command (I cannot type passwords) |

Cost: the Developer ID certificate already exists (valid to July 2031), so
the only recurring cost is the Apple Developer Program membership you already
pay for (US$99 a year). Please confirm it is active and when it renews.

## 1. What exists today (verified 29 Oct 2026)

**The live page promises an app that was never released.**

- `/desktop` advertises "v1.7.2 · Apple Silicon · macOS 12+", a ~5MB
  download, auto-updates, three tools and "100% local".
- `/api/desktop/download` 302-redirects to
  `/downloads/desktop/Accessibility%20Build_1.7.2_aarch64.dmg`, which is a
  **404**. `/downloads/desktop/latest.json` (the old updater feed) is also a 404.
- `public/downloads/desktop/README.md` is served publicly at
  `accessibility.build/downloads/desktop/README.md` and names a local folder
  on your Mac. It should go.
- The JSON-LD declares a `SoftwareApplication` with `downloadUrl` and
  `softwareVersion: 1.7.2`, so search engines are told a download exists.
- `/docs` has a "macOS desktop toolkit" card and every `/reports/[slug]` page
  has a "Get the desktop app" button. Both lead to the same dead end.
- The page title contains an em dash.

**Where v1.7.2 came from.** An earlier prototype (Tauri 2 and React,
versions 1.0.0 to 1.7.2, all written on 6 July 2026) was never signed,
notarized or uploaded, so no one has it installed and there is no
update-continuity constraint. It used `CGWindowListCreateImage`, deprecated in
macOS 14 and marked obsolete in the macOS 15 SDK, and its own notes listed the
move to ScreenCaptureKit as unfinished.

**Signing assets already on this Mac.**

- `Developer ID Application: Khushwant Parihar (TVQX6QVQ7N)` in the login
  keychain, valid until 22 July 2031.
- No notarytool keychain profile exists locally.

**Toolchain.** Xcode 26.6, Swift 6.3.3, macOS 27.0.1 on Apple Silicon,
XcodeGen installed.

**Website pieces built for the old app** (keep dormant in v1, decide later):
`/desktop/connect`, `/api/desktop/{devices,entitlements,reports}`,
`lib/desktop-auth.ts`, `desktop_devices` and `published_reports` tables. The
v1 app has no account, so it calls none of them.

**Reusable maths.** The website already has the exact algorithms the app
needs in `lib/color/`: `apca.ts` (APCA-W3 0.1.9), `cvd.ts` (Machado 2009 with
severity), `autofix.ts` (OKLCH lightness search for the nearest passing
colour), `grade.ts`, `wcag-sc.ts`. The app ports these and is tested against
fixtures generated from them, so the app and the web contrast checker can
never disagree.

## 2. Step 0: stop linking to a 404 (needs your OK before touching the live site)

**Option A, recommended: "In development".**

- Hero becomes "Accessibility Build for Mac is in development". Remove the
  download button, the version and the Apple Silicon/macOS line.
- Describe the planned tools in plain future tense, no dates, no hotkeys.
- Remove the `SoftwareApplication` JSON-LD entirely until a build ships (a
  download-less app entry misleads search engines).
- `/api/desktop/download` 302s to `/desktop` instead of a missing file.
- Delete `public/downloads/desktop/README.md`.
- Reword the `/docs` card and the `/reports/[slug]` button so neither offers a
  download. Fix the em dashes on the page.
- Rebuild the Curb assistant index so it stops describing a download.
- Effort: about an hour including `npm run build`, `next start` on :3100,
  merge and live check.

**Option B: waitlist.** Same as A plus an email field. Needs somewhere to
store emails (live DB, Resend audience or Formspree) and a privacy note. More
scope and new data collection for a temporary page. Not recommended.

**Option C: unpublish.** 302 `/desktop` to `/tools`, drop it from the sitemap.
Loses the page and its links. Only if you decide not to build the app.

## 3. Finish the prototype or rebuild natively

**Recommendation: rebuild as a native SwiftUI + AppKit menu-bar app.** Use
the prototype as a feature spec and port its maths, not its code.

| | Finish Tauri prototype | Native SwiftUI rebuild |
|---|---|---|
| Users to migrate | None | None |
| Screen capture | Must migrate xcap and CGWindowList to ScreenCaptureKit through Rust FFI anyway | ScreenCaptureKit is the native API |
| Accessibility of the app | Webview UI in transparent overlay windows; VoiceOver and keyboard support must be hand-built in HTML inside windows AppKit does not understand | Standard AppKit/SwiftUI controls expose the accessibility tree, Full Keyboard Access and Voice Control for free |
| Download size | Tauri runtime plus web bundle | Small Swift binary plus Sparkle (about 3 to 5 MB DMG, measured at build) |
| Toolchain to release | Rust, Node, pnpm, Tauri CLI, Xcode | Xcode only |
| Private APIs | `macOSPrivateApi: true` | None |
| Code quality | Written in about nine hours, never run by a user, no UI tests | Written with tests from the start |
| Windows port later | Easier to share code | Would be a separate app |

The one real cost of the rebuild is time (section 12). The only argument for
Tauri is a future Windows build, and nothing in this plan commits to one, so
the page should stop promising it.

## 4. v1.0 scope against what /desktop promises

Legend: **1.0** ships in the first release; **1.1** next release; **drop**
removed from the page.

| Page claim | Plan |
|---|---|
| Free, no account | 1.0 |
| Contrast picker: freeze the screen, magnified pixel loupe | 1.0 |
| WCAG AA/AAA verdicts (normal text, large text, UI components) | 1.0 |
| APCA Lc | 1.0, labelled as APCA (WCAG 3 draft method), never as a WCAG pass/fail |
| Drag across a gradient to find the worst-case pixel | 1.0 |
| One-click passing colour fixes | 1.0, same algorithm as the website's auto-fix |
| The pair under four colour-vision deficiencies | 1.0 (protanopia, deuteranopia, tritanopia, achromatopsia) |
| Colour-vision lens over anything on screen | 1.0 |
| Lens severity slider, low-vision blur, low-contrast filter | 1.0 |
| Lens split before/after view | 1.0 |
| Delayed capture (3s) | 1.0, as part of quick capture (region, window, display to clipboard or PNG) |
| Session log exported as Markdown | 1.0 (contrast checks and captures) |
| Fully customisable global shortcuts | 1.0 |
| Multi-monitor | 1.0, including mixed 1x and 2x displays |
| Auto-updates | 1.0 (Sparkle) |
| ~5MB download | 1.0, page shows the measured size |
| Capture and annotate: numbered issue badges mapped to WCAG 2.2 criteria with severity, 24x24 target measure, redaction, GitHub/Jira issue export | **1.1** (an accessible annotation editor is the biggest single piece; the page omits it until it ships) |
| "v1.7.2" | Becomes 1.0.0. No one has 1.7.2, so starting at 1.0.0 is honest |
| "Apple Silicon", "macOS 12+" | "Apple Silicon and Intel, macOS 14 or later" (section 5) |
| "A paid tier with full-page WCAG scans and PDF audit reports is planned" | drop |
| "A Windows version is on the roadmap" | drop |
| "nothing is uploaded, ever" | Reword precisely: screen pixels never leave the Mac; the only network request is the update check |
| Default hotkeys ⌥⌘P, ⌥⌘S, ⌥⌘L | Change defaults to ⌃⌥⌘ combinations. ⌥⌘P and ⌥⌘L are Finder shortcuts (path bar, Downloads) and a global hotkey would hijack them everywhere |

## 5. Architecture

**Shape.** A menu-bar-only app (`LSUIElement`), SwiftUI app lifecycle with
AppKit where SwiftUI cannot do the job (full-screen overlay panels, the lens
panel). App name "Accessibility Build", bundle ID
`build.accessibility.desktop` (unused by any install, so free to reuse).

**Minimum macOS 14, universal binary.** Reasons: `SCScreenshotManager` (the
one-shot ScreenCaptureKit capture used to freeze the screen) needs 14.0;
`MenuBarExtra` needs 13; the Observation framework needs 14; every Apple
Silicon Mac runs 14. The Intel slice costs well under a megabyte and is
smoke-tested under Rosetta (`arch -x86_64`) before the page says "Intel".

**Repository layout** (new repo, working name `accessibility-build-desktop`):

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not hand-edited)
App/                        app target: entry point, menu, windows, settings
  Picker/                   frozen overlay panels, loupe, keyboard nudging
  Lens/                     floating lens panel, SCStream, Core Image filter chain
  Capture/                  region, window and display capture, countdown HUD
  Results/                  contrast results window, fixes, CVD previews
  SessionLog/               log model and Markdown export
  Support/                  permissions, shortcuts, updates, launch at login
Packages/ColorCore/         pure Swift package: sRGB, WCAG ratio, APCA, CVD, auto-fix, formats
  Tests/Fixtures/           JSON vectors generated from the website's lib/color
Resources/                  assets, Info.plist, entitlements, PrivacyInfo.xcprivacy
scripts/                    fixtures-from-website, build, make-dmg, notarize, release
docs/                       PLAN.md (this file), RELEASING.md, ACCESSIBILITY.md, PRIVACY.md
CHANGELOG.md
```

**Dependencies** (Swift Package Manager, pinned exact versions):
[Sparkle 2](https://github.com/sparkle-project/Sparkle) for updates and
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for
user-recordable global shortcuts (Carbon hotkeys, no Accessibility
permission needed). Nothing else.

**ColorCore.** Ports `lib/color/{apca,cvd,autofix,grade,wcag-sc}.ts`. A script
in the app repo runs the website's TypeScript over a grid of colour pairs and
writes JSON fixtures; Swift tests assert the app matches to two decimal
places. When the website's maths changes, regenerating fixtures makes the app
tests fail until the port catches up.

**Screen capture.** One `ScreenCaptureService`:

- Permission: `CGPreflightScreenCaptureAccess` on launch, an onboarding
  window that explains why before calling `CGRequestScreenCaptureAccess`, and
  a clear "permission missing" state with a button to the right System
  Settings pane. macOS may ask the user to reconfirm the permission
  periodically; the app handles a revoked grant without crashing.
- Freeze: `SCScreenshotManager.captureImage` per display at native pixel
  size, cursor hidden, the app's own windows excluded.
- **Colour space trap:** captures are requested in sRGB
  (`SCStreamConfiguration.colorSpaceName = sRGB`). On a Display P3 screen a
  raw capture returns display-space values, so a CSS `#767676` would read as a
  different hex and every verdict would be slightly wrong. A test page with
  known CSS colours checks this on the built-in and an external display.
- Lens: an `SCStream` limited to the lens rectangle with the lens window
  excluded, at about 30 fps, stopped whenever the lens is hidden.

**Contrast picker flow.** Hotkey, freeze all displays, one borderless overlay
panel per display showing the frozen image, loupe follows the pointer
(pixel grid, hex, live ratio once text colour is picked). Click or Return
picks text colour, then background colour (or drag a region for the worst-case
pixel). Esc cancels. Results open in a standard window: both colours (editable
hex fields, swap), WCAG ratio and verdicts per text size, APCA Lc, fixes, CVD
previews, "Copy finding" (an audit sentence citing 1.4.3, 1.4.6 or 1.4.11),
add to session log.

**Lens.** A floating, resizable, movable panel. Filters run in Core Image:
Machado matrices applied in linear light (Core Image's working space is
linear, which is what the Machado model expects), severity interpolation,
achromatopsia via luminance, Gaussian blur, reduced contrast, and a split
mask for before/after.

**Quick capture.** Region (drag on a frozen overlay), window, or whole
display, optionally after a 3-second countdown HUD that removes itself before
the frame is taken. Output to clipboard and/or a PNG chosen in a save panel.

**Privacy, kept 100% local.**

- No account, no analytics, no crash upload, no AI.
- App Sandbox and Hardened Runtime on. Entitlements: `network.client` (update
  check only), `files.user-selected.read-write` (save panels), and Sparkle's two
  documented mach-lookup exceptions for its installer service. No
  screen-recording entitlement exists; the user grants it through macOS.
- The only network traffic is Sparkle fetching the appcast and, when the user
  accepts, the update. Sparkle's system profiling stays off and automatic
  checks are off until the user opts in on second launch (Sparkle's default
  prompt).
- Stored data: preferences and recent colour pairs in `UserDefaults`, inside
  the sandbox container, clearable from Settings. The session log lives in
  memory until the user exports it.
- `PrivacyInfo.xcprivacy` declares the `UserDefaults` use.
- Verified before release by watching network activity during a full session
  (section 9).

## 6. Accessibility of the app itself

An accessibility tool that is itself inaccessible would undo the page's
credibility, so these are release blockers, not polish.

- **Menu:** `MenuBarExtra` in menu style, which is a native `NSMenu`: VoiceOver,
  keyboard and Voice Control work without custom code. The status item has a
  label.
- **Keyboard-only picking:** arrow keys move the pick point one pixel, Shift
  plus arrow moves 10, Return picks, Esc cancels, Tab switches between text
  and background step. Every tool is usable without a pointer.
- **A non-visual path:** the results window accepts typed or pasted hex
  values, so a VoiceOver user can check a pair without the overlay. The overlay
  announces its instructions on open and the colour under the pick point on
  request, not on every pixel (that would flood speech).
- **Results window:** standard controls in a normal window. Verdicts are text
  plus an icon ("Passes AA, normal text"), never colour alone. The ratio is
  read as "4.6 to 1".
- **Contrast of the UI:** system semantic colours only, checked in light, dark
  and Increase Contrast. Verdict badges meet 4.5:1 for text and 3:1 for icons.
- **Reduce Motion:** no animation beyond what macOS draws itself; the loupe
  tracks without easing; the countdown is a number, not a spinner.
- **Reduce Transparency:** solid backgrounds when it is on (system materials
  handle this; no custom translucency).
- **Full Keyboard Access and focus:** every control reachable, visible focus
  ring, logical order, Esc closes panels.
- **Target size:** controls at least 24 by 24 points (WCAG 2.5.8), standard
  sizes where possible.
- **Lens:** labelled controls, number keys 1 to 5 switch filters, arrow keys
  move the lens when it has focus so it can be positioned without dragging.
- **Testing:** Accessibility Inspector audit, a scripted VoiceOver walkthrough
  of every flow, Full Keyboard Access, Voice Control "show numbers", Increase
  Contrast, Reduce Motion, Reduce Transparency, light and dark.
- **Honesty on the page:** a short "Accessibility of this app" section on
  /desktop lists what works and the known limit (the overlay and lens are
  visual tools; the hex entry path is the non-visual alternative).

## 7. Code signing and notarization

- Sign with the existing `Developer ID Application ... (TVQX6QVQ7N)`
  certificate, Hardened Runtime on, secure timestamp.
- Notarize with `xcrun notarytool submit --wait`, then `xcrun stapler staple`
  the DMG so Gatekeeper passes offline.
- **One-time step only you can do** (it needs your Apple ID app-specific
  password, which I must not type):

  ```bash
  xcrun notarytool store-credentials AB_NOTARY --apple-id <your Apple ID> --team-id TVQX6QVQ7N
  ```

  An App Store Connect API key (.p8) works too if you prefer it over an
  app-specific password.
- Releases are built locally by `scripts/release.sh` because the certificate
  and the notary profile are in this Mac's keychain. CI signing can come later
  (it needs the certificate and notarization credentials added as repository
  secrets).
- Checks on every build: `codesign --verify --deep --strict`,
  `spctl --assess --type execute` on the app,
  `spctl --assess --type open --context context:primary-signature` on the DMG,
  `xcrun stapler validate`.

## 8. Updates, packaging and hosting

**DMG.** `hdiutil` builds a compressed DMG holding the app and an
Applications shortcut; no third-party DMG tool. Name without spaces:
`Accessibility-Build-1.0.0.dmg`. The DMG itself is signed, notarized and
stapled.

**Updater: Sparkle 2.** EdDSA keys from Sparkle's `generate_keys` live in the
login keychain; the public key goes in `Info.plist`. Export a backup of the
private key into your password manager: losing it means installed copies can
never verify another update. Each release's DMG is signed with `sign_update`.

**Hosting the DMG: GitHub Releases, not Vercel `public/`.**

- Size alone would fit Vercel (a few MB against static upload limits of
  [100 MB on Hobby and 1 GB on Pro](https://vercel.com/docs/limits)), but every
  DMG committed to `public/` stays in the public website repo's history forever,
  each deploy carries it, and downloads count against Vercel bandwidth.
- GitHub Releases gives immutable versioned URLs, no bandwidth charge, per-file
  limit of 2 GiB, and a place for checksums and notes
  ([GitHub docs](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)).

**Which repo (D4).** Recommended: one new **public** repo under the
`Accessibility-build` org holding source and releases. Public source lets
anyone check the "100% local" claim, and it is one repo to manage. The
alternative is private source plus a public `desktop-releases` repo for
binaries. The licence is your call.

**Appcast served by the website.** `lib/desktop-release.ts` becomes the single
source of truth: current version, date, size, minimum macOS, architectures and
a list of releases with their EdDSA signatures. From that one file:

- `/desktop` renders the version, size, requirements and changelog;
- the JSON-LD gets `softwareVersion`, `downloadUrl`, `fileSize`,
  `operatingSystem`;
- `/desktop/appcast.xml` (a route handler, short cache) renders the Sparkle
  feed with enclosure URLs pointing at the GitHub release assets;
- `/api/desktop/download` redirects to the current version's GitHub asset and
  keeps its PostHog event. With no release in the file, it redirects to
  `/desktop`.

So a release is: publish the GitHub release, then one small website commit
editing one file. The page version and the download can never drift apart.

## 9. Testing

- **ColorCore unit tests** against website-generated fixtures (WCAG ratio,
  APCA Lc, CVD transforms at several severities, auto-fix outputs), plus edge
  cases: identical colours, pure black and white, near-threshold pairs
  (4.49 versus 4.5 must not round into a pass).
- **Geometry tests:** point-to-pixel mapping across 1x and 2x displays,
  displays left of or above the main one (negative origins), the worst-case
  region search, Markdown export formatting.
- **Colour accuracy:** a local HTML page with known CSS colours; the picker
  must return the exact hex on the built-in P3 display and an external display.
- **UI tests (XCUITest):** menu items, settings, results window driven only by
  keyboard, hex entry path.
- **Manual matrix:** every tool on two displays with different scales; Light,
  Dark, Increase Contrast, Reduce Motion, Reduce Transparency; VoiceOver
  walkthrough; permission denied, granted, then revoked while running; Rosetta
  run of the Intel slice.
- **Oldest supported OS:** smoke test in a macOS 14 virtual machine (tart or
  UTM; about a 15 GB download, needs your OK). If skipped, the page claims only
  what was tested.
- **Privacy check:** a full session with network monitoring (`nettop` filtered
  to the app) shows no traffic except the update check.
- **Release checks:** fresh macOS user account, download from the production
  URL in a browser (so the quarantine flag is set), open from the DMG, no
  Gatekeeper warning; then publish a 1.0.1 to a staging appcast and confirm
  1.0.0 updates itself.

## 10. Release runbook (`docs/RELEASING.md` in the app repo)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`;
   add a dated `CHANGELOG.md` entry.
2. `scripts/release.sh`: generate the project, run tests, archive Release
   (universal), export with Developer ID, build the DMG, sign it, notarize,
   staple, run every check from section 7, sign the DMG for Sparkle, print the
   version, byte length, EdDSA signature and SHA-256.
3. `gh release create v<version>` on the app repo with the DMG and a
   `SHA256SUMS.txt`; notes from the changelog.
4. Website, on a branch: add the release to `lib/desktop-release.ts`;
   `npm run build`; `next start` on :3100; check `/desktop`,
   `/desktop/appcast.xml` (valid XML, correct signature and length) and
   `/api/desktop/download` (302 to the new asset); merge `--no-ff` into main;
   push.
5. Live verification: `curl -IL https://accessibility.build/api/desktop/download`
   ends in a 200 with the expected length; download in a browser and open on a
   clean user account; an installed previous version offers the update.
6. `npm run assistant:index` and commit the index; ping IndexNow for
   `/desktop`.
7. Released artifacts are immutable. A fix ships as a new patch version.

## 11. Website changes

Step 0 (on your OK): section 2, Option A.

At v1.0 release:

- `lib/desktop-release.ts` (new): single source of truth (section 8).
- `app/api/desktop/download/route.ts`: redirect from the release file.
- `app/desktop/appcast.xml/route.ts` (new): Sparkle feed.
- `app/desktop/page.tsx`: copy that describes only what 1.0 does (section 4
  table), real hotkeys, system requirements, measured size, a precise privacy
  paragraph, "Accessibility of this app", changelog, and `SoftwareApplication`
  JSON-LD with no ratings or invented counts. Title without an em dash, under
  60 characters, no brand suffix.
- `app/docs/page.tsx` card and `app/reports/[slug]` button: point at a real
  download again.
- `lib/site-routes.ts`: update `lastModified` for `/desktop`.
- Untouched in v1: `/desktop/connect`, `/api/desktop/{devices,entitlements,reports}`,
  `lib/desktop-auth.ts` and their tables. A later decision can remove them or
  reuse them for an optional account tier.

## 12. Effort

Working days of focused build time, with your review points between phases.

| Phase | Work | Estimate |
|---|---|---|
| 0 | Interim page fix, build, merge, live check | 1 hour |
| 1 | Repo, XcodeGen project, ColorCore port, fixtures, tests | 0.5 day |
| 2 | Capture service, permission onboarding, colour-space handling | 0.5 day |
| 3 | Contrast picker overlay, loupe, keyboard picking, results window | 1.5 days |
| 4 | Colour-vision lens | 1 day |
| 5 | Quick capture, countdown, session log, shortcuts, settings, launch at login | 1 day |
| 6 | Accessibility pass and fixes | 0.5 day |
| 7 | Sparkle, signing, notarization, DMG, release script | 0.5 to 1 day |
| 8 | Website release changes, first release, live verification | 0.5 day |
| | **v1.0 total** | **about 6 to 7 days** |
| 1.1 | Accessible annotate editor (badges, WCAG 2.2 mapping, severity, target measure, redaction, issue export) | 3 to 4 days |

Your steps along the way: confirm membership, run the notarytool command,
approve creating the GitHub repo, back up the Sparkle key, and approve each
live site change.

## 13. Risks

- **Screen Recording prompts:** recent macOS versions ask users to reconfirm
  screen-capture access from time to time. The app must explain this, not
  fight it.
- **Global hotkey conflicts:** defaults chosen to avoid common shortcuts, all
  rebindable, and a hotkey that fails to register is shown as unset rather than
  silently ignored.
- **Lens performance on large panels:** cap the lens size and frame rate;
  measure CPU before release.
- **Notarization outages** delay a release but never break installed copies.
- **Losing the Sparkle private key** strands installed users on their version;
  mitigated by the backup step.
