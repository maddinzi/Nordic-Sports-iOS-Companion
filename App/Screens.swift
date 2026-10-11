import NordicSportsShared
import SwiftUI

/// The first iOS Companion (roadmap step 4): activities from the watch, linked to Strava and
/// retitled there, plus the spike screen for diagnostics. The Android texts are used where a
/// matching one exists; the rest is English until the screens settle.
struct RootView: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        TabView {
            ActivitiesScreen()
                .tabItem { Label("Activities", systemImage: "list.bullet") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
            WatchLinkSpikeView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .alert(
            companion.message ?? "",
            isPresented: Binding(get: { companion.message != nil }, set: { if !$0 { companion.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }
}

// MARK: - Activities

struct ActivitiesScreen: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        NavigationStack {
            Group {
                if companion.activities.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.get("activity_list_empty_no_activities"), systemImage: "applewatch")
                    } description: {
                        Text(L10n.get("activity_list_empty_hint"))
                    }
                } else {
                    List(companion.activities, id: \.id) { item in
                        NavigationLink {
                            ActivityDetailScreen(item: item)
                        } label: {
                            ActivityRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Activities")
            .refreshable { await companion.sync() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if companion.syncing {
                        ProgressView()
                    } else {
                        Button {
                            Task { await companion.sync() }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel(L10n.get("activity_list_sync_now_content_description"))
                    }
                }
            }
        }
    }
}

struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title.isEmpty ? L10n.get("activity_detail_title_fallback") : item.title)
                    .font(.headline)
                Spacer()
                if !item.stravaActivityId.isEmpty {
                    Image(systemName: "link").foregroundStyle(.orange)
                }
                if item.reviewPending {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.blue)
                }
                if item.conflict || item.stravaConflict {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }
            Text(Format.summary(item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ActivityDetailScreen: View {
    let item: ActivityItem

    var body: some View {
        Form {
            Section {
                LabeledContent("Start", value: Format.date(item.startEpochSec))
                LabeledContent("Duration", value: Format.duration(item.elapsedSec))
                if item.distanceM > 0 { LabeledContent("Distance", value: Format.distance(item.distanceM)) }
                if item.avgHeartRate > 0 { LabeledContent("Avg. heart rate", value: "\(item.avgHeartRate) bpm") }
                if item.maxHeartRate > 0 { LabeledContent("Max. heart rate", value: "\(item.maxHeartRate) bpm") }
                if item.totalAscentM > 0 { LabeledContent("Ascent", value: "\(Int(item.totalAscentM)) m") }
                if item.calories > 0 { LabeledContent("Calories", value: "\(item.calories) kcal") }
                if !item.locationName.isEmpty { LabeledContent("Place", value: item.locationName) }
            }
            Section(L10n.get("activity_detail_training_type_label")) {
                LabeledContent("Type", value: Format.presetWord(item.preset))
                if !item.trainingType.isEmpty, item.trainingType != "unknown" {
                    LabeledContent("Intensity", value: Format.trainingTypeWord(item.trainingType))
                }
                if item.rpe > 0 { LabeledContent("RPE", value: "\(item.rpe)") }
                if item.feeling > 0 { LabeledContent("Feeling", value: "\(item.feeling)") }
            }
            let zones = item.hrZonePercents.map { $0.floatValue }
            if zones.contains(where: { $0 > 0 }) {
                Section("Heart rate zones") {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, percent in
                        HStack {
                            Text("Zone \(index + 1)").frame(width: 70, alignment: .leading)
                            ProgressView(value: Double(percent), total: 100)
                            Text("\(Int(percent.rounded())) %").frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
            Section(L10n.get("activity_detail_synced_to")) {
                if item.stravaActivityId.isEmpty {
                    Text("Not linked to Strava yet")
                } else {
                    Link(destination: URL(string: "https://www.strava.com/activities/\(item.stravaActivityId)")!) {
                        LabeledContent("Strava", value: item.stravaTitle.isEmpty ? item.stravaActivityId : item.stravaTitle)
                    }
                    if item.stravaConflict {
                        Text("Changed on Strava since the Companion last saw it; the title was left alone.")
                            .foregroundStyle(.red)
                    }
                }
                if item.conflict {
                    Text("Another activity starts at almost the same time; check both.").foregroundStyle(.red)
                }
            }
            if !item.watch.isEmpty {
                Section("Source") { LabeledContent("Watch", value: item.watch) }
            }
        }
        .navigationTitle(item.title.isEmpty ? L10n.get("activity_detail_title_fallback") : item.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Watch") {
                    ForEach(watch.devices, id: \.uuid) { device in
                        LabeledContent(device.friendlyName ?? "?", value: watch.statuses[device.uuid] ?? "")
                    }
                    Button("Choose watch in Garmin Connect") { watch.chooseWatch() }
                }
                Section("Strava") {
                    if !companion.stravaConfigured {
                        Text("This build has no Strava app settings.").foregroundStyle(.secondary)
                    } else if companion.stravaConnected {
                        Label(L10n.get("status_strava_connected_status"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(L10n.get("status_backfill_sync_now")) { Task { await companion.sync() } }
                            .disabled(companion.syncing)
                        Button("Pull the last 7 days from Strava") { Task { await companion.backfill(days: 7) } }
                            .disabled(companion.syncing)
                        Button("Disconnect Strava", role: .destructive) { Task { await companion.disconnectStrava() } }
                    } else {
                        Button("Connect Strava") { companion.connectStrava() }
                    }
                }
                if companion.syncing || !companion.syncLines.isEmpty || companion.lastSync != nil {
                    Section("Last sync") {
                        if companion.syncing { ProgressView() }
                        if let last = companion.lastSync {
                            Text(last.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                        if companion.syncLines.isEmpty, !companion.syncing {
                            Text("Nothing to do.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(companion.syncLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote)
                        }
                    }
                }
                Section {
                    LabeledContent("Version", value: Format.appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Formatting

enum Format {
    static func date(_ epochSec: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(epochSec)).formatted(date: .abbreviated, time: .shortened)
    }

    static func duration(_ seconds: Int32) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%ld:%02ld:%02ld", s / 3600, s % 3600 / 60, s % 60)
            : String(format: "%ld:%02ld", s / 60, s % 60)
    }

    static func distance(_ meters: Float) -> String {
        Measurement(value: Double(meters) / 1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
    }

    static func summary(_ item: ActivityItem) -> String {
        var parts = [date(item.startEpochSec), duration(item.elapsedSec)]
        if item.distanceM > 0 { parts.append(distance(item.distanceM)) }
        return parts.joined(separator: " · ")
    }

    /// The watch's own word for a preset, in the app language (watch_labels.xml).
    static func presetWord(_ preset: String) -> String {
        let name = "watch_preset_\(preset)"
        let word = L10n.get(name)
        return word == name ? preset : word
    }

    static func trainingTypeWord(_ trainingType: String) -> String {
        let name = "watch_training_type_\(trainingType)"
        let word = L10n.get(name)
        return word == name ? trainingType : word
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
}
