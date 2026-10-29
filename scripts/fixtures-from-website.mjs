#!/usr/bin/env node
// Generates Packages/ColorCore/Tests/ColorCoreTests/Fixtures/website-color.json
// by running the website's own lib/color code. The Swift tests compare the
// app's port against these values, so the app and the web contrast checker
// cannot silently disagree. Re-run whenever lib/color changes:
//
//   node scripts/fixtures-from-website.mjs ~/Accessibility.Build-Main-Website

import { execFileSync } from "node:child_process"
import { mkdtempSync, writeFileSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join, resolve, dirname } from "node:path"
import { fileURLToPath, pathToFileURL } from "node:url"

const site = resolve(process.argv[2] ?? "")
const esbuild = join(site, "node_modules/.bin/esbuild")
if (!process.argv[2] || !existsSync(join(site, "lib/color/apca.ts")) || !existsSync(esbuild)) {
  console.error("usage: node scripts/fixtures-from-website.mjs <website repo with node_modules>")
  process.exit(1)
}

const work = mkdtempSync(join(tmpdir(), "ab-fixtures-"))
const entry = join(work, "entry.ts")
writeFileSync(
  entry,
  [
    `export { contrastRatioWCAG, hexToOklch, oklchToHex } from ${JSON.stringify(join(site, "lib/color/oklch.ts"))}`,
    `export { apcaContrast } from ${JSON.stringify(join(site, "lib/color/apca.ts"))}`,
    `export { simulateHex } from ${JSON.stringify(join(site, "lib/color/cvd.ts"))}`,
    `export { nudgeForContrast } from ${JSON.stringify(join(site, "lib/color/autofix.ts"))}`,
  ].join("\n"),
)
const bundle = join(work, "bundle.mjs")
execFileSync(esbuild, [entry, "--bundle", "--platform=node", "--format=esm", `--outfile=${bundle}`], {
  cwd: site,
  stdio: "inherit",
})
const lib = await import(pathToFileURL(bundle).href)

// Deterministic colors: anchors that sit on WCAG thresholds, greys, primaries
// and a seeded pseudo-random spread.
const anchors = [
  "#000000", "#FFFFFF", "#767676", "#777777", "#595959", "#949494", "#757575",
  "#808080", "#0B0F19", "#1A7F37", "#CF222E", "#2563EB", "#FF0000", "#00FF00",
  "#0000FF", "#FFFF00", "#00FFFF", "#FF00FF", "#E6E6E6", "#333333",
]
let seed = 20261029
const rand = () => ((seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296)
const hex2 = (n) => n.toString(16).padStart(2, "0").toUpperCase()
const randomColors = Array.from({ length: 20 }, () =>
  "#" + hex2(Math.floor(rand() * 256)) + hex2(Math.floor(rand() * 256)) + hex2(Math.floor(rand() * 256)),
)
const colors = [...anchors, ...randomColors]

const pairs = []
for (const fg of colors) {
  for (const bg of colors) {
    if (fg === bg) continue
    pairs.push({ fg, bg, wcag: lib.contrastRatioWCAG(fg, bg), apca: lib.apcaContrast(fg, bg) })
  }
}

const cvd = []
for (const hex of colors) {
  for (const type of ["protanopia", "deuteranopia", "tritanopia", "achromatopsia"]) {
    for (const severity of [1, 0.6]) {
      cvd.push({ hex, type, severity, out: lib.simulateHex(hex, type, severity).toUpperCase() })
    }
  }
}

const oklch = colors.map((hex) => ({ hex, ...lib.hexToOklch(hex) }))
const gamut = [
  { l: 0.7, c: 0.35, h: 30 },
  { l: 0.5, c: 0.4, h: 140 },
  { l: 0.9, c: 0.3, h: 260 },
  { l: 0.2, c: 0.25, h: 300 },
  { l: 0.62, c: 0.2, h: 90 },
].map((o) => ({ ...o, out: lib.oklchToHex(o).toUpperCase() }))

const autofix = []
for (const { fg, bg, wcag } of pairs.filter((_, i) => i % 7 === 0)) {
  for (const [metric, target] of [["wcag", 4.5], ["wcag", 7], ["wcag", 3], ["apca", 60]]) {
    for (const side of ["fg", "bg"]) {
      autofix.push({
        fg, bg, metric, target, side,
        out: lib.nudgeForContrast(fg, bg, { target, metric, side }).toUpperCase(),
      })
    }
  }
}

const here = dirname(fileURLToPath(import.meta.url))
const outPath = join(here, "../Packages/ColorCore/Tests/ColorCoreTests/Fixtures/website-color.json")
writeFileSync(outPath, JSON.stringify({ source: "lib/color (accessibility.build)", pairs, cvd, oklch, gamut, autofix }, null, 1) + "\n")
console.log(`wrote ${pairs.length} pairs, ${cvd.length} CVD, ${oklch.length} OKLCH, ${gamut.length} gamut, ${autofix.length} auto-fix cases to ${outPath}`)
