import SwiftUI

/// The first iOS Companion (roadmap step 4): watch activities stored by the shared Kotlin
/// core, linked to Strava and retitled there (App/). The feasibility spikes stay reachable
/// on the Diagnostics tab: the watch link (`spikes/watch-link/`, which also carries the real
/// watch connection for now), background runs (`spikes/background/`) and the diary workbook
/// from the Files app (`spikes/diary-file/`).
@main
struct NordicSportsCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var companion = Companion.shared

    init() {
        WatchLinkSpike.shared.start()
        // iOS requires the background task handlers before launch finishes.
        BackgroundSpike.shared.register()
        BackgroundSpike.shared.schedule(reason: "launch")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
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
                BackgroundSpike.shared.schedule(reason: "app went to background")
            default:
                break
            }
        }
    }
}
