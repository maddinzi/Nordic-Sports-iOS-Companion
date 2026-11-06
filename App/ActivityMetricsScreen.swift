import SwiftUI

// Moved from ActivityDetailScreen: the Metrics screen shows what the watch measured.
/// The read-only Metrics screen of an activity (Android: `ActivityMetricsScreen`): the technical data and, for a
/// watch activity, the technique analysis (Enhanced Metrics of a ski activity, the walk/run analysis of a run). It has
/// no edit state; the diary and Strava entries are on `ActivityDetailScreen`.
struct ActivityMetricsScreen: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem
    @State private var tab: MetricsTab

    init(item: ActivityItem, initialTab: MetricsTab = .data) {
        self.item = item
        _tab = State(initialValue: initialTab == .technique && item.hasTechniqueMetrics ? .technique : .data)
    }

    /// The row as the list has it now.
    private var current: ActivityItem { companion.activities.first { $0.id == item.id } ?? item }

    /// The wrist in the app language; the watch's own label is English.
    /// The number tiles of the technical data card in rows that belong together (as Android's `TechnicalDataCard`):
    /// time and energy, distance and pace, heart rate, climb. A row with one tile fills the width.
    private var technicalRows: [[KeyFigure]] {
        func figure(_ value: String, _ unit: String, _ key: String) -> KeyFigure { KeyFigure(value: value, unit: unit, name: L10n.get(key)) }
        let duration = figure(Format.duration(current.elapsedSec), "", "activity_detail_duration_label")
        let calories: KeyFigure? = current.calories > 0 ? figure("\(current.calories)", "kcal", "activity_detail_calories_label") : nil
        let distance: KeyFigure? = current.distanceM > 0 ? figure(Format.distance(current.distanceM), "", "activity_detail_distance_label") : nil
        // The unit of the speed pair goes into its name: both numbers and "km/h" side by side do not fit a half tile.
        let speed: KeyFigure? = current.avgSpeedMps > 0
            ? KeyFigure(value: String(format: "%.1f / %.1f", Double(current.avgSpeedMps) * 3.6, Double(current.maxSpeedMps) * 3.6),
                        unit: "", name: L10n.get("activity_detail_avg_max_speed_label") + " (km/h)")
            : nil
        let avgHeartRate: KeyFigure? = current.avgHeartRate > 0 ? figure("\(current.avgHeartRate)", "bpm", "activity_detail_avg_hr_label") : nil
        let maxHeartRate: KeyFigure? = current.maxHeartRate > 0 ? figure("\(current.maxHeartRate)", "bpm", "activity_detail_max_hr_label") : nil
        let ascent: KeyFigure? = current.totalAscentM > 0 ? figure("\(Int(current.totalAscentM))", "m", "activity_detail_ascent_label") : nil
        let descent: KeyFigure? = current.totalDescentM > 0 ? figure("\(Int(current.totalDescentM))", "m", "activity_detail_descent_label") : nil
        return [[duration, calories], [distance, speed], [avgHeartRate, maxHeartRate], [ascent, descent]].map { $0.compactMap { $0 } }
    }

    /// The facts that are text: start, the older-watch notes (poling averages, running share), device, wrist and place.
    private var technicalFacts: [(label: String, value: String)] {
        var facts: [(label: String, value: String)] = [(L10n.get("activity_detail_started_label"), Format.date(current.startEpochSec))]
        // Poling metrics only for rollski and langlauf, as on Android.
        if current.avgSpm > 0, current.enhancedMetrics == nil, current.preset.hasPrefix("rollski") || current.preset.hasPrefix("langlauf") {
            facts.append((L10n.get("activity_detail_stroke_metrics_label"),
                          String(format: "%lld / %.2f m / %.0f ms / %.0f %%", Int(current.avgSpm), Double(current.avgDpsM),
                                 Double(current.avgApidMs), Double(current.avgAdcPercent))))
        }
        if current.techniqueSharePercent.isEmpty, !current.watch.isEmpty,
           ["running", "poleRunning", "trailrun", "mountainRun", "track"].contains(current.preset) {
            facts.append((L10n.get("activity_detail_technique_share_label"), L10n.get("activity_detail_technique_share_running_missing")))
        }
        // Older watch versions: shares only; newer ones send averages (analysis section below).
        if current.techniqueCatalog == "running", current.techniqueSharePercent.count >= 2, current.analysisLines.isEmpty {
            facts.append((L10n.get("activity_detail_technique_share_label"),
                          String(format: L10n.get("activity_detail_technique_share_running_value"),
                                 current.techniqueSharePercent[0].doubleValue, current.techniqueSharePercent[1].doubleValue)))
        }
        if !current.watch.isEmpty { facts.append((L10n.get("activity_detail_device_label"), current.watch)) }
        if let wrist = wristText(current) { facts.append((L10n.get("activity_detail_watch_wrist_label"), wrist)) }
        if !current.locationName.isEmpty { facts.append((L10n.get("activity_detail_location_label"), current.locationName)) }
        return facts
    }

    private func wristText(_ a: ActivityItem) -> String? {
        switch a.watchWrist {
        case 1: return L10n.get("watch_option_wrist_left")
        case 2: return L10n.get("watch_option_wrist_right")
        default: return a.watchWristLabel.isEmpty ? nil : a.watchWristLabel
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.title.isEmpty ? L10n.get("activity_detail_title_fallback") : current.title).font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: current.origin == "watch" ? "checkmark.circle.fill" : "circle")
                            .font(.caption)
                            .foregroundStyle(current.origin == "watch" ? SyncChip.watch : Color.secondary)
                        Text(Format.summary(current)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(CardTone.blue.container)
            if current.hasTechniqueMetrics {
                Section {
                    Picker("", selection: $tab) {
                        Text(L10n.get("card_chip_data")).tag(MetricsTab.data)
                        Text(L10n.get("card_chip_technique")).tag(MetricsTab.technique)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
            }
            if tab == .data || !current.hasTechniqueMetrics {
                dataSections
            } else {
                techniqueSections
            }
        }
        .textSelection(.enabled)
        .navigationTitle(L10n.get("card_lane_metrics"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The technical data and the sets of a strength activity.
    @ViewBuilder private var dataSections: some View {
        Section {
            TechnicalDataCard(
                title: L10n.get("activity_detail_section_technical"),
                rows: technicalRows, facts: technicalFacts
            )
        }
        .listRowBackground(CardTone.navy.container)
        // Strength sets as the Strava description block says them (shared StrengthDescription.body).
        let setLines = current.strengthSetLines
        if !setLines.isEmpty {
            Section(L10n.get("activity_detail_strength_sets_label")) {
                ForEach(Array(setLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .listRowBackground(CardTone.grey.container)
        }
    }

    /// The watch's Enhanced Metrics (ski activity or run), the technique shares and the analysis block.
    @ViewBuilder private var techniqueSections: some View {
        // The watch's Enhanced Metrics (ski activity or run) as one collapsible card.
        if let metrics = current.enhancedMetrics {
            Section { EnhancedMetricsCard(view: metrics) }
                .listRowBackground(CardTone.blue.container)
        }
        if current.techniqueCatalog == "rollski", !current.techniqueSharePercent.isEmpty {
            Section(L10n.get("activity_detail_technique_share_rollski_label")) {
                ForEach(Array(current.techniqueSharePercent.enumerated()), id: \.offset) { index, percent in
                    LabeledContent(L10n.get("technique_labels_rollski_\(index)"), value: String(format: "%.0f%%", percent.doubleValue))
                }
            }
        }
        // The watch's analysis as the Strava description block says it (shared AnalysisDescription.body).
        let analysisLines = current.analysisLines
        if !analysisLines.isEmpty, current.enhancedMetrics == nil {
            Section(current.analysisTitle) {
                ForEach(Array(analysisLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .listRowBackground(CardTone.blue.container)
        }
    }
}
