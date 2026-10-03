import Testing
import UIKit
@testable import FocusTimer

struct DeviceCapabilitiesTests {
    @Test(arguments: [59.0, 62.0, 68.0])
    func islandPhones(inset: Double) {
        #expect(DeviceCapabilities.hasIsland(topInset: CGFloat(inset), idiom: .phone))
    }

    @Test(arguments: [0.0, 20.0, 44.0, 47.0, 48.0, 50.0, 58.9])
    func notchAndHomeButtonPhones(inset: Double) {
        #expect(!DeviceCapabilities.hasIsland(topInset: CGFloat(inset), idiom: .phone))
    }

    @Test func iPadNeverHasIsland() {
        #expect(!DeviceCapabilities.hasIsland(topInset: 24, idiom: .pad))
        #expect(!DeviceCapabilities.hasIsland(topInset: 64, idiom: .pad))
    }
}
