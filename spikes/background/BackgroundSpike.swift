import BackgroundTasks
import Foundation
import UIKit

/// Background sync (from spike 2): registers an app refresh task (short, "about every 15
/// minutes at the earliest", iOS decides) and a processing task (longer, needs network), asks
/// for them again after every run and whenever the app goes to the background, and runs the
/// Companion's sync in each ([Companion.backgroundSync], automated sync mode only). Every
/// wake-up is logged with how long it has been since the previous one.
final class BackgroundSpike {
    static let shared = BackgroundSpike()

    /// Must match BGTaskSchedulerPermittedIdentifiers in project.yml.
    static let refreshId = "me.maddin.nordicsports.companion.refresh"
    static let processingId = "me.maddin.nordicsports.companion.processing"

    private let defaults = UserDefaults.standard
    private var log: (String) -> Void { WatchLinkSpike.shared.add }

    /// Called from the app's init: iOS requires the handlers before launch finishes.
    func register() {
        let refresh = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshId, using: nil) { task in
            self.run(task, kind: "refresh")
        }
        let processing = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.processingId, using: nil) { task in
            self.run(task, kind: "processing")
        }
        log("bg: handlers registered (refresh \(refresh), processing \(processing)), Background App Refresh: \(Self.refreshStatus())")
    }

    /// Asks iOS for the next runs; iOS decides when (or whether) they happen.
    func schedule(reason: String) {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshId)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        let processing = BGProcessingTaskRequest(identifier: Self.processingId)
        processing.requiresNetworkConnectivity = true
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(refresh)
            try BGTaskScheduler.shared.submit(processing)
            log("bg: next runs requested (\(reason))")
        } catch {
            log("bg: request failed (\(reason)): \(error.localizedDescription)")
        }
    }

    private func run(_ task: BGTask, kind: String) {
        let key = "spike.bg.last.\(kind)"
        let now = Date()
        let since = (defaults.object(forKey: key) as? Date).map { Self.duration(now.timeIntervalSince($0)) } ?? "first run"
        defaults.set(now, forKey: key)
        let state = DispatchQueue.main.sync { UIApplication.shared.applicationState }
        log("bg: \(kind) task ran (\(since) since the previous one, app \(state == .background ? "in background" : "not in background"))")
        schedule(reason: "after \(kind)")
        // setTaskCompleted exactly once: when the sync ends, or when iOS ends the time.
        let finish = Finish(task)
        let work = Task { @MainActor in
            let outcome = await Companion.shared.backgroundSync()
            self.log("bg: \(kind) sync: \(outcome)")
            finish.complete(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            self.log("bg: \(kind) task expired before it finished")
            finish.complete(success: false)
        }
    }

    /// Completes a background task once, whichever of sync end and expiry comes first.
    private final class Finish {
        private let task: BGTask
        private var done = false
        private let lock = NSLock()

        init(_ task: BGTask) { self.task = task }

        func complete(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            task.setTaskCompleted(success: success)
        }
    }

    /// Background App Refresh as iOS reports it, plus Low Power Mode (which makes it
    /// "restricted"); logged at every app open (build 15 showed "restricted").
    static var refreshStatusLine: String {
        "Background App Refresh: \(refreshStatus()), Low Power Mode \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")"
    }

    private static func refreshStatus() -> String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "on"
        case .denied: return "off (Settings > General > Background App Refresh)"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes < 120 ? "\(minutes) min" : String(format: "%.1f h", seconds / 3600)
    }
}
