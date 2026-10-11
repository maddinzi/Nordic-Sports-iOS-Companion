import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

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
                .tabItem { Label(L10n.get("status_title"), systemImage: "gearshape") }
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
    @State private var adding = false

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
            .sheet(isPresented: $adding) { AddActivitySheet().environmentObject(companion) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.get("add_activity_title"))
                }
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
                if item.diaryWritten {
                    Image(systemName: "book.closed").foregroundStyle(item.diaryOutdated ? Color.yellow : Color.green)
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
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let item: ActivityItem
    @State private var confirmingDelete = false
    @State private var editing = false

    /// The row as the list has it now, so a push shows its result here too.
    private var current: ActivityItem { companion.activities.first { $0.id == item.id } ?? item }

    var body: some View {
        Form {
            if current.reviewPending {
                Section(L10n.get("activity_detail_review_heading")) {
                    Text(String(format: L10n.get("activity_detail_review_body_waits"),
                                Format.date(current.reviewDeadlineEpochMillis / 1000)))
                        .font(.footnote)
                    Button(L10n.get("activity_detail_review_heading")) { editing = true }
                    Button(L10n.get("activity_detail_review_skip")) {
                        Task { await companion.skipReview(item.id) }
                    }
                    .disabled(companion.syncing)
                }
            }
            Section {
                LabeledContent(L10n.get("activity_detail_started_label"), value: Format.date(item.startEpochSec))
                LabeledContent(L10n.get("activity_detail_duration_label"), value: Format.duration(item.elapsedSec))
                if item.distanceM > 0 { LabeledContent(L10n.get("activity_detail_distance_label"), value: Format.distance(item.distanceM)) }
                if item.avgHeartRate > 0 { LabeledContent(L10n.get("activity_detail_avg_hr_label"), value: "\(item.avgHeartRate) bpm") }
                if item.maxHeartRate > 0 { LabeledContent(L10n.get("activity_detail_max_hr_label"), value: "\(item.maxHeartRate) bpm") }
                if item.totalAscentM > 0 { LabeledContent(L10n.get("activity_detail_ascent_label"), value: "\(Int(item.totalAscentM)) m") }
                if item.calories > 0 { LabeledContent(L10n.get("activity_detail_calories_label"), value: "\(item.calories) kcal") }
                if !item.locationName.isEmpty { LabeledContent(L10n.get("activity_detail_location_label"), value: item.locationName) }
            }
            Section(L10n.get("activity_detail_training_type_label")) {
                LabeledContent(L10n.get("activity_detail_sport_label"), value: Format.presetWord(item.preset))
                if !item.trainingType.isEmpty, item.trainingType != "unknown" {
                    LabeledContent("Intensity", value: Format.trainingTypeWord(item.trainingType))
                }
                if item.rpe > 0 { LabeledContent(L10n.get("activity_detail_rpe_label"), value: "\(item.rpe)") }
                if item.feeling > 0 { LabeledContent(L10n.get("activity_detail_feeling_label"), value: "\(item.feeling)") }
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
            if companion.diaryConnected {
                Section(L10n.get("activity_detail_diary_card_title")) {
                    if current.diaryWritten {
                        Label(companion.diaryName, systemImage: "book.closed")
                        if current.diaryOutdated {
                            Text(L10n.get(companion.diarySettings.autoUpdate
                                ? "activity_detail_diary_outdated_auto" : "activity_detail_diary_outdated_manual"))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !current.diaryWritten || current.diaryOutdated {
                        Button(L10n.get(current.diaryWritten ? "activity_detail_diary_update" : "activity_detail_diary_push")) {
                            Task { await companion.pushToDiary(item.id) }
                        }
                        .disabled(companion.syncing)
                    }
                    if companion.syncing { ProgressView() }
                }
            }
            if !item.watch.isEmpty {
                Section { LabeledContent(L10n.get("activity_detail_device_label"), value: item.watch) }
            }
            Section {
                NavigationLink(L10n.get("activity_change_log_title")) { ActivityLogScreen(activityId: item.id) }
                Button(L10n.get("activity_detail_delete_confirm_button"), role: .destructive) { confirmingDelete = true }
                    .disabled(companion.syncing)
            }
        }
        .confirmationDialog(
            L10n.get("activity_detail_delete_confirm_title"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L10n.get("activity_detail_delete_confirm_button"), role: .destructive) {
                Task {
                    if await companion.deleteActivity(item.id) { dismiss() }
                }
            }
        } message: {
            Text(L10n.get("activity_detail_delete_confirm_body") + (item.stravaActivityId.isEmpty
                ? "" : "\n\n" + L10n.get("activity_detail_delete_confirm_strava_note")))
        }
        .navigationTitle(current.title.isEmpty ? L10n.get("activity_detail_title_fallback") : current.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $editing) { EditActivitySheet(item: current).environmentObject(companion) }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared
    @State private var exportURL: URL?
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Watch") {
                    ForEach(watch.devices, id: \.uuid) { device in
                        LabeledContent(device.friendlyName ?? "?", value: watch.statuses[device.uuid] ?? "")
                    }
                    Button("Choose watch in Garmin Connect") { watch.chooseWatch() }
                    NavigationLink("Watch settings") { WatchSettingsScreen() }
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
                Section(L10n.get("status_diary_label")) {
                    if companion.diaryConnected {
                        Label(String(format: L10n.get("connect_diary_connected_to"), companion.diaryName), systemImage: "book.closed")
                        if !companion.activeDiarySource.isEmpty {
                            Text(companion.activeDiarySource).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text("New activities are written at each sync: when the app opens, or pull down on Activities.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !companion.diaryIssue.isEmpty {
                            Text(L10n.get("status_diary_issue_title")).foregroundStyle(.red)
                            Text(companion.diaryIssue).font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle("Write new activities automatically", isOn: Binding(
                            get: { companion.diarySettings.autoUpdate },
                            set: { companion.setDiaryAutoUpdate($0) }
                        ))
                        Toggle("Round durations up", isOn: Binding(
                            get: { companion.diarySettings.roundDurationUp },
                            set: { companion.setDiaryRoundDurationUp($0) }
                        ))
                        Toggle("Compact diary entries", isOn: Binding(
                            get: { companion.diarySettings.compactDiary },
                            set: { companion.setDiaryCompact($0) }
                        ))
                        Button("Write the last 7 days to the diary") { Task { await companion.writeDiary(days: 7) } }
                            .disabled(companion.syncing)
                    } else {
                        Text("Connect your TTB diary: OneDrive, Dropbox, Google Drive, or a workbook in the Files app.")
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(L10n.get("connect_diary_title")) { DiaryLocationsScreen() }
                    if companion.diaryBusy {
                        HStack { ProgressView(); Text(L10n.get("connect_diary_connecting")) }
                    }
                }
                .disabled(companion.diaryBusy)
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
                Section(L10n.get("status_data_logs_heading")) {
                    NavigationLink(L10n.get("status_view_diary_log")) {
                        LogScreen(title: L10n.get("diary_work_log_title"), kind: .diary)
                    }
                    NavigationLink(L10n.get("status_view_app_log")) {
                        LogScreen(title: L10n.get("app_log_title"), kind: .app)
                    }
                    NavigationLink("Watch transfer log") {
                        LogScreen(title: "Watch transfer log", kind: .transfer)
                    }
                }
                Section(L10n.get("status_my_data_heading")) {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label(exportURL.lastPathComponent, systemImage: "square.and.arrow.up") }
                    } else {
                        Button(L10n.get("status_download_my_data")) {
                            Task { exportURL = await companion.exportFile() }
                        }
                    }
                    NavigationLink(L10n.get("feedback_title")) { FeedbackScreen() }
                    Button(L10n.get("status_delete_my_data"), role: .destructive) { confirmingDeleteAll = true }
                        .disabled(companion.syncing)
                }
                .confirmationDialog(
                    L10n.get("status_delete_confirm_title"), isPresented: $confirmingDeleteAll, titleVisibility: .visible
                ) {
                    Button(L10n.get("status_delete_confirm_button"), role: .destructive) {
                        exportURL = nil
                        Task { await companion.deleteAllData() }
                    }
                } message: {
                    Text(L10n.get("status_delete_confirm_body"))
                }
                Section {
                    LabeledContent("Version", value: Format.appVersion)
                }
            }
            .navigationTitle(L10n.get("status_title"))
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
