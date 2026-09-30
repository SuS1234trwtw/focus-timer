import SwiftUI

/// One big carved numeral in the chosen family, toned for the theme and lit state.
struct NumeralFace: View {
    let text: String
    let font: TimerFont
    let lit: Bool
    let palette: Palette

    var body: some View {
        CarvedNumeral(text: text, font: font, tone: palette.carvedTone(lit: lit), castShadow: palette.castShadow)
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

    @Environment(\.displayScale) private var displayScale

    private let horizontalInset: CGFloat = 22

    var body: some View {
        GeometryReader { proxy in
            let itemHeight = proxy.size.height * 0.56
            let cellSize = CGSize(width: proxy.size.width - horizontalInset * 2, height: itemHeight)
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        let lit = value == litValue
                        NumeralFace(text: "\(value)", font: font, lit: lit, palette: palette)
                            // Only the lit number gets a small spring pop; the reel itself never scales.
                            .keyframeAnimator(initialValue: 1.0, trigger: lit) { content, scale in
                                content.scaleEffect(scale)
                            } keyframes: { _ in
                                KeyframeTrack {
                                    SpringKeyframe(1.035, duration: 0.14, spring: .snappy)
                                    SpringKeyframe(1.0, duration: 0.45, spring: .smooth)
                                }
                            }
                            .padding(.horizontal, horizontalInset)
                            .frame(maxWidth: .infinity)
                            .frame(height: itemHeight)
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
            .onChange(of: PrewarmKey(position: position, font: font, palette: palette, litValue: litValue, size: cellSize), initial: true) { _, key in
                prewarm(key)
            }
        }
    }

    private struct PrewarmKey: Equatable {
        let position: Int?
        let font: TimerFont
        let palette: Palette
        let litValue: Int?
        let size: CGSize
    }

    /// Renders the neighbours and the lit version of the centre ahead of time, so nothing pops in.
    private func prewarm(_ key: PrewarmKey) {
        guard let centre = key.position, key.size.width > 0 else { return }
        var requests: [CarvedRenderRequest] = []
        for value in (centre - 2)...(centre + 2) where values.contains(value) {
            requests.append(request(value, lit: value == key.litValue, key))
        }
        requests.append(request(centre, lit: true, key))
        CarvedRenderer.prewarm(requests)
    }

    private func request(_ value: Int, lit: Bool, _ key: PrewarmKey) -> CarvedRenderRequest {
        CarvedRenderRequest(
            text: "\(value)", font: key.font, tone: key.palette.carvedTone(lit: lit),
            castShadow: key.palette.castShadow, size: key.size, scale: displayScale
        )
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
                            let rays = 18
                            for index in 0..<rays {
                                let i = CGFloat(index)
                                let jitter = sin(i * 12.9898) * 0.25
                                let angle = (i + jitter) / CGFloat(rays) * 2 * .pi
                                let speed = 0.75 + abs(sin(i * 78.233)) * 0.5
                                let start = reach * (0.22 + 0.8 * p * speed)
                                let end = start + reach * 0.26 * (1 - p)
                                var path = Path()
                                path.move(to: CGPoint(x: centre.x + cos(angle) * start, y: centre.y + sin(angle) * start))
                                path.addLine(to: CGPoint(x: centre.x + cos(angle) * end, y: centre.y + sin(angle) * end))
                                context.stroke(path, with: .color(color.opacity(1 - progress)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            }
                        }
                    }
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: 0.001)
                        CubicKeyframe(1.0, duration: 0.45)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
