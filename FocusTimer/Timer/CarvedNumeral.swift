import CoreGraphics
import SwiftUI
import UIKit

/// Faceted numeral families modelled in Figma ("Focus Timer — Carved Numerals & Icon"),
/// regenerated from scripts/carved_model.js into CarvedGlyphs.json.
/// Immutable after load, so it is safe to read from the background renderer.
final class CarvedGlyphSet: @unchecked Sendable {
    struct Facet {
        /// 0 (facing away from the light) … 1 (facing it).
        let light: Double
        let path: CGPath
    }

    struct Glyph {
        let width: CGFloat
        let facets: [Facet]
        /// Union of all facets: used for the extrusion, shadow and grain clip.
        let silhouette: CGPath
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
                let silhouette = CGMutablePath()
                let facets = glyph.f.compactMap { values -> Facet? in
                    guard values.count >= 7 else { return nil }
                    let path = CGMutablePath()
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

/// One rasterisation of a numeral: what to draw, in which tones, at which size.
struct CarvedRenderRequest: Sendable, Hashable {
    let text: String
    let font: TimerFont
    let tone: CarvedTone
    let castShadow: RGB
    /// Point size, rounded so tiny layout changes reuse the cached image.
    let size: CGSize
    let scale: CGFloat

    init(text: String, font: TimerFont, tone: CarvedTone, castShadow: RGB, size: CGSize, scale: CGFloat) {
        self.text = text
        self.font = font
        self.tone = tone
        self.castShadow = castShadow
        self.size = CGSize(width: (size.width / 4).rounded() * 4, height: (size.height / 4).rounded() * 4)
        self.scale = scale
    }

    var key: String {
        "\(text)|\(font.rawValue)|\(tone.id)|\(Int(size.width))x\(Int(size.height))@\(scale)"
    }
}

/// Draws carved numerals into bitmaps off the main thread and caches them, so scrolling and
/// state changes only move finished images instead of re-shading thousands of facets per frame.
enum CarvedRenderer {
    /// NSCache is internally synchronised.
    private final class Cache: @unchecked Sendable {
        let images: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.totalCostLimit = 120 * 1024 * 1024
            return cache
        }()
    }

    private static let cache = Cache()

    static func cached(_ request: CarvedRenderRequest) -> UIImage? {
        cache.images.object(forKey: request.key as NSString)
    }

    @concurrent
    static func render(_ request: CarvedRenderRequest) async -> UIImage? {
        if let hit = cached(request) { return hit }
        guard let image = draw(request) else { return nil }
        let pixels = Int(request.size.width * request.size.height * request.scale * request.scale * 4)
        cache.images.setObject(image, forKey: request.key as NSString, cost: pixels)
        return image
    }

    /// Warms the cache for images the user is about to see (neighbouring reel values, the lit state).
    static func prewarm(_ requests: [CarvedRenderRequest]) {
        let missing = requests.filter { cached($0) == nil }
        guard !missing.isEmpty else { return }
        Task(priority: .utility) {
            for request in missing { _ = await render(request) }
        }
    }

    private static func draw(_ request: CarvedRenderRequest) -> UIImage? {
        let set = CarvedGlyphSet.shared
        let family = set.glyphs(for: request.font)
        let glyphs = request.text.compactMap { family[$0] }
        let tracking: CGFloat = 10
        let totalWidth = glyphs.reduce(0) { $0 + $1.width } + tracking * CGFloat(max(glyphs.count - 1, 0))
        let size = request.size, scale = request.scale
        let pixelWidth = Int(size.width * scale), pixelHeight = Int(size.height * scale)
        guard !glyphs.isEmpty, totalWidth > 0, pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Work in points with y pointing down, like SwiftUI.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high

        // Leave room for the extrusion and shadow falling to the bottom-right.
        let glyphScale = min(size.width / totalWidth, size.height / set.height) * 0.9
        let depth = set.height * glyphScale * 0.035
        var x = (size.width - totalWidth * glyphScale) / 2 - depth
        let y = (size.height - set.height * glyphScale) / 2 - depth
        let placements: [(CarvedGlyphSet.Glyph, CGAffineTransform)] = glyphs.map { glyph in
            defer { x += (glyph.width + tracking) * glyphScale }
            return (glyph, CGAffineTransform(translationX: x, y: y).scaledBy(x: glyphScale, y: glyphScale))
        }

        let tone = request.tone
        func fillSilhouettes(offset: CGFloat, color: CGColor) {
            context.setFillColor(color)
            for (glyph, transform) in placements {
                context.saveGState()
                context.translateBy(x: offset, y: offset)
                context.concatenate(transform)
                context.addPath(glyph.silhouette)
                context.fillPath()
                context.restoreGState()
            }
        }

        // Cast shadow. Shadow offsets are in device space, where y points up.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: depth * 1.6 * scale, height: -depth * 2.2 * scale),
            blur: depth * 2.6 * scale,
            color: request.castShadow.cgColor
        )
        fillSilhouettes(offset: depth, color: tone.side.cgColor)
        context.restoreGState()

        // Stepped extrusion toward the bottom-right.
        let steps = 8
        for step in stride(from: steps, through: 1, by: -1) {
            fillSilhouettes(offset: depth * CGFloat(step) / CGFloat(steps), color: tone.side.cgColor)
        }

        // Facets, shaded between the tone's shadow and highlight.
        let levels = 48
        let ramp = (0..<levels).map { tone.shadow.mix(tone.highlight, Double($0) / Double(levels - 1)).cgColor }
        context.setLineWidth(0.6 / glyphScale)
        context.setLineJoin(.round)
        for (glyph, transform) in placements {
            context.saveGState()
            context.concatenate(transform)
            for facet in glyph.facets {
                let color = ramp[min(levels - 1, max(0, Int(facet.light * Double(levels - 1) + 0.5)))]
                context.setFillColor(color)
                // A hairline in the same colour hides anti-aliasing seams between facets.
                context.setStrokeColor(color)
                context.addPath(facet.path)
                context.drawPath(using: .fillStroke)
            }
            context.restoreGState()
        }

        // Stone grain over the faces.
        if let grain = GrainTile.shared.cgImage {
            context.saveGState()
            for (glyph, transform) in placements {
                var t = transform
                if let clip = glyph.silhouette.copy(using: &t) { context.addPath(clip) }
            }
            context.clip()
            context.setBlendMode(.overlay)
            context.setAlpha(0.55)
            context.draw(grain, in: CGRect(x: 0, y: 0, width: 80, height: 80), byTiling: true)
            context.restoreGState()
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

/// A carved numeral, drawn by `CarvedRenderer` and cross-faded when its tone changes
/// (dark ↔ lit), so state changes glow rather than snap.
struct CarvedNumeral: View {
    let text: String
    var font: TimerFont = .carved
    let tone: CarvedTone
    let castShadow: RGB

    @Environment(\.displayScale) private var displayScale
    @State private var rendered: Rendered?

    private struct Rendered: Equatable {
        let key: String
        let image: UIImage
        static func == (lhs: Rendered, rhs: Rendered) -> Bool { lhs.key == rhs.key }
    }

    var body: some View {
        GeometryReader { proxy in
            let request = CarvedRenderRequest(
                text: text, font: font, tone: tone, castShadow: castShadow,
                size: proxy.size, scale: displayScale
            )
            ZStack {
                if let rendered {
                    Image(uiImage: rendered.image)
                        .resizable()
                        .id(rendered.key)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.3), value: rendered)
            .task(id: request.key) {
                if let hit = CarvedRenderer.cached(request) {
                    show(Rendered(key: request.key, image: hit))
                    return
                }
                guard let image = await CarvedRenderer.render(request), !Task.isCancelled else { return }
                show(Rendered(key: request.key, image: image))
            }
        }
        .accessibilityLabel(text)
    }

    /// First appearance is instant (no fade while scrolling); later changes cross-fade.
    private func show(_ next: Rendered) {
        var transaction = Transaction()
        transaction.disablesAnimations = rendered == nil
        withTransaction(transaction) { rendered = next }
    }
}
