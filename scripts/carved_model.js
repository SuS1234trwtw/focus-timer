// Carved numeral model. Plain script (no imports) so the exact same code runs in the
// Figma Plugin API (to build the design boards) and in Node (scripts/carved_glyphs.mjs).
//
// Each glyph is a set of stroke skeletons. A stroke is swept with a cross-section profile
// (ridge, chamfer, dome…) into 3D facets; each facet is shaded from its real surface
// normal against a light from the top-left. Stroke ends get sloped pyramid caps.
var CarvedModel = (function () {
  var LIGHT = (function () { var v = [-0.45, -0.7, 0.55], l = Math.hypot(v[0], v[1], v[2]); return [v[0] / l, v[1] / l, v[2] / l]; })();
  var a = 20, b = 100, t = 20, bt = 220, R = 38;

  // Stroke skeletons on a 240-unit-tall cell: points are [x, y, filletRadius]; c = closed loop.
  var SKELETONS = {
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
    "+": { w: 120, s: [{ p: [[10,120,0],[110,120,0]] }, { p: [[60,70,0],[60,170,0]] }] }
  };

  // Cross-section profiles: [t, h] from the left edge (t = -1) to the right edge (t = 1).
  var RIDGE = [[-1, 0], [0, 1], [1, 0]];
  var CHAMFER = [[-1, 0], [-0.5, 1], [0.5, 1], [1, 0]];
  var DOME = [[-1, 0], [-0.82, 0.5], [-0.5, 0.86], [0, 1], [0.5, 0.86], [0.82, 0.5], [1, 0]];

  // Families. width: stroke width; height: profile height relative to half-width;
  // xScale: widen the skeleton; rScale: bigger fillets; soften: round sharp corners; skew: italic lean.
  var FAMILIES = {
    carved:   { name: "Carved",   width: 40, profile: RIDGE,   height: 1.0 },
    heavy:    { name: "Heavy",    width: 56, profile: RIDGE,   height: 1.0, xScale: 1.22, rScale: 1.15 },
    hairline: { name: "Hairline", width: 18, profile: RIDGE,   height: 1.4 },
    block:    { name: "Block",    width: 46, profile: CHAMFER, height: 0.5 },
    soft:     { name: "Soft",     width: 48, profile: DOME,    height: 0.9, rScale: 1.25, soften: 16 },
    lean:     { name: "Lean",     width: 40, profile: RIDGE,   height: 1.0, skew: 0.2 }
  };

  function sub(p, q) { return [p[0] - q[0], p[1] - q[1]]; }
  function add(p, q) { return [p[0] + q[0], p[1] + q[1]]; }
  function mul(p, k) { return [p[0] * k, p[1] * k]; }
  function len(p) { return Math.hypot(p[0], p[1]); }
  function nrm(p) { var l = len(p) || 1; return [p[0] / l, p[1] / l]; }
  function leftN(d) { return [d[1], -d[0]]; }

  function fillet(pts, closed) {
    var out = [], n = pts.length;
    for (var i = 0; i < n; i++) {
      var x = pts[i][0], y = pts[i][1], r = pts[i][2];
      if (!r || (!closed && (i === 0 || i === n - 1))) { out.push([x, y]); continue; }
      var P = [x, y], A = pts[(i - 1 + n) % n], B = pts[(i + 1) % n];
      var v1 = nrm(sub(A, P)), v2 = nrm(sub(B, P));
      var ang = Math.acos(Math.max(-1, Math.min(1, v1[0] * v2[0] + v1[1] * v2[1])));
      var d = Math.min(r / Math.tan(ang / 2), len(sub(A, P)) * 0.5, len(sub(B, P)) * 0.5);
      var rr = d * Math.tan(ang / 2), T1 = add(P, mul(v1, d)), T2 = add(P, mul(v2, d));
      var C = add(P, mul(nrm(add(v1, v2)), rr / Math.sin(ang / 2)));
      var a1 = Math.atan2(T1[1] - C[1], T1[0] - C[0]), da = Math.atan2(T2[1] - C[1], T2[0] - C[0]) - a1;
      while (da > Math.PI) da -= 2 * Math.PI;
      while (da < -Math.PI) da += 2 * Math.PI;
      var steps = Math.max(4, Math.ceil(Math.abs(da) / (Math.PI / 30)));
      for (var k = 0; k <= steps; k++) { var ak = a1 + da * k / steps; out.push([C[0] + rr * Math.cos(ak), C[1] + rr * Math.sin(ak)]); }
    }
    // Neighbouring fillets can meet at the same point; a zero-length segment would spike the miter.
    var clean = out.filter(function (p, i) { return i === 0 || len(sub(p, out[i - 1])) > 0.5; });
    if (closed && clean.length > 1 && len(sub(clean[0], clean[clean.length - 1])) <= 0.5) clean.pop();
    return clean;
  }

  // Newell normal of a 3D polygon, facing the viewer; Lambert shade 0.24…1.
  function shade(poly) {
    var nx = 0, ny = 0, nz = 0;
    for (var i = 0; i < poly.length; i++) {
      var p = poly[i], q = poly[(i + 1) % poly.length];
      nx += (p[1] - q[1]) * (p[2] + q[2]);
      ny += (p[2] - q[2]) * (p[0] + q[0]);
      nz += (p[0] - q[0]) * (p[1] + q[1]);
    }
    var l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    if (nz < 0) { nx = -nx; ny = -ny; nz = -nz; }
    return 0.24 + 0.76 * Math.max(0, nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]);
  }

  function strokeFacets(stroke, fam, w) {
    var HW = fam.width / 2, H = HW * fam.height, prof = fam.profile, closed = !!stroke.c;
    var xs = fam.xScale || 1, rs = fam.rScale || 1, skew = fam.skew || 0;
    var skel = stroke.p.map(function (q) { return [w / 2 + (q[0] - w / 2) * xs, q[1], q[2] ? q[2] * rs : (fam.soften || 0)]; });
    var P = fillet(skel, closed).map(function (q) { return [q[0] + (120 - q[1]) * skew, q[1]]; });
    var n = P.length, segCount = closed ? n : n - 1, dirs = [];
    for (var i = 0; i < segCount; i++) dirs.push(nrm(sub(P[(i + 1) % n], P[i])));
    var off = P.map(function (_, i) {
      var dIn = closed ? dirs[(i - 1 + segCount) % segCount] : dirs[Math.max(0, i - 1)];
      var dOut = closed ? dirs[i % segCount] : dirs[Math.min(segCount - 1, i)];
      var n1 = leftN(dIn), m = nrm(add(n1, leftN(dOut)));
      return mul(m, Math.min(HW / Math.max(m[0] * n1[0] + m[1] * n1[1], 0.2), HW * 2.5));
    });
    // Profile point t at skeleton vertex i, lifted to height h; stroke ends are inset by height (45° caps).
    function pt(i, pr) {
      var p = add(P[i], mul(off[i], -pr[0]));
      if (!closed && i === 0) p = add(p, mul(dirs[0], pr[1] * HW));
      if (!closed && i === n - 1) p = sub(p, mul(dirs[segCount - 1], pr[1] * HW));
      return [p[0], p[1], pr[1] * H];
    }
    function edge(i, pr) { var p = add(P[i], mul(off[i], -pr[0])); return [p[0], p[1], 0]; }
    var F = [];
    function push(poly) { F.push({ pts: poly.map(function (q) { return [q[0], q[1]]; }), g: shade(poly) }); }
    for (var s = 0; s < segCount; s++) {
      var j = (s + 1) % n;
      for (var k = 0; k < prof.length - 1; k++) push([pt(s, prof[k]), pt(j, prof[k]), pt(j, prof[k + 1]), pt(s, prof[k + 1])]);
    }
    if (!closed) {
      [0, n - 1].forEach(function (e) {
        for (var k = 0; k < prof.length - 1; k++) {
          if (prof[k][1] === 0 && prof[k + 1][1] === 0) continue;
          var poly = [pt(e, prof[k]), pt(e, prof[k + 1]), edge(e, prof[k + 1]), edge(e, prof[k])];
          if (prof[k][1] === 0) poly.splice(3, 1);           // left edge collapses to a point
          else if (prof[k + 1][1] === 0) poly.splice(2, 1);  // right edge collapses to a point
          push(poly);
        }
      });
    }
    return F;
  }

  function buildGlyph(familyKey, ch) {
    var fam = FAMILIES[familyKey], g = SKELETONS[ch], w = g.w * (fam.xScale || 1);
    var facets = [];
    g.s.forEach(function (st) { facets = facets.concat(strokeFacets(st, fam, w)); });
    return { w: w, facets: facets };
  }

  return { FAMILIES: FAMILIES, SKELETONS: SKELETONS, buildGlyph: buildGlyph };
})();
if (typeof module !== "undefined") module.exports = CarvedModel;
