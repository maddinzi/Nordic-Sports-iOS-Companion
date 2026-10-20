import SwiftUI

/// The developer log (watch link, diary, background runs; newest first), kept for bug reports from
/// TestFlight: share it or clear it. Under Settings > Data logs, not a tab of its own.
struct DeveloperLogScreen: View {
    @ObservedObject var spike = WatchLinkSpike.shared

    var body: some View {
        List {
            ForEach(Array(spike.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced())
            }
        }
        .navigationTitle(L10n.get("ios_developer_log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: spike.log.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
                Button(role: .destructive) { spike.clearLog() } label: { Image(systemName: "trash") }
            }
        }
    }
}
