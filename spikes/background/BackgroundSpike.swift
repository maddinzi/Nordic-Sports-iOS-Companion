import BackgroundTasks
import Foundation
import UIKit

/// Spike 2 (roadmap step 1, throw-away): what does iOS really give the Companion in the
/// background? Registers an app refresh task (short, "about every 15 minutes at the
/// earliest") and a processing task (longer, needs network), asks for them again after every
/// run and whenever the app goes to the background, and logs each wake-up into the spike log
/// with how long it has been since the previous one. Together with spike 1's arrivals the log
/// shows whether sync can run in the background or only when the app is opened.
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
        task.expirationHandler = { self.log("bg: \(kind) task expired before it finished") }
        schedule(reason: "after \(kind)")
        // A real sync would run here (webhook events, diary write); the spike only measures.
        task.setTaskCompleted(success: true)
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
