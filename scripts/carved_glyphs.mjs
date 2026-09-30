// Generates FocusTimer/Resources/CarvedGlyphs.json from the carved numeral model
// (scripts/carved_model.js — the same code that builds the boards in the Figma file
// "Focus Timer — Carved Numerals & Icon").
//
// Run from the repo root:  node scripts/carved_glyphs.mjs
// Output: { h, families: { carved: { name, glyphs: { "0": { w, f: [[shade, x1, y1, …], …] } } } } }
// shade is 0–100 (facet brightness); the app maps it onto each theme's colours.

import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const { FAMILIES, SKELETONS, buildGlyph } = require("./carved_model.js");

const r1 = v => Math.round(v * 10) / 10;
const families = {};
const summary = {};
for (const [key, fam] of Object.entries(FAMILIES)) {
  const glyphs = {};
  let count = 0, shadeSum = 0;
  for (const ch of Object.keys(SKELETONS)) {
    const { w, facets } = buildGlyph(key, ch);
    const f = facets.map(({ pts, g }) => [Math.round(g * 100), ...pts.flatMap(([x, y]) => [r1(x), r1(y)])]);
    glyphs[ch] = { w: r1(w), f };
    count += f.length;
    shadeSum += f.reduce((s, x) => s + x[0], 0);
  }
  families[key] = { name: fam.name, glyphs };
  summary[key] = [count, shadeSum];
}

writeFileSync(new URL("../FocusTimer/Resources/CarvedGlyphs.json", import.meta.url), JSON.stringify({ h: 240, families }));
console.log(JSON.stringify(summary));
