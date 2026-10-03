import SwiftUI

/// Motion tokens (transitions.dev scale). Surfaces move on a smooth ease-out; text, icon and colour
/// swaps use ease-in-out. Closes run faster than opens.
enum Motion {
    /// Smooth ease-out for surface motion: open/close, slide, resize, list moves.
    static func smooth(_ duration: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: duration) }
    /// Text, icon and colour swaps.
    static func swap(_ duration: Double = 0.25) -> Animation { .easeInOut(duration: duration) }

    static var quick: Animation { smooth(0.15) }     // close, small swap, press in
    static var fast: Animation { smooth(0.25) }      // open, page/tab/list change, press out
    static var medium: Animation { smooth(0.35) }    // panel close
    static var slow: Animation { smooth(0.4) }       // panel open
    static var verySlow: Animation { smooth(0.5) }   // emphasis

    /// Something appearing in a column: fades in from 8 pt above, fades out on the quick token.
    /// Opacity only with Reduce Motion.
    @MainActor static func reveal(reduceMotion: Bool) -> AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -8)),
            removal: .opacity.animation(quick)
        )
    }

    /// Text or icon swap: 4 pt rise and a 2 pt blur. Opacity only with Reduce Motion.
    @MainActor static func textSwap(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity
                .combined(with: .offset(y: 4))
                .combined(with: .modifier(active: MotionBlur(radius: 2), identity: MotionBlur(radius: 0)))
    }
}

private struct MotionBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
