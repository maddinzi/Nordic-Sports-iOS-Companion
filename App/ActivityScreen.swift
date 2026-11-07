import NordicSportsShared
import SwiftUI

/// The two modes of an activity screen (Android: `ActivityMode`): what the athlete declares, and what the watch measured.
enum ActivityMode: Hashable {
    case entry, metrics
}

/// One screen per activity with a switch between its Entry (diary and Strava) and its Metrics (Android: `ActivityScreen`).
/// Both parts stay alive while the other is shown, so text typed in the Entry survives a look at the Metrics. A tap on
/// the list opens the mode and tab it names (`ActivityTarget`).
struct ActivityScreen: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem
    @State private var mode: ActivityMode
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
            HStack(spacing: 14) {
                SyncChip(name: L10n.get("sync_presence_destination_watch"), on: current.origin == "watch", tint: SyncChip.watch)
                SyncChip(name: "Strava", on: !current.stravaActivityId.isEmpty, tint: SyncChip.strava)
                if companion.diaryReceives {
                    SyncChip(name: L10n.get("settings_diary_short_name"),
                             on: current.diaryWritten && !current.diaryOutdated, tint: SyncChip.diary)
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
            if item.hasWatchMetrics {
                Picker("", selection: $mode) {
                    Label(L10n.get("card_lane_entry"), systemImage: "square.and.pencil").tag(ActivityMode.entry)
                    Label(L10n.get("card_lane_metrics"), systemImage: "chart.bar.fill").tag(ActivityMode.metrics)
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
                    ActivityMetricsScreen(item: item, initialTab: metricsTab, pick: pick)
                        .opacity(mode == .metrics ? 1 : 0)
                        .allowsHitTesting(mode == .metrics)
                        .accessibilityHidden(mode != .metrics)
                }
            }
        }
        .navigationTitle(L10n.get(mode == .entry ? "card_lane_entry" : "card_lane_metrics"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
