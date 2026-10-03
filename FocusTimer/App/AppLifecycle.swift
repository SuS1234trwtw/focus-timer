import BackgroundTasks
import UIKit
import UserNotifications

/// App-level lifecycle the SwiftUI scene phase doesn't cover: termination.
///
/// When the app is killed (swiped away in the app switcher) we END the island: nothing would drive its
/// timer any more and its buttons would act on a dead app. iOS only tells a *running* app it's being
/// terminated (a suspended one just dies), so on entering the background we ask for a short background
/// task: a quick swipe-away right after leaving the app still reaches `applicationWillTerminate`.
/// (An idle timer's island is already gone by then: going to the background refreshes it, and the
/// policy ends it.)
///
/// It also runs the background update check (BGAppRefreshTask) and is the notification-center delegate,
/// so tapping an update notification opens Settings → updates.
@MainActor
final class AppLifecycle: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated static let updateTaskID = "com.focustimer.app.updatecheck"

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
        UNUserNotificationCenter.current().delegate = self
        Self.registerUpdateTask()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginBackgroundGrace() }
            Self.scheduleUpdateTask()
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

    // MARK: Notifications

    /// Foreground: show update alerts, but keep the timer's own end notification silent as before
    /// (the app plays the chime itself while open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.userInfo["route"] as? String == UpdateChecker.notificationRoute ? [.banner, .sound] : []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.content.userInfo["route"] as? String == UpdateChecker.notificationRoute else { return }
        await MainActor.run { UpdateChecker.shared.openUpdatesRequested = true }
    }

    // MARK: Background update check

    /// Must run before `didFinishLaunching` returns. Closures made here are nonisolated, so iOS may call
    /// them on its background queue without tripping a main-actor check.
    nonisolated private static func registerUpdateTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: updateTaskID, using: nil) { task in
            handleUpdateTask(task)
        }
    }

    /// Asks iOS for a refresh in about four hours (iOS decides when, if ever; best effort).
    nonisolated static func scheduleUpdateTask() {
        let request = BGAppRefreshTaskRequest(identifier: updateTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleUpdateTask(_ task: BGTask) {
        scheduleUpdateTask()
        // BGTask isn't Sendable; it's only touched here and once by the work task, which calls
        // setTaskCompleted exactly once (expiry cancels the work, which then completes with false).
        nonisolated(unsafe) let task = task
        let work = Task.detached {
            await UpdateChecker.backgroundCheck()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
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
