import SwiftUI

/// CRT flavor: faint scanlines, a vignette, and a soft accent glow from the top.
struct TerminalOverlay: View {
    let accent: Color

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(0.14), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.16)))
                    y += 3
                }
            }
            RadialGradient(
                colors: [.clear, .black.opacity(0.45)],
                center: .center,
                startRadius: 180,
                endRadius: 640
            )
        }
    }
}
