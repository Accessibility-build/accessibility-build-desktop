# Privacy

The app reads your screen only when you use a tool, and processes those
pixels on your Mac. Nothing it captures is uploaded.

## What it does with your screen

- The contrast picker and region capture take one still image of each display
  when you start them and discard it when you finish. Only the colors you pick
  and any capture you choose to copy or save leave that moment.
- The lens streams only the area under its own window while it is open and
  keeps no frames.
- The app's own windows are excluded from every capture.

## What it stores

- Preferences, shortcuts and the last ten color pairs, in the app's sandboxed
  container (`UserDefaults`). Settings has a button to clear the color pairs.
- The session log lives in memory and is gone when you quit, unless you save
  the Markdown export.

## Network

- The Mac App Store build makes no network requests at all and has no
  network entitlement. The rest of this section is about the website build.
- The update check fetches `https://accessibility.build/desktop/appcast.xml`.
  Like any web request it reveals your IP address, and it includes the app's
  version. Sparkle's optional system profile is turned off.
- When you choose to install an update, the DMG is downloaded from GitHub
  Releases and its EdDSA signature is checked before installing.
- No account, no analytics, no crash reporting, no AI services.

## Enforcement

The app runs in the macOS App Sandbox. The website build has only these
entitlements: outgoing network (for updates), files you choose in a save
panel, and the two Mach services Sparkle's installer needs. The App Store
build has only the save-panel one. The public policy is at
https://accessibility.build/desktop/privacy. Screen Recording is granted by you in
System Settings and can be revoked there at any time.
