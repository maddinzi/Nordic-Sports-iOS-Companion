import Charts
import NordicSportsShared
import SwiftUI

/// The tinted card look of the activity detail screen, as on Android (`CardTone` in Theme.kt):
/// a light tint, a thin frame in the same hue and a title in a dark shade of it.
enum CardTone {
    /// The detail screen follows one scheme from the top (as Android): yellow (what the athlete enters), green (feeling),
    /// darkGreen (equipment), navy (technical data), blue (Enhanced Metrics). Orange and red stay for notices and problems.
    case blue, navy, red, green, darkGreen, yellow, orange, purple, teal, grey

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }

    var container: Color {
        switch self {
        case .blue: return Self.dyn(0xEAF4FD, 0x12283B)
        case .red: return Self.dyn(0xFDECEC, 0x3A1A1A)
        case .green: return Self.dyn(0xEAF6EC, 0x14301A)
        case .darkGreen: return Self.dyn(0xD3E8D7, 0x0C2214)
        case .navy: return Self.dyn(0xDCE5F3, 0x0F1B33)
        case .yellow: return Self.dyn(0xFFF7DB, 0x2B2610)
        case .orange: return Self.dyn(0xFFEEDF, 0x33200F)
        case .purple: return Self.dyn(0xF3EDFB, 0x251A36)
        case .teal: return Self.dyn(0xE6F6F5, 0x0F2F2E)
        case .grey: return Self.dyn(0xF0F2F4, 0x22262B)
        }
    }

    var border: Color {
        switch self {
        case .blue: return Self.dyn(0x8FC2EC, 0x2F5F85)
        case .red: return Self.dyn(0xE8A0A0, 0x8A3A3A)
        case .green: return Self.dyn(0x9BCBA3, 0x3C7A48)
        case .darkGreen: return Self.dyn(0x5A9467, 0x2D6B3E)
        case .navy: return Self.dyn(0x5878AD, 0x3A5A92)
        case .yellow: return Self.dyn(0xE6C65C, 0x8A7220)
        case .orange: return Self.dyn(0xF0A66B, 0x9A5A2A)
        case .purple: return Self.dyn(0xBBA3E0, 0x6F4FA0)
        case .teal: return Self.dyn(0x8FCFCA, 0x2F8A85)
        case .grey: return Self.dyn(0xB5BDC6, 0x58626E)
        }
    }

    var title: Color {
        switch self {
        case .blue: return Self.dyn(0x0B3A5E, 0xBFE0FA)
        case .red: return Self.dyn(0x6B1D1D, 0xF5C2C2)
        case .green: return Self.dyn(0x1B4D26, 0xBFE8C7)
        case .darkGreen: return Self.dyn(0x0F3A1B, 0xA9DCB4)
        case .navy: return Self.dyn(0x0B2547, 0xB9CCEE)
        case .yellow: return Self.dyn(0x5C4400, 0xFFE69A)
        case .orange: return Self.dyn(0x7A3300, 0xFFD3B0)
        case .purple: return Self.dyn(0x3F2468, 0xE0D0F5)
        case .teal: return Self.dyn(0x0F4A47, 0xBDEDE9)
        case .grey: return Self.dyn(0x2B3138, 0xDDE3EA)
        }
    }

    var subtitle: Color {
        switch self {
        case .blue: return Self.dyn(0x2F5F85, 0x9DB9D0)
        case .red: return Self.dyn(0x8A3A3A, 0xD9A0A0)
        case .green: return Self.dyn(0x2F6B3C, 0x9CC8A5)
        case .darkGreen: return Self.dyn(0x24572F, 0x86B892)
        case .navy: return Self.dyn(0x2C4A78, 0x8FA6CC)
        case .yellow: return Self.dyn(0x7A5E10, 0xD4BE70)
        case .orange: return Self.dyn(0x9A4B12, 0xE0AE85)
        case .purple: return Self.dyn(0x5E4290, 0xB9A3D6)
        case .teal: return Self.dyn(0x2A6B67, 0x94C8C4)
        case .grey: return Self.dyn(0x515A64, 0xA9B3BE)
        }
    }

    /// The tile and badge backgrounds inside a card of this tone.
    var tile: Color { self == .navy ? Self.dyn(0xFFFFFF, 0x1B2D50) : Self.dyn(0xFFFFFF, 0x1B3550) }
}

/// A collapsible group of the detail screen: tinted background and frame like Android's `CollapsibleCard`.
struct ToneGroup<Content: View>: View {
    let title: String
    var subtitle: String?
    let tone: CardTone
    @State private var expanded = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) { content() }.padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(tone.title)
                if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(tone.subtitle) }
            }
        }
        .tint(tone.title)
        .padding(.vertical, 4)
    }
}

extension Color {
    // Blue, green, grey by intensity (Companion `design/colour-scheme.md`, `TechniqueCatalogs.COLOR_RGB`).
    static let techniqueBlue = Color(red: 0x2A / 255, green: 0x6D / 255, blue: 0xBD / 255)
    static let techniqueDeepBlue = Color(red: 0x1B / 255, green: 0x4F / 255, blue: 0x8F / 255)
    static let techniqueMidBlue = Color(red: 0x5B / 255, green: 0x9B / 255, blue: 0xE0 / 255)
    static let techniqueLightBlue = Color(red: 0x9C / 255, green: 0xC7 / 255, blue: 0xF2 / 255)
    static let techniqueGreen = Color(red: 0x3F / 255, green: 0xA0 / 255, blue: 0x64 / 255)
    static let runBlue = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)
    static let techniqueOrange = Color(red: 0xE0 / 255, green: 0x8A / 255, blue: 0x1E / 255)
    static let techniqueGrey = Color(red: 0x8D / 255, green: 0x99 / 255, blue: 0xA6 / 255)
    static let techniqueLight = Color(red: 0xC9 / 255, green: 0xD0 / 255, blue: 0xD8 / 255)
    // Running terrain, orange over yellow and light green to dark green (`TechniqueCatalogs.COLOR_RGB`).
    static let terrainSteep = Color(red: 0xE2 / 255, green: 0x57 / 255, blue: 0x1E / 255)
    static let terrainUp = Color(red: 0xF0 / 255, green: 0xB3 / 255, blue: 0x23 / 255)
    static let terrainFlat = Color(red: 0x9C / 255, green: 0xCB / 255, blue: 0x5A / 255)
    static let terrainDown = Color(red: 0x2E / 255, green: 0x7D / 255, blue: 0x4F / 255)
    static let terrainSteepDown = Color(red: 0x14 / 255, green: 0x53 / 255, blue: 0x2D / 255)
}

/// The watch's heart rate zone colours (`RecordingView.zoneArcColor`: light grey, blue, green, yellow, red) in Garmin's
/// palette values; Android: `hrZoneColor`. `zone` is 1...5.
func hrZoneColor(_ zone: Int) -> Color {
    func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    switch zone {
    case 1: return rgb(0xAAAAAA)
    case 2: return rgb(0x0055FF)
    case 3: return rgb(0x00AA00)
    case 4: return rgb(0xFFAA00)
    default: return rgb(0xFF0000)
    }
}

/// Colour per catalog state: techniques (V2, V1, ...) and terrain (UP, FLAT, ...).
func stateColor(_ key: String) -> Color {
    switch key {
    case "KLAEBO": return .techniqueDeepBlue
    case "V2", "DIA": return .techniqueBlue
    case "V2A", "KDP": return .techniqueMidBlue
    case "V1": return .techniqueLightBlue
    case "DP": return .techniqueGreen
    case "RUN": return .runBlue
    case "STEEP": return .terrainSteep
    case "UP": return .terrainUp
    case "FLAT": return .terrainFlat
    case "DOWN": return .terrainDown
    case "STEEP_DOWN": return .terrainSteepDown
    case "GLIDE", "WALK": return .techniqueGrey
    default: return .techniqueLight
    }
}

/// Athlete-facing name of a state ("V2A" -> "Symmetric 2:1 (V2A)"), also for GLIDE, OTHER and the terrain.
private func stateName(_ key: String) -> String {
    switch key {
    case "V2": return L10n.get("technique_name_v2")
    case "V2A": return L10n.get("technique_name_v2a")
    case "V1": return L10n.get("technique_name_v1")
    case "DP": return L10n.get("technique_name_dp")
    case "DIA": return L10n.get("technique_name_dia")
    case "KDP": return L10n.get("technique_name_kdp")
    case "KLAEBO": return L10n.get("technique_name_klaebo")
    case "GLIDE": return L10n.get("strava_analysis_glide")
    case "OTHER": return L10n.get("strava_analysis_other")
    case "UP": return L10n.get("em_up")
    case "FLAT": return L10n.get("em_flat")
    case "DOWN": return L10n.get("em_down")
    case "STEEP": return L10n.get("em_steep")
    case "STEEP_DOWN": return L10n.get("em_steep_down")
    case "RUN": return L10n.get("em_run")
    case "WALK": return L10n.get("em_walk")
    default: return key
    }
}

/// The short code in the grid: GLIDE and OTHER in words, the rest as is.
func stateShort(_ key: String) -> String {
    switch key {
    case "GLIDE", "OTHER", "UP", "FLAT", "DOWN", "STEEP", "STEEP_DOWN": return stateName(key)
    case "KLAEBO": return "Klæbo"   // a name, like the codes, never translated
    default: return key
    }
}

func clock(_ totalSeconds: Int) -> String {
    let h = totalSeconds / 3600, m = totalSeconds % 3600 / 60, s = totalSeconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// The bar chart of the cards (ski by technique, running by terrain), drawn from the shared `EmBarChart`:
/// one bar per state, the dashed average line named in the header, a pale bar for a state with little time and a
/// bold label on the emphasised bar. Same layout as Android's `MetricBars`; the bars grow in when it appears, so
/// give it `.id(chart.id)` to replay that when the metric changes.
private struct MetricBars: View {
    let title: String
    let chart: EmBarChart
    /// A state key to keep in colour; the other bars fade (the donut's selection).
    var highlight: String? = nil
    /// A tap on a bar passes its key, so the bars select and clear the same state as the donut.
    var onSelect: ((String) -> Void)? = nil
    /// Inline in the card, or the whole landscape screen (the expand button opens a second `MetricBars` for it).
    var space = ChartSpace.inline
    @State private var grow: CGFloat = 0
    @State private var expanded = false
    private let tone = CardTone.blue

    private var average: Double? { chart.average?.doubleValue }

    private var scale: Double {
        let top = chart.bars.map { $0.value }.max() ?? 0
        let widest = max(top, average ?? 0)
        return widest > 0 ? widest : 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tone.subtitle)
                Spacer()
                if average != nil, let text = chart.averageText {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 5))
                        path.addLine(to: CGPoint(x: 18, y: 5))
                    }
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 18, height: 10)
                    Text("Ø \(text)").font(.caption).foregroundStyle(tone.subtitle)
                }
                if !space.maximized { ExpandChartButton(tone: tone) { expanded = true } }
            }
            ForEach(chart.bars, id: \.key) { bar in row(bar) }
        }
        .padding(12)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { withAnimation(.easeOut(duration: 0.4)) { grow = 1 } }
        .fullScreenCover(isPresented: $expanded) {
            FullScreenChart(title: title, tone: tone, onClose: { expanded = false }) { space in
                ScrollView {
                    MetricBars(title: title, chart: chart, highlight: highlight, onSelect: onSelect, space: space)
                }
            }
        }
    }

    private func row(_ bar: EmBar) -> some View {
        let name = stateShort(bar.key)
        let time = clock(Int(bar.seconds))
        let dim = highlight != nil && highlight != bar.key
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
                Text(time).font(.caption2).foregroundStyle(tone.subtitle)
            }
            .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(stateColor(bar.key).opacity((bar.faded ? 0.45 : 1) * (dim ? 0.4 : 1)))
                        .frame(width: geo.size.width * CGFloat(bar.value / scale) * grow)
                    if let average {
                        let x = geo.size.width * CGFloat(average / scale)
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                        .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
            }
            .frame(height: 22 * space.scale)
            Text(bar.text).font(.footnote.weight(bar.emphasis ? .bold : .regular))
                .opacity(dim ? 0.45 : 1)
                .frame(width: 72, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(bar.key) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(time) \(bar.text)")
        .accessibilityAddTraits(onSelect == nil ? [] : .isButton)
    }
}

/// What each headline key shows: name, explanation and the abbreviation (ski only).
private func tileTexts(_ key: String) -> (name: String, desc: String, abbreviation: String?) {
    switch key {
    case "rate": return (L10n.get("em_rate_name"), L10n.get("em_rate_desc"), "SPM")
    case "dps": return (L10n.get("em_dps_name"), L10n.get("em_dps_desc"), "DPS")
    case "apid": return (L10n.get("em_apid_name"), L10n.get("em_apid_desc"), "APID")
    case "adc": return (L10n.get("em_adc_name"), L10n.get("em_adc_desc"), "ADC")
    case "eff": return (L10n.get("em_eff_name"), L10n.get("em_eff_desc"), nil)
    case "fade": return (L10n.get("em_fade_name"), L10n.get("em_fade_desc"), nil)
    case "gct": return (L10n.get("em_gct_name"), L10n.get("em_gct_desc"), nil)
    case "vo": return (L10n.get("em_vo_name"), L10n.get("em_vo_desc"), nil)
    case "vr": return (L10n.get("em_vr_name"), L10n.get("em_vr_desc"), nil)
    case "ascent": return (L10n.get("em_ascent_name"), L10n.get("em_ascent_desc"), nil)
    case "descent": return (L10n.get("em_descent_name"), L10n.get("em_descent_desc"), nil)
    case "rmssd": return (L10n.get("em_rmssd_name"), L10n.get("em_rmssd_desc"), nil)
    case "sdnn": return (L10n.get("em_sdnn_name"), L10n.get("em_sdnn_desc"), nil)
    default: return (key, "", nil)
    }
}

/// The watch's Enhanced Metrics of a ski activity or a run in one collapsible blue card (Android:
/// `EnhancedMetricsCard.kt` / `RunningMetricsCard.kt`). The numbers come from the shared
/// `EnhancedMetricsView`; the texts are the `em_*` and `technique_name_*` strings.
struct EnhancedMetricsCard: View {
    let view: EnhancedMetricsView
    private let tone = CardTone.blue
    @State private var explaining = false
    @State private var polingOpen = false
    /// The ski tile whose bar chart is open (a `view.charts` id), and the metric chosen on the run card.
    @State private var openChart: String?
    @State private var selectedChart: String?
    /// The technique or terrain picked on the donut (a state key); the legend and the bar charts follow it.
    @State private var selectedKey: String?
    @State private var selectedAngle: Double?
    /// The heart rate zone (0...4) picked on the zone donut.
    @State private var selectedZone: Int?
    /// The card's charts, for paging through them with a swipe while one is full screen.
    @State private var registry = ChartRegistry()

    private var isRun: Bool { view.kind == "run" }

    var body: some View {
        ToneGroup(title: L10n.get("em_title"),
                  subtitle: L10n.get(isRun ? "em_run_subtitle" : "em_subtitle"), tone: tone) {
            if !view.headline.isEmpty {
                section(L10n.get(isRun ? "em_run_eff_title" : "em_poling_title")) {
                    tiles(view.headline)
                    if !isRun, let id = openChart, let chart = view.charts.first(where: { $0.id == id }) {
                        MetricBars(title: skiChartTitle(id), chart: chart, highlight: selectedKey, onSelect: toggleSelection).id(id)
                    }
                }
            }
            if isRun, !view.form.isEmpty || view.balanceLeft > 0 {
                section(L10n.get("em_form_title"), badge: sourceName) {
                    tiles(view.form)
                    if view.balanceLeft > 0 { balance(Double(view.balanceLeft)) }
                }
            }
            if isRun, !view.gait.isEmpty {
                ChartFrame(title: L10n.get("em_gait_title"), tone: tone) { space in gaitBar(space) }
            }
            if !view.shares.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ChartFrame(title: L10n.get(isRun ? "em_terrain_title" : "em_share_title"),
                               hint: L10n.get(isRun ? "em_terrain_desc" : "em_share_desc"), tone: tone) { space in donut(space) }
                    if isRun {
                        Text(L10n.get("em_terrain_time_note")).font(.caption).foregroundStyle(tone.subtitle)
                        runCharts
                    }
                }
            }
            if !view.rows.isEmpty {
                section(L10n.get(isRun ? "em_terrain_table_title" : "em_table_title"),
                        hint: L10n.get(isRun ? "em_terrain_table_desc" : "em_table_desc")) { grid }
            }
            if !isRun, !view.polingRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button { withAnimation(.easeInOut(duration: 0.25)) { polingOpen.toggle() } } label: {
                        HStack {
                            Text(L10n.get("em_poling_matrix_title")).font(.subheadline.weight(.semibold))
                                .foregroundStyle(tone.title)
                            Spacer()
                            Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                                .foregroundStyle(tone.title)
                                .rotationEffect(.degrees(polingOpen ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.get(polingOpen ? "em_collapse" : "em_expand"))
                    if polingOpen {
                        Text(L10n.get("em_poling_matrix_desc")).font(.caption).foregroundStyle(tone.subtitle)
                        polingGrid
                    }
                }
            }
            if isRun, !view.geoRows.isEmpty {
                section(L10n.get("em_geo_title"), hint: L10n.get("em_geo_desc")) { geoGrid }
            }
            if isRun, !view.climbRows.isEmpty {
                section(L10n.get("em_climb_geo_title"), hint: L10n.get("em_climb_geo_desc")) { climbGrid }
            }
            if !view.splits.isEmpty {
                section(L10n.get("em_splits_title")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(Array(view.splits.enumerated()), id: \.offset) { index, split in
                            VStack(spacing: 2) {
                                Text("\(index + 1)").font(.caption2).foregroundStyle(tone.subtitle)
                                Text(split).font(.footnote.weight(.bold))
                            }
                        }
                    }
                    .padding(10)
                    .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            // The Garmin-sensor sections last, next to each other (Android: same order).
            if !view.climb.isEmpty {
                section(L10n.get("em_climb_title")) { tiles(view.climb) }
            }
            if !view.hrv.isEmpty || hasHrZones {
                section(L10n.get("em_hrv_title"), badge: view.hrv.isEmpty ? nil : hrvSourceName) {
                    if !view.hrv.isEmpty {
                        tiles(view.hrv)
                        Text(L10n.get("em_hrv_note")).font(.caption).foregroundStyle(tone.subtitle)
                    }
                    if hasHrZones { zoneDonut }
                    ForEach(view.zoneGroups, id: \.id) { group in zoneBars(group) }
                }
            }
            // After the heart rate section, like Android: the time -> technique -> zone Sankey (ski, watch after 0.9.120).
            if !isRun, let byTime = view.sankeyByTime {
                TechniqueSankeyChart(byTime: byTime, byLap: view.sankeyByLap)
            }
            // A sport without technique (kind "sensor": climb, heart rate zones, HRV) has nothing to explain or estimate.
            if view.kind != "sensor" {
                Button { explaining = true } label: {
                    Label(L10n.get("em_explain_link"), systemImage: "info.circle")
                }
                .buttonStyle(.borderless)
                Text(L10n.get(isRun ? "em_run_footnote" : "em_footnote"))
                    .font(.caption2).foregroundStyle(tone.subtitle)
            }
        }
        .sheet(isPresented: $explaining) { explanation }
        .environment(\.chartRegistry, registry)
    }

    private var zonePercents: [Double] { view.hrZones.map { Double(truncating: $0) } }

    private var hasHrZones: Bool { zonePercents.contains { $0 > 0 } }

    /// Share of the heart rate time per zone as a donut with a legend, in the watch's zone colours; a tap on a legend row
    /// picks the zone (Android: `HeartRateSection`).
    private var zoneDonut: some View {
        ChartFrame(title: L10n.get("ios_hr_zones"), tone: tone) { space in zoneDonutBody(space) }
    }

    /// The diameter of a donut: 124 pt in the card; full screen, as large as the height allows (at most half the width).
    private func donutSize(_ space: ChartSpace) -> CGFloat {
        space.maximized ? max(124, min(space.size.height - 24, space.size.width * 0.5)) : 124
    }

    /// The text in a donut's hole: Dynamic Type in the card, grown with the ring (`f` = ring size / 124) full screen.
    private func centerFont(_ f: CGFloat) -> Font { f > 1 ? .system(size: 15 * f, weight: .semibold) : .subheadline.weight(.semibold) }
    private func centerCaption(_ f: CGFloat) -> Font { f > 1 ? .system(size: 11 * f) : .caption2 }

    /// Seconds in zone `index` (0 = Z1), summed over the rows of the first zone group; nil without a tally.
    private func zoneSeconds(_ index: Int) -> Int? {
        guard let group = view.zoneGroups.first, !group.rows.isEmpty else { return nil }
        return group.rows.reduce(0) { total, row in
            index < row.seconds.count ? total + Int(truncating: row.seconds[index]) : total
        }
    }

    private func zoneDonutBody(_ space: ChartSpace) -> some View {
        let size = donutSize(space)
        let f = size / 124
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ZStack {
                    Chart(Array(zonePercents.enumerated()), id: \.offset) { index, percent in
                        SectorMark(angle: .value("share", max(percent, 0.1)),
                                   innerRadius: .ratio(0.62), outerRadius: .ratio(selectedZone == index ? 1.0 : 0.92),
                                   angularInset: 0.5)
                            .foregroundStyle(hrZoneColor(index + 1).opacity(selectedZone == nil || selectedZone == index ? 1 : 0.3))
                    }
                    .chartLegend(.hidden)
                    .frame(width: size, height: size)
                    .accessibilityLabel(L10n.get("ios_hr_zones"))
                    VStack(spacing: 0) {
                        if let zone = selectedZone {
                            Text("\(Int(zonePercents[zone]))%").font(centerFont(f))
                            Text("Z\(zone + 1)").font(centerCaption(f)).foregroundStyle(.secondary)
                            if space.maximized, let seconds = zoneSeconds(zone) {
                                Text(clock(seconds)).font(centerCaption(f)).foregroundStyle(.secondary)
                            }
                        } else if view.avgHeartRate > 0 {
                            Text("\(view.avgHeartRate)").font(centerFont(f))
                            Text("bpm").font(centerCaption(f)).foregroundStyle(.secondary)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<zonePercents.count, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { selectedZone = selectedZone == index ? nil : index }
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3).fill(hrZoneColor(index + 1)).frame(width: 12, height: 12)
                                Text(String(format: L10n.get("ios_zone_n"), index + 1))
                                    .font(.footnote.weight(selectedZone == index ? .bold : .regular))
                                Spacer(minLength: 4)
                                // Full screen: the time and the share as two right-aligned columns, like a table.
                                if space.maximized, zoneSeconds(0) != nil {
                                    Text(zoneSeconds(index).map { clock($0) } ?? "").font(.footnote).foregroundStyle(.secondary)
                                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                                }
                                Text("\(Int(zonePercents[index]))%").font(.footnote.weight(.bold))
                                    .monospacedDigit().frame(width: 48, alignment: .trailing)
                            }
                            .padding(.horizontal, 4).padding(.vertical, 3)
                            .background(selectedZone == index ? Color.primary.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// One stacked bar per technique, gait or terrain state: its seconds in zones 1 to 5 (Android: `HeartRateSection`).
    private func zoneBars(_ group: EmZoneGroup) -> some View {
        let title: String
        switch group.id {
        case "gait": title = L10n.get("em_hr_by_gait")
        case "terrain": title = L10n.get("em_hr_by_terrain")
        default: title = L10n.get("em_hr_by_technique")
        }
        return ChartFrame(title: title, tone: tone) { space in zoneBarRows(group, space) }
    }

    private func zoneBarRows(_ group: EmZoneGroup, _ space: ChartSpace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 10 * space.scale) {
                ForEach(group.rows, id: \.key) { row in
                    let seconds = row.seconds.map { Int(truncating: $0) }
                    let rowDim = group.rows.contains(where: { $0.key == selectedKey }) && selectedKey != row.key
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(stateColor(row.key)).frame(width: 10, height: 10)
                        Text(stateShort(row.key)).font(.footnote.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: group.id == "terrain" ? 92 : 52, alignment: .leading)
                        Chart(Array(seconds.enumerated()), id: \.offset) { index, value in
                            BarMark(x: .value("seconds", value))
                                .foregroundStyle(hrZoneColor(index + 1).opacity(selectedZone == nil || selectedZone == index ? 1 : 0.25))
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden).chartLegend(.hidden)
                        .frame(height: 16 * space.scale)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        // A picked zone dims the other zones and the column then shows the time in that zone.
                        Text(clock(selectedZone.map { $0 < seconds.count ? seconds[$0] : 0 } ?? seconds.reduce(0, +)))
                            .font(.caption.weight(selectedZone == nil ? .regular : .bold))
                            .foregroundStyle(selectedZone == nil ? tone.subtitle : Color.primary)
                            .monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    .opacity(rowDim ? 0.4 : 1)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSelection(row.key) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(stateShort(row.key)) \(clock(seconds.reduce(0, +)))")
                }
            }
            .padding(12)
            .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
            // The legend goes with the full-screen chart: what each zone colour is.
            if space.maximized {
                HStack(spacing: 16) {
                    ForEach(1...5, id: \.self) { zone in
                        legendDot(hrZoneColor(zone), "Z\(zone)")
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(selectedZone == zone - 1 ? Color.primary.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedZone = selectedZone == zone - 1 ? nil : zone - 1 }
                            }
                    }
                }
            }
        }
    }

    private var hrvSourceName: String? {
        switch view.hrvSource {
        case "strap": return L10n.get("em_src_strap")
        case "wrist": return L10n.get("em_src_wrist_sensor")
        default: return nil
        }
    }

    private var sourceName: String? {
        switch view.formSource {
        case "sensor": return L10n.get("em_src_sensor")
        case "wrist": return L10n.get("em_src_wrist")
        default: return nil
        }
    }

    private func section<C: View>(_ title: String, hint: String? = nil, badge: String? = nil,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tone.title)
                Spacer()
                if let badge {
                    Text(badge).font(.caption2.weight(.semibold)).foregroundStyle(tone.title)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(tone.border.opacity(0.35), in: Capsule())
                }
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(tone.subtitle) }
            content()
        }
    }

    private func tiles(_ values: [EmValue]) -> some View {
        // A Grid, not a LazyVGrid: both tiles of a row stretch to the taller one.
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: values.count, by: 2)), id: \.self) { start in
                GridRow {
                    tile(values[start])
                    if start + 1 < values.count {
                        tile(values[start + 1])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ value: EmValue) -> some View {
        if !isRun, view.charts.contains(where: { $0.id == value.key }) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { openChart = openChart == value.key ? nil : value.key }
            } label: { tileCard(value, chevron: true, open: openChart == value.key) }
                .buttonStyle(.plain)
        } else {
            tileCard(value, chevron: false, open: false)
        }
    }

    private func tileCard(_ value: EmValue, chevron: Bool, open: Bool) -> some View {
        let texts = tileTexts(value.key)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.value).font(.title.weight(.semibold))
                if !value.unit.isEmpty { Text(value.unit).font(.footnote).foregroundStyle(.secondary) }
                if chevron {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(tone.subtitle)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            Text(texts.abbreviation.map { "\(texts.name) (\($0))" } ?? texts.name)
                .font(.footnote.weight(.semibold))
            Text(texts.desc).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(open ? tone.subtitle : Color.clear, lineWidth: 2))
    }

    private func skiChartTitle(_ id: String) -> String {
        switch id {
        case "rate": return "SPM · /min"
        case "dps": return "DPS · m"
        case "apid": return "APID · ms"
        case "adc": return "ADC · %"
        default: return id
        }
    }

    private func runChartName(_ id: String) -> String {
        switch id {
        case "pace": return L10n.get("em_col_pace")
        case "gap": return L10n.get("em_col_gap")
        case "hr": return L10n.get("em_col_hr")
        case "gain": return L10n.get("em_col_gain")
        case "loss": return L10n.get("em_col_loss")
        default: return id
        }
    }

    /// Pace, GAP, heart rate, gain and loss by terrain, one metric at a time (chips choose); Android: `TerrainBars`.
    @ViewBuilder
    private var runCharts: some View {
        if !view.charts.isEmpty {
            let current = view.charts.first(where: { $0.id == selectedChart }) ?? view.charts[0]
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(view.charts, id: \.id) { chart in
                            if chart.id == current.id {
                                Button(runChartName(chart.id)) { selectedChart = chart.id }
                                    .buttonStyle(.borderedProminent).controlSize(.small)
                            } else {
                                Button(runChartName(chart.id)) { selectedChart = chart.id }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                MetricBars(title: runChartName(current.id), chart: current, highlight: selectedKey, onSelect: toggleSelection).id(current.id)
            }
        }
    }

    private func balance(_ left: Double) -> some View {
        let l = min(max(left, 1), 99)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.get("em_lr_name") + " (L/R)").font(.footnote.weight(.semibold))
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.techniqueBlue).frame(width: geo.size.width * l / 100)
                    Rectangle().fill(Color.techniqueOrange)
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack {
                Text(String(format: "L %.1f%%", left)).font(.footnote.weight(.bold))
                Spacer()
                Text(String(format: "R %.1f%%", 100 - left)).font(.footnote.weight(.bold))
            }
            Text(L10n.get("em_lr_desc")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gaitBar(_ space: ChartSpace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(view.gait, id: \.key) { share in
                BarMark(x: .value("share", Double(share.percent)))
                    .foregroundStyle(stateColor(share.key).opacity(gaitDim(share.key) ? 0.3 : 1))
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...100)
            .frame(height: 18 * space.scale)
            HStack {
                ForEach(view.gait, id: \.key) { share in
                    legendDot(stateColor(share.key),
                              "\(stateName(share.key)) \(Int(share.percent))% · \(clock(Int(share.seconds)))")
                        .opacity(gaitDim(share.key) ? 0.4 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleSelection(share.key) }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Whether a walk/run state fades because the other one is picked (on this bar or on the zone bars).
    private func gaitDim(_ key: String) -> Bool {
        view.gait.contains(where: { $0.key == selectedKey }) && selectedKey != key
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.footnote)
        }
    }

    /// The picked state when it is one of the donut's slices (a gait picked on the walk/run bar is not).
    private var terrainKey: String? {
        guard let key = selectedKey, view.shares.contains(where: { $0.key == key }) else { return nil }
        return key
    }

    /// A second tap on the picked state, or the legend row again, clears the selection.
    private func toggleSelection(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) { selectedKey = selectedKey == key ? nil : key }
        selectedAngle = nil
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) { selectedKey = nil }
        selectedAngle = nil
    }

    private func donut(_ space: ChartSpace) -> some View {
        let size = donutSize(space)
        let f = size / 124
        return HStack(spacing: 14) {
            ZStack {
                Chart(view.shares, id: \.key) { share in
                    SectorMark(angle: .value("share", Double(max(share.percent, 0.1))),
                               innerRadius: .ratio(0.62), outerRadius: .ratio(terrainKey == share.key ? 1.0 : 0.92),
                               angularInset: 0.5)
                        .foregroundStyle(stateColor(share.key).opacity(terrainKey == nil || terrainKey == share.key ? 1 : 0.3))
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $selectedAngle)
                .onChange(of: selectedAngle) { _, angle in
                    guard let angle else { return }
                    var end = 0.0
                    for share in view.shares {
                        end += Double(max(share.percent, 0.1))
                        if angle <= end { toggleSelection(share.key); break }
                    }
                }
                .frame(width: size, height: size)
                .accessibilityLabel(L10n.get("em_share_a11y"))
                if let key = terrainKey, let share = view.shares.first(where: { $0.key == key }) {
                    VStack(spacing: 0) {
                        Text("\(Int(share.percent))%").font(centerFont(f))
                        Text(stateShort(key)).font(centerCaption(f)).foregroundStyle(.secondary)
                        if space.maximized, share.seconds > 0 {
                            Text(clock(Int(share.seconds))).font(centerCaption(f)).foregroundStyle(.secondary)
                        }
                    }
                } else if view.totalSeconds > 0 {
                    VStack(spacing: 0) {
                        Text(clock(Int(view.totalSeconds))).font(centerFont(f))
                        Text(L10n.get("em_share_tracked")).font(centerCaption(f)).foregroundStyle(.secondary)
                    }
                }
                // The hole: a tap here clears the selection (the chart's angle selection would pick a slice).
                Color.clear.frame(width: 64 * f, height: 64 * f).contentShape(Circle())
                    .onTapGesture { clearSelection() }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(view.shares, id: \.key) { share in
                    Button { toggleSelection(share.key) } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(stateColor(share.key)).frame(width: 12, height: 12)
                            Text(stateName(share.key)).font(.footnote.weight(terrainKey == share.key ? .bold : .regular))
                            Spacer(minLength: 4)
                            if space.maximized, view.shares.contains(where: { $0.seconds > 0 }) {
                                Text(share.seconds > 0 ? clock(Int(share.seconds)) : "").font(.footnote).foregroundStyle(.secondary)
                                    .monospacedDigit().frame(width: 64, alignment: .trailing)
                            }
                            Text("\(Int(share.percent))%").font(.footnote.weight(.bold))
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 3)
                        .background(terrainKey == share.key ? Color.primary.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if isRun, view.uphillTotalPercent >= 0 {
                    Divider()
                    HStack(spacing: 8) {
                        Text(L10n.get("em_uphill_total")).font(.footnote)
                        Spacer(minLength: 4)
                        Text("\(Int(view.uphillTotalPercent))%").font(.footnote.weight(.bold))
                    }
                }
            }
        }
        .padding(12)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private var geoGrid: some View {
        VStack(spacing: 0) {
            gridRow([L10n.get("em_col_terrain"), L10n.get("em_col_distance"), L10n.get("em_col_distance_share"),
                     L10n.get("em_col_slope")], header: true, color: nil)
            Divider()
            ForEach(view.geoRows, id: \.key) { row in
                gridRow([stateShort(row.key)] + row.cells.map { $0 }, header: false, color: stateColor(row.key), key: row.key)
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private var polingGrid: some View {
        VStack(spacing: 0) {
            gridRow([L10n.get("em_col_technique"), "SPM\n/min", "DPS\nm", "APID\nms", "ADC\n%"], header: true, color: nil)
            Divider()
            ForEach(view.polingRows, id: \.key) { row in
                gridRow([stateShort(row.key)] + row.cells.map { $0 }, header: false, color: stateColor(row.key), key: row.key)
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private var climbGrid: some View {
        VStack(spacing: 0) {
            gridRow([L10n.get("em_col_terrain"), L10n.get("em_col_gain"), L10n.get("em_col_loss")], header: true, color: nil)
            Divider()
            ForEach(view.climbRows, id: \.key) { row in
                gridRow([stateShort(row.key)] + row.cells.map { $0 }, header: false, color: stateColor(row.key), key: row.key)
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private var headers: [String] {
        view.columns.map { column in
            switch column {
            case "time": return L10n.get("em_col_time")
            case "speed": return L10n.get("em_col_speed") + "\nkm/h"
            case "hr": return L10n.get("em_col_hr")
            case "dps": return L10n.get("em_col_dps")
            case "pace": return L10n.get("em_col_pace")
            case "gap": return L10n.get("em_col_gap")
            default: return column
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            gridRow([L10n.get(isRun ? "em_col_terrain" : "em_col_technique")] + headers, header: true, color: nil)
            Divider()
            ForEach(view.rows, id: \.key) { row in
                gridRow([stateShort(row.key)] + row.cells.map { $0 }, header: false, color: stateColor(row.key), key: row.key)
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    /// One table row. With a `key` it is part of the interaction: the state picked on a chart marks it and fades the
    /// others, and a tap picks (or clears) it (Android: `GridRow`).
    private func gridRow(_ cells: [String], header: Bool, color: Color?, key: String? = nil) -> some View {
        let marked = key != nil && selectedKey == key
        let dim = key != nil && selectedKey != nil && selectedKey != key
        return HStack(alignment: header ? .bottom : .center, spacing: 4) {
            HStack(spacing: 6) {
                if let color { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10) }
                Text(cells[0]).font(header ? .caption2 : .footnote.weight(.bold))
                    .foregroundStyle(header ? Color.secondary : Color.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(1..<cells.count, id: \.self) { index in
                Text(cells[index]).font(header ? .caption2 : .footnote)
                    .foregroundStyle(header ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, header ? 6 : 8)
        .padding(.horizontal, 4)
        .background(marked ? Color.primary.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .opacity(dim ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if let key { toggleSelection(key) } }
    }

    private var explanation: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(explainKeys, id: \.self) { key in
                        let texts = tileTexts(key)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(texts.abbreviation.map { "\(texts.name) (\($0))" } ?? texts.name).font(.subheadline.weight(.bold))
                            Text(texts.desc).font(.subheadline)
                        }
                    }
                    if isRun {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.get("em_gap_name") + " (GAP)").font(.subheadline.weight(.bold))
                            Text(L10n.get("em_gap_desc")).font(.subheadline)
                        }
                    }
                }
                Section(L10n.get(isRun ? "em_terrain_title" : "em_sheet_techniques")) {
                    ForEach(stateKeysForSheet, id: \.self) { key in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 3).fill(stateColor(key)).frame(width: 12, height: 12).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stateName(key)).font(.footnote.weight(.bold))
                                Text(stateDescription(key)).font(.footnote)
                            }
                        }
                    }
                    if isRun { Text(L10n.get("em_terrain_method")).font(.footnote) }
                }
            }
            .navigationTitle(L10n.get("em_sheet_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("em_sheet_close")) { explaining = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var explainKeys: [String] {
        isRun ? ["eff", "fade", "gct", "vo", "vr"] : ["rate", "dps", "apid", "adc"]
    }

    private var stateKeysForSheet: [String] {
        isRun ? ["STEEP", "UP", "FLAT", "DOWN", "STEEP_DOWN"] : view.shares.map { $0.key }.filter { $0 != "OTHER" }
    }

    private func stateDescription(_ key: String) -> String {
        switch key {
        case "V2": return L10n.get("em_desc_v2")
        case "V1": return L10n.get("em_desc_v1")
        case "V2A": return L10n.get("em_desc_v2a")
        case "DP": return L10n.get("em_desc_dp")
        case "DIA": return L10n.get("em_desc_dia")
        case "KDP": return L10n.get("em_desc_kdp")
        case "KLAEBO": return L10n.get("em_desc_klaebo")
        case "GLIDE": return L10n.get("em_desc_glide")
        case "UP": return L10n.get("em_desc_up")
        case "FLAT": return L10n.get("em_desc_flat")
        case "DOWN": return L10n.get("em_desc_down")
        case "STEEP": return L10n.get("em_desc_steep")
        case "STEEP_DOWN": return L10n.get("em_desc_steep_down")
        default: return ""
        }
    }
}
