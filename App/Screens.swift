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
    /// Stage `nudge`: the reminder to move to the server, at most once in 20 hours.
    @AppStorage("serverNudgeShownAt") private var serverNudgeShownAt = 0.0
    @State private var showServerNudge = false
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
            // A new go-home request rebuilds the stack: every pushed screen, sheet and cover on it closes.
            ActivitiesScreen()
                .id(companion.goHomeRequest)
                .tabItem { Label(L10n.get("ios_tab_activities"), systemImage: "list.bullet") }
                .tag(0)
            TrendsScreen()
                .tabItem { Label(L10n.get("trends_tab_trends"), systemImage: "chart.bar.xaxis") }
                .tag(2)
            SettingsScreen()
                .id(companion.goHomeRequest)
                .tabItem { Label(L10n.get("status_title"), systemImage: "gearshape") }
                .tag(1)
        }
        // A tapped notification shows its activity on the first tab.
        .onChange(of: companion.openActivityId) { _, id in
            if id != nil { tab = 0 }
        }
        // A fresh Sensor Record (stored just now, or its notification tapped) shows its charts over any tab.
        .sheet(item: Binding(
            get: { companion.openSensorRecordId.map { OpenSensorRecord(id: $0) } },
            set: { companion.openSensorRecordId = $0?.id }
        )) { record in
            NavigationStack {
                SensorRecordView(burstId: record.id, showUpload: true)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.get("em_sheet_close")) { companion.openSensorRecordId = nil }
                        }
                    }
            }
            .environmentObject(companion)
        }
        // A tap on a screen's title: the activity list, also from the other tabs and the Sensor Record sheet.
        .onChange(of: companion.goHomeRequest) { _, _ in
            companion.openSensorRecordId = nil
            tab = 0
        }
        .onChange(of: companion.trendsRequest) { _, request in
            if request != nil { tab = 2 }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingScreen { showOnboarding = false }
                .environmentObject(companion)
        }
        .sheet(isPresented: $showServerNudge) {
            ServerNudgeSheet { showServerNudge = false }
                .environmentObject(companion)
        }
        .task {
            // Decided once at start, so connecting Strava inside the guide does not close it.
            if !onboardingDone && !companion.stravaConnected && !companion.diaryReceives && companion.activities.isEmpty {
                showOnboarding = true
            }
            onboardingDone = true
            // A local install past the guide is reminded to move while the stage is `nudge`.
            let now = Date().timeIntervalSince1970
            if !showOnboarding, !companion.demoOn, !companion.onServerConnection, now - serverNudgeShownAt >= 20 * 3600,
               await companion.serverMoveStage() == "nudge" {
                serverNudgeShownAt = now
                showServerNudge = true
            }
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
/// The Sensor Record the root view shows in a sheet ([Companion.openSensorRecordId]).
struct OpenSensorRecord: Identifiable {
    let id: String
}

struct ActivityRoute: Hashable {
    let id: String
    var target: ActivityTarget = .diary
    /// A technique or terrain picked on the Metrics screen.
    var pick: String?
}

/// The detail of the activity with [id]; a spinner until the list has loaded it.
struct ActivityRouteView: View {
    @EnvironmentObject var companion: Companion
    let id: String
    var target: ActivityTarget = .diary
    var pick: String?

    var body: some View {
        if let item = companion.activities.first(where: { $0.id == id }) {
            ActivityScreen(item: item, target: target, pick: pick)
        } else {
            ProgressView()
        }
    }
}

struct ActivitiesScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var adding = false
    /// The "+" choice (Android's sheet: record now, or enter a finished activity), the start and the live screen.
    @State private var choosing = false
    @State private var recordStart = false
    /// "Record on my watch": how to start Nordic Sports on the watch (the phone cannot open the watch app).
    @State private var watchHelp = false
    @State private var recordLive = false
    @State private var route: ActivityRoute?
    /// A Sensor Record opened from the live card; back returns to the card (Android: `burst/{id}` over the list).
    @State private var burstRoute: BurstRoute?
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

    /// The list's density (Android: the toggle in the status card); remembered across launches.
    @AppStorage("list_compact") private var compactList = false

    @ViewBuilder private func activityRow(_ item: ActivityItem) -> some View {
        let open: (ActivityTarget) -> Void = { route = ActivityRoute(id: item.id, target: $0) }
        if compactList { CompactActivityRow(item: item, onOpen: open) } else { ActivityCard(item: item, stravaConnected: companion.stravaConnected, diaryConnected: companion.diaryReceives, onOpen: open) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if companion.activities.isEmpty && companion.liveActivities.isEmpty && companion.crashReports.isEmpty {
                    VStack(spacing: 0) {
                    if companion.showSetupTip { SetupTips().padding() }
                    ContentUnavailableView {
                        Label(companion.nickname.isEmpty
                              ? L10n.get("activity_list_empty_no_activities")
                              : String(format: L10n.get("activity_list_empty_no_activities_named"), companion.nickname),
                              systemImage: "applewatch")
                    } description: {
                        Text(L10n.get("activity_list_empty_hint"))
                    }
                    }
                } else {
                    let open = openItems
                    List {
                        if let status = companion.syncStatus {
                            let review = open
                            Section {
                                SyncStatusCard(status: status, toReview: review) { id in route = ActivityRoute(id: id, target: .diary) }
                                    .padding(.trailing, 40)
                                    .overlay(alignment: .trailing) {
                                        Button { compactList.toggle() } label: {
                                            Image(systemName: compactList ? "rectangle.grid.1x2" : "list.bullet")
                                                .frame(width: 36, height: 36)
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel(L10n.get(compactList ? "list_density_full" : "list_density_compact"))
                                    }
                            }
                                .listRowBackground(SyncStatusCard.tone(status, reviewing: !review.isEmpty).container)
                        }
                        // A recording on this phone (running, or left unfinished by a closed app).
                        PhoneRecordingSection(phone: companion.phone) { recordLive = true }
                        // What runs now, then the decisions asked of the athlete (one Boost card at a time).
                        if !companion.liveActivities.isEmpty || !companion.crashReports.isEmpty
                            || !companion.boostReminders.isEmpty {
                            Section {
                                ForEach(companion.liveActivities, id: \.deviceId) { live in
                                    WatchLiveCard(live: live) { burstRoute = BurstRoute(id: $0) }
                                }
                                if let report = companion.crashReports.first {
                                    WatchCrashCard(report: report)
                                }
                                if let reminder = companion.boostReminders.first {
                                    BoostReminderCard(reminder: reminder, more: companion.boostReminders.count - 1)
                                }
                            }
                        }
                        // Optional setup hints: slim, neutral, one at a time, dismissed for good.
                        if companion.showSetupTip {
                            Section { SetupTips() }
                        }
                        // As Android: activities still to review on top, oldest first (the order the
                        // diary fills a day's slots in), then the rest under "Done".
                        let openIds = Set(open.map { $0.id })
                        let finished = justDone.compactMap { id in companion.activities.first { $0.id == id } }
                        let finishedIds = Set(finished.map { $0.id })
                        let rest = companion.activities.filter { !openIds.contains($0.id) && !finishedIds.contains($0.id) }
                        if !open.isEmpty {
                            Section(L10n.get("activity_list_section_open")) {
                                ForEach(open, id: \.id) { item in
                                    activityRow(item)
                                        .listRowBackground(CardTone.blue.container)
                                }
                            }
                        }
                        Section(open.isEmpty && finished.isEmpty ? "" : L10n.get("activity_list_section_done")) {
                            ForEach(finished, id: \.id) { item in
                                activityRow(item)
                                    .listRowBackground(CardTone.blue.container)
                            }
                            ForEach(rest, id: \.id) { item in
                                activityRow(item)
                                    .listRowBackground(CardTone.blue.container)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.get("ios_tab_activities"))
            .navigationDestination(item: $route) { route in
                ActivityRouteView(id: route.id, target: route.target, pick: route.pick)
            }
            .navigationDestination(item: $burstRoute) { route in
                SensorRecordView(burstId: route.id, showUpload: true)
            }
            .onChange(of: companion.openActivityId, initial: true) { _, id in
                guard let id else { return }
                let pick = companion.openPick
                route = ActivityRoute(id: id, target: companion.openActivityTarget ?? (pick == nil ? .diary : .data), pick: pick)
                companion.openActivityId = nil
                companion.openPick = nil
                companion.openActivityTarget = nil
            }
            .onChange(of: openItems.map { $0.id }, initial: true) { _, ids in trackOpen(Set(ids)) }
            .onAppear { companion.refreshWatchCards() }
            .refreshable {
                justDone = []
                companion.refreshWatchCards()
                await companion.sync()
            }
            .sheet(isPresented: $adding) { AddActivitySheet().environmentObject(companion) }
            // Watch and phone as twins, then the manual entry (Android's "+" menu, same wording).
            .confirmationDialog(L10n.get("add_activity_title"), isPresented: $choosing, titleVisibility: .visible) {
                Button(L10n.get("add_choice_watch")) { watchHelp = true }
                Button(L10n.get("add_choice_record")) { recordStart = true }
                Button(L10n.get("add_choice_enter")) { adding = true }
                Button(L10n.get("common_cancel"), role: .cancel) {}
            }
            .sheet(isPresented: $watchHelp) { WatchRecordStartView().environmentObject(companion) }
            .sheet(isPresented: $recordStart) {
                PhoneRecordStartScreen(phone: companion.phone) {
                    // The live screen opens once the start sheet is gone.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recordLive = true }
                }
                .environmentObject(companion)
            }
            .fullScreenCover(isPresented: $recordLive) {
                PhoneRecordingLiveScreen(phone: companion.phone) { id in route = ActivityRoute(id: id) }
                    .environmentObject(companion)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        // A recording runs already: back to it.
                        if companion.phone.view != nil { recordLive = true } else { choosing = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(L10n.get("add_activity_title"))
                }
                // How recently a watch talked to the phone (Android: left of the settings button); tap for the watch page.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsWatchPage() } label: { WatchContactMark() }
                }
                // Android's chat icon next to settings: feedback one tap away, not only under Settings › Privacy.
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        FeedbackHubScreen()
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

/// A Sensor Record to open from the live card.
struct BurstRoute: Identifiable, Hashable {
    let id: String
}

/// A recording on a watch (its `activityStart`), as Android's card: which watch, activity
/// and training type, since when and how long, the start position, and a line per Sensor Record that opens it.
struct WatchLiveCard: View {
    @EnvironmentObject var companion: Companion
    let live: LiveActivityView
    var onOpenBurst: (String) -> Void = { _ in }
    /// The Sensor Records of this recording so far, newest first (id and capture time only).
    @State private var bursts: [BurstRef] = []
    @State private var showRecording = false
    /// Drives the breathing border and the recording dot while the watch records.
    @State private var pulse = false
    private static let liveRed = Color(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
    /// Recordings whose screen opened by itself already (once per recording and app run, as on Android).
    private static var autoOpened = Set<Int64>()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if !live.discarded {
                        Circle().fill(Self.liveRed).frame(width: 9, height: 9).opacity(pulse ? 0.35 : 1)
                    }
                    Text(String(format: L10n.get(live.discarded ? "watch_live_discarded_title" : "watch_live_title"), live.watchName))
                        .font(live.discarded ? .caption : .caption.bold())
                        .foregroundStyle(live.discarded ? Color.secondary : CardTone.red.title)
                }
                Text(live.title).font(.headline)
                let started = Date(timeIntervalSince1970: TimeInterval(live.startEpochSec)).formatted(date: .omitted, time: .shortened)
                if live.discarded {
                    Text(String(format: L10n.get("watch_live_discarded_detail"), started)).font(.subheadline)
                } else {
                    let running = max(0, (live.discardedEpochSec > 0 ? Int(live.discardedEpochSec) : Int(context.date.timeIntervalSince1970)) - Int(live.startEpochSec))
                    Text(String(format: L10n.get("watch_live_since"), started, Format.duration(Int32(clamping: running)))).font(.subheadline)
                }
                if live.hasPosition {
                    Text(String(format: "%.4f, %.4f", live.lat, live.lon)).font(.footnote).foregroundStyle(.secondary)
                }
                // One line per Sensor Record: a tap opens its charts directly, back returns to this card.
                ForEach(bursts, id: \.id) { burst in
                    let time = Date(timeIntervalSince1970: TimeInterval(burst.burstId)).formatted(date: .omitted, time: .shortened)
                    Button { onOpenBurst(burst.id) } label: {
                        Label(String(format: L10n.get("burst_live_item"), time), systemImage: "chart.xyaxis.line")
                            .font(.subheadline).lineLimit(1)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // A tap opens the Recording screen (live values and the track with instant mode), as on Android.
            .onTapGesture { if !live.discarded { showRecording = true } }
        }
        // While the watch records the card stands out from the blue activity rows (Android's live card): recording
        // red, a border that breathes and a pulsing dot by the title. A discarded recording stays grey.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12)
                .fill(live.discarded ? CardTone.grey.container : CardTone.red.container)
                .overlay {
                    if !live.discarded {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(pulse ? CardTone.red.border : Self.liveRed, lineWidth: 2.5)
                    }
                }
        )
        // A recording that just started opens its screen by itself, once.
        .onAppear {
            if !live.discarded {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
            let age = Int64(Date().timeIntervalSince1970) - live.startEpochSec
            if !live.discarded && age < 120 && !Self.autoOpened.contains(live.startEpochSec) {
                Self.autoOpened.insert(live.startEpochSec)
                showRecording = true
            }
        }
        .fullScreenCover(isPresented: $showRecording) {
            RecordingScreen(startEpochSec: live.startEpochSec).environmentObject(companion)
        }
        // The Sensor Records arrive during the recording: look again every 10 s (ids only, no sensor data).
        .task(id: live.startEpochSec) {
            while !Task.isCancelled {
                if let refs = try? await companion.core.recordingBoostRefsSince(sinceEpochSec: live.startEpochSec) {
                    bursts = refs
                }
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }
}

/// The Recording Boost bursts of one activity: when each was captured and the CSV file it was saved to
/// (name and folder in the Files app). Labelling stays under Settings > Data logs.
struct ActivityBoostsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let boosts: [RecordingBoostView]

    /// The CSV in the app's Documents folder (`Companion.exportBoostFiles`), nil while it is not there.
    private static func fileURL(_ burst: RecordingBoostView) -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(Companion.boostFolder, isDirectory: true).appendingPathComponent(burst.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        NavigationStack {
            List(boosts, id: \.id) { burst in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.date(burst.burstId)).font(.subheadline.bold())
                    if burst.fileName.isEmpty {
                        Text(L10n.get("recording_boost_list_file_missing")).font(.footnote).foregroundStyle(.red)
                    } else {
                        Text(String(format: L10n.get("recording_boost_list_file_name"), burst.fileName))
                            .font(.system(.footnote, design: .monospaced))
                        Text(String(format: L10n.get("recording_boost_list_file_folder"), burst.location))
                            .font(.system(.footnote, design: .monospaced))
                        // Android's "Open file": the share sheet hands the CSV to another app or Files.
                        if let url = Self.fileURL(burst) {
                            ShareLink(item: url) {
                                Label(L10n.get("recording_boost_list_open_file"), systemImage: "square.and.arrow.up")
                            }
                            .font(.footnote)
                        }
                    }
                }
            }
            .homeTitle(L10n.get("activity_detail_boosts_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("activity_detail_boosts_close")) { dismiss() }
                }
            }
        }
    }
}

/// The Connect IQ Store listing as a tappable card (Android's `WatchStoreCard`): the watch app's icon, name, line, arrow.
struct WatchStoreCard: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Button { companion.openWatchStore() } label: {
            HStack(spacing: 12) {
                // The watch app's store icon (the skater with "WATCH").
                Image("WatchStoreIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.get("onboarding_guide_watch_store_name")).font(.headline)
                    Text(L10n.get("onboarding_guide_watch_store_sub")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\u{2197}").font(.title3).foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Send the Recording Boost files of this activity?": Choose files opens the feedback form with the
/// activity's files chosen; Discard removes the card for good (the files stay on the phone). Neither sends anything.
struct BoostReminderCard: View {
    @EnvironmentObject var companion: Companion
    let reminder: FeedbackBoostReminderView
    /// How many other activities with Boost files wait behind this one.
    var more: Int = 0
    @State private var openFeedback = false
    @State private var expanded = false

    var body: some View {
        // Compact: the explanation shows two lines until tapped, the date sits in the button row (as on Android).
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.get("feedback_boost_reminder_title")).font(.headline)
            Text(String(format: L10n.get("feedback_boost_reminder_body"), reminder.title, Int(reminder.fileCount)))
                .font(.footnote)
                .lineLimit(expanded ? nil : 2)
                .onTapGesture { withAnimation { expanded.toggle() } }
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    if reminder.activityStartEpochSec > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(reminder.activityStartEpochSec)).formatted(date: .abbreviated, time: .shortened))
                    }
                    if more > 0 {
                        Text(String(format: L10n.get("home_more_waiting"), more))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(L10n.get("feedback_boost_reminder_discard")) { companion.declineBoostReminder(reminder.activityId) }
                    .buttonStyle(.borderless)
                Button(L10n.get("feedback_boost_reminder_upload")) { openFeedback = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(CardTone.blue.container)
        .navigationDestination(isPresented: $openFeedback) {
            FeedbackScreen(startCategory: "boost", preselectActivityId: reminder.activityId)
        }
    }
}

/// One optional setup hint on the activity list: a slim neutral row (icon, title, one line), tapping it opens
/// the target, the cross dismisses it for good (Android's `SetupTipRow`).
struct SetupTipCard<Icon: View>: View {
    let title: String
    let detail: String
    let action: () -> Void
    let dismiss: () -> Void
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    icon()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.bold())
                        Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.get("watch_reminder_close"))
        }
        .listRowBackground(CardTone.grey.container)
    }
}

/// The setup tip to show: the watch first, else the diary (one at a time).
struct SetupTips: View {
    @EnvironmentObject var companion: Companion
    @State private var openDiary = false

    var body: some View {
        if companion.showWatchTip {
            SetupTipCard(
                title: L10n.get("watch_reminder_title"),
                detail: L10n.get("watch_reminder_body"),
                action: { companion.openWatchStore() },
                dismiss: { companion.dismissWatchReminder() }
            ) {
                Image("WatchStoreIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else if companion.showDiaryTip {
            SetupTipCard(
                title: L10n.get("diary_tip_title"),
                detail: L10n.get("diary_tip_body"),
                action: { openDiary = true },
                dismiss: { companion.dismissDiaryTip() }
            ) {
                Image(systemName: "calendar")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
            }
            .navigationDestination(isPresented: $openDiary) { DiaryLocationsScreen() }
        }
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
            Text(L10n.get(report.startError.isEmpty ? "watch_crash_title" : "watch_start_error_title")).font(.headline)
            let at = Date(timeIntervalSince1970: TimeInterval(report.lastSignEpochSec)).formatted(date: .omitted, time: .shortened)
            Text(!report.startError.isEmpty
                 ? String(format: L10n.get("watch_start_error_detail"), report.watchName, at)
                 : report.rebooted
                 ? String(format: L10n.get("watch_crash_detail_rebooted"), report.watchName, at)
                 : String(format: L10n.get("watch_crash_detail"), report.watchName, at, report.screen))
                .font(.footnote)
            HStack {
                Spacer()
                Button(L10n.get("watch_crash_dismiss")) { companion.dismissCrashReport(report.id) }
                    .buttonStyle(.borderless)
                Button(L10n.get(report.startError.isEmpty ? "watch_crash_review" : "watch_start_error_report")) { reviewing = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(CardTone.red.container)
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
                if item.isDemo {
                    Text(L10n.get("demo_badge"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2), in: Capsule())
                }
                switch item.source {
                case "watch": Image(systemName: "applewatch").foregroundStyle(.primary)
                case "phone": Image(systemName: "iphone").foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.get("activity_source_phone_long"))
                case "manual": Image(systemName: "pencil").foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.get("activity_source_manual_long"))
                default: EmptyView()
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
    var tint: Color = .green

    /// Android's colour code: Watch dark blue, Strava orange, diary yellow (lighter on dark backgrounds).
    static let watch = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 108 / 255, green: 142 / 255, blue: 232 / 255, alpha: 1)
        : UIColor(red: 13 / 255, green: 43 / 255, blue: 107 / 255, alpha: 1) })
    static let strava = Color(red: 252 / 255, green: 76 / 255, blue: 2 / 255)
    static let diary = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 213 / 255, blue: 79 / 255, alpha: 1)
        : UIColor(red: 217 / 255, green: 164 / 255, blue: 0, alpha: 1) })

    var body: some View {
        Label(name, systemImage: on ? "checkmark.circle.fill" : "circle")
            .font(.subheadline)
            .foregroundStyle(on ? tint : Color.secondary)
    }
}

struct ActivityDetailScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let item: ActivityItem
    @State private var tab: EntryTab
    @State private var confirmingDelete = false
    // A delete takes a few seconds (diary, files): a busy overlay says so meanwhile (Android: DeletingOverlay).
    @State private var deleting = false
    @State private var editing = false
    @State private var stravaRemovedAt: Int64 = 0
    @State private var boosts: [RecordingBoostView] = []
    @State private var showBoosts = false
    @State private var conflictDetail: StravaTitleConflict?
    @State private var showConflict = false
    /// The stored track (Instant Mode) and its map's choices; nil without a track (Android `ActivityTrackCard`).
    @State private var track: LiveFeedView?
    @StateObject private var mapChoices = LiveMapChoices()
    @State private var mapFull = false
    /// The stored weather (start, end), empty while there is none (Out there tab).
    @State private var weather: [WeatherReading] = []

    init(item: ActivityItem, initialTab: EntryTab = .diary) {
        self.item = item
        _tab = State(initialValue: initialTab)
    }

    /// The row as the list has it now, so a push shows its result here too.
    private var current: ActivityItem { companion.activities.first { $0.id == item.id } ?? item }

    /// The Strava tab exists when the activity has a Strava link, a Strava problem or a preview to send.
    private var showStravaTab: Bool {
        !current.stravaActivityId.isEmpty || current.stravaConflict || current.stravaUnavailable || current.stravaPreview != nil
    }

    private var onStravaTab: Bool { showStravaTab && tab == .strava }

    /// The Diary tab (also where a Strava target lands when there is no Strava tab).
    private var onDiaryTab: Bool { tab == .diary || (tab == .strava && !showStravaTab) }

    private var onOutThereTab: Bool { tab == .outThere }

    /// Snow only for cross-country skiing on snow, or when a classification is stored (Android `showSnow`).
    private var showSnow: Bool {
        current.sportArt == SportArt.langlauf || !current.snowAge.isEmpty || !current.snowGrain.isEmpty
            || !current.snowMoisture.isEmpty || !current.snowTempText.isEmpty
    }

    var body: some View {
        Form {
            // The sync marks and the demo declaration are in the top card of ActivityScreen. The tabs (Android
            // `EntryTab`): Diary, Out there, and Strava while the activity has something there.
            Section {
                Picker("", selection: $tab) {
                    Text(L10n.get("sync_presence_destination_diary")).tag(EntryTab.diary)
                    Text(L10n.get("activity_detail_section_out_there")).tag(EntryTab.outThere)
                    if showStravaTab { Text("Strava").tag(EntryTab.strava) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            }
            .listRowBackground(Color.clear)
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
                .listRowBackground(CardTone.yellow.container)
            }
            // The Recording Boost captures of this activity: a count, a tap lists them with their CSV files.
            if !boosts.isEmpty {
                Section {
                    Button(String(format: L10n.get("activity_detail_boosts"), boosts.count)) { showBoosts = true }
                }
            }
            if onOutThereTab {
                // The stored track: the same map as the live recording, framed on the whole track; export in the header.
                if let track {
                    Section {
                        LiveTrackMap(points: TrackPoints(track), automatic: track.baseMap, choices: mapChoices, onExpand: { mapFull = true })
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        HStack {
                            Text(L10n.get("activity_detail_section_map"))
                            Spacer()
                            TrackExportMenu(item: current)
                        }
                    }
                }
                if !weather.isEmpty { WeatherSection(readings: weather) }
                if showSnow { SnowSection(item: current) }
                if track == nil && weather.isEmpty && !showSnow {
                    Text(L10n.get("out_there_empty")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if onDiaryTab {
            Section(L10n.get("activity_detail_training_type_label")) {
                LabeledContent(L10n.get("activity_detail_sport_label"), value: Format.presetWord(current.preset))
                if !current.trainingType.isEmpty, current.trainingType != "unknown" {
                    LabeledContent(L10n.get("ios_intensity"), value: Format.trainingTypeWord(current.trainingType))
                }
                if current.rpe > 0 { LabeledContent(L10n.get("activity_detail_rpe_label"), value: "\(current.rpe)") }
                if current.feeling > 0 { LabeledContent(L10n.get("activity_detail_feeling_label"), value: "\(current.feeling)") }
            }
            .listRowBackground(CardTone.green.container)
            let zones = current.hrZonePercents.map { $0.floatValue }
            if zones.contains(where: { $0 > 0 }) {
                Section(L10n.get("ios_hr_zones")) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { index, percent in
                        HStack {
                            // The zone with the athlete's range under it, when the watch sent the limits.
                            VStack(alignment: .leading, spacing: 0) {
                                Text(String(format: L10n.get("ios_zone_n"), index + 1))
                                if let range = HrZoneBounds.shared.rangeText(bounds: current.hrZoneBounds, zone: Int32(index + 1)) {
                                    Text("\(range) bpm").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(width: 90, alignment: .leading)
                            ProgressView(value: Double(percent), total: 100)
                            Text("\(Int(percent.rounded())) %").frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
            }
            // What goes to Strava (title, sport type, description), built by the shared code from the
            // same blocks the write uses (StravaWritePreview), so it is clear before anything is sent.
            // An activity recorded elsewhere has no preview (the app never changes it on Strava): say so (Android
            // `activity_detail_strava_imported_*`).
            if onStravaTab && !current.appRecorded {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.get("activity_detail_strava_imported_title")).font(.headline)
                        Text(L10n.get("activity_detail_strava_imported_body")).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(SyncChip.strava.opacity(0.10))
            }
            if onStravaTab, let preview = current.stravaPreview {
                Section {
                    if !preview.title.isEmpty {
                        LabeledContent(L10n.get("activity_detail_strava_preview_title"), value: preview.title)
                    }
                    if !preview.sportType.isEmpty {
                        LabeledContent(L10n.get("activity_detail_strava_preview_sport_type"), value: preview.sportType)
                    }
                    if !preview.description_.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.get("activity_detail_strava_preview_description"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(preview.description_)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text(L10n.get("activity_detail_strava_preview_heading"))
                } footer: {
                    Text(L10n.get("activity_detail_strava_preview_note"))
                }
            }
            if onStravaTab || (!showStravaTab && onDiaryTab) {
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
                        Button(L10n.get("main_strava_conflict_dialog_title")) {
                            Task {
                                conflictDetail = await companion.stravaConflict(of: item.id)
                                showConflict = conflictDetail != nil
                            }
                        }
                    }
                    if current.stravaUnavailable {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.get("activity_detail_unavailable_title")).font(.subheadline.bold()).foregroundStyle(.orange)
                            Text(L10n.get("activity_detail_unavailable_body")).font(.footnote)
                            Button(L10n.get("activity_detail_retry_button")) {
                                Task { await companion.retryStravaAvailability(item.id) }
                            }
                            .buttonStyle(.borderless)
                            .disabled(companion.syncing)
                        }
                    }
                }
                if current.conflict {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.get("data_conflict_title")).font(.subheadline.bold()).foregroundStyle(.red)
                        Text(L10n.get(current.conflictMessageKey)).font(.footnote)
                        Button(L10n.get("data_conflict_dismiss")) {
                            Task { await companion.dismissDataConflict(item.id) }
                        }
                            .buttonStyle(.borderless)
                    }
                }
            }
            }
            if companion.diaryConnected, onDiaryTab {
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
                deleting = true
                Task {
                    if await companion.deleteActivity(item.id) { dismiss() } else { deleting = false }
                }
            }
        } message: {
            Text(L10n.get("activity_detail_delete_confirm_body")
                + (item.stravaActivityId.isEmpty ? "" : "\n\n" + L10n.get("activity_detail_delete_confirm_strava_note"))
                + (current.diaryWritten ? "\n\n" + L10n.get("activity_detail_delete_confirm_diary_note") : ""))
        }
        // Long-press copies a value (SPM, DPS, ...), as on Android.
        .textSelection(.enabled)
        .overlay {
            if deleting { BusyOverlayView(text: L10n.get("activity_detail_deleting")) }

        }
        .navigationBarBackButtonHidden(deleting)
        // Denser than the default list: less height per row and between the sections (Android: tighter Entry cards).
        .environment(\.defaultMinListRowHeight, 34)
        .listSectionSpacing(.compact)
        // No grouped top margin: the tabs sit right under the mode switch.
        .contentMargins(.top, 4, for: .scrollContent)
        .homeTitle(L10n.get("card_lane_entry"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = true } label: { Image(systemName: "pencil") }
            }
        }
        .sheet(isPresented: $editing) { EditActivitySheet(item: current).environmentObject(companion) }
        .task(id: current.stravaActivityId) { stravaRemovedAt = await companion.stravaDataRemovedAt(item.id) }
        .task(id: item.id) { boosts = await companion.recordingBoosts(of: item.id) }
        .task(id: item.id) { track = await companion.activityTrack(of: item) }
        .task(id: item.id) { weather = await companion.activityWeather(of: item) }
        .fullScreenCover(isPresented: $mapFull) {
            if let track {
                ZStack(alignment: .bottomTrailing) {
                    LiveTrackMap(points: TrackPoints(track), automatic: track.baseMap, choices: mapChoices, fullScreen: true)
                    Button(L10n.get("em_sheet_close")) { mapFull = false }
                        .buttonStyle(.borderedProminent)
                        .padding()
                }
            }
        }
        .sheet(isPresented: $showBoosts) { ActivityBoostsSheet(boosts: boosts) }
        .alert(L10n.get("main_strava_conflict_dialog_title"), isPresented: $showConflict, presenting: conflictDetail) { _ in
            Button(L10n.get("main_strava_conflict_overwrite")) { Task { await companion.overwriteStrava(item.id) } }
            Button(L10n.get("main_strava_conflict_keep_strava")) { Task { await companion.keepStravaVersion(item.id) } }
            Button(L10n.get("common_cancel"), role: .cancel) {}
        } message: { c in
            Text(L10n.get("main_strava_conflict_dialog_body") + "\n\n"
                 + String(format: L10n.get("main_strava_conflict_current_format"), c.currentName, c.currentType) + "\n"
                 + String(format: L10n.get("main_strava_conflict_proposed_format"), c.proposedName, c.proposedType))
        }
    }
}

// MARK: - Settings

/// The overview, as Android's: the connections first (watch, Strava, diary, add), then the other
/// settings, each on a page of its own.
struct SettingsScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var watch = WatchLinkSpike.shared
    @ObservedObject private var contact = WatchContact.shared
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
                 words: ["Strava", L10n.get("status_backfill_sync_now"), L10n.get("ios_pull_strava_7"), L10n.get("ios_disconnect_strava"),
                         L10n.get("status_strava_update_my_activities"), L10n.get("status_strava_include_other_devices")],
                 destination: AnyView(SettingsStravaPage())),
            Page(id: "diary", title: diaryTitle,
                 words: ["ios_diary_auto", "status_ttb_round_switch", "status_ttb_compact_switch", "ios_diary_write_7", "connect_diary_title"].map(L10n.get),
                 destination: AnyView(SettingsDiaryPage())),
            Page(id: "sync", title: L10n.get("sync_mode_section_title"),
                 words: ["sync_mode_option_automated", "sync_mode_option_manual", "ios_last_sync"].map(L10n.get),
                 destination: AnyView(SettingsSyncPage())),
            Page(id: "app", title: L10n.get("settings_group_app"),
                 words: ["nickname_label", "settings_review_new_activities", "status_place_names_switch", "language_section_title", "theme_section_title"].map(L10n.get),
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
                            // The name and, live, connected or when the watch last talked to the phone.
                            LabeledContent(L10n.get("settings_tile_watch"),
                                           value: [watch.devices.first?.friendlyName ?? L10n.get("settings_value_none"),
                                                   contact.text(watch.devices.first.map { WatchLinkSpike.deviceId($0) })]
                                               .compactMap { $0 }.joined(separator: " · "))
                                .settingsIcon(.watch, connected: watch.devices.first != nil)
                        }
                        NavigationLink {
                            SettingsStravaPage()
                        } label: {
                            LabeledContent(String(format: L10n.get("settings_tile_repository_named"), "Strava"),
                                           value: L10n.get(companion.stravaConnected ? "settings_value_connected" : "settings_value_not_connected"))
                                .settingsIcon(.strava, connected: companion.stravaConnected)
                        }
                        NavigationLink {
                            SettingsDiaryPage()
                        } label: {
                            LabeledContent(diaryTitle,
                                           value: companion.diaryConnected ? companion.diaryName : L10n.get("settings_value_not_connected"))
                                .settingsIcon(.diary, connected: companion.diaryConnected)
                        }
                        ForEach(companion.folderDestinations, id: \.id) { destination in
                            NavigationLink {
                                FolderDestinationPage(id: destination.id)
                            } label: {
                                LabeledContent(
                                    L10n.get(destination.format == "CSV_MONTHLY" ? "destination_format_csv" : "destination_format_json"),
                                    value: destination.name
                                )
                                .settingsIcon(.files, connected: destination.enabled && destination.issue.isEmpty)
                            }
                        }
                        NavigationLink(L10n.get("settings_add_connection")) { DiaryLocationsScreen() }
                    }
                    Section(L10n.get("settings_group_general")) {
                        NavigationLink { SettingsSyncPage() } label: { Text(L10n.get("sync_mode_section_title")).settingsIcon(.sync) }
                        NavigationLink { SettingsAppPage() } label: { Text(L10n.get("settings_group_app")).settingsIcon(.app) }
                        NavigationLink { SettingsPrivacyPage() } label: { Text(L10n.get("settings_page_privacy")).settingsIcon(.privacy) }
                        NavigationLink { SettingsLogsPage() } label: { Text(L10n.get("status_data_logs_heading")).settingsIcon(.logs) }
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
        .homeTitle(L10n.get("settings_tile_watch"))
    }
}

struct SettingsAppPage: View {
    @EnvironmentObject var companion: Companion
    @State private var nicknameDraft = ""
    @State private var languageChoice = AppLanguage.chosen
    /// A language picked while a watch could switch too: waits for "Both" / "Only the Companion".
    @State private var pendingLanguage: String?
    /// "" follows the system, else "light" / "dark"; read by the app's root (`preferredColorScheme`).
    @AppStorage("themeChoice") private var themeChoice = ""

    var body: some View {
        Form {
                Section {
                    Picker(L10n.get("theme_section_title"), selection: $themeChoice) {
                        Text(L10n.get("theme_option_system_default")).tag("")
                        Text(L10n.get("theme_option_light")).tag("light")
                        Text(L10n.get("theme_option_dark")).tag("dark")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(L10n.get("theme_section_title"))
                }
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
                } header: {
                    Text(L10n.get("language_section_title"))
                }
                .onChange(of: languageChoice) { _, code in
                    guard code != AppLanguage.chosen else { return }
                    let effective = code.isEmpty ? AppLanguage.system : code
                    if companion.watchesForLanguage(effective).isEmpty {
                        companion.chooseAppLanguage(code)
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
                        pendingLanguage = nil
                        companion.chooseAppLanguage(code)
                    }
                    Button(L10n.get("language_offer_only_companion")) {
                        pendingLanguage = nil
                        companion.chooseAppLanguage(code)
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
                    Toggle(L10n.get("settings_review_imported_activities"), isOn: Binding(
                        get: { companion.reviewImportedActivities },
                        set: { companion.setReviewImportedActivities($0) }
                    ))
                    Text(L10n.get("settings_review_imported_activities_description"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle(L10n.get("status_place_names_switch"), isOn: Binding(
                        get: { companion.placeNamesEnabled },
                        set: { companion.setPlaceNamesEnabled($0) }
                    ))
                    Text(L10n.get("status_place_names_body")).font(.footnote).foregroundStyle(.secondary)
                    // PRIVACY-SYNC: "Weather for activities" (shared WeatherSettingsStore, default on): off, no weather lookup leaves the phone. Changing this? Re-check the Companion's design/privacy-notice-sync.md.
                    Toggle(L10n.get("status_weather_switch"), isOn: Binding(
                        get: { companion.weatherEnabled },
                        set: { companion.setWeatherEnabled($0) }
                    ))
                    Text(L10n.get("status_weather_body")).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(L10n.get("settings_group_app"))
                }
                .onAppear { nicknameDraft = companion.nickname }
                Section {
                    Toggle(L10n.get("demo_switch"), isOn: Binding(
                        get: { companion.demoOn },
                        set: { on in Task { if on { await companion.loadDemoData() } else { await companion.removeDemoData() } } }
                    ))
                    if companion.demoOn {
                        Button(L10n.get("demo_reload")) { Task { await companion.loadDemoData() } }
                    }
                } header: {
                    Text(L10n.get("demo_section_title"))
                } footer: {
                    Text(L10n.get("demo_section_body"))
                }
                .onDisappear { if nicknameDraft != companion.nickname { companion.setNickname(nicknameDraft) } }
        }
        .homeTitle(L10n.get("settings_group_app"))
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
        .homeTitle(L10n.get("sync_mode_section_title"))
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
                        // The Strava mark in orange says "connected" (Android: the same, instead of the old cable icon).
                        Label {
                            Text(L10n.get("status_strava_connected_status"))
                        } icon: {
                            SettingsRowIcon(kind: .strava, connected: true)
                        }
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
                        // The grey mark says "not connected", next to Strava's own Connect button.
                        HStack(spacing: 12) {
                            SettingsRowIcon(kind: .strava, connected: false)
                            Spacer()
                            StravaConnectButton { companion.connectStrava() }
                        }
                    }
                    if companion.stravaConfigured { PoweredByStrava() }
                }
                if companion.stravaConnected {
                    Section {
                        Toggle(L10n.get("status_strava_update_my_activities"), isOn: Binding(
                            get: { companion.stravaUpdateMyActivities },
                            set: { companion.setStravaUpdateMyActivities($0) }
                        ))
                        Text(L10n.get("status_strava_update_my_activities_description")).font(.footnote).foregroundStyle(.secondary)
                        Toggle(L10n.get("status_strava_include_other_devices"), isOn: Binding(
                            get: { companion.stravaIncludeOtherDevices },
                            set: { companion.setStravaIncludeOtherDevices($0) }
                        ))
                        Text(L10n.get("status_strava_include_other_devices_description")).font(.footnote).foregroundStyle(.secondary)
                        // PRIVACY-SYNC: the default of "Upload to Strava" for recordings on the phone (shared StravaSettingsStore).
                        Toggle(L10n.get("status_strava_upload_phone"), isOn: Binding(
                            get: { companion.stravaUploadPhoneRecordings },
                            set: { companion.setStravaUploadPhoneRecordings($0) }
                        ))
                        Text(L10n.get("status_strava_upload_phone_description")).font(.footnote).foregroundStyle(.secondary)
                    } footer: {
                        Text(L10n.get("status_strava_body"))
                    }
                }
        }
        .homeTitle("Strava")
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
                        if companion.diarySettings.roundDurationUp {
                            Toggle(isOn: Binding(
                                get: { companion.diarySettings.roundNearest },
                                set: { companion.setDiaryRoundNearest($0) }
                            )) {
                                VStack(alignment: .leading) {
                                    Text(L10n.get("status_ttb_round_nearest_switch"))
                                    Text(L10n.get("status_ttb_round_nearest_body")).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Toggle(L10n.get("status_ttb_compact_switch"), isOn: Binding(
                            get: { companion.diarySettings.compactDiary },
                            set: { companion.setDiaryCompact($0) }
                        ))
                        Button(L10n.get("ios_diary_write_7")) { Task { await companion.writeDiary(days: 7) } }
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
        .homeTitle(L10n.get("status_diary_label"))
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
                    ShareLink(item: LogFile(companion: companion, kinds: [.activityHistory, .watchTransfers, .stravaApi, .diary, .app]),
                              preview: SharePreview(L10n.get("log_share_all"))) {
                        Label(L10n.get("log_share_all"), systemImage: "square.and.arrow.up")
                    }
                }
        }
        .homeTitle(L10n.get("status_data_logs_heading"))
    }
}

struct SettingsPrivacyPage: View {
    @EnvironmentObject var companion: Companion
    @State private var confirmingDeleteAll = false

    var body: some View {
        Form {
                Section(L10n.get("status_my_data_heading")) {
                    DownloadMyDataButton()
                    NavigationLink(L10n.get("feedback_title")) { FeedbackHubScreen() }
                    Button(L10n.get("status_delete_my_data"), role: .destructive) { confirmingDeleteAll = true }
                        .disabled(companion.syncing)
                }
                .confirmationDialog(
                    L10n.get("status_delete_confirm_title"), isPresented: $confirmingDeleteAll, titleVisibility: .visible
                ) {
                    Button(L10n.get("status_delete_confirm_button"), role: .destructive) {
                        Task { await companion.deleteAllData() }
                    }
                } message: {
                    Text(L10n.get("status_delete_confirm_body"))
                }
        }
        .homeTitle(L10n.get("settings_page_privacy"))
    }
}

/// A spinning wheel with a text over a dimmed screen that takes every tap while a held action runs
/// (Android: ui/BusyOverlay.kt).
struct BusyOverlayView: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            HStack(spacing: 16) {
                ProgressView()
                Text(text)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}

// MARK: - Formatting

enum Format {
    static func date(_ epochSec: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(epochSec)).formatted(date: .abbreviated, time: .shortened)
    }

    /// Today only the time (a narrow row has room for little more), otherwise like [date].
    static func dateOrTimeToday(_ epochSec: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : date(epochSec)
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
        "walk": "watch_preset_walk",
        "hike": "watch_preset_hike",
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
    /// Activities that wait for the athlete's declaration, oldest first (Android `toReview`).
    var toReview: [ActivityItem] = []
    var onReview: (String) -> Void = { _ in }

    /// One card by priority, as Android: problems orange, activities to declare yellow, all fine green, grey while
    /// neither Strava nor a diary is connected (nothing to be "caught up" with).
    static func tone(_ status: SyncStatusView, reviewing: Bool) -> CardTone {
        if status.total > 0 { return .orange }
        if reviewing { return .yellow }
        return !status.stravaConnected && !status.diaryConnected ? .grey : .green
    }

    private var nothingConnected: Bool { !status.stravaConnected && !status.diaryConnected }

    /// One open category; [activityId] is the activity a tap opens (the first one it counts).
    private struct Line: Hashable {
        let text: String
        var activityId = ""
    }

    private var lines: [Line] {
        var parts: [Line] = []
        if status.pendingStrava > 0 { parts.append(Line(text: String(format: L10n.get("sync_status_pending_strava"), status.pendingStrava), activityId: status.firstPendingStravaId)) }
        if status.pendingDiary > 0 { parts.append(Line(text: String(format: L10n.get("sync_status_pending_diary"), status.pendingDiary), activityId: status.firstPendingDiaryId)) }
        if status.pendingDocs > 0 { parts.append(Line(text: String(format: L10n.get("sync_status_pending_docs"), status.pendingDocs), activityId: status.firstPendingDocsId)) }
        if status.stravaConflicts > 0 { parts.append(Line(text: String(format: L10n.get("sync_status_pending_strava_conflicts"), status.stravaConflicts), activityId: status.firstConflictId)) }
        if status.stravaUnavailable > 0 { parts.append(Line(text: String(format: L10n.get("sync_status_strava_unavailable"), status.stravaUnavailable))) }
        for id in status.twiceOnStravaIds { parts.append(Line(text: L10n.get("sync_status_phone_on_strava_twice"), activityId: id)) }
        if !status.stravaIssue.isEmpty {
            parts.append(Line(text: status.stravaIssueStandalone
                              ? status.stravaIssue
                              : String(format: L10n.get("sync_status_strava_issue"), status.stravaIssue)))
        }
        if !status.diaryIssue.isEmpty { parts.append(Line(text: String(format: L10n.get("sync_status_diary_issue"), status.diaryIssue))) }
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

    private var reviewTitle: String { L10n.plural("activity_list_review_title", toReview.count) }

    @ViewBuilder private var reviewButton: some View {
        if let oldest = toReview.first {
            Button(L10n.get("activity_list_review_button")) { onReview(oldest.id) }
        }
    }

    var body: some View {
        let tone = Self.tone(status, reviewing: !toReview.isEmpty)
        if status.total == 0, let oldest = toReview.first {
            // In sync, but activities wait for their declaration: one yellow card with the sync line inside.
            // Compact: the body at most two lines, the sync line beside the button (as on Android).
            VStack(alignment: .leading, spacing: 4) {
                Text(reviewTitle).font(.headline).foregroundStyle(tone.title)
                Text(String(format: L10n.get("activity_list_review_body"), oldest.title)).font(.footnote).lineLimit(2)
                HStack(spacing: 8) {
                    if !nothingConnected {
                        Label(detail, systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    reviewButton.buttonStyle(.borderedProminent).lineLimit(1).fixedSize()
                }
            }
        } else if status.total == 0 {
            VStack(alignment: .leading, spacing: 4) {
                if nothingConnected {
                    Text(companion.nickname.isEmpty
                         ? L10n.get("activity_list_hello")
                         : String(format: L10n.get("activity_list_hello_named"), companion.nickname))
                        .font(.headline)
                        .foregroundStyle(tone.title)
                } else {
                    Label(companion.nickname.isEmpty
                          ? L10n.get("activity_list_up_to_date")
                          : String(format: L10n.get("activity_list_up_to_date_named"), companion.nickname),
                          systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(companion.nickname.isEmpty
                      ? L10n.plural("activity_list_needs_attention_count", Int(status.total))
                      : L10n.plural("activity_list_needs_attention_count_named", Int(status.total), companion.nickname),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(tone.title)
                ForEach(lines, id: \.self) { line in
                    if let item = companion.activities.first(where: { $0.id == line.activityId }) {
                        NavigationLink {
                            ActivityDetailScreen(item: item)
                        } label: {
                            Label(line.text, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                        }
                    } else {
                        Label(line.text, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                    }
                }
                // The activities to declare share this card (Android: the review line in the problem box).
                if !toReview.isEmpty {
                    HStack {
                        Text(reviewTitle).font(.subheadline.weight(.semibold))
                        Spacer()
                        reviewButton.buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
