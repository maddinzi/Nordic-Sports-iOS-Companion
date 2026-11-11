import NordicSportsShared
import SwiftUI

/// The two modes of an activity screen (Android: `ActivityMode`): what the athlete declares, and what the watch measured.
enum ActivityMode: Hashable {
    case entry, metrics, sensor
}

/// One screen per activity with a switch between its Entry (diary and Strava) and its Metrics (Android: `ActivityScreen`).
/// Both parts stay alive while the other is shown, so text typed in the Entry survives a look at the Metrics. A tap on
/// the list opens the mode and tab it names (`ActivityTarget`).
struct ActivityScreen: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem
    @State private var mode: ActivityMode
    /// The Sensor Records captured during this activity; the Sensor mode exists only when there is one.
    @State private var bursts: [RecordingBoostView] = []
    private let entryTab: EntryTab
    private let metricsTab: MetricsTab

    private let pick: String?

    init(item: ActivityItem, target: ActivityTarget, pick: String? = nil) {
        self.item = item
        self.pick = pick
        switch target {
        case .diary, .strava:
            _mode = State(initialValue: .entry)
        case .data, .technique:
            _mode = State(initialValue: item.hasWatchMetrics ? .metrics : .entry)
        case .sensor:
            _mode = State(initialValue: .sensor)
        }
        entryTab = target == .strava ? .strava : .diary
        metricsTab = target == .technique ? .technique : .data
    }

    /// The row as the list has it now.
    private var current: ActivityItem { companion.activities.first { $0.id == item.id } ?? item }

    /// The top card (Android: `ActivityBar`): the name and when, where the activity is synced to and the demo declaration.
    private var topCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current.title.isEmpty ? L10n.get("activity_detail_title_fallback") : current.title).font(.headline)
            Text(Format.summary(current)).font(.subheadline).foregroundStyle(.secondary)
            // The origin icon, then the destination marks without words (Android `SyncPresenceRow` in the header).
            HStack(spacing: 14) {
                OriginMark(item: current, font: .body)
                if let mark = current.stravaMark(connected: companion.stravaConnected) {
                    Image(systemName: "chevron.up.2").foregroundStyle(markColor(mark, done: SyncChip.strava))
                        .accessibilityLabel("Strava")
                }
                if let mark = current.diaryMark(connected: companion.diaryReceives) {
                    Image(systemName: "book.closed")
                        .foregroundStyle(markColor(current.diaryOutdated && mark == .done ? .pending : mark, done: SyncChip.diary))
                        .accessibilityLabel(L10n.get("sync_presence_destination_diary"))
                }
                if current.isDemo {
                    Label(L10n.get("demo_badge"), systemImage: "testtube.2").font(.subheadline)
                }
            }
            if current.isDemo {
                Text(L10n.get("demo_nothing_sent")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(CardTone.blue.container)
    }

    var body: some View {
        VStack(spacing: 0) {
            topCard
            // Level 2 of the navigation: the mode, always in reach above the content.
            if item.hasWatchMetrics || !bursts.isEmpty {
                Picker("", selection: $mode) {
                    Label(L10n.get("card_lane_entry"), systemImage: "square.and.pencil").tag(ActivityMode.entry)
                    if item.hasWatchMetrics {
                        Label(L10n.get("card_lane_metrics"), systemImage: "chart.bar.fill").tag(ActivityMode.metrics)
                    }
                    if !bursts.isEmpty {
                        Label(L10n.get("card_lane_sensor"), systemImage: "waveform.path.ecg").tag(ActivityMode.sensor)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            ZStack {
                ActivityDetailScreen(item: item, initialTab: entryTab)
                    .opacity(mode == .entry ? 1 : 0)
                    .allowsHitTesting(mode == .entry)
                    .accessibilityHidden(mode != .entry)
                if item.hasWatchMetrics {
                    ActivityMetricsScreen(item: item, initialTab: metricsTab, pick: pick, bursts: bursts)
                        .opacity(mode == .metrics ? 1 : 0)
                        .allowsHitTesting(mode == .metrics)
                        .accessibilityHidden(mode != .metrics)
                }
                // Built only when opened: each record computes its charts.
                if mode == .sensor && !bursts.isEmpty {
                    SensorModeView(bursts: bursts)
                }
            }
        }
        .task(id: item.id) { bursts = await companion.recordingBoosts(of: item.id) }
        .homeTitle(L10n.get(mode == .entry ? "card_lane_entry" : mode == .metrics ? "card_lane_metrics" : "card_lane_sensor"))
    }
}
