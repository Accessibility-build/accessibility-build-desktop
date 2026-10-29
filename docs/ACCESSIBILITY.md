# Accessibility of the app

An accessibility tool has to be usable by the people it is for. These are
release requirements, checked before every release (see the checklist at the
end).

## What is supported

- **Menu bar.** The status item is a native `NSMenu`: VoiceOver, keyboard
  navigation and Voice Control work as in any system menu.
- **Keyboard-only picking.** In the contrast picker and region capture, arrow
  keys move the pick point one pixel (Shift for ten) and move the pointer with
  it, Return picks, Delete goes back a step, Space reads the color aloud (or
  captures the whole display in region mode), C copies the hex value, Esc
  cancels. Region capture sets corners with Return.
- **A non-visual path.** Check Colors accepts typed or pasted hex values, so a
  pair can be checked without the overlay. The overlay announces its
  instructions on open and the current color on request rather than on every
  pixel, which would flood speech.
- **Results.** Standard controls in a normal window. Each verdict is a word
  and an icon shape, never color alone, and each row reads to VoiceOver as one
  sentence, such as "Normal text: AA fails, AAA fails", with the criteria and
  thresholds as its hint.
  Ratios are truncated, never rounded up, so a failing pair never reads as
  passing.
- **Contrast of the interface.** System semantic colors, plus verdict colors
  tuned for light, dark and Increase Contrast so icons keep at least 3:1.
- **Motion.** No decorative animation; the loupe follows without easing; the
  countdown is a number.
- **Transparency.** Floating chrome (the picker HUD, the loupe caption, the
  lens bar) uses Liquid Glass on macOS 26 and later and a material before
  that. With Reduce Transparency on, all of it switches to solid backgrounds.
  Window content uses standard opaque system surfaces.
- **Lens.** Labelled controls (the short segment names read as the full
  deficiency names); number keys 1 to 4 choose a simulation and 5 turns it
  off; with the lens view focused, arrow keys move the lens.
- **Session log.** Entries are removable with Delete, the toolbar, the
  context menu or the VoiceOver Remove action.

## Known limits

- The overlay and the lens are visual tools. VoiceOver users can use the hex
  fields in Check Colors instead of the overlay.
- Global shortcuts can clash with other apps; all of them can be changed or
  removed in Settings.

## Release checklist

Run on the build being released:

- [ ] Accessibility Inspector audit of Check Colors, Session Log, Settings,
      Screen Recording and the lens: no warnings.
- [ ] VoiceOver: open the menu, run the picker with the keyboard only, read
      the results, use a fix, export the log.
- [ ] Full Keyboard Access on: every control reachable and visibly focused.
- [ ] Voice Control "Show numbers": every control has a number and a name.
- [ ] Increase Contrast, Reduce Motion, Reduce Transparency, light and dark.
- [ ] Two displays with different scales: picker and lens on each.
