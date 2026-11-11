import NordicSportsShared
import SwiftUI

/// What the Trends charts read: the selection, the shared numbers (`Trends`), the cross-chart highlight and the
/// callbacks to change it (Android: `TrendsUi`).
struct TrendsData {
    let periodDays: Int
    let compare: Bool
    let cur: [TrendActivity]
    let prev: [TrendActivity]
    let window: [TrendActivity]
    let buckets: [TrendBucket]
    let prevBuckets: [TrendBucket]
    let tech: String
    let zone: Int
    let bucket: Int
    let picked: String
    let views: [String: Int]
    let onTech: (String) -> Void
    let onZone: (Int) -> Void
    let onBucket: (Int) -> Void
    let onPick: (String) -> Void
    let onView: (String, Int) -> Void
    let tone: CardTone

    func view(_ id: String) -> Int { views[id] ?? 0 }
    func dimTech(_ key: String) -> Double { !tech.isEmpty && tech != key ? 0.25 : 1 }
    func dimZone(_ zone1: Int) -> Double { zone != 0 && zone != zone1 ? 0.25 : 1 }
    func dimBucket(_ index: Int) -> Double { bucket >= 0 && bucket != index ? 0.4 : 1 }
}

private struct TrendChartDef {
    let id: String
    let title: String
    let show: Bool
    /// How to read the chart or what its terms mean, behind an (i) in the title row.
    var info: String? = nil
}

/// The Trends tab (Android: `TrendsScreen`): what the watch's Enhanced Metrics add up to over the last week or month
/// (`design/metrics-dashboard.md` in the Companion). A filter bar (period, sport, style, other sports, compare), the
/// key numbers, a swipeable row of charts that also open full screen and page there, and the activities behind the
/// selection. A technique, zone or column tapped in one chart dims the others in every chart.
/// A request from a Metrics screen to open Trends on one sport and style (Android: `TrendsRequest`).
struct TrendsRequest: Equatable {
    let family: String
    let style: String
}

struct TrendsScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var all: [TrendActivity] = []
    @State private var periodDays = 7
    @State private var family = "ALL"
    @State private var style = "ALL"
    @State private var includeOther = false
    @State private var compare = false
    @State private var tech = ""
    @State private var zone = 0
    @State private var bucket = -1
    @State private var picked = ""
    @State private var views: [String: Int] = [:]
    @State private var page = 0
    @State private var expandedId: String?
    /// The filter bar: closed it is one line saying what is shown; a tap opens the chips (Android `FilterBar`).
    @State private var filterOpen = false
    @State private var registry = ChartRegistry()
    private let tone = CardTone.blue

    // MARK: Derived numbers (all from the shared `Trends`)

    private var query: TrendQuery {
        TrendQuery(periodDays: Int32(periodDays), family: family, style: style, includeOther: includeOther)
    }
    private var cur: [TrendActivity] { Trends.shared.select(all: all, q: query, previous: false) }
    private var prev: [TrendActivity] { Trends.shared.select(all: all, q: query, previous: true) }
    private var window: [TrendActivity] { Trends.shared.window(all: all, q: query, days: Int32(2 * periodDays)) }

    private var data: TrendsData {
        TrendsData(
            periodDays: periodDays, compare: compare, cur: cur, prev: prev, window: window,
            buckets: Trends.shared.buckets(list: cur, periodDays: Int32(periodDays)),
            prevBuckets: Trends.shared.previousBuckets(all: all, q: query),
            tech: tech, zone: zone, bucket: bucket, picked: picked, views: views,
            onTech: { key in tech = tech == key ? "" : key },
            onZone: { z in zone = zone == z ? 0 : z },
            onBucket: { i in bucket = bucket == i ? -1 : i },
            onPick: { id in picked = id },
            onView: { id, value in picked = ""; views[id] = value },
            tone: tone
        )
    }

    /// Guided interval sessions of the selection (watch tables and phone recordings alike).
    private var intervalSessions: [TrendIntervalSession] { Trends.shared.intervalSessions(list: cur) }

    /// Strength per exercise. Strength counts as an "other" sport, so this reads the period itself (with every sport or
    /// "other" picked), whatever the "other" switch says (as Android).
    private var strengthExercises: [TrendExercise] {
        guard family == "ALL" || family == "OTHER" else { return [] }
        return Trends.shared.strengthExercises(list: all.filter { Int($0.daysAgo) < periodDays }, holds: StrengthCatalog.shared.HOLD_EXERCISES)
    }

    private var charts: [TrendChartDef] {
        let cur = self.cur, window = self.window
        let hasState = cur.contains { !$0.techniques.isEmpty || !$0.terrain.isEmpty }
        return [
            TrendChartDef(id: "load", title: L10n.get("trends_c_load"), show: !cur.isEmpty),
            TrendChartDef(id: "int", title: L10n.get("trends_c_int"), show: cur.contains { $0.zones.map { $0.intValue }.reduce(0, +) > 0 }),
            TrendChartDef(id: "mix", title: L10n.get("trends_c_mix"), show: hasState),
            TrendChartDef(id: "matrix", title: L10n.get("trends_c_matrix"), show: hasState),
            TrendChartDef(id: "pol", title: L10n.get("trends_c_pol"), show: cur.contains { $0.techniques.contains { $0.rate != nil } }),
            TrendChartDef(id: "slope", title: L10n.get("trends_c_slope"), show: cur.contains { ($0.techniques + $0.terrain).contains { $0.gradePct != nil } }),
            TrendChartDef(id: "eff", title: L10n.get("trends_c_eff"), show: window.filter { $0.efficiency > 0 }.count >= 3),
            // RMSSD explained behind the (i), as on Android.
            TrendChartDef(id: "rec", title: L10n.get("trends_c_rec"), show: window.filter { $0.rmssd > 0 }.count >= 2,
                          info: ["\(L10n.get("em_rmssd_name")): \(L10n.get("em_rmssd_desc"))",
                                 L10n.get("em_hrv_note")].joined(separator: "\n\n")),
            TrendChartDef(id: "climb", title: L10n.get("trends_c_climb"), show: cur.contains { $0.ascentM > 0 || $0.descentM > 0 }),
            TrendChartDef(id: "intervals", title: L10n.get("trends_c_intervals"), show: !intervalSessions.isEmpty),
            TrendChartDef(id: "strength", title: L10n.get("trends_c_strength"), show: !strengthExercises.isEmpty),
        ]
    }
    private var visible: [TrendChartDef] { charts.filter { $0.show } }

    /// Four themes with two or three charts under each other (Android: `themes` in `TrendsScreen`).
    private var themes: [(label: String, charts: [TrendChartDef])] {
        let shown = visible
        let spec: [(String, [String])] = [
            (L10n.get("trends_theme_volume"), ["load", "climb"]),
            (L10n.get("trends_theme_intensity"), ["int", "rec"]),
            (L10n.get("dash_tab_technique"), ["mix", "matrix"]),
            (L10n.get("trends_theme_performance"), ["pol", "slope", "eff"]),
            (L10n.get("trends_theme_sessions"), ["intervals", "strength"]),
        ]
        return spec.map { (label, ids) in (label: label, charts: ids.compactMap { id in shown.first { $0.id == id } }) }
            .filter { !$0.charts.isEmpty }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterBar
                    // A tap anywhere below the open filter closes it; the tap still does its own thing (Android
                    // `closeFilterOnTapOutside`).
                    VStack(alignment: .leading, spacing: 12) {
                        kpiGrid
                        selectionRow
                        if visible.isEmpty {
                            emptyCard
                        } else {
                            chartPager
                        }
                        activityList
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        if filterOpen { withAnimation(.easeInOut(duration: 0.2)) { filterOpen = false } }
                    }, including: filterOpen ? .all : .subviews)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(L10n.get("trends_tab_trends"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await reload() }
        .onChange(of: companion.activities.count) { _, _ in Task { await reload() } }
        .onAppear { registerPages() }
        .onChange(of: companion.trendsRequest, initial: true) { _, request in
            guard let request else { return }
            family = request.family; style = request.style; tech = ""; picked = ""; bucket = -1
            companion.trendsRequest = nil
        }
        .onChange(of: visible.map { $0.id }) { _, _ in registerPages(); page = min(page, max(themes.count - 1, 0)) }
        .fullScreenCover(isPresented: Binding(get: { expandedId != nil }, set: { if !$0 { expandedId = nil } })) {
            let id = expandedId ?? ""
            FullScreenChart(
                title: charts.first { $0.id == id }?.title ?? "", tone: tone, onClose: { expandedId = nil },
                pages: registry.pages, startId: id
            ) { space in
                chartBody(id, space)
            }
        }
    }

    private func reload() async {
        all = await companion.trendActivities()
    }

    /// Every visible chart is known to the full-screen view, also those the pager has not shown yet: a swipe there pages through all of them.
    private func registerPages() {
        let fresh = ChartRegistry()
        for chart in themes.flatMap({ $0.charts }) {
            fresh.register(ChartRegistry.Page(id: chart.id, title: chart.title, tone: tone, content: { space in AnyView(chartBody(chart.id, space)) }))
        }
        registry = fresh
    }

    @ViewBuilder
    private func chartBody(_ id: String, _ space: ChartSpace) -> some View {
        let d = data
        switch id {
        case "load": TrendLoadChart(data: d, space: space)
        case "int": TrendIntensityChart(data: d, space: space)
        case "mix": TrendMixChart(data: d, space: space)
        case "matrix": TrendMatrixChart(data: d, space: space)
        case "pol": TrendPolingChart(data: d, space: space)
        case "slope": TrendSlopeChart(data: d, space: space)
        case "eff": TrendEfficiencyChart(data: d, space: space)
        case "rec": TrendRecoveryChart(data: d, space: space)
        case "intervals": TrendIntervalSessionsChart(sessions: intervalSessions) { companion.openActivityId = $0 }
        case "strength": TrendStrengthExercisesChart(exercises: strengthExercises) { companion.openActivityId = $0 }
        default: TrendClimbChart(data: d, space: space)
        }
    }

    // MARK: Filter bar

    /// What is shown, in words: "Last 7 days · Rollski · Skating · compared with the 7 days before".
    private var filterSummary: String {
        var parts = [L10n.get(periodDays == 7 ? "trends_summary_week" : "trends_summary_month"),
                     family == "ALL" ? L10n.get("trends_summary_all_sports") : familyName(family)]
        if style != "ALL" { parts.append(trendStyleName(style)) }
        if compare { parts.append(String(format: L10n.get("trends_summary_compare"), periodDays)) }
        if includeOther && family == "ALL" { parts.append(L10n.get("trends_summary_other")) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var filterBar: some View {
        FilterBar(summary: filterSummary, expanded: $filterOpen) { filterChips }
    }

    private var filterChips: some View {
        // Period, the two switches, then sports and styles over as many lines as they need (Android in step).
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: Binding(get: { periodDays }, set: { periodDays = $0; bucket = -1; picked = "" })) {
                Text(L10n.get("trends_period_week")).tag(7)
                Text(L10n.get("trends_period_month")).tag(30)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            HStack(spacing: 16) {
                miniSwitch(L10n.get("trends_compare_short"), isOn: $compare)
                miniSwitch(L10n.get("trends_other_short"), isOn: Binding(get: { includeOther }, set: { on in
                    includeOther = on
                    if !on && family == "OTHER" { family = "ALL"; style = "ALL" }
                }))
            }
            Divider()
            let counts = Trends.shared.familyCounts(all: all, q: query)
            ChipFlow(spacing: 8) {
                ForEach(includeOther ? ["ALL", "XC", "ROLLSKI", "RUNNING", "INLINE", "OTHER"] : ["ALL", "XC", "ROLLSKI", "RUNNING", "INLINE"], id: \.self) { f in
                    trendChip("\(familyName(f)) \(counts[f]?.intValue ?? 0)", on: family == f) {
                        family = f; style = "ALL"; tech = ""; picked = ""; bucket = -1
                    }
                }
            }
            let styles = styleKeys(family)
            if !styles.isEmpty {
                let styleCounts = Trends.shared.styleCounts(all: all, q: query)
                ChipFlow(spacing: 8) {
                    trendChip(L10n.get("trends_style_all"), on: style == "ALL") { style = "ALL"; picked = "" }
                    ForEach(styles, id: \.self) { s in
                        trendChip("\(trendStyleName(s)) \(styleCounts[s]?.intValue ?? 0)", on: style == s) { style = s; picked = "" }
                    }
                }
            }
        }
    }

    /// A small switch with a short label (Android: `MiniSwitch`).
    private func miniSwitch(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 2) {
            Toggle("", isOn: isOn).labelsHidden().scaleEffect(0.65).frame(width: 38, height: 24)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }

    private func trendChip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(on ? tone.title : tone.container, in: Capsule())
                .foregroundStyle(on ? Color(.systemBackground) : tone.title)
        }
        .buttonStyle(.plain)
    }

    private func familyName(_ f: String) -> String {
        switch f {
        case "ALL": return L10n.get("trends_family_all")
        case "XC": return L10n.get("trends_family_xc")
        case "ROLLSKI": return L10n.get("trends_family_rollski")
        case "RUNNING": return L10n.get("trends_family_running")
        case "INLINE": return L10n.get("trends_family_inline")
        default: return L10n.get("trends_family_other")
        }
    }

    // MARK: Key numbers

    private var kpiGrid: some View {
        let k = Trends.shared.kpis(list: cur), p = Trends.shared.kpis(list: prev)
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                kpi(L10n.get("trends_kpi_time"), k.seconds > 0 ? trendDuration(Int(k.seconds)) : "–", "", Double(k.seconds), Double(p.seconds))
                kpi(L10n.get("trends_kpi_distance"), "\(Int((Double(k.distanceM) / 1000).rounded()))", "km", Double(k.distanceM), Double(p.distanceM))
                kpi(L10n.get("trends_kpi_climb"), "\(k.ascentM)", "m", Double(k.ascentM), Double(p.ascentM))
            }
            GridRow {
                kpi(L10n.get("trends_kpi_sessions"), "\(k.sessions)", "", Double(k.sessions), Double(p.sessions))
                kpi(L10n.get("trends_kpi_hr"), k.avgHr > 0 ? "\(k.avgHr)" : "–", "bpm", Double(k.avgHr), Double(p.avgHr))
                kpi(L10n.get("trends_kpi_hard"), k.hardSeconds > 0 ? trendDuration(Int(k.hardSeconds)) : "–", "", Double(k.hardSeconds), Double(p.hardSeconds))
            }
        }
    }

    private func kpi(_ label: String, _ value: String, _ unit: String, _ now: Double, _ before: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).foregroundStyle(tone.title).lineLimit(1).minimumScaleFactor(0.7)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(tone.subtitle) }
            }
            Text(label).font(.caption2).foregroundStyle(tone.subtitle).lineLimit(1)
            if compare {
                if before <= 0 {
                    Text(L10n.get("trends_no_previous")).font(.caption2).foregroundStyle(tone.subtitle)
                } else {
                    let pct = (now - before) / before * 100
                    let text = String(format: L10n.get("trends_delta"), (pct >= 0 ? "+" : "") + "\(Int(pct.rounded()))%")
                    Text(text).font(.caption2).foregroundStyle(abs(pct) < 2 ? tone.subtitle : (pct > 0 ? Color.green : Color.orange))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(tone.container, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Selection

    @ViewBuilder private var selectionRow: some View {
        if !tech.isEmpty || zone != 0 || bucket >= 0 {
            HStack(spacing: 6) {
                if !tech.isEmpty { filterChip(String(format: L10n.get("trends_filter_tech"), tech)) { tech = "" } }
                if zone != 0 { filterChip(String(format: L10n.get("trends_filter_zone"), zone)) { zone = 0 } }
                if bucket >= 0 { filterChip(trendBucketLabel(bucket, periodDays)) { bucket = -1 } }
                Spacer(minLength: 0)
                Button(L10n.get("trends_clear_all")) { tech = ""; zone = 0; bucket = -1; picked = "" }.font(.footnote)
            }
        } else if !cur.isEmpty {
            Text(L10n.get("trends_filter_tip")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func filterChip(_ text: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            Text("\(text) ✕").font(.footnote)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(tone.title, in: Capsule()).foregroundStyle(Color(.systemBackground))
        }
        .buttonStyle(.plain)
    }

    // MARK: Charts

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.get("trends_empty_title")).font(.headline).foregroundStyle(tone.title)
            Text(L10n.get("trends_empty_body")).font(.footnote).foregroundStyle(tone.subtitle)
            Button(L10n.get("trends_show_all")) { family = "ALL"; style = "ALL"; periodDays = 30 }.font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tone.container, in: RoundedRectangle(cornerRadius: 14))
    }

    /// The themes as a pill row (level 3 of the navigation), under it the selected theme's charts in cards under each other.
    private var chartPager: some View {
        let list = themes
        let current = min(page, max(list.count - 1, 0))
        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(list.enumerated()), id: \.offset) { i, theme in
                        Button { page = i } label: {
                            Text(theme.label).font(.subheadline.weight(current == i ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(current == i ? tone.title : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(tone.title, lineWidth: 1.5))
                                .foregroundStyle(current == i ? Color(.systemBackground) : tone.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !list.isEmpty {
                ForEach(list[current].charts, id: \.id) { chart in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(chart.title).font(.subheadline.weight(.semibold)).foregroundStyle(tone.title)
                            Spacer()
                            if let info = chart.info { ChartInfoButton(title: chart.title, text: info) }
                            ExpandChartButton(tone: tone) { expandedId = chart.id }
                        }
                        chartBody(chart.id, .inline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(tone.container, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            if visible.count < charts.count {
                Text(String(format: L10n.get("trends_hidden_note"), charts.count - visible.count, charts.count))
                    .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Activities behind the selection

    @ViewBuilder private var activityList: some View {
        let shown = cur.filter { a in
            (bucket < 0 || Int(periodDays <= 7 ? a.daysAgo : a.daysAgo / 7) == bucket)
                && (tech.isEmpty || a.techniques.contains { $0.key == tech } || a.terrain.contains { $0.key == tech })
                && (zone == 0 || Double(a.zones[zone - 1].intValue) >= Double(a.seconds) * 0.05)
        }.sorted { $0.startEpochSec > $1.startEpochSec }
        if !cur.isEmpty {
            Text(String(format: L10n.get("trends_activities_in_view"), shown.count))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(shown.prefix(8)), id: \.id) { a in
                Button {
                    companion.openPick = tech.isEmpty ? nil : tech
                    companion.openActivityId = a.id
                } label: { activityRow(a) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func activityRow(_ a: TrendActivity) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(a.startEpochSec))
        let sec = tech.isEmpty ? 0 : Int((a.techniques + a.terrain).first { $0.key == tech }?.seconds ?? 0)
        var parts = [date.formatted(date: .abbreviated, time: .omitted), trendDuration(Int(a.seconds))]
        if a.distanceM > 0 { parts.append(String(format: "%.1f km", Double(a.distanceM) / 1000)) }
        if a.avgHr > 0 { parts.append("\(a.avgHr) bpm") }
        if sec > 0 { parts.append("\(tech) \(trendDuration(sec))") }
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(trendGroupColor(a.group)).frame(width: 8, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Shared helpers

func styleKeys(_ family: String) -> [String] {
    switch family {
    case "XC", "ROLLSKI": return ["SKATING", "CLASSIC", "DOUBLE_POLE"]
    case "RUNNING": return ["ROAD", "TRAIL", "TRACK", "POLE"]
    default: return []
    }
}

func trendStyleName(_ style: String) -> String {
    switch style {
    case "SKATING": return L10n.get("trends_style_skating")
    case "CLASSIC": return L10n.get("trends_style_classic")
    case "DOUBLE_POLE": return L10n.get("trends_style_double_pole")
    case "ROAD": return L10n.get("trends_style_road")
    case "TRAIL": return L10n.get("trends_style_trail")
    case "TRACK": return L10n.get("trends_style_track")
    case "POLE": return L10n.get("trends_style_pole")
    default: return ""
    }
}

func trendGroupName(_ group: String) -> String {
    let parts = group.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let family = parts.first ?? ""
    let style = parts.count > 1 ? parts[1] : ""
    let name: String
    switch family {
    case "XC": name = L10n.get("trends_family_xc")
    case "ROLLSKI": name = L10n.get("trends_family_rollski")
    case "RUNNING": name = L10n.get("trends_family_running")
    case "INLINE": name = L10n.get("trends_family_inline")
    default: name = L10n.get("trends_family_other")
    }
    return style.isEmpty ? name : "\(name) \(trendStyleName(style))"
}

/// The colour of a sport and style: the families keep a hue, the styles shade it (Android: `trendGroupColor`).
func trendGroupColor(_ group: String) -> Color {
    func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    switch group {
    case "XC|SKATING": return rgb(0x1B4F8F)
    case "XC|CLASSIC": return rgb(0x2A6DBD)
    case "XC|DOUBLE_POLE": return rgb(0x7DB2EA)
    case "ROLLSKI|SKATING": return rgb(0xC2570C)
    case "ROLLSKI|CLASSIC": return rgb(0xE8892B)
    case "ROLLSKI|DOUBLE_POLE": return rgb(0xF2B866)
    case "RUNNING|ROAD": return rgb(0x2E8B57)
    case "RUNNING|TRAIL": return rgb(0x1E6B45)
    case "RUNNING|TRACK": return rgb(0x5FBF7F)
    case "RUNNING|POLE": return rgb(0x9AD5AE)
    case "INLINE|": return rgb(0x7B5EA7)
    default:
        if group.hasPrefix("XC") { return rgb(0x2A6DBD) }
        if group.hasPrefix("ROLLSKI") { return rgb(0xE8892B) }
        if group.hasPrefix("RUNNING") { return rgb(0x2E8B57) }
        return rgb(0x8D99A6)
    }
}

/// "1:27" for 5220 s, "42 min" under an hour.
func trendDuration(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600 + 30) / 60
    if h == 0 { return "\(m) min" }
    if m == 60 { return "\(h + 1):00" }
    return String(format: "%d:%02d", h, m)
}

/// The label of column `index`: the weekday for a 7-day period, the end date of the week for a month.
func trendBucketLabel(_ index: Int, _ periodDays: Int) -> String {
    let calendar = Calendar.current
    if periodDays <= 7 {
        let day = calendar.date(byAdding: .day, value: -index, to: Date()) ?? Date()
        return day.formatted(.dateTime.weekday(.abbreviated))
    }
    let end = calendar.date(byAdding: .day, value: -index * 7, to: Date()) ?? Date()
    let c = calendar.dateComponents([.day, .month], from: end)
    return "\(c.day ?? 0).\(c.month ?? 0)."
}

/// A filter that takes one slim row while closed: [summary] says in words what is shown; a tap opens [content] (the
/// chips that change it) below the row, another tap closes it (Android `ui/FilterBar.kt`). Open, the row and the
/// chips sit in one card; the screen closes it on a tap elsewhere.
struct FilterBar<Content: View>: View {
    let summary: String
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(summary).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(expanded ? 3 : 1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.get("filter_bar_change") + ": " + summary)
            if expanded {
                content()
                    .padding(.horizontal, 12).padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            if expanded { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 1) }
        }
    }
}
