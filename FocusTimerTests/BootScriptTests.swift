import Foundation
import Testing
@testable import FocusTimer

struct BootScriptTests {
    @Test func bannerIsFiveRowsOf45Columns() {
        #expect(BootScript.bannerRows.count == 5)
        for row in BootScript.bannerRows {
            #expect(row.count == 45)
        }
        #expect(BootScript.bannerColumns == 45)
    }

    @Test func filledCellsMatchBlockCharacters() {
        let blocks = BootScript.bannerRows.reduce(0) { total, row in total + row.filter { $0 == "█" }.count }
        #expect(blocks > 0)
        #expect(BootScript.bannerCells.count == blocks)
        for cell in BootScript.bannerCells {
            let row = Array(BootScript.bannerRows[cell.row])
            #expect(row[cell.col] == "█")
        }
    }

    @Test func stepsStartWithTheCommand() {
        #expect(!BootScript.steps.isEmpty)
        #expect(BootScript.steps.first == "$ focus --start")
        #expect(BootScript.command == "$ focus --start")
        #expect(BootScript.logSteps.count == BootScript.steps.count - 1)
    }

    @Test func logLinesLineUp() {
        let widths = Set(BootScript.logSteps.map { BootScript.logLine($0).count })
        #expect(widths.count == 1)
    }

    @Test func revealThresholdsCoverEveryCellOnce() {
        let count = BootScript.bannerCells.count
        let thresholds = BootScript.revealThresholds(count: count)
        #expect(thresholds.count == count)
        #expect(Set(thresholds).count == count)
        #expect(thresholds.allSatisfy { $0 >= 0 && $0 < 1 - BootScript.revealRamp + 1e-9 })
    }

    @Test func percentAndClockFormatting() {
        #expect(BootScript.percent(0) == "000%")
        #expect(BootScript.percent(0.5) == "050%")
        #expect(BootScript.percent(1.2) == "100%")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(BootScript.clock(Date(timeIntervalSince1970: 3_723), calendar: calendar) == "01:02:03")
    }
}
