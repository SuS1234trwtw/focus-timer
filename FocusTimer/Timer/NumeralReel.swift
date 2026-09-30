import SwiftUI

/// A numeral that reads as a carved, extruded block: soft cast shadow, a stepped side
/// extrusion toward the bottom-right, and a bevelled face lit from the top-left.
struct ChiseledNumeral: View {
    let text: String
    let font: Font
    let face: Color
    let lit: Bool
    let palette: Palette
    /// Extrusion depth in points.
    let depth: CGFloat

    private let layers = 6

    var body: some View {
        let glyph = Text(text).font(font).lineLimit(1).minimumScaleFactor(0.25)
        let side = face.mix(with: .black, by: lit ? 0.35 : 0.5)

        ZStack {
            glyph
                .foregroundStyle(palette.castShadow)
                .offset(x: depth * 1.6, y: depth * 2.4)
                .blur(radius: depth * 1.4)

            ForEach(1...layers, id: \.self) { step in
                glyph
                    .foregroundStyle(side)
                    .offset(x: depth * CGFloat(step) / CGFloat(layers), y: depth * CGFloat(step) / CGFloat(layers))
            }

            glyph.foregroundStyle(
                LinearGradient(
                    colors: [face.mix(with: .white, by: lit ? 0.0 : 0.1), face, face.mix(with: .black, by: 0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .shadow(.inner(color: .white.opacity(lit ? 0.9 : 0.16), radius: 1.2, x: -2, y: -2))
                .shadow(.inner(color: .black.opacity(lit ? 0.3 : 0.5), radius: 3, x: 3, y: 3))
            )
        }
        .compositingGroup()
    }
}

/// One big numeral in the chosen typeface: carved glyphs from Figma, or a font with the chiseled treatment.
struct NumeralFace: View {
    let text: String
    let font: TimerFont
    let lit: Bool
    let palette: Palette
    let height: CGFloat

    var body: some View {
        if font == .carved, CarvedGlyphSet.shared.supports(text) {
            CarvedNumeral(text: text, tone: palette.carvedTone(lit: lit), castShadow: palette.castShadow)
        } else {
            ChiseledNumeral(
                text: text,
                font: font.font(size: height * 0.98),
                face: lit ? palette.numeralLit : palette.numeral,
                lit: lit,
                palette: palette,
                depth: height * 0.022 * font.extrusion
            )
        }
    }
}

/// Vertical reel of minute values. Scroll to choose; the centred value is the block length.
struct NumeralReel: View {
    let values: [Int]
    @Binding var position: Int?
    let font: TimerFont
    let palette: Palette
    /// The value currently lit (timer running), if any.
    let litValue: Int?
    let locked: Bool

    var body: some View {
        GeometryReader { proxy in
            let itemHeight = proxy.size.height * 0.56
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        let lit = value == litValue
                        NumeralFace(text: "\(value)", font: font, lit: lit, palette: palette, height: itemHeight)
                        .padding(.horizontal, 22)
                        .frame(maxWidth: .infinity)
                        .frame(height: itemHeight)
                        .animation(.easeOut(duration: 0.35), value: lit)
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            content
                                .opacity(1 - abs(phase.value) * 0.4)
                                .scaleEffect(CGFloat(1 - abs(phase.value) * 0.06))
                        }
                        .accessibilityLabel("\(value) minutes")
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, (proxy.size.height - itemHeight) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollDisabled(locked)
            .sensoryFeedback(.selection, trigger: position)
        }
    }
}

/// Radial streaks that fly out from the centre when a block starts.
struct StartBurst: View {
    let trigger: Int
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            Color.clear
                .keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, progress in
                    content.overlay {
                        Canvas { context, size in
                            guard progress < 1 else { return }
                            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                            let reach = hypot(size.width, size.height) / 2
                            let p = CGFloat(progress)
                            let rays = 22
                            for index in 0..<rays {
                                let i = CGFloat(index)
                                let jitter = sin(i * 12.9898) * 0.25
                                let angle = (i + jitter) / CGFloat(rays) * 2 * .pi
                                let speed = 0.75 + abs(sin(i * 78.233)) * 0.5
                                let start = reach * (0.12 + 0.85 * p * speed)
                                let end = start + reach * 0.22 * (1 - p)
                                var path = Path()
                                path.move(to: CGPoint(x: centre.x + cos(angle) * start, y: centre.y + sin(angle) * start))
                                path.addLine(to: CGPoint(x: centre.x + cos(angle) * end, y: centre.y + sin(angle) * end))
                                context.stroke(path, with: .color(color.opacity(1 - progress)), lineWidth: 3)
                            }
                        }
                    }
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: 0.001)
                        CubicKeyframe(1.0, duration: 0.7)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
