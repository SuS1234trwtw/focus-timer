import SwiftUI

/// Faceted numeral families modelled in Figma ("Focus Timer — Carved Numerals & Icon"),
/// regenerated from scripts/carved_model.js into CarvedGlyphs.json.
final class CarvedGlyphSet: @unchecked Sendable {
    struct Facet {
        /// 0 (facing away from the light) … 1 (facing it).
        let light: Double
        let path: Path
    }

    struct Glyph {
        let width: CGFloat
        let facets: [Facet]
        /// Union of all facets: used for the extrusion and cast shadow.
        let silhouette: Path
    }

    let height: CGFloat
    /// Family key (TimerFont raw value) → glyphs.
    let families: [String: [Character: Glyph]]

    static let shared = CarvedGlyphSet()

    private init() {
        struct Raw: Decodable {
            struct RawGlyph: Decodable { let w: Double; let f: [[Double]] }
            struct RawFamily: Decodable { let glyphs: [String: RawGlyph] }
            let h: Double
            let families: [String: RawFamily]
        }

        guard
            let url = Bundle.main.url(forResource: "CarvedGlyphs", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let raw = try? JSONDecoder().decode(Raw.self, from: data)
        else {
            height = 240
            families = [:]
            return
        }

        var built: [String: [Character: Glyph]] = [:]
        for (familyKey, family) in raw.families {
            let shades = family.glyphs.values.flatMap { $0.f.compactMap(\.first) }
            let lo = shades.min() ?? 0, range = max((shades.max() ?? 100) - lo, 1)
            var glyphs: [Character: Glyph] = [:]
            for (key, glyph) in family.glyphs {
                guard let character = key.first else { continue }
                var silhouette = Path()
                let facets = glyph.f.compactMap { values -> Facet? in
                    guard values.count >= 7 else { return nil }
                    var path = Path()
                    path.move(to: CGPoint(x: values[1], y: values[2]))
                    for index in stride(from: 3, to: values.count - 1, by: 2) {
                        path.addLine(to: CGPoint(x: values[index], y: values[index + 1]))
                    }
                    path.closeSubpath()
                    silhouette.addPath(path)
                    return Facet(light: (values[0] - lo) / range, path: path)
                }
                glyphs[character] = Glyph(width: glyph.w, facets: facets, silhouette: silhouette)
            }
            built[familyKey] = glyphs
        }
        height = raw.h
        families = built
    }

    func glyphs(for font: TimerFont) -> [Character: Glyph] {
        families[font.rawValue] ?? families[TimerFont.carved.rawValue] ?? [:]
    }
}

/// Colours a carved numeral is shaded between.
struct CarvedTone: Equatable {
    /// Facets turned away from the light.
    let shadow: Color
    /// Facets facing the light.
    let highlight: Color
    /// The extruded sides.
    let side: Color
}

/// Draws a carved numeral: a soft cast shadow, a stepped extrusion toward the
/// bottom-right, then every facet shaded between the tone's shadow and highlight.
struct CarvedNumeral: View {
    let text: String
    var font: TimerFont = .carved
    let tone: CarvedTone
    let castShadow: Color

    private let set = CarvedGlyphSet.shared
    /// Gap between glyphs, in glyph units.
    private let tracking: CGFloat = 10

    var body: some View {
        let family = set.glyphs(for: font)
        let glyphs = text.compactMap { family[$0] }
        let grain = GrainOverlay.tile
        let totalWidth = glyphs.reduce(0) { $0 + $1.width } + tracking * CGFloat(max(glyphs.count - 1, 0))

        Canvas { context, size in
            guard !glyphs.isEmpty, totalWidth > 0 else { return }

            // Leave room for the extrusion and shadow falling to the bottom-right.
            let scale = min(size.width / totalWidth, size.height / set.height) * 0.9
            let depth = set.height * scale * 0.035
            let origin = CGPoint(
                x: (size.width - totalWidth * scale) / 2 - depth,
                y: (size.height - set.height * scale) / 2 - depth
            )

            var placements: [(CarvedGlyphSet.Glyph, CGAffineTransform)] = []
            var x = origin.x
            for glyph in glyphs {
                placements.append((glyph, CGAffineTransform(translationX: x, y: origin.y).scaledBy(x: scale, y: scale)))
                x += (glyph.width + tracking) * scale
            }

            var silhouette = Path()
            for (glyph, transform) in placements {
                silhouette.addPath(glyph.silhouette, transform: transform)
            }

            context.drawLayer { layer in
                layer.addFilter(.blur(radius: depth * 1.3))
                layer.fill(silhouette.offsetBy(dx: depth * 1.6, dy: depth * 2.2), with: .color(castShadow))
            }

            let steps = 8
            for step in stride(from: steps, through: 1, by: -1) {
                let offset = depth * CGFloat(step) / CGFloat(steps)
                context.fill(silhouette.offsetBy(dx: offset, dy: offset), with: .color(tone.side))
            }

            for (glyph, transform) in placements {
                for facet in glyph.facets {
                    let path = facet.path.applying(transform)
                    let color = tone.shadow.mix(with: tone.highlight, by: facet.light)
                    context.fill(path, with: .color(color))
                    // Hairline in the same colour hides anti-aliasing seams between facets.
                    context.stroke(path, with: .color(color), lineWidth: 0.6)
                }
            }

            // Stone grain over the faces so they read as a material, not flat vector.
            context.drawLayer { layer in
                layer.blendMode = .overlay
                layer.opacity = 0.55
                layer.fill(silhouette, with: .tiledImage(grain, scale: 0.5))
            }
        }
        .accessibilityLabel(text)
    }
}
