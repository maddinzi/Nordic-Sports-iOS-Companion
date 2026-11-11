import SwiftUI

/// "Record on my watch" (Android `WatchRecordStartScreen`), for athletes who know their Garmin: first the settings
/// worth a quick check before a watch recording (Sensor Record, Instant Mode, Auto Lap, Auto Pause), changeable here
/// as on the watch settings page, then the start in five short steps (the phone cannot start the watch app).
struct WatchRecordStartView: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    private let tone = CardTone.blue
    /// In this order, only those the watch reports.
    private static let keySettings = ["RecordingBoostEnabled", "InstantMode", "AutoLapDistance", "AutoPause"]

    /// The most recently reported real watch; the demo watch (negative id) only when no real one is known.
    private var watch: WatchSettingsView? {
        let real = companion.watchSettings.filter { $0.deviceId >= 0 }
        return (real.isEmpty ? companion.watchSettings : real).max { $0.reportedAtEpochSec < $1.reportedAtEpochSec }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let watch {
                        let items = watch.groups.flatMap { $0.items }
                        let instantOn = items.contains { $0.key == "InstantMode" && $0.value != 0 }
                        ForEach(Self.keySettings.compactMap { key in items.first { $0.key == key } }, id: \.key) { item in
                            WatchSettingRow(deviceId: watch.deviceId, item: item, instantModeOn: instantOn)
                        }
                    } else {
                        Text(L10n.get("watch_settings_none")).foregroundStyle(.secondary)
                    }
                    NavigationLink(L10n.get("watch_start_settings_all")) { WatchSettingsScreen() }
                } header: {
                    Text(L10n.get("watch_start_settings_title"))
                } footer: {
                    if let watch { Text(String(format: L10n.get("watch_start_settings_hint"), watch.watchName)) }
                }
                Section(L10n.get("watch_start_steps_title")) {
                    ForEach(1...5, id: \.self) { n in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(n)").font(.subheadline.bold()).foregroundStyle(tone.container)
                                .frame(width: 26, height: 26).background(tone.title, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.get("watch_start_step\(n)_title")).font(.subheadline.weight(.semibold))
                                Text(L10n.get("watch_start_step\(n)_body")).font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .listRowBackground(tone.container)
            }
            .homeTitle(L10n.get("add_choice_watch_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.get("common_cancel"))
                }
            }
            .onAppear { companion.refreshWatchSettings() }
        }
    }
}
