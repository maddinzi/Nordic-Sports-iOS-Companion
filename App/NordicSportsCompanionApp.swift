import SwiftUI
import UserNotifications

/// The first iOS Companion (roadmap step 4): watch activities stored by the shared Kotlin
/// core, linked to Strava and retitled there (App/). Two spikes still do real work: the watch
/// link (`spikes/watch-link/`, the watch connection for now) and background runs (`spikes/background/`).
/// Their log is under Settings > Data logs > Developer log.
@main
struct NordicSportsCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var companion = Companion.shared

    init() {
        // Before launch finishes, so a tap on a notification that started the app is delivered.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        WatchLinkSpike.shared.start()
        // iOS requires the background task handlers before launch finishes.
        BackgroundSpike.shared.register()
        BackgroundSpike.shared.schedule(reason: "launch")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Built again when the app language changes, so every text is in the new one.
                .id(companion.language)
                .environmentObject(companion)
                // Garmin Connect Mobile returns the device selection through our URL scheme.
                .onOpenURL { url in WatchLinkSpike.shared.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                WatchLinkSpike.shared.add("app in foreground, \(BackgroundSpike.refreshStatusLine)")
                // Like Android's onResume: Strava events and title updates on every open.
                Task { await companion.syncOnOpen() }
            case .background:
                WatchLinkSpike.shared.add("app in background")
                WatchLinkSpike.shared.flushLog()
                BackgroundSpike.shared.schedule(reason: "app went to background")
            default:
                break
            }
        }
    }
}
