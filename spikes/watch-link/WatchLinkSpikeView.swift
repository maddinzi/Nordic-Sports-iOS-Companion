import SwiftUI

/// The spike's only screen: the selected watches, three actions and the log (newest first).
struct WatchLinkSpikeView: View {
    @ObservedObject var spike = WatchLinkSpike.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Watches") {
                    if spike.devices.isEmpty {
                        Text("No watch selected yet.").foregroundStyle(.secondary)
                    }
                    ForEach(spike.devices, id: \.uuid) { device in
                        HStack {
                            Text(device.friendlyName ?? "?")
                            Spacer()
                            Text(spike.statuses[device.uuid] ?? "-").foregroundStyle(.secondary)
                        }
                    }
                    Button("Choose watch in Garmin Connect") { spike.chooseWatch() }
                    Button("Check watch app versions") { spike.checkApps() }
                        .disabled(spike.devices.isEmpty)
                    Button("Ask the watch for its settings") { spike.requestSettings() }
                        .disabled(spike.devices.isEmpty)
                }
                Section("Log (newest first)") {
                    ForEach(Array(spike.log.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Watch link spike")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(version).font(.caption).foregroundStyle(.secondary)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: spike.log.joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) { spike.clearLog() } label: { Image(systemName: "trash") }
                }
            }
        }
    }
}
