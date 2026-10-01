import Foundation
import Testing
@testable import FocusTimer

struct IslandControlsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// A running block with 10 minutes left and every setting left at its default (nil).
    private func running(_ configure: (inout FocusActivityAttributes.ContentState) -> Void = { _ in }) -> FocusActivityAttributes.ContentState {
        var state = FocusActivityAttributes.ContentState(
            mode: "focus", endDate: now.addingTimeInterval(600), remaining: 600, total: 1500,
            taskTitle: nil, accentHex: "F5A05A", backgroundHex: "1A1614", textHex: "E8DCCF", dimHex: "8A7D72",
            trackLine: nil, started: true
        )
        configure(&state)
        return state
    }

    @Test func runningWithDefaultsShowsControls() {
        let state = running()
        #expect(state.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(state.showsControls(now: now, isStale: false, lockScreen: true))
    }

    @Test func pausedHidesControls() {
        let state = running { $0.endDate = nil }
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: false))
    }

    @Test func endedBlockHidesControls() {
        let state = running { $0.endDate = self.now }
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(!state.showsControls(now: now.addingTimeInterval(1), isStale: false, lockScreen: false))
    }

    @Test func staleHidesControls() {
        #expect(!running().showsControls(now: now, isStale: true, lockScreen: false))
    }

    @Test func terminatedAppHidesControls() {
        let state = running { $0.appAlive = false }
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(running { $0.appAlive = true }.showsControls(now: now, isStale: false, lockScreen: false))
    }

    @Test func masterSwitchOffHidesControls() {
        let state = running { $0.controls = false }
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: true))
    }

    @Test func lockScreenSettingOnlyAffectsLockScreen() {
        let state = running { $0.lockControls = false }
        #expect(state.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(!state.showsControls(now: now, isStale: false, lockScreen: true))
    }

    @Test func needsAtLeastOneButton() {
        let none = running { $0.showToggle = false; $0.showSwitch = false }
        #expect(!none.showsControls(now: now, isStale: false, lockScreen: false))

        let onlySwitch = running { $0.showToggle = false }
        #expect(onlySwitch.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(!onlySwitch.showsToggle && onlySwitch.showsSwitch)

        let onlyPause = running { $0.showSwitch = false }
        #expect(onlyPause.showsControls(now: now, isStale: false, lockScreen: false))
        #expect(onlyPause.showsToggle && !onlyPause.showsSwitch)
    }

    @Test func oldStateWithoutNewFieldsStillDecodesAndShowsControls() throws {
        let json = """
        {"mode":"rest","endDate":\(now.addingTimeInterval(60).timeIntervalSinceReferenceDate),"remaining":60,"total":300,
         "accentHex":"F5A05A","backgroundHex":"1A1614","textHex":"E8DCCF","dimHex":"8A7D72"}
        """
        let state = try JSONDecoder().decode(FocusActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(state.controls == nil && state.appAlive == nil)
        #expect(state.showsControls(now: now, isStale: false, lockScreen: true))
    }

    @Test func settingsDefaultWhenUnset() throws {
        let suite = "IslandControlsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(IslandSettings.buttons(in: defaults))
        #expect(IslandSettings.pauseButton(in: defaults))
        #expect(IslandSettings.switchButton(in: defaults))
        #expect(IslandSettings.lockScreenButtons(in: defaults))

        defaults.set(false, forKey: IslandSettings.Key.switchButton)
        #expect(!IslandSettings.switchButton(in: defaults))
    }
}
