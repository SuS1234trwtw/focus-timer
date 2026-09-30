// Carved numeral model — the same code that builds the glyphs in the Figma file
// "Focus Timer — Carved Numerals & Icon". Each stroke is a prism split along its
// centre ridge into facets; each facet is shaded by its angle to a top-left light.
//
// Run from the repo root:  node scripts/carved_glyphs.mjs
// Writes FocusTimer/Resources/CarvedGlyphs.json: { h, glyphs: { "0": { w, f: [[shade, x1, y1, x2, y2, ...], ...] } } }
// shade is 0–100 (facet brightness); the app maps it onto each theme's colours.

import { writeFileSync } from "node:fs";

const W = 40, HW = W / 2;
const LIGHT = (() => { const v = [-0.45, -0.7, 0.55]; const l = Math.hypot(...v); return v.map(x => x / l); })();
const a = 20, b = 100, t = 20, bt = 220, R = 38;

// Stroke skeletons: points are [x, y, filletRadius]; `c: true` closes the loop.
export const GLYPHS = {
  "0": { w: 120, s: [{ c: true, p: [[a,t,R],[b,t,R],[b,bt,R],[a,bt,R]] }] },
  "1": { w: 96,  s: [{ p: [[30,70,0],[58,40,0]] }, { p: [[66,t,0],[66,bt,0]] }] },
  "2": { w: 120, s: [{ p: [[a,66,0],[a,t,R],[b,t,R],[b,104,0],[a,bt,0],[b,bt,0]] }] },
  "3": { w: 120, s: [{ p: [[a,t,0],[b,t,0],[48,108,0]] }, { p: [[40,106,0],[b,106,R],[b,bt,R],[a,bt,0]] }] },
  "4": { w: 128, s: [{ p: [[82,t,0],[a,158,0],[118,158,0]] }, { p: [[82,t,0],[82,bt,0]] }] },
  "5": { w: 120, s: [{ p: [[b,t,0],[a,t,0],[a,112,0],[b,112,R],[b,bt,R],[a,bt,0]] }] },
  "6": { w: 120, s: [{ p: [[b,t,0],[a,t,R],[a,bt,R],[b,bt,R],[b,112,R],[a,112,0]] }] },
  "7": { w: 120, s: [{ p: [[a,t,0],[b,t,0],[46,bt,0]] }] },
  "8": { w: 120, s: [{ c: true, p: [[a,112,R],[b,112,R],[b,bt,R],[a,bt,R]] }, { c: true, p: [[a+6,t,32],[b-6,t,32],[b-6,114,32],[a+6,114,32]] }] },
  "9": { w: 120, s: [{ p: [[a,bt,0],[b,bt,R],[b,t,R],[a,t,R],[a,128,R],[b,128,0]] }] },
  "+": { w: 120, s: [{ p: [[10,120,0],[110,120,0]] }, { p: [[60,70,0],[60,170,0]] }] },
};

const sub = (p, q) => [p[0]-q[0], p[1]-q[1]], add = (p, q) => [p[0]+q[0], p[1]+q[1]], mul = (p, k) => [p[0]*k, p[1]*k];
const len = p => Math.hypot(p[0], p[1]), nrm = p => { const l = len(p) || 1; return [p[0]/l, p[1]/l]; }, leftN = d => [d[1], -d[0]];

function fillet(pts, closed) {
  const out = [], n = pts.length;
  for (let i = 0; i < n; i++) {
    const [x, y, r] = pts[i];
    if (!r || (!closed && (i === 0 || i === n - 1))) { out.push([x, y]); continue; }
    const P = [x, y], A = pts[(i - 1 + n) % n], B = pts[(i + 1) % n];
    const v1 = nrm(sub(A, P)), v2 = nrm(sub(B, P));
    const ang = Math.acos(Math.max(-1, Math.min(1, v1[0]*v2[0] + v1[1]*v2[1])));
    const d = Math.min(r / Math.tan(ang / 2), len(sub(A, P)) * 0.5, len(sub(B, P)) * 0.5);
    const rr = d * Math.tan(ang / 2), T1 = add(P, mul(v1, d)), T2 = add(P, mul(v2, d));
    const C = add(P, mul(nrm(add(v1, v2)), rr / Math.sin(ang / 2)));
    const a1 = Math.atan2(T1[1]-C[1], T1[0]-C[0]); let da = Math.atan2(T2[1]-C[1], T2[0]-C[0]) - a1;
    while (da > Math.PI) da -= 2*Math.PI; while (da < -Math.PI) da += 2*Math.PI;
    const steps = Math.max(4, Math.ceil(Math.abs(da) / (Math.PI / 30)));
    for (let k = 0; k <= steps; k++) { const ak = a1 + da * k / steps; out.push([C[0] + rr*Math.cos(ak), C[1] + rr*Math.sin(ak)]); }
  }
  return out;
}

function shade(n2) {
  const N = [n2[0]*0.72, n2[1]*0.72, 0.69];
  return 0.24 + 0.76 * Math.max(0, N[0]*LIGHT[0] + N[1]*LIGHT[1] + N[2]*LIGHT[2]);
}

export function facets(stroke) {
  const closed = !!stroke.c, P = fillet(stroke.p, closed), n = P.length, segCount = closed ? n : n - 1;
  const dirs = []; for (let i = 0; i < segCount; i++) dirs.push(nrm(sub(P[(i+1) % n], P[i])));
  const off = P.map((_, i) => {
    const dIn = closed ? dirs[(i - 1 + segCount) % segCount] : dirs[Math.max(0, i - 1)];
    const dOut = closed ? dirs[i % segCount] : dirs[Math.min(segCount - 1, i)];
    const n1 = leftN(dIn), m = nrm(add(n1, leftN(dOut)));
    return mul(m, Math.min(HW / Math.max(m[0]*n1[0] + m[1]*n1[1], 0.2), HW * 2.5));
  });
  const Lp = P.map((p, i) => add(p, off[i])), Rp = P.map((p, i) => sub(p, off[i])), C = P.map(p => p.slice());
  if (!closed) { C[0] = add(P[0], mul(dirs[0], HW)); C[n-1] = sub(P[n-1], mul(dirs[segCount-1], HW)); }
  const F = [];
  for (let i = 0; i < segCount; i++) {
    const j = (i + 1) % n, nl = leftN(dirs[i]);
    F.push({ pts: [Lp[i], Lp[j], C[j], C[i]], g: shade(nl) });
    F.push({ pts: [C[i], C[j], Rp[j], Rp[i]], g: shade(mul(nl, -1)) });
  }
  if (!closed) {
    F.push({ pts: [Lp[0], C[0], Rp[0]], g: shade(mul(dirs[0], -1)) });
    F.push({ pts: [Lp[n-1], Rp[n-1], C[n-1]], g: shade(dirs[segCount-1]) });
  }
  return F;
}

const r1 = v => Math.round(v * 10) / 10;
const glyphs = {};
for (const [name, g] of Object.entries(GLYPHS)) {
  const f = g.s.flatMap(facets).map(({ pts, g: s }) => [Math.round(s * 100), ...pts.flatMap(([x, y]) => [r1(x), r1(y)])]);
  glyphs[name] = { w: g.w, f };
}

const summary = Object.fromEntries(Object.entries(glyphs).map(([k, g]) => [k, [g.f.length, g.f.reduce((s, f) => s + f[0], 0)]]));
writeFileSync(new URL("../FocusTimer/Resources/CarvedGlyphs.json", import.meta.url), JSON.stringify({ h: 240, glyphs }));
console.log(JSON.stringify(summary));
