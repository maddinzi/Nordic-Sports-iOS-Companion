import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

// Roadmap step 5.3, 5.4 and 5.6 on iOS: the watch app's settings, adding an activity by
// hand, the transparency logs and feedback. Logic and texts come from the shared core
// (CompanionCore); these views only show and forward.

// MARK: - Watch settings

struct WatchSettingsScreen: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Form {
            Section { Text(L10n.get("settings_intro_watch")).font(.footnote).foregroundStyle(.secondary) }
            if companion.watchSettings.isEmpty {
                Text(L10n.get("watch_settings_none")).foregroundStyle(.secondary)
            }
            ForEach(companion.watchSettings, id: \.deviceId) { watch in
                Section {
                    Text(String(format: L10n.get("watch_settings_as_of"), Format.date(watch.reportedAtEpochSec)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if watch.pendingCount > 0 {
                        Text(L10n.plural("watch_settings_waiting", Int(watch.pendingCount)))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        // Changes wait and the watch has been silent for hours: the link is probably stuck.
                        if Date().timeIntervalSince1970 - TimeInterval(watch.reportedAtEpochSec) > 3600 {
                            Text(L10n.get("watch_settings_stale_hint"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Button(L10n.get("watch_settings_refresh")) { companion.askWatchAgain(deviceId: watch.deviceId) }
                    if let sync = watch.sync {
                        WatchSyncRow(sync: sync)
                    }
                    if !watch.dataFieldGroups.isEmpty {
                        NavigationLink(L10n.get("watch_data_fields_title")) { WatchDataFieldsScreen(deviceId: watch.deviceId) }
                    }
                    if !watch.intervalSlots.isEmpty {
                        NavigationLink(L10n.get("watch_interval_menu")) { WatchPlansScreen(deviceId: watch.deviceId, routines: false) }
                    }
                    if !watch.routineSlots.isEmpty {
                        NavigationLink(L10n.get("watch_strength_routines")) { WatchPlansScreen(deviceId: watch.deviceId, routines: true) }
                    }
                } header: {
                    Text(watch.watchName)
                }
                if let hr = watch.hrStrap {
                    Section(hr.title) {
                        Text(hr.status).foregroundStyle(hr.notFound ? Color.red : Color.primary)
                        Text(hr.checked).font(.footnote).foregroundStyle(.secondary)
                        ForEach(hr.lines, id: \.label) { line in
                            LabeledContent(line.label, value: line.value)
                        }
                    }
                }
                ForEach(watch.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items, id: \.key) { item in
                            WatchSettingRow(deviceId: watch.deviceId, item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.get("settings_tile_watch"))
        .onAppear { companion.refreshWatchSettings() }
    }
}

/// The last settings message to or from the watch (Android's sync strip): direction, what
/// happened and when, and what it means.
private struct WatchSyncRow: View {
    let sync: WatchSyncView

    var body: some View {
        let color: Color = sync.kind == "failed" ? .red : (sync.kind == "received" ? .green : .accentColor)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Image(systemName: sync.kind == "failed" ? "exclamationmark.triangle"
                      : (sync.toWatch ? "arrow.right" : "arrow.left"))
                    .foregroundStyle(color)
                Image(systemName: "applewatch")
                Text(sync.direction).font(.footnote).foregroundStyle(.secondary)
            }
            let at = Date(timeIntervalSince1970: TimeInterval(sync.atEpochMillis) / 1000).formatted(date: .omitted, time: .shortened)
            Text("\(sync.title) · \(at)").font(.subheadline).foregroundStyle(color)
            Text(sync.detail).font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One watch's data fields, grouped by activity type like the watch menu: per screen the
/// left, right and bottom field, each a choice of the watch's field catalog.
struct WatchDataFieldsScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64

    var body: some View {
        let watch = companion.watchSettings.first { $0.deviceId == deviceId }
        Form {
            ForEach(watch?.dataFieldGroups ?? [], id: \.key) { group in
                Section {
                    ForEach(Array(group.screens.enumerated()), id: \.offset) { _, screen in
                        if !screen.title.isEmpty {
                            Text(screen.title).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(screen.slots, id: \.index) { slot in
                            Picker(slot.label, selection: Binding(
                                get: { slot.field },
                                set: { companion.changeWatchDataField(deviceId: deviceId, key: group.key, index: slot.index, field: $0) }
                            )) {
                                ForEach(watch?.dataFieldOptions ?? [], id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                        }
                    }
                    if !group.note.isEmpty {
                        HStack {
                            Text(group.note).font(.footnote).foregroundStyle(group.pending ? Color.orange : Color.red)
                            if !group.pending {
                                Spacer()
                                Button(L10n.get("watch_settings_note_dismiss")) {
                                    companion.dismissWatchNote(deviceId: deviceId, key: group.key)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
        .navigationTitle(L10n.get("watch_data_fields_title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One watch's interval plans or strength routines: the three slots with the watch's
/// summary; each opens [WatchPlanEditScreen].
struct WatchPlansScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    let routines: Bool

    var body: some View {
        let watch = companion.watchSettings.first { $0.deviceId == deviceId }
        Form {
            Section { Text(L10n.get(routines ? "watch_routines_intro" : "watch_intervals_intro")).font(.footnote).foregroundStyle(.secondary) }
            ForEach((routines ? watch?.routineSlots : watch?.intervalSlots) ?? [], id: \.key) { slot in
                Section {
                    NavigationLink {
                        WatchPlanEditScreen(deviceId: deviceId, key: slot.key, title: slot.title, routine: routines)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.title)
                            Text(slot.summary).font(.subheadline).foregroundStyle(.secondary)
                            if !slot.detail.isEmpty {
                                Text(slot.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !slot.note.isEmpty {
                        HStack {
                            Text(slot.note).font(.footnote).foregroundStyle(slot.pending ? Color.orange : Color.red)
                            if !slot.pending {
                                Spacer()
                                Button(L10n.get("watch_settings_note_dismiss")) {
                                    companion.dismissWatchNote(deviceId: deviceId, key: slot.key)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.get(routines ? "watch_strength_routines" : "watch_interval_menu"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { companion.refreshWatchSettings() }
    }
}

/// Edits one plan or routine with the watch editor's own choices (shared WatchPlanEditor).
/// Back discards the draft; Save sends it to the watch.
struct WatchPlanEditScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let deviceId: Int64
    let key: String
    let title: String
    let routine: Bool
    @State private var view: PlanEditView?
    @State private var confirmClear = false

    var body: some View {
        Form {
            if let view {
                Section { Text(view.summary).font(.headline) }
                ForEach(Array(view.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.rows, id: \.id) { row in
                            PlanRow(row: row) { option in
                                self.view = companion.editWatchPlan(view, key: key, rowId: row.id, option: option)
                            }
                        }
                        if !section.removeId.isEmpty {
                            Button(L10n.get("watch_strength_remove_exercise"), role: .destructive) {
                                self.view = companion.editWatchPlan(view, key: key, rowId: section.removeId, option: 0)
                            }
                        }
                    } header: {
                        if !section.title.isEmpty { Text(section.title) }
                    }
                }
                if view.canClear {
                    Section {
                        Button(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), role: .destructive) {
                            confirmClear = true
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.get("watch_intervals_save")) {
                    if let view { companion.saveWatchPlan(deviceId: deviceId, key: key, draft: view.draft) }
                    dismiss()
                }
                .disabled(view == nil)
            }
        }
        .confirmationDialog(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), isPresented: $confirmClear) {
            Button(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), role: .destructive) {
                companion.saveWatchPlan(deviceId: deviceId, key: key, draft: [])
                dismiss()
            }
        }
        .onAppear {
            if view == nil { view = companion.openWatchPlan(deviceId: deviceId, key: key) }
        }
    }
}

/// A picker for a row with a selection; a menu for an action row ("Start from", "Add exercise")
/// or a value outside the watch's list.
private struct PlanRow: View {
    let row: PlanEditRow
    let pick: (Int32) -> Void

    var body: some View {
        if row.selected >= 0 {
            Picker(row.label, selection: Binding(get: { row.selected }, set: { pick($0) })) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { index, option in
                    Text(option).tag(Int32(index))
                }
            }
        } else {
            Menu {
                ForEach(Array(row.options.enumerated()), id: \.offset) { index, option in
                    Button(option) { pick(Int32(index)) }
                }
            } label: {
                HStack {
                    Text(row.label).foregroundStyle(Color.primary)
                    Spacer()
                    Text(row.value.isEmpty ? "…" : row.value).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WatchSettingRow: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    let item: WatchSettingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isToggle {
                Toggle(item.label, isOn: Binding(
                    get: { item.value != 0 },
                    set: { companion.changeWatchSetting(deviceId: deviceId, key: item.key, value: $0 ? 1 : 0) }
                ))
            } else {
                Picker(item.label, selection: Binding(
                    get: { item.value },
                    set: { companion.changeWatchSetting(deviceId: deviceId, key: item.key, value: $0) }
                )) {
                    ForEach(item.options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            }
            if !item.note.isEmpty {
                HStack {
                    Text(item.note)
                        .font(.footnote)
                        .foregroundStyle(item.pending ? Color.orange : Color.red)
                    if !item.pending {
                        Spacer()
                        Button(L10n.get("watch_settings_note_dismiss")) {
                            companion.dismissWatchNote(deviceId: deviceId, key: item.key)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }
}

// MARK: - Logs

struct LogScreen: View {
    @EnvironmentObject var companion: Companion
    let title: String
    let kind: Companion.LogKind
    @State private var lines: [LogLine] = []
    @State private var loaded = false

    init(title: String, kind: Companion.LogKind) {
        self.title = title
        self.kind = kind
    }

    var body: some View {
        LogList(lines: lines, loaded: loaded)
            .navigationTitle(title)
            .task {
                lines = await companion.logLines(kind)
                loaded = true
            }
            .refreshable { lines = await companion.logLines(kind) }
    }
}

/// One activity's history (Android: the activity change log).
struct ActivityLogScreen: View {
    @EnvironmentObject var companion: Companion
    let activityId: String
    @State private var lines: [LogLine] = []
    @State private var loaded = false
    @State private var failure: String?

    init(activityId: String) {
        self.activityId = activityId
    }

    var body: some View {
        LogList(lines: lines, loaded: loaded, empty: L10n.get("activity_change_log_empty"), failure: failure)
            .navigationTitle(L10n.get("activity_change_log_title"))
            .task {
                do { lines = try await companion.activityLog(activityId) } catch {
                    if !error.isCancellation { failure = error.localizedDescription }
                }
                loaded = true
            }
    }
}

/// Every Strava API call the app made (Android: Strava API usage), grouped per day.
struct StravaApiUsageScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var calls: [StravaApiCallView] = []
    @State private var loaded = false
    @State private var failure: String?

    private struct Day: Identifiable {
        let day: Date
        let calls: [StravaApiCallView]
        var id: Date { day }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: calls) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.epochMillis) / 1000))
        }
        return grouped.keys.sorted(by: >).map { Day(day: $0, calls: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if let failure { LoadFailedRow(reason: failure) }
            if loaded && calls.isEmpty && failure == nil {
                Text(L10n.get("strava_api_usage_empty")).foregroundStyle(.secondary)
            }
            ForEach(days) { group in
                Section {
                    ForEach(group.calls, id: \.id) { call in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(call.method) \(call.endpoint)").font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Date(timeIntervalSince1970: TimeInterval(call.epochMillis) / 1000)
                                    .formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            Text(call.purpose).font(.footnote)
                            HStack(spacing: 8) {
                                Text(L10n.get(call.success ? "strava_api_call_success" : "strava_api_call_failed"))
                                    .foregroundStyle(call.success ? Color.green : Color.red)
                                if !call.httpStatus.isEmpty {
                                    Text(String(format: L10n.get("strava_api_call_http_status"), call.httpStatus))
                                }
                            }
                            .font(.caption)
                            if !call.detail.isEmpty {
                                Text(call.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                    }
                } header: {
                    let failed = group.calls.filter { !$0.success }.count
                    let count = L10n.plural("strava_api_usage_call_count", group.calls.count)
                    Text("\(group.day.formatted(date: .complete, time: .omitted)) \u{00B7} "
                         + (failed > 0 ? String(format: L10n.get("strava_api_usage_with_failures"), count, failed) : count))
                }
            }
        }
        .navigationTitle(L10n.get("strava_api_usage_title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            calls = try await companion.core.stravaApiCalls(limit: 500)
            failure = nil
        } catch {
            if !error.isCancellation {
                WatchLinkSpike.shared.add("Strava API usage not loaded: \(error.localizedDescription)")
                failure = error.localizedDescription
            }
            calls = []
        }
        loaded = true
    }
}

/// Android's BuildExpiryScreen for a build below the server's minimum: no sync any more, but the
/// athlete's own data stays reachable (export, delete).
struct OutdatedScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var exportURL: URL?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.get("expiry_outdated_title")).font(.title2.bold())
            Text(L10n.get("expiry_body_store"))
            Text(L10n.get("expiry_data_note")).font(.footnote).foregroundStyle(.secondary)
            if let exportURL {
                ShareLink(item: exportURL) { Label(exportURL.lastPathComponent, systemImage: "square.and.arrow.up") }
            } else {
                Button(L10n.get("status_download_my_data")) {
                    Task { exportURL = await companion.exportFile() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button(L10n.get("status_delete_my_data"), role: .destructive) { confirmingDelete = true }
            Spacer()
        }
        .padding()
        .confirmationDialog(L10n.get("status_delete_confirm_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L10n.get("status_delete_confirm_button"), role: .destructive) {
                exportURL = nil
                Task { await companion.deleteAllData() }
            }
        } message: {
            Text(L10n.get("status_delete_confirm_body"))
        }
        .onDisappear {
            companion.discardExport(exportURL)
            exportURL = nil
        }
    }
}

/// Android's first-start guide: three steps (nickname, online repository, diary), each skippable;
/// shown once (also left out when the app is already set up).
struct OnboardingScreen: View {
    @EnvironmentObject var companion: Companion
    let finish: () -> Void
    @State private var step = 0
    @State private var nickname = ""
    @State private var diaryShown = false

    private let steps = 3

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(format: L10n.get("onboarding_guide_step"), step + 1, steps))
                    .font(.footnote).foregroundStyle(.secondary)
                switch step {
                case 0:
                    Text(L10n.get("onboarding_guide_nickname_title")).font(.title2.bold())
                    Text(L10n.get("onboarding_guide_nickname_body"))
                    TextField("", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: nickname) { _, value in nickname = String(value.prefix(20)) }
                    Text(L10n.get("onboarding_guide_nickname_later")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("onboarding_guide_nickname_save")) {
                        companion.setNickname(nickname)
                        step += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
                case 1:
                    Text(L10n.get("onboarding_guide_strava_title")).font(.title2.bold())
                    Text(L10n.get("onboarding_guide_strava_body"))
                    Text(L10n.get("onboarding_guide_strava_how")).font(.footnote).foregroundStyle(.secondary)
                    StravaConnectButton { companion.connectStrava() }
                    Text(L10n.get("onboarding_guide_place_names_notice")).font(.footnote).foregroundStyle(.secondary)
                default:
                    Text(L10n.get("onboarding_guide_diary_title")).font(.title2.bold())
                    Text(L10n.get("onboarding_guide_diary_body"))
                    Text(L10n.get("onboarding_guide_diary_how")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("onboarding_guide_choose_diary")) { diaryShown = true }
                        .buttonStyle(.borderedProminent)
                }
                Text(L10n.get("onboarding_guide_later")).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.get(step == steps - 1 ? "common_ok" : "onboarding_guide_not_now")) {
                    if step == steps - 1 { finish() } else { step += 1 }
                }
            }
            .padding()
            .navigationDestination(isPresented: $diaryShown) { DiaryLocationsScreen() }
        }
    }
}

/// Android's About: version, what's new, help with the translations, privacy policy, imprint,
/// the description and the trademark note.
struct AboutScreen: View {
    private static let site = "https://nordicsports.maddin.me"

    var body: some View {
        List {
            Section {
                Text("Nordic Sports Companion").font(.title3.bold())
                Text(Format.appVersion).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink(L10n.get("about_view_changelog")) { ChangelogScreen() }
                NavigationLink(L10n.get("about_help_translate")) { FeedbackScreen(startCategory: "wording") }
                if let privacy = URL(string: Self.site + "/privacy.html") {
                    Link(L10n.get("about_privacy_policy"), destination: privacy)
                }
                if let imprint = URL(string: Self.site + "/impressum.html") {
                    Link(L10n.get("about_imprint"), destination: imprint)
                }
            }
            Section {
                Text(L10n.get("about_body"))
                Text(L10n.get("about_trademark_disclaimer")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.get("about_title"))
    }
}

/// What changed, for the athlete: starts with the first iOS version (Android's older entries do
/// not apply here). Each release adds its lines on top.
struct ChangelogScreen: View {
    private struct Entry: Identifiable {
        let version: String
        let date: String
        let keys: [String]
        var id: String { version }
    }

    private let entries = [
        Entry(version: "0.9.96", date: "2026-10-20", keys: [
            "changelog_0996_retention", "changelog_0996_deleted_on_strava", "changelog_0996_disconnect",
            "changelog_0996_log", "changelog_0996_withdrawn", "changelog_0996_wording",
        ]),
    ]

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section("\(entry.version) · \(entry.date)") {
                    ForEach(entry.keys, id: \.self) { key in
                        Text(L10n.get(key))
                    }
                }
            }
        }
        .navigationTitle(L10n.get("changelog_title"))
    }
}

/// Every Recording Boost burst received from the watch, newest capture first (Android: Recording
/// Boost activities): when, how much, which activity, and where its CSV file is.
struct RecordingBoostScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var bursts: [RecordingBoostView] = []
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Text(String(format: L10n.get("recording_boost_list_default_folder"),
                            "On My iPhone \u{203A} Nordic Sports \u{203A} \(Companion.boostFolder)"))
                    .font(.system(.footnote, design: .monospaced))
            }
            if let failure { LoadFailedRow(reason: failure) }
            if loaded && bursts.isEmpty && failure == nil {
                Text(L10n.get("recording_boost_list_empty")).foregroundStyle(.secondary)
            }
            ForEach(bursts, id: \.id) { burst in
                VStack(alignment: .leading, spacing: 3) {
                    Text(Date(timeIntervalSince1970: TimeInterval(burst.burstId)).formatted(date: .abbreviated, time: .standard))
                        .font(.headline)
                    let seconds = burst.sampleRateHz > 0 ? Int(burst.sampleCount) / Int(burst.sampleRateHz) : 0
                    Text(String(format: L10n.get("recording_boost_list_samples"), Int(burst.sampleCount), seconds, Int(burst.sampleRateHz)))
                    Text(String(format: L10n.get("recording_boost_list_received"),
                                Date(timeIntervalSince1970: TimeInterval(burst.receivedAtEpochMillis) / 1000)
                                    .formatted(date: .abbreviated, time: .standard)))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(burst.activityTitle.isEmpty
                         ? L10n.get("recording_boost_list_not_linked")
                         : String(format: L10n.get("recording_boost_list_linked"), burst.activityTitle))
                        .font(.caption)
                    if !burst.fileName.isEmpty {
                        Text(L10n.get("recording_boost_list_file_saved")).font(.subheadline.bold())
                        Text(String(format: L10n.get("recording_boost_list_file_name"), burst.fileName))
                            .font(.system(.caption, design: .monospaced))
                        Text(String(format: L10n.get("recording_boost_list_file_size"), Int(burst.sizeBytes)))
                            .font(.caption)
                    } else {
                        Text(L10n.get("recording_boost_list_file_missing")).font(.subheadline.bold()).foregroundStyle(.red)
                        if burst.error.isEmpty {
                            Text(L10n.get("recording_boost_list_file_pending")).font(.caption)
                        } else {
                            Text(String(format: L10n.get("recording_boost_list_file_error"), burst.error))
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.get("recording_boost_list_title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            bursts = try await companion.core.recordingBoosts()
            failure = nil
        } catch {
            if !error.isCancellation {
                WatchLinkSpike.shared.add("Recording Boost list not loaded: \(error.localizedDescription)")
                failure = error.localizedDescription
            }
            bursts = []
        }
        loaded = true
    }
}

/// A list that could not be loaded says so, instead of looking empty.
struct LoadFailedRow: View {
    let reason: String

    var body: some View {
        Text(String(format: L10n.get("ios_list_load_failed"), reason))
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

private struct LogList: View {
    let lines: [LogLine]
    let loaded: Bool
    var empty = "Nothing logged yet."
    var failure: String?

    var body: some View {
        List {
            if let failure { LoadFailedRow(reason: failure) }
            if loaded && lines.isEmpty && failure == nil {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date(timeIntervalSince1970: TimeInterval(line.atEpochMillis) / 1000)
                        .formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.title).font(.subheadline)
                    if !line.detail.isEmpty {
                        Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Feedback

struct FeedbackScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    @State private var category: String

    /// [startCategory] "wording" opens the form on "Wording / translation" (About > Help improve the translations).
    init(startCategory: String = "error_report") {
        _category = State(initialValue: startCategory)
    }

    @State private var app = "companion"
    @State private var text = ""
    @State private var email = ""
    @State private var includeDetails = true
    @State private var includeNickname = false
    @State private var watches: [FeedbackWatchView] = []
    @State private var watchIndex = 0
    @State private var wordingEntries: [WordingEntry] = []
    @State private var wordingPicked: WordingEntry?
    @State private var wordingLang = "en"
    @State private var wordingProposed = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    private var emailValid: Bool { email.isEmpty || (email.contains("@") && email.contains(".")) }
    private var wording: Bool { category == "wording" }
    private var canSend: Bool {
        let blank = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if wording { return wordingPicked != nil && !blank(wordingProposed) }
        return !blank(text)
    }

    var body: some View {
        Form {
            if sent {
                Section {
                    Text(L10n.get("feedback_thanks_title")).font(.headline)
                    Text(L10n.get("feedback_thanks_body"))
                    Button(L10n.get("feedback_thanks_done")) { dismiss() }
                }
            } else {
                Section { Text(L10n.get("feedback_intro")).font(.footnote) }
                Section {
                    Picker(L10n.get("feedback_category_label"), selection: $category) {
                        Text(L10n.get("feedback_category_error")).tag("error_report")
                        Text(L10n.get("feedback_category_feature")).tag("feature_request")
                        Text(L10n.get("feedback_category_other")).tag("other")
                        Text(L10n.get("feedback_category_wording")).tag("wording")
                    }
                    if !wording {
                        Picker(L10n.get("feedback_app_label"), selection: $app) {
                            Text(L10n.get("feedback_app_watch")).tag("watch")
                            Text(L10n.get("feedback_app_companion")).tag("companion")
                            Text(L10n.get("feedback_app_both")).tag("both")
                        }
                    }
                }
                if wording {
                    WordingPicker(entries: wordingEntries, appLanguage: companion.language,
                                  picked: $wordingPicked, lang: $wordingLang, proposed: $wordingProposed)
                }
                if !wording && app != "companion" && !watches.isEmpty {
                    Section {
                        Picker(L10n.get("feedback_watch_label"), selection: $watchIndex) {
                            ForEach(Array(watches.enumerated()), id: \.offset) { index, watch in
                                Text(watch.name).tag(index)
                            }
                        }
                    }
                }
                Section(L10n.get(wording ? "feedback_wording_reason" : "feedback_message_label")) {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
                if !companion.nickname.isEmpty {
                    Section {
                        Toggle(L10n.get("feedback_nickname_switch"), isOn: $includeNickname)
                        Text(String(format: L10n.get(includeNickname ? "feedback_nickname_on" : "feedback_nickname_off"), companion.nickname))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(L10n.get("feedback_email_label")) {
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(L10n.get(emailValid ? "feedback_email_hint" : "feedback_email_invalid"))
                        .font(.footnote)
                        .foregroundStyle(emailValid ? Color.secondary : Color.red)
                }
                Section {
                    Toggle(L10n.get("feedback_details_switch"), isOn: $includeDetails)
                    if includeDetails {
                        let details = Companion.deviceDetails()
                        Text("\(L10n.get("feedback_detail_app")) \(Format.appVersion) · \(details["phone"] ?? "") · iOS \(details["ios"] ?? "") · \(companion.language)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.get("feedback_details_off")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task {
                            sending = true
                            error = nil
                            var sendApp = app
                            var sendCategory = category
                            var sendText = text
                            var extra: [String: String] = [:]
                            if wording, let entry = wordingPicked {
                                let composed = WordingFeedback.compose(
                                    entry: entry, lang: wordingLang, current: entry.texts[wordingLang] ?? "",
                                    proposed: wordingProposed.trimmingCharacters(in: .whitespacesAndNewlines),
                                    reason: text.trimmingCharacters(in: .whitespacesAndNewlines))
                                sendApp = entry.app.wireValue
                                sendCategory = "other"
                                sendText = composed.message
                                extra = composed.details
                            }
                            let watch = !wording && app != "companion" && watches.indices.contains(watchIndex) ? watches[watchIndex] : nil
                            let result = await companion.sendFeedback(
                                category: sendCategory, app: sendApp, text: sendText, email: email, includeDetails: includeDetails,
                                watch: watch, includeNickname: includeNickname, extraDetails: extra
                            )
                            sending = false
                            switch result {
                            case "sent": sent = true
                            case "tooMany": error = L10n.get("feedback_error_too_many")
                            default: error = L10n.get("feedback_error_failed")
                            }
                        }
                    } label: {
                        if sending { ProgressView() } else { Text(L10n.get("feedback_send")) }
                    }
                    .disabled(sending || !canSend || !emailValid)
                }
            }
        }
        .navigationTitle(L10n.get("feedback_title"))
        .task {
            watches = await companion.feedbackWatches()
            wordingEntries = WordingFeedback.load()
        }
    }
}

// MARK: - Add activity by hand

struct AddActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    @State private var typeKey = ""
    @State private var endedNow = true
    @State private var minutes = 60
    @State private var otherMinutes = ""
    @State private var start = Date()
    @State private var saving = false

    private static let durations = [30, 60, 90, 120]

    private var duration: Int { Int(otherMinutes) ?? minutes }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.get("add_activity_type_heading")) {
                    Picker(L10n.get("add_activity_type_heading"), selection: $typeKey) {
                        ForEach(companion.manualTypes, id: \.key) { type in
                            Text(type.label).tag(type.key)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section(L10n.get("add_activity_duration_heading")) {
                    Picker(L10n.get("add_activity_duration_heading"), selection: $minutes) {
                        ForEach(Self.durations, id: \.self) { value in
                            Text(String(format: L10n.get("add_activity_duration_minutes"), value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(L10n.get("add_activity_duration_other"), text: $otherMinutes)
                        .keyboardType(.numberPad)
                }
                Section(L10n.get("add_activity_when_heading")) {
                    Picker(L10n.get("add_activity_when_heading"), selection: $endedNow) {
                        Text(L10n.get("add_activity_ended_now")).tag(true)
                        Text(L10n.get("add_activity_starts_now")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    DatePicker(L10n.get("activity_detail_started_label"), selection: $start)
                }
            }
            .navigationTitle(L10n.get("add_activity_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.get("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("add_activity_save_button")) {
                        Task {
                            saving = true
                            let id = await companion.addActivity(typeKey: typeKey, start: start, minutes: duration)
                            saving = false
                            if id != nil { dismiss() }
                        }
                    }
                    .disabled(saving || typeKey.isEmpty || duration <= 0)
                }
            }
            .onAppear {
                if typeKey.isEmpty { typeKey = companion.manualTypes.first?.key ?? "" }
                updateStart()
            }
            .onChange(of: endedNow) { _, _ in updateStart() }
            .onChange(of: minutes) { _, _ in updateStart() }
            .onChange(of: otherMinutes) { _, _ in updateStart() }
        }
    }

    /// "Ended now" starts the activity its duration ago; "Starts now" starts it now.
    private func updateStart() {
        start = endedNow ? Date().addingTimeInterval(-Double(duration) * 60) : Date()
    }
}

// MARK: - Edit an activity

/// Android's detail-screen edits that matter most on the go: name, training type, RPE,
/// feeling, diary comment and corrected duration/distance. Saving is the review.
struct EditActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let item: ActivityItem
    @State private var title: String
    @State private var trainingType: String
    @State private var rpe: Int
    @State private var feeling: Int
    @State private var comment: String
    @State private var minutes: String
    @State private var kilometers: String
    @State private var saving = false

    init(item: ActivityItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _trainingType = State(initialValue: item.trainingType)
        _rpe = State(initialValue: Int(item.rpe))
        _feeling = State(initialValue: Int(item.feeling))
        _comment = State(initialValue: item.diaryComment)
        _minutes = State(initialValue: item.overrideElapsedSec > 0 ? String(item.overrideElapsedSec / 60) : "")
        _kilometers = State(initialValue: item.overrideDistanceM > 0 ? String(format: "%.1f", Double(item.overrideDistanceM) / 1000) : "")
    }

    private var trainingOptions: [(String, String)] {
        item.preset == "strength"
            ? [("hypertrophy", "activity_detail_training_option_hypertrophy"),
               ("speedStrength", "activity_detail_training_option_speed_strength"),
               ("strengthEndurance", "activity_detail_training_option_strength_endurance")]
            : [("endurance", "activity_detail_training_option_endurance"),
               ("intervals", "activity_detail_training_option_intervals"),
               ("technique", "activity_detail_training_option_technique"),
               ("sprints", "activity_detail_training_option_sprints")]
    }

    private static let feelings = [
        "activity_detail_feeling_option_not_entered", "activity_detail_feeling_option_very_weak",
        "activity_detail_feeling_option_weak", "activity_detail_feeling_option_normal",
        "activity_detail_feeling_option_good", "activity_detail_feeling_option_very_good",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.get("activity_detail_name_label"), text: $title)
                    Picker(L10n.get("activity_detail_training_type_label"), selection: $trainingType) {
                        ForEach(trainingOptions, id: \.0) { option in Text(L10n.get(option.1)).tag(option.0) }
                        if !trainingOptions.contains(where: { $0.0 == trainingType }) {
                            Text(Format.trainingTypeWord(trainingType)).tag(trainingType)
                        }
                    }
                }
                Section {
                    Picker(L10n.get("activity_detail_rpe_label"), selection: $rpe) {
                        ForEach(0...10, id: \.self) { value in Text(value == 0 ? "–" : "\(value)").tag(value) }
                    }
                    Picker(L10n.get("activity_detail_feeling_label"), selection: $feeling) {
                        ForEach(Self.feelings.indices, id: \.self) { index in Text(L10n.get(Self.feelings[index])).tag(index) }
                    }
                }
                Section(L10n.get("activity_detail_diary_comment_label")) {
                    TextEditor(text: $comment).frame(minHeight: 80)
                }
                Section {
                    LabeledContent(L10n.get("activity_detail_duration_label")) {
                        TextField(Format.duration(item.elapsedSec), text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("min").foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.get("activity_detail_distance_label")) {
                        TextField(item.distanceM > 0 ? String(format: "%.1f", Double(item.distanceM) / 1000) : "0", text: $kilometers)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("km").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(L10n.get("ios_leave_empty_watch"))
                }
                sendSection
            }
            .navigationTitle(L10n.get("activity_detail_review_heading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.get("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Automatic mode sends on its own: there the form's "Save & send" replaces "Save".
                    if !(companion.automaticSync && companion.sendsSomewhere) {
                        Button(L10n.get("activity_detail_save_button")) { Task { await save(send: false) } }
                            .disabled(saving)
                    }
                }
            }
        }
    }

    /// Every button saves the screen's values first, so nothing sent is older than what is shown.
    private func save(send: Bool, createOnStrava: Bool = false) async {
        saving = true
        let km = Double(kilometers.replacingOccurrences(of: ",", with: ".")) ?? 0
        let saved = await companion.saveActivity(
            item.id, title: title, trainingType: trainingType, rpe: rpe, feeling: feeling,
            comment: comment, minutes: Int(minutes) ?? 0, kilometers: km
        )
        if saved {
            if createOnStrava { await companion.createOnStrava(item.id) }
            if send { await companion.sendNow(item.id) }
        }
        saving = false
        if saved { dismiss() }
    }

    /// "Save & send" (automatic mode) or "Send now" (manual mode), and "Create on Strava" while
    /// the activity has no Strava link.
    @ViewBuilder
    private var sendSection: some View {
        let sends = companion.sendsSomewhere
        let canCreate = companion.stravaConnected && item.stravaActivityId.isEmpty
        if sends || canCreate {
            Section {
                if sends {
                    Button(L10n.get(companion.automaticSync ? "activity_detail_save_and_send" : "activity_detail_send_now")) {
                        Task { await save(send: true) }
                    }
                    .disabled(saving)
                }
                if canCreate {
                    Button(L10n.get("activity_detail_strava_create")) {
                        Task { await save(send: false, createOnStrava: true) }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}

// MARK: - Diary locations

/// Android's "Athlete's Diary connections": the Files app and the three clouds, each
/// connected on its own; one is active and receives the diary entries. A cloud needs a
/// sign-in (system sheet) and then the folder's sharing link (Dropbox: link or path).
struct DiaryLocationsScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var pickingFile = false
    @State private var links: [String: String] = [:]
    @State private var choice: DiaryLocateView?
    @State private var choosing = false

    private static let xlsx = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        Form {
            Section {
                Text(L10n.get("connect_diary_intro")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    AddFolderDestinationScreen(format: "JSON_PER_ACTIVITY")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.get("settings_add_connection_json"))
                        Text(L10n.get("settings_add_connection_json_help")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    AddFolderDestinationScreen(format: "CSV_MONTHLY")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.get("settings_add_connection_csv"))
                        Text(L10n.get("settings_add_connection_csv_help")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(companion.diarySources, id: \.key) { source in
                Section(source.name) { rows(source) }
            }
            if companion.diaryBusy {
                HStack { ProgressView(); Text(L10n.get("connect_diary_connecting")) }
            }
        }
        .disabled(companion.diaryBusy)
        .navigationTitle(L10n.get("connect_diary_title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [Self.xlsx]) { result in
            switch result {
            case .success(let url): Task { await companion.connectDiary(url) }
            case .failure(let error): companion.post(error.localizedDescription)
            }
        }
        .onChange(of: pickingFile) { _, open in companion.filePickerOpen = open }
        .confirmationDialog(
            L10n.get("connect_diary_file_selection_title"), isPresented: $choosing, titleVisibility: .visible, presenting: choice
        ) { found in
            ForEach(Array(found.candidates.enumerated()), id: \.offset) { index, name in
                Button(name) { Task { show(await companion.chooseCloudWorkbook(index)) } }
            }
        } message: { found in
            if found.status == "confirm" {
                Text(L10n.get("ios_diary_confirm_workbook"))
            } else if found.candidates.isEmpty {
                Text(String(format: L10n.get("ios_diary_no_files"), found.folderName))
            } else {
                Text(String(format: L10n.get("ios_diary_pick_workbook"), found.folderName))
            }
        }
    }

    @ViewBuilder
    private func rows(_ source: DiarySourceView) -> some View {
        if !source.available {
            Text(source.key == "LOCAL" ? L10n.get("ios_not_available") : L10n.get("ios_not_available_build")).foregroundStyle(.secondary)
        } else {
            if source.connected {
                Label(String(format: L10n.get("connect_diary_connected_to"), source.workbookName), systemImage: "book.closed")
                if source.active {
                    Text(L10n.get("connect_diary_active")).font(.footnote).foregroundStyle(.green)
                } else {
                    Text(L10n.get("connect_diary_not_active")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("ios_make_active")) {
                        companion.setActiveDiary(source.key)
                    }
                }
            }
            if source.key == "LOCAL" {
                if !source.connected {
                    Text(L10n.get("ios_local_workbook_hint"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button(source.connected ? L10n.get("ios_choose_other_workbook") : L10n.get("ios_choose_workbook")) { pickingFile = true }
            } else if !source.signedIn {
                Button("\(L10n.get("destination_sign_in")) · \(source.name)") { companion.signInCloud(source.key) }
            } else {
                TextField(locationLabel(source.key), text: Binding(
                    get: { links[source.key] ?? source.location },
                    set: { links[source.key] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                Button(L10n.get("connect_diary_connect_button")) {
                    let link = links[source.key] ?? source.location
                    Task { show(await companion.connectCloud(source.key, location: link)) }
                }
                .disabled((links[source.key] ?? source.location).trimmingCharacters(in: .whitespaces).isEmpty)
                Button("\(L10n.get("cloud_account_sign_out_button")) · \(source.name)", role: .destructive) { companion.signOutCloud(source.key) }
            }
            if source.connected {
                Button(L10n.get("connect_diary_disconnect_button"), role: .destructive) { companion.disconnectDiary(source.key) }
            }
        }
    }

    private func locationLabel(_ key: String) -> String {
        switch key {
        case "ONE_DRIVE": return L10n.get("connect_diary_location_label_onedrive")
        case "DROPBOX": return L10n.get("connect_diary_location_label_dropbox")
        default: return L10n.get("connect_diary_location_label_google_drive")
        }
    }

    private func show(_ result: DiaryLocateView?) {
        guard let result else { return }
        switch result.status {
        case "connected":
            companion.post(String(format: L10n.get("connect_diary_connected_to"), result.workbookName))
        case "confirm", "choose":
            choice = result
            choosing = !result.candidates.isEmpty
            if result.candidates.isEmpty {
                companion.post(String(format: L10n.get("ios_diary_no_files"), result.folderName))
            }
        default:
            companion.message = result.message
        }
    }
}
