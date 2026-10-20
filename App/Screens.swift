import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

/// The first iOS Companion (roadmap step 4): activities from the watch, linked to Strava and
/// retitled there, plus the spike screen for diagnostics. The Android texts are used where a
/// matching one exists; the rest is English until the screens settle.
struct RootView: View {
    @EnvironmentObject var companion: Companion
    /// The first-start guide is shown once; an app that is already set up skips it.
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            ActivitiesScreen()
                .tabItem { Label("Activities", systemImage: "list.bullet") }
            SettingsScreen()
                .tabItem { Label(L10n.get("status_title"), systemImage: "gearshape") }
            WatchLinkSpikeView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingScreen { showOnboarding = false }
                .environmentObject(companion)
        }
        .task {
            // Decided once at start, so connecting Strava inside the guide does not close it.
            if !onboardingDone && !companion.stravaConnected && !companion.diaryConnected && companion.activities.isEmpty {
                showOnboarding = true
            }
            onboardingDone = true
        }
        .alert(
            companion.message ?? "",
            isPresented: Binding(get: { companion.message != nil }, set: { if !$0 { companion.message = nil } })
        ) {
            Button(L10n.get("common_ok"), role: .cancel) {}
        }
        // A second alert needs its own view: the Strava deletion and withdrawal confirmations.
        .background {
            Color.clear.alert(
                companion.notice?.title ?? "",
                isPresented: Binding(get: { companion.notice != nil }, set: { shown in
                    if !shown {
                        companion.notice?.onDismiss?()
                        companion.notice = nil
                    }
                })
            ) {
                Button(L10n.get("common_ok"), role: .cancel) {}
            } message: {
                Text(companion.notice?.text ?? "")
            }
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
                if companion.activities.isEmpty && companion.liveActivities.isEmpty && companion.crashReports.isEmpty {
                    ContentUnavailableView {
                        Label(companion.nickname.isEmpty
                              ? L10n.get("activity_list_empty_no_activities")
                              : String(format: L10n.get("activity_list_empty_no_activities_named"), companion.nickname),
                              systemImage: "applewatch")
                    } description: {
                        Text(L10n.get("activity_list_empty_hint"))
                    }
                } else {
                    List {
                        if !companion.liveActivities.isEmpty || !companion.crashReports.isEmpty {
                            Section {
                                ForEach(companion.liveActivities, id: \.deviceId) { live in
                                    WatchLiveCard(live: live)
                                }
                                if let report = companion.crashReports.first {
                                    WatchCrashCard(report: report)
                                }
                            }
                        }
                        // As Android: activities still to review on top, oldest first (the order the
                        // diary fills a day's slots in), then the rest under "Done".
                        let now = Int64(Date().timeIntervalSince1970 * 1000)
                        let open = companion.activities
                            .filter { $0.reviewPending && now < $0.reviewDeadlineEpochMillis }
                            .sorted { $0.startEpochSec < $1.startEpochSec }
                        let openIds = Set(open.map { $0.id })
                        let rest = companion.activities.filter { !openIds.contains($0.id) }
                        if !open.isEmpty {
                            Section(L10n.get("activity_list_section_open")) {
                                ForEach(open, id: \.id) { item in
                                    NavigationLink {
                                        ActivityDetailScreen(item: item)
                                    } label: {
                                        ActivityRow(item: item)
                                    }
                                }
                            }
                        }
                        Section(open.isEmpty ? "" : L10n.get("activity_list_section_done")) {
                            ForEach(rest, id: \.id) { item in
                                NavigationLink {
                                    ActivityDetailScreen(item: item)
                                } label: {
                                    ActivityRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Activities")
            .onAppear { companion.refreshWatchCards() }
            .refreshable {
                companion.refreshWatchCards()
                await companion.sync()
            }
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

/// A recording on a watch (its `activityStart`), as Android's card: which watch, activity
/// and training type, since when and how long, and the start position.
struct WatchLiveCard: View {
    let live: LiveActivityView

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: L10n.get(live.discarded ? "watch_live_discarded_title" : "watch_live_title"), live.watchName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(live.title).font(.headline)
                let started = Date(timeIntervalSince1970: TimeInterval(live.startEpochSec)).formatted(date: .omitted, time: .shortened)
                if live.discarded {
                    Text(String(format: L10n.get("watch_live_discarded_detail"), started)).font(.subheadline)
                } else {
                    let running = max(0, Int(context.date.timeIntervalSince1970) - Int(live.startEpochSec))
                    Text(String(format: L10n.get("watch_live_since"), started, Format.duration(Int32(running)))).font(.subheadline)
                }
                if live.hasPosition {
                    Text(String(format: "%.4f, %.4f", live.lat, live.lon)).font(.footnote).foregroundStyle(.secondary)
                }
                if !live.discarded {
                    Text(L10n.get("watch_live_hint")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(live.discarded ? Color.gray.opacity(0.15) : Color.accentColor.opacity(0.15))
    }
}

/// "Your watch app closed unexpectedly", with Dismiss and Review; Review shows exactly what
/// would be sent and sends only on Send (asked each time).
struct WatchCrashCard: View {
    @EnvironmentObject var companion: Companion
    let report: CrashReportView
    @State private var reviewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.get("watch_crash_title")).font(.headline)
            let at = Date(timeIntervalSince1970: TimeInterval(report.lastSignEpochSec)).formatted(date: .omitted, time: .shortened)
            Text(report.rebooted
                 ? String(format: L10n.get("watch_crash_detail_rebooted"), report.watchName, at)
                 : String(format: L10n.get("watch_crash_detail"), report.watchName, at, report.screen))
                .font(.footnote)
            HStack {
                Spacer()
                Button(L10n.get("watch_crash_dismiss")) { companion.dismissCrashReport(report.id) }
                    .buttonStyle(.borderless)
                Button(L10n.get("watch_crash_review")) { reviewing = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color.red.opacity(0.12))
        .sheet(isPresented: $reviewing) {
            WatchCrashSheet(report: report).environmentObject(companion)
        }
    }
}

struct WatchCrashSheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let report: CrashReportView
    @State private var note = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(L10n.get("watch_crash_dialog_body")).font(.footnote) }
                Section {
                    Text(report.reportText).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
                Section(L10n.get("watch_crash_note")) {
                    TextEditor(text: $note).frame(minHeight: 80)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(L10n.get("watch_crash_dialog_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.get("watch_crash_not_now")) { dismiss() }.disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button(L10n.get("feedback_send")) {
                            Task {
                                sending = true
                                error = nil
                                switch await companion.sendCrashReport(report.id, note: String(note.prefix(1000))) {
                                case "sent": dismiss()
                                case "tooMany": error = L10n.get("feedback_error_too_many")
                                default: error = L10n.get("feedback_error_failed")
                                }
                                sending = false
                            }
                        }
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
    @State private var stravaRemovedAt: Int64 = 0

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
                if current.stravaActivityId.isEmpty {
                    Text("Not linked to Strava yet")
                    if stravaRemovedAt > 0 {
                        Label(String(format: L10n.get("activity_detail_strava_removed_note"), Format.date(stravaRemovedAt / 1000)),
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !current.stravaTitle.isEmpty { LabeledContent("Strava", value: current.stravaTitle) }
                    ViewOnStravaLink(stravaActivityId: current.stravaActivityId)
                    PoweredByStrava()
                    if current.stravaConflict {
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
        .task(id: current.stravaActivityId) { stravaRemovedAt = await companion.stravaDataRemovedAt(item.id) }
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared
    @State private var exportURL: URL?
    @State private var confirmingDeleteAll = false
    @State private var confirmingStravaDisconnect = false
    @State private var nicknameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.get("settings_tile_watch")) {
                    ForEach(watch.devices, id: \.uuid) { device in
                        LabeledContent(device.friendlyName ?? "?", value: watch.statuses[device.uuid] ?? "")
                    }
                    Button("Choose watch in Garmin Connect") { watch.chooseWatch() }
                    NavigationLink("Watch settings") { WatchSettingsScreen() }
                }
                Section {
                    TextField(L10n.get("nickname_label"), text: $nicknameDraft)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { companion.setNickname(nicknameDraft); nicknameDraft = companion.nickname }
                    Text(L10n.get("nickname_body")).font(.footnote).foregroundStyle(.secondary)
                    Toggle(L10n.get("settings_review_new_activities"), isOn: Binding(
                        get: { companion.reviewNewActivities },
                        set: { companion.setReviewNewActivities($0) }
                    ))
                    Text(L10n.get(companion.reviewNewActivities
                                  ? "interaction_option_interactive_description"
                                  : "interaction_option_passive_description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(L10n.get("status_place_names_switch"), isOn: Binding(
                        get: { companion.placeNamesEnabled },
                        set: { companion.setPlaceNamesEnabled($0) }
                    ))
                    Text(L10n.get("status_place_names_body")).font(.footnote).foregroundStyle(.secondary)
                    Picker(L10n.get("sync_mode_section_title"), selection: Binding(
                        get: { companion.syncAutomatically },
                        set: { companion.setSyncAutomatically($0) }
                    )) {
                        Text(L10n.get("sync_mode_option_automated")).tag(true)
                        Text(L10n.get("sync_mode_option_manual")).tag(false)
                    }
                    Text(L10n.get(companion.syncAutomatically
                                  ? "sync_mode_option_automated_description"
                                  : "sync_mode_option_manual_description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(L10n.get("settings_group_app"))
                }
                .onAppear { nicknameDraft = companion.nickname }
                .onDisappear { if nicknameDraft != companion.nickname { companion.setNickname(nicknameDraft) } }
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
                        Button("Disconnect Strava", role: .destructive) { confirmingStravaDisconnect = true }
                            .confirmationDialog(
                                String(format: L10n.get("status_disconnect_confirm_title"), "Strava"),
                                isPresented: $confirmingStravaDisconnect,
                                titleVisibility: .visible
                            ) {
                                Button(L10n.get("status_disconnect_button"), role: .destructive) {
                                    Task { await companion.disconnectStrava() }
                                }
                            } message: {
                                // Strava API Policy 7.4: the disconnect deletes the Strava data held.
                                Text(L10n.get("status_disconnect_confirm_body_strava"))
                            }
                    } else {
                        StravaConnectButton { companion.connectStrava() }
                    }
                    if companion.stravaConfigured { PoweredByStrava() }
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
                        Toggle(L10n.get("status_ttb_round_switch"), isOn: Binding(
                            get: { companion.diarySettings.roundDurationUp },
                            set: { companion.setDiaryRoundDurationUp($0) }
                        ))
                        Toggle("Compact diary entries", isOn: Binding(
                            get: { companion.diarySettings.compactDiary },
                            set: { companion.setDiaryCompact($0) }
                        ))
                        Button("Write the last 7 days to the diary") { Task { await companion.writeDiary(days: 7) } }
                            .disabled(companion.syncing)
                        // TEMPORARY, as on Android: remove a few versions after 0.9.93.
                        Text(L10n.get("settings_intro_compact_diary")).font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.get("status_compact_diary_heading")) { Task { await companion.compactDiary(days: 7) } }
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
                    NavigationLink(L10n.get("status_view_strava_api_usage")) { StravaApiUsageScreen() }
                    NavigationLink(L10n.get("status_view_recording_boosts")) { RecordingBoostScreen() }
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
                    NavigationLink(L10n.get("status_about_button")) { AboutScreen() }
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

// MARK: - Strava branding (Strava's guidelines; Companion design/strava-brand-compliance.md)

/// Strava's own "Connect with Strava" button, unmodified, 48 pt high, wherever the sign-in
/// starts (also to reconnect).
struct StravaConnectButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("StravaConnectButton").resizable().scaledToFit().frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.get("strava_connect_button_description")))
    }
}

/// Strava's "Powered by Strava" logo (orange, horizontal), about 18 pt high.
struct PoweredByStrava: View {
    var body: some View {
        Image("StravaPoweredBy").resizable().scaledToFit().frame(height: 18)
            .accessibilityLabel(Text(L10n.get("strava_powered_by_description")))
    }
}

/// "View on Strava": these exact words in every language, bold, underlined, Strava orange
/// (#FC5200). Opens the Strava app when installed (universal link), else Safari.
struct ViewOnStravaLink: View {
    let stravaActivityId: String

    var body: some View {
        if let url = URL(string: "https://www.strava.com/activities/\(stravaActivityId)") {
            Link(destination: url) {
                Text(L10n.get("strava_view_on_strava"))
                    .bold()
                    .underline()
                    .foregroundStyle(Color(red: 252 / 255, green: 82 / 255, blue: 0))
            }
        }
    }
}
