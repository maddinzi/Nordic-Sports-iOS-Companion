import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

/// The first iOS Companion (roadmap step 4): activities from the watch, linked to Strava and
/// retitled there. The Android texts are used where a
/// matching one exists; the rest is English until the screens settle.
struct RootView: View {
    @EnvironmentObject var companion: Companion
    /// The first-start guide is shown once; an app that is already set up skips it.
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showOnboarding = false
    @State private var tab = 0

    var body: some View {
        if companion.outdated {
            OutdatedScreen()
        } else {
            mainTabs
        }
    }

    private var mainTabs: some View {
        TabView(selection: $tab) {
            ActivitiesScreen()
                .tabItem { Label(L10n.get("ios_tab_activities"), systemImage: "list.bullet") }
                .tag(0)
            SettingsScreen()
                .tabItem { Label(L10n.get("status_title"), systemImage: "gearshape") }
                .tag(1)
        }
        // A tapped notification shows its activity on the first tab.
        .onChange(of: companion.openActivityId) { _, id in
            if id != nil { tab = 0 }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingScreen { showOnboarding = false }
                .environmentObject(companion)
        }
        .task {
            // Decided once at start, so connecting Strava inside the guide does not close it.
            if !onboardingDone && !companion.stravaConnected && !companion.diaryReceives && companion.activities.isEmpty {
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
        // "Companion language too?" after the watch's language changed.
        .background {
            Color.clear.alert(
                L10n.get("language_offer_companion_title"),
                isPresented: Binding(get: { companion.companionLanguageOffer != nil }, set: { if !$0 { companion.companionLanguageOffer = nil } }),
                presenting: companion.companionLanguageOffer
            ) { tag in
                Button(L10n.get("language_offer_both")) { companion.chooseAppLanguage(tag) }
                Button(L10n.get("language_offer_only_watch"), role: .cancel) {}
            } message: { tag in
                Text(String(format: L10n.get("language_offer_companion_body"), companion.languageNativeName(tag)))
            }
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

/// A request to show one activity, from a tapped notification.
struct ActivityRoute: Hashable {
    let id: String
}

/// The detail of the activity with [id]; a spinner until the list has loaded it.
struct ActivityRouteView: View {
    @EnvironmentObject var companion: Companion
    let id: String

    var body: some View {
        if let item = companion.activities.first(where: { $0.id == id }) {
            ActivityDetailScreen(item: item)
        } else {
            ProgressView()
        }
    }
}

struct ActivitiesScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var adding = false
    @State private var route: ActivityRoute?
    /// Items that were open and are not any more, newest first: they stay on top of "Done" with a
    /// green frame until the next pull to refresh (as Android's `JustReviewed`).
    @State private var seenOpen: Set<String> = []
    @State private var justDone: [String] = []

    /// Activities still to review (review pending and before its deadline), oldest first.
    private var openItems: [ActivityItem] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return companion.activities
            .filter { $0.reviewPending && now < $0.reviewDeadlineEpochMillis }
            .sorted { $0.startEpochSec < $1.startEpochSec }
    }

    private func trackOpen(_ ids: Set<String>) {
        for id in seenOpen where !ids.contains(id) {
            seenOpen.remove(id)
            justDone.removeAll { $0 == id }
            justDone.insert(id, at: 0)
        }
        seenOpen.formUnion(ids)
        justDone.removeAll { ids.contains($0) }
    }

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
                        if let status = companion.syncStatus {
                            Section { SyncStatusCard(status: status) }
                        }
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
                        let open = openItems
                        let openIds = Set(open.map { $0.id })
                        let finished = justDone.compactMap { id in companion.activities.first { $0.id == id } }
                        let finishedIds = Set(finished.map { $0.id })
                        let rest = companion.activities.filter { !openIds.contains($0.id) && !finishedIds.contains($0.id) }
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
                        Section(open.isEmpty && finished.isEmpty ? "" : L10n.get("activity_list_section_done")) {
                            ForEach(finished, id: \.id) { item in
                                NavigationLink {
                                    ActivityDetailScreen(item: item)
                                } label: {
                                    ActivityRow(item: item)
                                }
                                .listRowBackground(Color.green.opacity(0.18))
                            }
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
            .navigationTitle(L10n.get("ios_tab_activities"))
            .navigationDestination(item: $route) { route in
                ActivityRouteView(id: route.id)
            }
            .onChange(of: companion.openActivityId, initial: true) { _, id in
                guard let id else { return }
                route = ActivityRoute(id: id)
                companion.openActivityId = nil
            }
            .onChange(of: openItems.map { $0.id }, initial: true) { _, ids in trackOpen(Set(ids)) }
            .onAppear { companion.refreshWatchCards() }
            .refreshable {
                justDone = []
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
                // Android's chat icon next to settings: feedback one tap away, not only under Settings › Privacy.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FeedbackScreen()
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                    }
                    .accessibilityLabel(L10n.get("activity_list_feedback_content_description"))
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
                    Text(String(format: L10n.get("watch_live_since"), started, Format.duration(Int32(clamping: running)))).font(.subheadline)
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
                if item.origin == "watch" {
                    Image(systemName: "applewatch").foregroundStyle(.primary)
                }
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

/// One place an activity is synced to: ticked when it is there.
struct SyncChip: View {
    let name: String
    let on: Bool

    var body: some View {
        Label(name, systemImage: on ? "checkmark.circle.fill" : "circle")
            .font(.subheadline)
            .foregroundStyle(on ? Color.green : Color.secondary)
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

    /// The wrist in the app language; the watch's own label is English.
    private func wristText(_ a: ActivityItem) -> String? {
        switch a.watchWrist {
        case 1: return L10n.get("watch_option_wrist_left")
        case 2: return L10n.get("watch_option_wrist_right")
        default: return a.watchWristLabel.isEmpty ? nil : a.watchWristLabel
        }
    }

    var body: some View {
        Form {
            // Where this activity is synced to, as Android's header box.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.get("activity_detail_synced_to")).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        SyncChip(name: L10n.get("sync_presence_destination_watch"), on: current.origin == "watch")
                        SyncChip(name: "Strava", on: !current.stravaActivityId.isEmpty)
                        if companion.diaryReceives {
                            SyncChip(name: L10n.get("settings_diary_short_name"),
                                     on: current.diaryWritten && !current.diaryOutdated)
                        }
                    }
                }
            }
            if current.reviewPending {
                Section(L10n.get("activity_detail_review_heading")) {
                    Text(companion.diarySettings.autoUpdate
                         ? String(format: L10n.get("activity_detail_review_body_waits"),
                                  Format.date(current.reviewDeadlineEpochMillis / 1000))
                         : L10n.get("activity_detail_review_body"))
                        .font(.footnote)
                    Button(L10n.get("activity_detail_review_heading")) { editing = true }
                    Button(L10n.get("activity_detail_review_skip")) {
                        Task { await companion.skipReview(item.id) }
                    }
                    .disabled(companion.syncing)
                }
                .listRowBackground(Color.yellow.opacity(0.18))
            }
            Section {
                LabeledContent(L10n.get("activity_detail_started_label"), value: Format.date(current.startEpochSec))
                LabeledContent(L10n.get("activity_detail_duration_label"), value: Format.duration(current.elapsedSec))
                if current.distanceM > 0 { LabeledContent(L10n.get("activity_detail_distance_label"), value: Format.distance(current.distanceM)) }
                if current.avgHeartRate > 0 { LabeledContent(L10n.get("activity_detail_avg_hr_label"), value: "\(current.avgHeartRate) bpm") }
                if current.maxHeartRate > 0 { LabeledContent(L10n.get("activity_detail_max_hr_label"), value: "\(current.maxHeartRate) bpm") }
                if current.totalAscentM > 0 { LabeledContent(L10n.get("activity_detail_ascent_label"), value: "\(Int(current.totalAscentM)) m") }
                if current.calories > 0 { LabeledContent(L10n.get("activity_detail_calories_label"), value: "\(current.calories) kcal") }
                if current.avgSpeedMps > 0 {
                    LabeledContent(L10n.get("activity_detail_avg_max_speed_label"),
                                   value: String(format: "%.1f / %.1f km/h", Double(current.avgSpeedMps) * 3.6, Double(current.maxSpeedMps) * 3.6))
                }
                // Poling metrics only for rollski and langlauf, as on Android.
                if current.avgSpm > 0, current.preset.hasPrefix("rollski") || current.preset.hasPrefix("langlauf") {
                    LabeledContent(L10n.get("activity_detail_stroke_metrics_label"),
                                   value: String(format: "%lld / %.2f m / %.0f ms / %.0f %%", Int(current.avgSpm), Double(current.avgDpsM),
                                                 Double(current.avgApidMs), Double(current.avgAdcPercent)))
                }
                if current.techniqueSharePercent.isEmpty, !current.watch.isEmpty,
                   ["running", "trailrun", "track"].contains(current.preset) {
                    LabeledContent(L10n.get("activity_detail_technique_share_label"),
                                   value: L10n.get("activity_detail_technique_share_running_missing"))
                }
                if current.techniqueCatalog == "running", current.techniqueSharePercent.count >= 2 {
                    LabeledContent(L10n.get("activity_detail_technique_share_label"),
                                   value: String(format: L10n.get("activity_detail_technique_share_running_value"),
                                                 current.techniqueSharePercent[0].doubleValue, current.techniqueSharePercent[1].doubleValue))
                }
                if !current.watch.isEmpty { LabeledContent(L10n.get("activity_detail_device_label"), value: current.watch) }
                if let wrist = wristText(current) { LabeledContent(L10n.get("activity_detail_watch_wrist_label"), value: wrist) }
                if !current.locationName.isEmpty { LabeledContent(L10n.get("activity_detail_location_label"), value: current.locationName) }
            }
            Section(L10n.get("activity_detail_training_type_label")) {
                LabeledContent(L10n.get("activity_detail_sport_label"), value: Format.presetWord(current.preset))
                if !current.trainingType.isEmpty, current.trainingType != "unknown" {
                    LabeledContent(L10n.get("ios_intensity"), value: Format.trainingTypeWord(current.trainingType))
                }
                if current.rpe > 0 { LabeledContent(L10n.get("activity_detail_rpe_label"), value: "\(current.rpe)") }
                if current.feeling > 0 { LabeledContent(L10n.get("activity_detail_feeling_label"), value: "\(current.feeling)") }
            }
            let zones = current.hrZonePercents.map { $0.floatValue }
            if zones.contains(where: { $0 > 0 }) {
                Section(L10n.get("ios_hr_zones")) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, percent in
                        HStack {
                            Text(String(format: L10n.get("ios_zone_n"), index + 1)).frame(width: 70, alignment: .leading)
                            ProgressView(value: Double(percent), total: 100)
                            Text("\(Int(percent.rounded())) %").frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
            if current.techniqueCatalog == "rollski", !current.techniqueSharePercent.isEmpty {
                Section(L10n.get("activity_detail_technique_share_rollski_label")) {
                    ForEach(Array(current.techniqueSharePercent.enumerated()), id: \.offset) { index, percent in
                        LabeledContent(L10n.get("technique_labels_rollski_\(index)"), value: String(format: "%.0f%%", percent.doubleValue))
                    }
                }
            }
            Section(L10n.get("activity_detail_synced_to")) {
                if current.stravaActivityId.isEmpty {
                    Text(L10n.get("ios_not_linked_strava"))
                    if stravaRemovedAt > 0 {
                        Label(String(format: L10n.get("activity_detail_strava_removed_note"), Format.date(stravaRemovedAt / 1000)),
                              systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !current.stravaTitle.isEmpty { LabeledContent("Strava", value: current.stravaTitle) }
                    HStack(spacing: 16) {
                        ViewOnStravaLink(stravaActivityId: current.stravaActivityId)
                        PoweredByStrava()
                    }
                    if current.stravaConflict {
                        Text(L10n.get("ios_strava_changed"))
                            .foregroundStyle(.red)
                    }
                }
                if current.conflict {
                    Text(L10n.get("data_conflict_title")).foregroundStyle(.red)
                }
            }
            if companion.diaryConnected {
                Section(L10n.get("activity_detail_diary_card_title")) {
                    Text(L10n.get("activity_detail_diary_card_intro")).font(.footnote).foregroundStyle(.secondary)
                    if current.diaryWritten {
                        // The workbook, as plain text: a tinted icon made it look like a link.
                        Label {
                            Text(companion.diaryName)
                        } icon: {
                            Image(systemName: "book.closed").foregroundStyle(.secondary)
                        }
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
        // Long-press copies a value (SPM, DPS, ...), as on Android.
        .textSelection(.enabled)
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

/// The overview, as Android's: the connections first (watch, Strava, diary, add), then the other
/// settings, each on a page of its own.
struct SettingsScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared
    @State private var query = ""

    private var diaryTitle: String {
        String(format: L10n.get("settings_tile_diary_named"), L10n.get("settings_diary_short_name"))
    }

    /// One page of the overview, with the texts on it for the search (a hit on any of them lists the page).
    private struct Page: Identifiable {
        let id: String
        let title: String
        let words: [String]
        let destination: AnyView
    }

    private var pages: [Page] {
        [
            Page(id: "watch", title: L10n.get("settings_tile_watch"),
                 words: ["ios_choose_watch", "settings_tile_watch"].map(L10n.get), destination: AnyView(SettingsWatchPage())),
            Page(id: "strava", title: String(format: L10n.get("settings_tile_repository_named"), "Strava"),
                 words: ["Strava", L10n.get("status_backfill_sync_now"), L10n.get("ios_pull_strava_7"), L10n.get("ios_disconnect_strava")],
                 destination: AnyView(SettingsStravaPage())),
            Page(id: "diary", title: diaryTitle,
                 words: ["ios_diary_auto", "status_ttb_round_switch", "status_ttb_compact_switch", "ios_diary_write_7", "connect_diary_title"].map(L10n.get),
                 destination: AnyView(SettingsDiaryPage())),
            Page(id: "sync", title: L10n.get("sync_mode_section_title"),
                 words: ["sync_mode_option_automated", "sync_mode_option_manual", "ios_last_sync"].map(L10n.get),
                 destination: AnyView(SettingsSyncPage())),
            Page(id: "app", title: L10n.get("settings_group_app"),
                 words: ["nickname_label", "settings_review_new_activities", "status_place_names_switch", "language_section_title"].map(L10n.get),
                 destination: AnyView(SettingsAppPage())),
            Page(id: "privacy", title: L10n.get("settings_page_privacy"),
                 words: ["status_download_my_data", "status_delete_my_data", "feedback_title"].map(L10n.get),
                 destination: AnyView(SettingsPrivacyPage())),
            Page(id: "logs", title: L10n.get("status_data_logs_heading"),
                 words: ["status_view_diary_log", "status_view_app_log", "ios_transfer_log", "status_view_strava_api_usage", "status_view_recording_boosts"].map(L10n.get),
                 destination: AnyView(SettingsLogsPage())),
            Page(id: "about", title: L10n.get("status_about_button"),
                 words: [], destination: AnyView(AboutScreen())),
        ]
    }

    private var hits: [Page] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return pages.filter { page in
            page.title.localizedCaseInsensitiveContains(q) || page.words.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if hits.isEmpty {
                        Text(L10n.get("settings_search_no_results")).foregroundStyle(.secondary)
                    }
                    ForEach(hits) { page in
                        NavigationLink(page.title) { page.destination }
                    }
                } else {
                    Section(L10n.get("status_connections_heading")) {
                        NavigationLink {
                            SettingsWatchPage()
                        } label: {
                            LabeledContent(L10n.get("settings_tile_watch"),
                                           value: watch.devices.first?.friendlyName ?? L10n.get("settings_value_none"))
                        }
                        NavigationLink {
                            SettingsStravaPage()
                        } label: {
                            LabeledContent(String(format: L10n.get("settings_tile_repository_named"), "Strava"),
                                           value: L10n.get(companion.stravaConnected ? "settings_value_connected" : "settings_value_not_connected"))
                        }
                        NavigationLink {
                            SettingsDiaryPage()
                        } label: {
                            LabeledContent(diaryTitle,
                                           value: companion.diaryConnected ? companion.diaryName : L10n.get("settings_value_not_connected"))
                        }
                        ForEach(companion.folderDestinations, id: \.id) { destination in
                            NavigationLink {
                                FolderDestinationPage(id: destination.id)
                            } label: {
                                LabeledContent(
                                    L10n.get(destination.format == "CSV_MONTHLY" ? "destination_format_csv" : "destination_format_json"),
                                    value: destination.name
                                )
                            }
                        }
                        NavigationLink(L10n.get("settings_add_connection")) { DiaryLocationsScreen() }
                    }
                    Section(L10n.get("settings_group_general")) {
                        NavigationLink(L10n.get("sync_mode_section_title")) { SettingsSyncPage() }
                        NavigationLink(L10n.get("settings_group_app")) { SettingsAppPage() }
                        NavigationLink(L10n.get("settings_page_privacy")) { SettingsPrivacyPage() }
                        NavigationLink(L10n.get("status_data_logs_heading")) { SettingsLogsPage() }
                    }
                    Section {
                        NavigationLink(L10n.get("status_about_button")) { AboutScreen() }
                        LabeledContent(L10n.get("ios_version"), value: Format.appVersion)
                    }
                }
            }
            .searchable(text: $query, prompt: L10n.get("settings_search_hint"))
            .navigationTitle(L10n.get("status_title"))
        }
    }
}

struct SettingsWatchPage: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared

    var body: some View {
        Form {
                Section(L10n.get("settings_tile_watch")) {
                    ForEach(watch.devices, id: \.uuid) { device in
                        LabeledContent(device.friendlyName ?? "?", value: watch.statuses[device.uuid] ?? "")
                    }
                    Button(L10n.get("ios_choose_watch")) { watch.chooseWatch() }
                    NavigationLink(L10n.get("settings_tile_watch")) { WatchSettingsScreen() }
                }
        }
        .navigationTitle(L10n.get("settings_tile_watch"))
    }
}

struct SettingsAppPage: View {
    @EnvironmentObject var companion: Companion
    @State private var nicknameDraft = ""
    @State private var languageChoice = AppLanguage.chosen
    /// A language picked while a watch could switch too: waits for "Both" / "Only the Companion".
    @State private var pendingLanguage: String?

    var body: some View {
        Form {
                Section {
                    Picker(L10n.get("language_section_title"), selection: $languageChoice) {
                        Text(String(format: L10n.get("language_option_system_with_language"),
                                    L10n.get("language_name_\(AppLanguage.system)"))).tag("")
                        ForEach(AppLanguage.supported, id: \.self) { code in
                            Text(L10n.get("language_name_\(code)")).tag(code)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if languageChoice != AppLanguage.atLaunch {
                        Text(L10n.get("ios_language_restart")).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(L10n.get("language_section_title"))
                }
                .onChange(of: languageChoice) { _, code in
                    guard code != AppLanguage.chosen else { return }
                    let effective = code.isEmpty ? AppLanguage.system : code
                    if companion.watchesForLanguage(effective).isEmpty {
                        AppLanguage.chosen = code
                    } else {
                        pendingLanguage = code
                    }
                }
                .alert(
                    L10n.get("language_offer_watch_title"),
                    isPresented: Binding(get: { pendingLanguage != nil }, set: { if !$0 { cancelLanguage() } }),
                    presenting: pendingLanguage
                ) { code in
                    Button(L10n.get("language_offer_both")) {
                        let effective = code.isEmpty ? AppLanguage.system : code
                        for watch in companion.watchesForLanguage(effective) { companion.setWatchLanguage(watch.deviceId, effective) }
                        AppLanguage.chosen = code
                        pendingLanguage = nil
                    }
                    Button(L10n.get("language_offer_only_companion")) {
                        AppLanguage.chosen = code
                        pendingLanguage = nil
                    }
                    Button(L10n.get("common_cancel"), role: .cancel) {}
                } message: { code in
                    let effective = code.isEmpty ? AppLanguage.system : code
                    Text(String(format: L10n.get("language_offer_watch_body"),
                                companion.watchesForLanguage(effective).map { $0.watchName }.joined(separator: ", "),
                                companion.languageNativeName(effective)))
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
                } header: {
                    Text(L10n.get("settings_group_app"))
                }
                .onAppear { nicknameDraft = companion.nickname }
                .onDisappear { if nicknameDraft != companion.nickname { companion.setNickname(nicknameDraft) } }
        }
        .navigationTitle(L10n.get("settings_group_app"))
    }

    /// The offer was closed without a choice: the picker goes back to the language in use.
    private func cancelLanguage() {
        pendingLanguage = nil
        languageChoice = AppLanguage.chosen
    }
}

struct SettingsSyncPage: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Form {
                Section {
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
                }
                if companion.syncing || !companion.syncLines.isEmpty || companion.lastSync != nil {
                    Section(L10n.get("ios_last_sync")) {
                        if companion.syncing { ProgressView() }
                        if let last = companion.lastSync {
                            Text(last.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        }
                        if companion.syncLines.isEmpty, !companion.syncing {
                            Text(L10n.get("ios_nothing_to_do")).foregroundStyle(.secondary)
                        }
                        ForEach(Array(companion.syncLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote)
                        }
                    }
                }
        }
        .navigationTitle(L10n.get("sync_mode_section_title"))
    }
}

struct SettingsStravaPage: View {
    @EnvironmentObject var companion: Companion
    @State private var confirmingStravaDisconnect = false

    var body: some View {
        Form {
                Section("Strava") {
                    if !companion.stravaConfigured {
                        Text(L10n.get("ios_no_strava_config")).foregroundStyle(.secondary)
                    } else if companion.stravaConnected {
                        Label(L10n.get("status_strava_connected_status"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(L10n.get("status_backfill_sync_now")) { Task { await companion.sync() } }
                            .disabled(companion.syncing)
                        Button(L10n.get("ios_pull_strava_7")) { Task { await companion.backfill(days: 7) } }
                            .disabled(companion.syncing)
                        Button(L10n.get("ios_disconnect_strava"), role: .destructive) { confirmingStravaDisconnect = true }
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
        }
        .navigationTitle("Strava")
        .disabled(companion.stravaBusy != nil)
        .overlay {
            // Connecting and disconnecting take a few seconds: say so, and block a second tap.
            if let text = companion.stravaBusy {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(text).multilineTextAlignment(.center)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(32)
            }
        }
    }
}

struct SettingsDiaryPage: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Form {
                Section(L10n.get("status_diary_label")) {
                    if companion.diaryConnected {
                        Label(String(format: L10n.get("connect_diary_connected_to"), companion.diaryName), systemImage: "book.closed")
                        if !companion.activeDiarySource.isEmpty {
                            Text(companion.activeDiarySource).font(.footnote).foregroundStyle(.secondary)
                        }
                        Text(L10n.get("ios_diary_auto_hint"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !companion.diaryIssue.isEmpty {
                            Text(L10n.get("status_diary_issue_title")).foregroundStyle(.red)
                            Text(companion.diaryIssue).font(.footnote).foregroundStyle(.secondary)
                        }
                        Toggle(L10n.get("ios_diary_auto"), isOn: Binding(
                            get: { companion.diarySettings.autoUpdate },
                            set: { companion.setDiaryAutoUpdate($0) }
                        ))
                        Toggle(L10n.get("status_ttb_round_switch"), isOn: Binding(
                            get: { companion.diarySettings.roundDurationUp },
                            set: { companion.setDiaryRoundDurationUp($0) }
                        ))
                        Toggle(L10n.get("status_ttb_compact_switch"), isOn: Binding(
                            get: { companion.diarySettings.compactDiary },
                            set: { companion.setDiaryCompact($0) }
                        ))
                        Button(L10n.get("ios_diary_write_7")) { Task { await companion.writeDiary(days: 7) } }
                            .disabled(companion.syncing)
                        // TEMPORARY, as on Android: remove a few versions after 0.9.93.
                        Text(L10n.get("settings_intro_compact_diary")).font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.get("status_compact_diary_heading")) { Task { await companion.compactDiary(days: 7) } }
                            .disabled(companion.syncing)
                    } else {
                        Text(L10n.get("ios_diary_connect_hint"))
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink(L10n.get("connect_diary_title")) { DiaryLocationsScreen() }
                    if companion.diaryBusy {
                        HStack { ProgressView(); Text(L10n.get("connect_diary_connecting")) }
                    }
                }
                .disabled(companion.diaryBusy)
        }
        .navigationTitle(L10n.get("status_diary_label"))
    }
}

struct SettingsLogsPage: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Form {
                Section(L10n.get("status_data_logs_heading")) {
                    NavigationLink(L10n.get("status_view_diary_log")) {
                        LogScreen(title: L10n.get("diary_work_log_title"), kind: .diary)
                    }
                    NavigationLink(L10n.get("status_view_app_log")) {
                        LogScreen(title: L10n.get("app_log_title"), kind: .app)
                    }
                    NavigationLink(L10n.get("ios_transfer_log")) {
                        LogScreen(title: L10n.get("ios_transfer_log"), kind: .transfer)
                    }
                    NavigationLink(L10n.get("status_view_strava_api_usage")) { StravaApiUsageScreen() }
                    NavigationLink(L10n.get("status_view_recording_boosts")) { RecordingBoostScreen() }
                    NavigationLink(L10n.get("ios_developer_log")) { DeveloperLogScreen() }
                }
        }
        .navigationTitle(L10n.get("status_data_logs_heading"))
    }
}

struct SettingsPrivacyPage: View {
    @EnvironmentObject var companion: Companion
    @State private var exportURL: URL?
    @State private var confirmingDeleteAll = false

    var body: some View {
        Form {
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
        }
        .onDisappear {
            companion.discardExport(exportURL)
            exportURL = nil
        }
        .navigationTitle(L10n.get("settings_page_privacy"))
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
    /// Lowercased Strava `sport_type` -> the text name of this app's own word for it, so a
    /// Strava-origin row never shows Strava's term (Android's WatchWording.STRAVA_SPORT_LABEL).
    private static let stravaSport: [String: String] = [
        "rollerski": "activity_detail_sport_option_rollski",
        "nordicski": "activity_detail_sport_option_langlauf",
        "inlineskate": "watch_preset_inlineSkating",
        "run": "watch_preset_running",
        "virtualrun": "watch_preset_running",
        "walk": "watch_preset_running",
        "trailrun": "watch_preset_trailrun",
        "ride": "watch_preset_cycling",
        "virtualride": "watch_preset_cycling",
        "gravelride": "watch_preset_cycling",
        "ebikeride": "watch_preset_cycling",
        "mountainbikeride": "watch_preset_mtb",
        "emountainbikeride": "watch_preset_mtb",
        "weighttraining": "watch_preset_strength",
        "crossfit": "watch_preset_strength",
        "workout": "watch_preset_training",
        "highintensityintervaltraining": "watch_preset_training",
        "swim": "watch_preset_swim",
        "standuppaddling": "watch_preset_sup",
    ]

    static func presetWord(_ preset: String) -> String {
        // A Strava row ("strava:<sport_type>"): Strava's raw term only when unknown.
        if preset.hasPrefix("strava:") {
            let sportType = String(preset.dropFirst("strava:".count))
            return stravaSport[sportType.lowercased()].map { L10n.get($0) } ?? sportType
        }
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

    /// The version for the server's `app_version` ("0.9.100+ios.33"): it accepts only letters,
    /// digits, ".", "+" and "-", and the "+ios" tells the reports apart from Android's.
    static var serverVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "0")+ios.\(info["CFBundleVersion"] as? String ?? "0")"
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

/// Strava's "Powered by Strava" logo (orange, horizontal; Strava's white one in dark mode, set in the asset), about 18 pt high.
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

/// Android's status banner: "All caught up" when nothing waits, else one line per open category.
struct SyncStatusCard: View {
    @EnvironmentObject var companion: Companion
    let status: SyncStatusView

    private var lines: [String] {
        var parts: [String] = []
        if status.pendingStrava > 0 { parts.append(String(format: L10n.get("sync_status_pending_strava"), status.pendingStrava)) }
        if status.pendingDiary > 0 { parts.append(String(format: L10n.get("sync_status_pending_diary"), status.pendingDiary)) }
        if status.pendingDocs > 0 { parts.append(String(format: L10n.get("sync_status_pending_docs"), status.pendingDocs)) }
        if status.stravaConflicts > 0 { parts.append(String(format: L10n.get("sync_status_pending_strava_conflicts"), status.stravaConflicts)) }
        if status.stravaUnavailable > 0 { parts.append(String(format: L10n.get("sync_status_strava_unavailable"), status.stravaUnavailable)) }
        if !status.stravaIssue.isEmpty {
            parts.append(status.stravaIssueStandalone
                         ? status.stravaIssue
                         : String(format: L10n.get("sync_status_strava_issue"), status.stravaIssue))
        }
        if !status.diaryIssue.isEmpty { parts.append(String(format: L10n.get("sync_status_diary_issue"), status.diaryIssue)) }
        return parts
    }

    private var detail: String {
        let checked = (companion.lastSync ?? Date()).formatted(date: .omitted, time: .shortened)
        switch (status.stravaConnected, status.diaryConnected) {
        case (true, true): return String(format: L10n.get("activity_list_up_to_date_detail_both"), checked)
        case (true, false): return String(format: L10n.get("activity_list_up_to_date_detail_strava"), checked)
        case (false, true): return String(format: L10n.get("activity_list_up_to_date_detail_diary"), checked)
        case (false, false): return L10n.get("activity_list_up_to_date_detail_none")
        }
    }

    var body: some View {
        if status.total == 0 {
            VStack(alignment: .leading, spacing: 4) {
                Label(companion.nickname.isEmpty
                      ? L10n.get("activity_list_up_to_date")
                      : String(format: L10n.get("activity_list_up_to_date_named"), companion.nickname),
                      systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                }
            }
        }
    }
}
