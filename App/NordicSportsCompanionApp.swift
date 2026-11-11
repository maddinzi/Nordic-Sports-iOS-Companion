import SwiftUI
import UserNotifications

/// The first iOS Companion (roadmap step 4): watch activities stored by the shared Kotlin
/// core, linked to Strava and retitled there (App/). Two spikes still do real work: the watch
/// link (`spikes/watch-link/`, the watch connection for now) and background runs (`spikes/background/`).
/// Their log is under Settings > Data logs > Developer log.
@main
struct NordicSportsCompanionApp: App {
    /// Keeps every screen in portrait except a chart opened full screen (`OrientationLock`).
    @UIApplicationDelegateAdaptor(AppOrientationDelegate.self) private var orientationDelegate

    init() {
        // Before launch finishes, so a tap on a notification that started the app is delivered.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        // iOS requires the background task handlers before launch finishes (also when the database is too new:
        // a run then ends at once).
        BackgroundSpike.shared.register()
        // A database from a newer build: nothing may create Companion.shared (DatabaseGuard).
        guard !DatabaseGuard.tooNew else { return }
        WatchLinkSpike.shared.start()
        BackgroundSpike.shared.schedule(reason: "launch")
    }

    var body: some Scene {
        WindowGroup {
            if DatabaseGuard.tooNew {
                DatabaseTooNewScreen()
            } else {
                CompanionRootScene()
            }
        }
    }
}

/// The app itself; a view of its own so `Companion.shared` is created only when the database can be opened.
private struct CompanionRootScene: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var companion = Companion.shared
    /// Settings > App > Appearance: "" = system, "light", "dark".
    @AppStorage("themeChoice") private var themeChoice = ""

    var body: some View {
        RootView()
            // Holds the screen while delete-all-data or a Strava overwrite runs (Companion.busyText).
            .overlay { if let text = companion.busyText { BusyOverlayView(text: text) } }
            // Built again when the app language changes, so every text is in the new one.
            .id(companion.language)
            .environmentObject(companion)
            .preferredColorScheme(themeChoice == "light" ? .light : themeChoice == "dark" ? .dark : nil)
            // Garmin Connect Mobile returns the device selection through our URL scheme.
            .onOpenURL { url in WatchLinkSpike.shared.handle(url: url) }
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
