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
    /// The charts of every theme, so the full-screen view pages through all of them (the other themes are composed out of sight).
    @State private var registry = ChartRegistry()
    /// The Sensor Records of this activity (the time chart marks them).
    let bursts: [RecordingBoostView]
    /// The stored track (Instant Mode or a phone recording) for the Timeline theme's map and time chart; nil without one.
    @State private var track: LiveFeedView?
    @State private var trackLoaded = false
    /// The time window and picked moment the map and the time chart share.
    @StateObject private var timeView = TimeViewState()

    init(item: ActivityItem, initialTab: MetricsTab = .data, pick: String? = nil, bursts: [RecordingBoostView] = []) {
        self.item = item
        self.bursts = bursts
        let start = MetricsPick()
        start.key = pick
        _pick = StateObject(wrappedValue: start)
        // The themes open on their first page (the overview); the data target, from the old tabs, opens All data.
        // A guided session opens on its sets, steps or laps, as Android's first page.
        let guided = !item.strengthSetLines.isEmpty || !item.stepRows.isEmpty || !item.lapRows.isEmpty
        _theme = State(initialValue: initialTab == .data && !item.hasTechniqueMetrics && !guided ? .allData : nil)
    }

    /// The themes of this activity in the order of the pill row (Android: `dashboardPages`).
    private var themes: [MetricsTheme] {
        var out: [MetricsTheme] = []
        if hasLegacyLines { out.append(.legacy) }
        if let metrics = current.enhancedMetrics { out += metrics.themes.map { MetricsTheme.enhanced($0) } }
        // A stored track gives the Timeline theme its map and time chart, also without blocks (Android `dashboardPages(hasTrack)`).
        if track?.series != nil && !out.contains(.enhanced(.timeline)) { out.append(.track) }
        // The guided pages (Android: SETS, STEPS, LAPS), from the watch's tables or a phone recording.
        if !current.strengthSetLines.isEmpty { out.append(.sets) }
        if !current.stepRows.isEmpty { out.append(.steps) }
        if !current.lapRows.isEmpty { out.append(.laps) }
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
            // The pills and "Clear selection" share one tight section: on their own each cost a full section gap.
            let showPills = themes.count > 1
            let showClear = !pick.isEmpty && selectedTheme != .allData
            if showPills || showClear {
                Section {
                    if showPills {
                        PartPills(pills: themes.map { entry in
                            PartPill(id: String(describing: entry), label: entry.label, selected: entry == selectedTheme) { theme = entry }
                        })
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    if showClear {
                        Button(L10n.get("dash_pick_clear")) { pick.clear() }.font(.footnote)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 2, trailing: 0))
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
        // Dense like the Entry mode: compact section gaps, and no grouped top margin under the mode switch.
        .listSectionSpacing(.compact)
        .contentMargins(.top, 4, for: .scrollContent)
        .environment(\.chartRegistry, registry)
        .background(alignment: .topLeading) { hiddenThemes }
        .task(id: item.id) { typical = await companion.typical(for: item) }
        .task(id: item.id) {
            track = await companion.activityTrack(of: item)
            trackLoaded = true
        }
        .homeTitle(L10n.get("card_lane_metrics"))
    }

    /// The technical data (the sets have their own page).
    @ViewBuilder private var dataSections: some View {
        Section {
            TechnicalDataCard(
                title: L10n.get("activity_detail_section_technical"),
                rows: technicalRows, facts: technicalFacts
            )
        }
        .listRowBackground(CardTone.navy.container)
    }

    /// The themes that are not open, composed at no size and not drawn: their charts register with the screen's registry.
    private var hiddenThemes: some View {
        VStack {
            ForEach(themes.filter { $0 != selectedTheme }, id: \.self) { entry in
                if entry == .track, let track {
                    ActivityTimeSection(item: current, track: track, bursts: bursts, showMap: false, view: timeView)
                }
                if case .enhanced(let part) = entry, let metrics = current.enhancedMetrics {
                    if part == .timeline {
                        if let track { ActivityTimeSection(item: current, track: track, bursts: bursts, showMap: false, view: timeView) }
                        TimelineSection(view: metrics, pick: pick)
                    } else {
                        EnhancedMetricsCard(view: metrics, theme: part, pick: pick)
                    }
                }
            }
        }
        .frame(width: 0, height: 0)
        .clipped()
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The charts of one theme: a part of the watch's Enhanced Metrics, or the older technique lines.
    @ViewBuilder private func themeSections(_ entry: MetricsTheme) -> some View {
        switch entry {
        case .enhanced(let part):
            if let metrics = current.enhancedMetrics, part == .timeline {
                // Everything over time together: the map and the time chart first, then the blocks.
                timeSection
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
        case .sets:
            Section(L10n.get("activity_detail_strength_sets_label")) {
                ForEach(Array(current.strengthSetLines.enumerated()), id: \.offset) { _, line in Text(line) }
                ForEach(Array(current.setRows.enumerated()), id: \.offset) { _, row in
                    Text(row.text).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(CardTone.blue.container)
        case .steps:
            Section(L10n.get("watch_training_type_intervals")) {
                if !current.stepsSummary.isEmpty { Text(current.stepsSummary).font(.body.weight(.semibold)) }
                guidedRows(current.stepRows)
            }
            .listRowBackground(CardTone.blue.container)
        case .laps:
            Section(L10n.get("em_timeline_by_lap")) { guidedRows(current.lapRows) }
                .listRowBackground(CardTone.blue.container)
        case .track:
            timeSection
        case .allData:
            EmptyView()
        }
    }

    /// The map and the time chart of the stored track, or the line that says what they need.
    @ViewBuilder private var timeSection: some View {
        if let track {
            Section { ActivityTimeSection(item: current, track: track, bursts: bursts, view: timeView) }
                .listRowBackground(CardTone.blue.container)
        } else if trackLoaded {
            Section { NoTrackNote() }
                .listRowBackground(Color.clear)
        }
    }

    /// The lines of the Intervals or Laps page; a work step or the fastest lap stands out.
    private func guidedRows(_ rows: [GuidedRowView]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Text(row.text)
                .font(row.emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(row.emphasized ? Color.primary : Color.secondary)
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
    case enhanced(EnhancedTheme), legacy, sets, steps, laps, allData
    /// The Timeline theme of an activity with a track but no time blocks.
    case track

    var label: String {
        switch self {
        case .track: return L10n.get("dash_tab_timeline")
        case .legacy, .enhanced(.overview): return L10n.get("dash_tab_overview")
        case .enhanced(.technique): return L10n.get("dash_tab_technique")
        case .enhanced(.terrain): return L10n.get("dash_tab_terrain")
        case .enhanced(.form): return L10n.get("dash_tab_form")
        case .enhanced(.heartRate): return L10n.get("dash_tab_heart_rate")
        case .enhanced(.timeline): return L10n.get("dash_tab_timeline")
        case .sets: return L10n.get("dash_tab_sets")
        case .steps: return L10n.get("watch_training_type_intervals")
        case .laps: return L10n.get("em_timeline_by_lap")
        case .allData: return L10n.get("dash_tab_all_data")
        }
    }
}
