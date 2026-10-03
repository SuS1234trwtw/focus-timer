import Foundation
import Testing
@testable import FocusTimer

struct TimerLengthTests {
    @Test func lengthEditableOnlyWhenIdle() {
        let started = Date()
        #expect(TimerView.canEditLength(isRunning: false, segmentStartedAt: nil))
        #expect(!TimerView.canEditLength(isRunning: true, segmentStartedAt: nil))
        #expect(!TimerView.canEditLength(isRunning: false, segmentStartedAt: started))
        #expect(!TimerView.canEditLength(isRunning: true, segmentStartedAt: started))
    }

    @Test func classicPresetComesFirst() {
        #expect(TimerLengthSheet.presets.first == TimerLengthSheet.Preset(focus: 25, rest: 5))
        #expect(TimerLengthSheet.presets.count == 4)
    }
}
