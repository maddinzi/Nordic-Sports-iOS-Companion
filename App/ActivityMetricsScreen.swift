import NordicSportsShared
import SwiftUI

// Moved from ActivityDetailScreen: the Metrics screen shows what the watch measured.
/// The read-only Metrics screen of an activity (Android: `ActivityMetricsScreen`): the technical data and, for a
/// watch activity, the technique analysis (Enhanced Metrics of a ski activity, the walk/run analysis of a run). It has
/// no edit state; the diary and Strava entries are on `ActivityDetailScreen`.
struct ActivityMetricsScreen: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem
    @State private var theme: MetricsTheme?
    @StateObject private var pick = MetricsPick()
    @State private var typical: TrendTypical?
    @State private var vsTypical = false

    init(item: ActivityItem, initialTab: MetricsTab = .data, pick: String? = nil) {
        self.item = item
        let start = MetricsPick()
        start.key = pick
        _pick = StateObject(wrappedValue: start)
        // The themes open on their first page (the overview); the data target, from the old tabs, opens All data.
        _theme = State(initialValue: initialTab == .data && !item.hasTechniqueMetrics ? .allData : nil)
    }

    /// The themes of this activity in the order of the pill row (Android: `dashboardPages`).
    private var themes: [MetricsTheme] {
        var out: [MetricsTheme] = []
        if hasLegacyLines { out.append(.legacy) }
        if let metrics = current.enhancedMetrics { out += metrics.themes.map { MetricsTheme.enhanced($0) } }
        out.append(.allData)
        return out
    }

    /// Older watch versions and hand-over formats: technique lines that have no chart.
    private var hasLegacyLines: Bool {
        (current.techniqueCatalog == "rollski" && !current.techniqueSharePercent.isEmpty)
            || (!current.analysisLines.isEmpty && current.enhancedMetrics == nil)
    }

    private var selectedTheme: MetricsTheme {
        let list = themes
        if let theme, list.contains(theme) { return theme }
        return list.first ?? .allData
    }

    /// The row as the list has it now.
    private var current: ActivityItem { companion.activities.first { $0.id == item.id } ?? item }

    /// The wrist in the app language; the watch's own label is English.
    /// The number tiles of the technical data card in rows that belong together (as Android's `TechnicalDataCard`):
    /// time and energy, distance and pace, heart rate, climb. A row with one tile fills the width.
    /// Each tile has the plain-language line under it (Android: the same texts). The groups fill rows of two; a lone tile fills its row.
    private var technicalRows: [[KeyFigure]] {
        func figure(_ value: String, _ unit: String, _ key: String, _ desc: String) -> KeyFigure {
            KeyFigure(value: value, unit: unit, name: L10n.get(key), description: L10n.get(desc))
        }
        let figures = ActivityFigures.shared
        let movingTime = figure(Format.duration(current.elapsedSec), "", "activity_detail_moving_time_label", "activity_detail_moving_time_desc")
        // Wall-clock time and the pause, for a watch that sent them (0.9.120 and later): moving time alone hides a long stop.
        let pause = figures.pauseSeconds(elapsedTimeSec: current.elapsedTimeSec, elapsedSec: current.elapsedSec)?.int32Value
        let totalTime: KeyFigure? = pause.map { paused in
            KeyFigure(value: Format.duration(current.elapsedTimeSec), unit: "", name: L10n.get("activity_detail_total_time_label"),
                      description: String(format: L10n.get("activity_detail_total_time_desc"), Format.duration(paused)))
        }
        let calories: KeyFigure? = current.calories > 0 ? figure("\(current.calories)", "kcal", "activity_detail_calories_label", "activity_detail_calories_desc") : nil
        let distance: KeyFigure? = current.distanceM > 0
            ? KeyFigure(value: Format.distance(current.distanceM), unit: "", name: L10n.get("activity_detail_distance_label")) : nil
        // Running reads as a pace (min/km), everything else as a speed. The unit goes into the name: both numbers and
        // "km/h" side by side do not fit a half tile. Not for activities without a speed (strength).
        var speed: KeyFigure?
        if current.avgSpeedMps > 0 {
            if figures.usesPace(art: current.sportArt) {
                if let avg = figures.paceSecPerKm(speedMps: current.avgSpeedMps)?.int32Value {
                    let best = figures.paceSecPerKm(speedMps: current.maxSpeedMps)?.int32Value
                    let value = best.map { "\(figures.paceText(secPerKm: avg)) / \(figures.paceText(secPerKm: $0))" } ?? figures.paceText(secPerKm: avg)
                    speed = figure(value, "", "activity_detail_avg_best_pace_label", "activity_detail_speed_desc")
                }
            } else {
                speed = KeyFigure(value: String(format: "%.1f / %.1f", Double(current.avgSpeedMps) * 3.6, Double(current.maxSpeedMps) * 3.6),
                                  unit: "", name: L10n.get("activity_detail_avg_max_speed_label") + " (km/h)",
                                  description: L10n.get("activity_detail_speed_desc"))
            }
        }
        let avgHeartRate: KeyFigure? = current.avgHeartRate > 0 ? figure("\(current.avgHeartRate)", "bpm", "activity_detail_avg_hr_label", "activity_detail_avg_hr_desc") : nil
        let maxHeartRate: KeyFigure? = current.maxHeartRate > 0 ? figure("\(current.maxHeartRate)", "bpm", "activity_detail_max_hr_label", "activity_detail_max_hr_desc") : nil
        let ascent: KeyFigure? = current.totalAscentM > 0 ? figure("\(Int(current.totalAscentM))", "m", "activity_detail_ascent_label", "em_ascent_desc") : nil
        let descent: KeyFigure? = current.totalDescentM > 0 ? figure("\(Int(current.totalDescentM))", "m", "activity_detail_descent_label", "em_descent_desc") : nil
        let groups: [[KeyFigure?]] = [[movingTime, totalTime, calories, distance, speed], [avgHeartRate, maxHeartRate], [ascent, descent]]
        return groups.flatMap { group -> [[KeyFigure]] in
            let tiles = group.compactMap { $0 }
            return stride(from: 0, to: tiles.count, by: 2).map { Array(tiles[$0 ..< min($0 + 2, tiles.count)]) }
        }
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
        // The watch app, its firmware and when the phone got the activity (Android: the same lines).
        let app = [current.watchAppVersion, current.watchBuild].filter { !$0.isEmpty }.joined(separator: " · ")
        if !app.isEmpty { facts.append((L10n.get("activity_detail_watch_app_label"), app)) }
        let firmware = ([current.watchFirmware].filter { !$0.isEmpty } + (current.watchCiqVersion.isEmpty ? [] : ["Connect IQ \(current.watchCiqVersion)"]))
            .joined(separator: " · ")
        if !firmware.isEmpty { facts.append((L10n.get("activity_detail_watch_firmware_label"), firmware)) }
        if current.receivedAtEpochMillis > 0 {
            facts.append((L10n.get("activity_detail_received_label"), Format.date(current.receivedAtEpochMillis / 1000)))
        }
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
            // The title, sync ticks and demo declaration are in the top card of ActivityScreen.
            // Level 3 of the navigation: the themes as a pill row; the first numbers stay above every theme but All data.
            if themes.count > 1 {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(themes, id: \.self) { entry in
                                let on = entry == selectedTheme
                                Button { theme = entry } label: {
                                    Text(entry.label).font(.subheadline.weight(on ? .semibold : .regular))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(on ? Color.accentColor : Color.clear, in: Capsule())
                                        .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1.5))
                                        .foregroundStyle(on ? Color(.systemBackground) : Color.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            if !pick.isEmpty && selectedTheme != .allData {
                Section {
                    Button(L10n.get("dash_pick_clear")) { pick.clear() }.font(.footnote)
                }
                .listRowBackground(Color.clear)
            }
            if selectedTheme == .allData {
                dataSections
            } else {
                Section {
                    KeyFiguresStrip(item: current, typical: vsTypical ? typical : nil, jump: { theme = $0 })
                    if let typical {
                        Toggle(isOn: $vsTypical) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(L10n.get("dash_vs_typical")).font(.subheadline)
                                Text(String(format: L10n.get("dash_vs_typical_hint"), Int(typical.count)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listRowBackground(CardTone.navy.container)
                themeSections(selectedTheme)
            }
            if current.hasWatchMetrics {
                Section {
                    Button(L10n.get("dash_more_like_this")) { Task { await companion.showTrends(for: current) } }
                        .font(.footnote)
                }
                .listRowBackground(Color.clear)
            }
        }
        .textSelection(.enabled)
        .task(id: item.id) { typical = await companion.typical(for: item) }
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

    /// The charts of one theme: a part of the watch's Enhanced Metrics, or the older technique lines.
    @ViewBuilder private func themeSections(_ entry: MetricsTheme) -> some View {
        switch entry {
        case .enhanced(let part):
            if let metrics = current.enhancedMetrics, part == .timeline {
                Section { TimelineSection(view: metrics, pick: pick) }
                    .listRowBackground(CardTone.blue.container)
            } else if let metrics = current.enhancedMetrics {
                Section { EnhancedMetricsCard(view: metrics, theme: part, pick: pick).id(part) }
                    .listRowBackground(CardTone.blue.container)
            }
        case .legacy:
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
        case .allData:
            EmptyView()
        }
    }
}

/// What the athlete picked in any chart of the Metrics screen (Android: `MetricsPick`): a technique or terrain, a heart rate
/// zone and a time block. Every chart reads it, so a pick in one shows in all of them, across the themes.
final class MetricsPick: ObservableObject {
    @Published var key: String?
    @Published var zone: Int?
    @Published var block: Int?

    var isEmpty: Bool { key == nil && zone == nil && block == nil }
    func clear() { key = nil; zone = nil; block = nil }
}

/// The themes of the Metrics screen (Android: `DashTab`): the Enhanced Metrics parts, the older technique lines and All data.
enum MetricsTheme: Hashable {
    case enhanced(EnhancedTheme), legacy, allData

    var label: String {
        switch self {
        case .legacy, .enhanced(.overview): return L10n.get("dash_tab_overview")
        case .enhanced(.technique): return L10n.get("dash_tab_technique")
        case .enhanced(.terrain): return L10n.get("dash_tab_terrain")
        case .enhanced(.form): return L10n.get("dash_tab_form")
        case .enhanced(.heartRate): return L10n.get("dash_tab_heart_rate")
        case .enhanced(.timeline): return L10n.get("dash_tab_timeline")
        case .allData: return L10n.get("dash_tab_all_data")
        }
    }
}
