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
    let item: ActivityItem
    @State private var mode: ActivityMode
    private let entryTab: EntryTab
    private let metricsTab: MetricsTab

    init(item: ActivityItem, target: ActivityTarget) {
        self.item = item
        switch target {
        case .diary, .strava:
            _mode = State(initialValue: .entry)
        case .data, .technique:
            _mode = State(initialValue: item.hasWatchMetrics ? .metrics : .entry)
        }
        entryTab = target == .strava ? .strava : .diary
        metricsTab = target == .technique ? .technique : .data
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    ActivityMetricsScreen(item: item, initialTab: metricsTab)
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
