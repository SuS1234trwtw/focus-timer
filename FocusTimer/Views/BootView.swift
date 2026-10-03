import SwiftUI

/// The launch "boot" screen, mirroring the website's: a tty window types `$ focus --start`,
/// prints a short init log, fills a progress bar and assembles the FOCUS pixel banner, then fades away.
struct BootView: View {
    /// `@AppStorage` key for the "boot animation" setting (default on).
    static let enabledKey = "bootAnimation"

    let palette: Palette
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var typed = 0
    @State private var shownLines = 0
    @State private var doneLines = 0
    @State private var progress = 0.0
    @State private var stage = "post"
    @State private var bannerStart: Date?
    @State private var bannerDone = false
    @State private var thresholds = BootScript.revealThresholds(count: BootScript.bannerCells.count)
    @State private var exiting = false
    @State private var hidden = false
    @State private var didFinish = false

    /// How long the banner takes to assemble.
    private static let bannerDuration = 0.4

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()

            window
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .scaleEffect(hidden && !reduceMotion ? 0.96 : 1)

            VStack {
                Spacer()
                Text(palette.style.isFlat ? "TAP TO SKIP" : "tap to skip")
                    .font(palette.mono(10, relativeTo: .caption2))
                    .tracking(1.6)
                    .foregroundStyle(palette.dim)
                    .padding(.bottom, 16)
            }
        }
        .opacity(hidden ? 0 : 1)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .contentShape(.rect)
        .onTapGesture { requestExit() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus is starting")
        .accessibilityHint("Double-tap to skip")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { requestExit() }
        .task { await runSequence() }
        .task(id: exiting) {
            guard exiting else { return }
            withAnimation(.easeOut(duration: 0.35)) { hidden = true }
            try? await Task.sleep(for: .milliseconds(350))
            finish()
        }
    }

    // MARK: - Window

    private var window: some View {
        VStack(spacing: 0) {
            topBar
            hairline
            ZStack {
                log
                    .opacity(bannerStart == nil ? 1 : 0.12)
                    .blur(radius: bannerStart == nil ? 0 : 2)
                if bannerStart != nil {
                    banner
                        .padding(.horizontal, 18)
                        .transition(.opacity)
                }
            }
            hairline
            bottomBar
        }
        .background(palette.surface.opacity(0.55), in: .rect(cornerRadius: palette.style.radius(10)))
        .clipShape(.rect(cornerRadius: palette.style.radius(10)))
        .overlay(RoundedRectangle(cornerRadius: palette.style.radius(10)).strokeBorder(palette.border, lineWidth: 1))
    }

    private var hairline: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .strokeBorder(index == 0 ? palette.text : palette.border, lineWidth: 1)
                        .background(Circle().fill(index == 0 ? palette.text : Color.clear))
                        .frame(width: 9, height: 9)
                }
            }
            Spacer(minLength: 4)
            Text("FOCUS — BOOT — TTY1")
                .lineLimit(1)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(BootScript.clock(context.date))
                    .monospacedDigit()
            }
        }
        .font(palette.mono(10, relativeTo: .caption2))
        .tracking(1.2)
        .foregroundStyle(palette.dim)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var log: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 0) {
                Text(String(BootScript.command.prefix(typed)))
                    .foregroundStyle(palette.text)
                if bannerStart == nil {
                    Text(palette.style.cursor).foregroundStyle(palette.accent)
                }
            }
            .font(palette.mono(13, .bold, relativeTo: .footnote))

            ForEach(Array(BootScript.logSteps.prefix(shownLines).enumerated()), id: \.offset) { index, step in
                let done = index < doneLines
                HStack(spacing: 0) {
                    Text(BootScript.logLine(step)).foregroundStyle(palette.dim)
                    Text(done ? "[ ok ]" : "[ .. ]").foregroundStyle(done ? palette.text : palette.dim)
                }
                .transition(.opacity)
            }
        }
        .font(palette.mono(12, relativeTo: .caption))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var banner: some View {
        TimelineView(.animation(minimumInterval: nil, paused: bannerStart == nil || bannerDone)) { timeline in
            let elapsed: Double = bannerDone
                ? .infinity
                : bannerStart.map { timeline.date.timeIntervalSince($0) } ?? 0
            BannerCanvas(
                reveal: elapsed / Self.bannerDuration,
                thresholds: thresholds,
                ink: palette.text,
                glow: !palette.style.isFlat
            )
        }
        .frame(maxWidth: 360)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text(stage.uppercased())
                .foregroundStyle(palette.text)
                .frame(minWidth: 62, alignment: .leading)
            Rectangle()
                .fill(palette.text)
                .scaleEffect(x: max(0, min(progress, 1)), y: 1, anchor: .leading)
                .padding(1)
                .frame(height: 6)
                .overlay(Rectangle().strokeBorder(palette.border, lineWidth: 1))
            Text(BootScript.percent(progress))
                .monospacedDigit()
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
        }
        .font(palette.mono(10, relativeTo: .caption2))
        .tracking(1.2)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Timing

    /// Sleeps, then reports whether the sequence should keep going (not cancelled, not skipped).
    private func pause(_ milliseconds: Int) async -> Bool {
        try? await Task.sleep(for: .milliseconds(milliseconds))
        return !Task.isCancelled && !exiting
    }

    private func runSequence() async {
        if reduceMotion {
            // A static, finished frame, then a plain fade.
            typed = BootScript.command.count
            shownLines = BootScript.logSteps.count
            doneLines = BootScript.logSteps.count
            progress = 1
            stage = "ready"
            bannerStart = .now
            bannerDone = true
            guard await pause(400) else { return }
            requestExit()
            return
        }

        // 1. the command, typed
        guard await pause(80) else { return }
        for count in 1...BootScript.command.count {
            typed = count
            progress = 0.1 * Double(count) / Double(BootScript.command.count)
            guard await pause(22) else { return }
        }
        guard await pause(60) else { return }

        // 2. init log: "[ .. ]" then "[ ok ]"
        stage = "modules"
        let steps = BootScript.logSteps.count
        for index in 0..<steps {
            withAnimation(.easeOut(duration: 0.12)) {
                shownLines = index + 1
                progress = 0.1 + 0.74 * (Double(index) + 0.5) / Double(steps)
            }
            guard await pause(55) else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                doneLines = index + 1
                progress = 0.1 + 0.74 * Double(index + 1) / Double(steps)
            }
            guard await pause(55) else { return }
        }
        guard await pause(40) else { return }

        // 3. the banner assembles over the dimmed log while the bar fills
        stage = "render"
        withAnimation(.easeOut(duration: 0.2)) { bannerStart = .now }
        withAnimation(.linear(duration: Self.bannerDuration)) { progress = 1 }
        guard await pause(Int(Self.bannerDuration * 1000)) else { return }
        bannerDone = true
        stage = "ready"

        // 4. a beat to read it, then out
        guard await pause(180) else { return }
        requestExit()
    }

    private func requestExit() {
        guard !exiting else { return }
        exiting = true
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

/// The FOCUS pixel banner; each cell fades and grows in once `reveal` (0...1) passes its threshold.
private struct BannerCanvas: View {
    let reveal: Double
    let thresholds: [Double]
    let ink: Color
    let glow: Bool

    var body: some View {
        let cells = BootScript.bannerCells
        let thresholds = thresholds
        let reveal = reveal
        let ink = ink
        let ramp = BootScript.revealRamp
        Canvas { context, size in
            let cell = size.width / CGFloat(BootScript.bannerColumns)
            for (index, position) in cells.enumerated() {
                let start = index < thresholds.count ? thresholds[index] : 0
                let local = min(max((reveal - start) / ramp, 0), 1)
                guard local > 0 else { continue }
                // Full cells overlap a hair so no seams show between neighbours.
                let side = cell * CGFloat(0.4 + 0.6 * local) + (local >= 1 ? 0.5 : 0)
                let rect = CGRect(
                    x: CGFloat(position.col) * cell + (cell - side) / 2,
                    y: CGFloat(position.row) * cell + (cell - side) / 2,
                    width: side,
                    height: side
                )
                context.opacity = local
                context.fill(Path(rect), with: .color(ink))
            }
        }
        .aspectRatio(CGFloat(BootScript.bannerColumns) / CGFloat(BootScript.bannerRows.count), contentMode: .fit)
        .shadow(color: glow ? ink.opacity(0.25) : .clear, radius: 6)
        .accessibilityHidden(true)
    }
}

/// The boot screen's script and banner, kept pure so it can be tested.
enum BootScript {
    /// The website's 5-row FOCUS bitmap, one string per letter row.
    static let letters: [[String]] = [
        ["███████", "██     ", "█████  ", "██     ", "██     "],          // F
        [" ██████ ", "██    ██", "██    ██", "██    ██", " ██████ "],     // O
        [" ██████", "██     ", "██     ", "██     ", " ██████"],          // C
        ["██    ██", "██    ██", "██    ██", "██    ██", " ██████ "],     // U
        [" ██████", "██     ", " █████ ", "     ██", "██████ "]           // S
    ]

    /// FOCUS in 5 rows, the letters joined by two spaces (45 columns).
    static let bannerRows: [String] = (0..<5).map { row in
        letters.map { $0[row] }.joined(separator: "  ")
    }

    static let bannerColumns = 45

    /// Every filled cell of the banner, row by row.
    static let bannerCells: [(row: Int, col: Int)] = {
        var cells: [(row: Int, col: Int)] = []
        for (row, line) in bannerRows.enumerated() {
            for (col, character) in line.enumerated() where character == "█" {
                cells.append((row: row, col: col))
            }
        }
        return cells
    }()

    /// The typed command first, then the init log lines.
    static let steps: [String] = [
        "$ focus --start",
        "init timer engine",
        "init core haptics",
        "init dynamic island",
        "mount ~/tasks (sync)",
        "init google calendar"
    ]

    static var command: String { steps[0] }
    static var logSteps: ArraySlice<String> { steps.dropFirst() }

    /// Share of the banner's reveal each cell spends growing in.
    static let revealRamp = 0.2

    /// A random start point in 0..<(1 - ramp) for each cell, so they light up in a random order.
    static func revealThresholds(count: Int) -> [Double] {
        guard count > 0 else { return [] }
        return Array(0..<count).shuffled().map { Double($0) / Double(count) * (1 - revealRamp) }
    }

    /// The step name followed by a dotted leader, padded so every status lines up.
    static func logLine(_ name: String, width: Int = 26) -> String {
        "\(name) \(String(repeating: ".", count: max(1, width - name.count - 1))) "
    }

    /// "000%" ... "100%".
    static func percent(_ progress: Double) -> String {
        String(format: "%03d%%", Int((min(max(progress, 0), 1) * 100).rounded()))
    }

    /// 24-hour HH:MM:SS.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

#Preview {
    BootView(palette: TerminalStyle.mono.basePalette(for: .focus)) {}
        .preferredColorScheme(.dark)
}
