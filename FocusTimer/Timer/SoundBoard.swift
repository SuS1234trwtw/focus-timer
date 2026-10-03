import AVFoundation
import Foundation
import UserNotifications

/// The four moments a block can make a sound.
enum SoundMoment: String, CaseIterable, Identifiable, Sendable {
    case focusStart, focusEnd, breakStart, breakEnd

    var id: String { rawValue }

    var label: String {
        switch self {
        case .focusStart: "focus starts"
        case .focusEnd: "focus ends"
        case .breakStart: "break starts"
        case .breakEnd: "break ends"
        }
    }

    var isEnd: Bool { self == .focusEnd || self == .breakEnd }

    /// Today's behaviour: the chime when a block ends, silence when one starts.
    var defaultChoice: SoundChoice { isEnd ? .builtIn("chime") : .none }
}

/// What plays at a moment: a bundled `pack_<name>.wav`, a file the user imported into Library/Sounds, or nothing.
enum SoundChoice: Hashable, Codable, Sendable {
    case builtIn(String)
    /// File name (with extension) in Library/Sounds.
    case custom(String)
    case none

    var name: String {
        switch self {
        case .builtIn(let name): name
        case .custom(let file): (file as NSString).deletingPathExtension
        case .none: "none"
        }
    }
}

enum SoundImportError: LocalizedError {
    case notAudio, empty

    var errorDescription: String? {
        switch self {
        case .notAudio: "that file isn't audio iOS can read"
        case .empty: "that file has no sound in it"
        }
    }
}

/// Which sound plays when, the user's imported sounds, and playback.
enum SoundBoard {
    /// Names of the bundled `pack_<name>.wav` files (see scripts/generate_assets.py).
    static let builtIns = ["chime", "bell", "beep", "blip", "wood", "softpad", "arcade"]
    /// iOS refuses notification sounds of 30 s or more.
    static let maxSeconds: Double = 29

    static func key(_ moment: SoundMoment) -> String { "sound.\(moment.rawValue)" }

    // MARK: Choices

    static func choice(for moment: SoundMoment, defaults: UserDefaults = .standard) -> SoundChoice {
        guard let data = defaults.data(forKey: key(moment)),
              let choice = try? JSONDecoder().decode(SoundChoice.self, from: data) else { return moment.defaultChoice }
        return choice
    }

    static func set(_ choice: SoundChoice, for moment: SoundMoment, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(choice) else { return }
        defaults.set(data, forKey: key(moment))
    }

    // MARK: Notifications

    static func notificationSoundName(for choice: SoundChoice) -> UNNotificationSoundName? {
        switch choice {
        case .builtIn(let name): UNNotificationSoundName("pack_\(name).wav")
        // iOS looks in the app's Library/Sounds for notification sounds too.
        case .custom(let file): UNNotificationSoundName(file)
        case .none: nil
        }
    }

    /// Nil means a silent notification.
    static func notificationSound(for moment: SoundMoment, defaults: UserDefaults = .standard) -> UNNotificationSound? {
        notificationSoundName(for: choice(for: moment, defaults: defaults)).map { UNNotificationSound(named: $0) }
    }

    // MARK: Files

    static var soundsFolder: URL {
        URL.libraryDirectory.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    /// The file to play for a choice, falling back to the chime when a file has gone missing.
    static func url(for choice: SoundChoice) -> URL? {
        let chime = Bundle.main.url(forResource: "chime", withExtension: "wav")
        switch choice {
        case .builtIn(let name):
            return Bundle.main.url(forResource: "pack_\(name)", withExtension: "wav") ?? chime
        case .custom(let file):
            let url = soundsFolder.appending(path: file)
            return FileManager.default.fileExists(atPath: url.path) ? url : chime
        case .none:
            return nil
        }
    }

    static func customFiles() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: soundsFolder.path)) ?? []
        return files.filter { ["caf", "wav", "aiff"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Removes an imported sound; moments that used it go back to their default.
    static func delete(_ name: String, defaults: UserDefaults = .standard) {
        try? FileManager.default.removeItem(at: soundsFolder.appending(path: name))
        for moment in SoundMoment.allCases where choice(for: moment, defaults: defaults) == .custom(name) {
            defaults.removeObject(forKey: key(moment))
        }
    }

    /// Copies a picked audio file into Library/Sounds as ≤29 s 16-bit PCM .caf (a format notifications accept).
    /// Returns the new file name.
    static func importFile(_ url: URL) async throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let input: AVAudioFile
        do { input = try AVAudioFile(forReading: url) } catch { throw SoundImportError.notAudio }
        guard input.length > 0 else { throw SoundImportError.empty }

        let format = input.processingFormat
        try FileManager.default.createDirectory(at: soundsFolder, withIntermediateDirectories: true)
        let name = uniqueName(for: url)
        let destination = soundsFolder.appending(path: name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let output = try AVAudioFile(forWriting: destination, settings: settings,
                                         commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            var remaining = min(input.length, AVAudioFramePosition(maxSeconds * format.sampleRate))
            let chunk: AVAudioFrameCount = 32_768
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw SoundImportError.notAudio }
            while remaining > 0 {
                try input.read(into: buffer, frameCount: AVAudioFrameCount(min(AVAudioFramePosition(chunk), remaining)))
                if buffer.frameLength == 0 { break }
                try output.write(from: buffer)
                remaining -= AVAudioFramePosition(buffer.frameLength)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw (error as? SoundImportError) ?? SoundImportError.notAudio
        }
        return name
    }

    /// "My Song!.mp3" → "My Song_.caf", then "My Song_ 2.caf" if taken.
    static func uniqueName(for url: URL) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let raw = url.deletingPathExtension().lastPathComponent
        var base = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
            .trimmingCharacters(in: .whitespaces)
        base = String(base.prefix(40))
        if base.isEmpty { base = "sound" }
        let taken = Set(customFiles().map { $0.lowercased() })
        var candidate = "\(base).caf"
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n).caf"
            n += 1
        }
        return candidate
    }

    // MARK: Playback

    /// One player per slot, so a start sound right after an end sound doesn't cut it off.
    @MainActor private static var players: [Bool: AVAudioPlayer] = [:]

    /// Plays the chosen sound. Ends always ring (like the chime did, even on silent);
    /// starts are UI-like: they follow the sounds switch and the silent switch.
    @MainActor
    static func play(_ moment: SoundMoment) {
        if !moment.isEnd {
            guard UserDefaults.standard.object(forKey: Feedback.Key.sounds) as? Bool ?? true else { return }
        }
        play(url(for: choice(for: moment)), ringOnSilent: moment.isEnd)
    }

    /// Plays a choice from the picker, whatever the switches say.
    @MainActor
    static func preview(_ choice: SoundChoice) {
        play(url(for: choice), ringOnSilent: true)
    }

    @MainActor
    private static func play(_ url: URL?, ringOnSilent: Bool) {
        guard let url else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Playback rings on silent; ambient respects it. Both mix so music keeps playing.
            try session.setCategory(ringOnSilent ? .playback : .ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.8
            player.play()
            players[ringOnSilent] = player
        } catch {
            // A missing sound should never interrupt the timer.
        }
    }
}
