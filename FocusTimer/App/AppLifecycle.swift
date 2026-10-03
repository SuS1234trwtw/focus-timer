import UIKit

/// App-level lifecycle the SwiftUI scene phase doesn't cover: termination.
///
/// When the app is killed (swiped away in the app switcher) we END the island: nothing would drive its
/// timer any more and its buttons would act on a dead app. iOS only tells a *running* app it's being
/// terminated (a suspended one just dies), so on entering the background we ask for a short background
/// task: a quick swipe-away right after leaving the app still reaches `applicationWillTerminate`.
/// (An idle timer's island is already gone by then: going to the background refreshes it, and the
/// policy ends it.)
@MainActor
final class AppLifecycle: NSObject, UIApplicationDelegate {
    /// How long to stay awake after entering the background (iOS allows roughly 30 seconds).
    private static let backgroundGrace: Duration = .seconds(25)

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundTimer: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // A SwiftUI app is scene-based, so the delegate's own background/active callbacks aren't
        // called; the app-wide notifications still are (on the main queue we ask for).
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginBackgroundGrace() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endBackgroundGrace()
                AppModel.shared.appDidBecomeActive()
            }
        })
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Waits (bounded) for the island to be ended, since the process ends when this returns.
        AppModel.shared.appWillTerminate()
        endBackgroundGrace()
    }

    // MARK: Background grace period

    private func beginBackgroundGrace() {
        endBackgroundGrace()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "island.terminationWatch") { [weak self] in
            // iOS calls this on the main thread when time is up; the task must end right now.
            MainActor.assumeIsolated { self?.endBackgroundGrace() }
        }
        backgroundTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.backgroundGrace)
            guard !Task.isCancelled else { return }
            self?.endBackgroundGrace()
        }
    }

    private func endBackgroundGrace() {
        backgroundTimer?.cancel()
        backgroundTimer = nil
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
