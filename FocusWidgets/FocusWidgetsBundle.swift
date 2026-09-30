import SwiftUI
import WidgetKit

@main
struct FocusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusStatusWidget()
        FocusLiveActivity()
    }
}
