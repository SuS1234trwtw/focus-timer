import Foundation
import Testing
import UserNotifications
@testable import FocusTimer

struct SoundBoardTests {
    func freshDefaults() -> UserDefaults {
        let suite = "SoundBoardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsKeepTodaysBehaviour() {
        let defaults = freshDefaults()
        #expect(SoundBoard.choice(for: .focusEnd, defaults: defaults) == .builtIn("chime"))
        #expect(SoundBoard.choice(for: .breakEnd, defaults: defaults) == .builtIn("chime"))
        #expect(SoundBoard.choice(for: .focusStart, defaults: defaults) == .none)
        #expect(SoundBoard.choice(for: .breakStart, defaults: defaults) == .none)
    }

    @Test func setThenReadBack() {
        let defaults = freshDefaults()
        SoundBoard.set(.custom("rain.caf"), for: .breakStart, defaults: defaults)
        #expect(SoundBoard.choice(for: .breakStart, defaults: defaults) == .custom("rain.caf"))
        #expect(SoundBoard.choice(for: .focusStart, defaults: defaults) == .none)
    }

    @Test(arguments: [SoundChoice.builtIn("bell"), .custom("my song.caf"), .none])
    func choiceRoundTrips(_ choice: SoundChoice) throws {
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(SoundChoice.self, from: data) == choice)
    }

    @Test func notificationSoundNames() {
        #expect(SoundBoard.notificationSoundName(for: .builtIn("bell")) == UNNotificationSoundName("pack_bell.wav"))
        #expect(SoundBoard.notificationSoundName(for: .custom("my song.caf")) == UNNotificationSoundName("my song.caf"))
        #expect(SoundBoard.notificationSoundName(for: .none) == nil)
    }

    @Test func noneMeansSilentNotification() {
        let defaults = freshDefaults()
        SoundBoard.set(.none, for: .focusEnd, defaults: defaults)
        #expect(SoundBoard.notificationSound(for: .focusEnd, defaults: defaults) == nil)
        #expect(SoundBoard.notificationSound(for: .breakEnd, defaults: defaults) != nil)
    }

    @Test func builtInsMatchTheGeneratedPack() {
        #expect(SoundBoard.builtIns == ["chime", "bell", "beep", "blip", "wood", "softpad", "arcade"])
        #expect(SoundMoment.allCases.map(\.label) == ["focus starts", "focus ends", "break starts", "break ends"])
    }
}
