import SwiftUI

/// For now the app is the watch link spike (roadmap step 1, `spikes/watch-link/`): it
/// reaches a real iPhone through the same TestFlight chain the Companion will use. The
/// shared Kotlin module comes after the spike's go/no-go.
@main
struct NordicSportsCompanionApp: App {
    init() {
        WatchLinkSpike.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            WatchLinkSpikeView()
                // Garmin Connect Mobile returns the device selection through our URL scheme.
                .onOpenURL { url in WatchLinkSpike.shared.handle(url: url) }
        }
    }
}
