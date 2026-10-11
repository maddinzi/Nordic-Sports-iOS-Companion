import SwiftUI

/// For now the app is the set of feasibility spikes (roadmap step 1): the watch link
/// (`spikes/watch-link/`), background runs (`spikes/background/`) and the diary workbook from
/// the Files app (`spikes/diary-file/`). It reaches a real iPhone through the same TestFlight
/// chain the Companion will use and already links the shared Kotlin module.
@main
struct NordicSportsCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        WatchLinkSpike.shared.start()
        // iOS requires the background task handlers before launch finishes.
        BackgroundSpike.shared.register()
        BackgroundSpike.shared.schedule(reason: "launch")
    }

    var body: some Scene {
        WindowGroup {
            WatchLinkSpikeView()
                // Garmin Connect Mobile returns the device selection through our URL scheme.
                .onOpenURL { url in WatchLinkSpike.shared.handle(url: url) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                WatchLinkSpike.shared.add("app in foreground")
            case .background:
                WatchLinkSpike.shared.add("app in background")
                BackgroundSpike.shared.schedule(reason: "app went to background")
            default:
                break
            }
        }
    }
}
