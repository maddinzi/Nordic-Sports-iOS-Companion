import Charts
import NordicSportsShared
import SwiftUI

/// The tinted card look of the activity detail screen, as on Android (`CardTone` in Theme.kt):
/// a light tint, a thin frame in the same hue and a title in a dark shade of it.
enum CardTone {
    case blue, red, green, yellow, orange, purple, teal, grey

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
        case .yellow: return Self.dyn(0x7A5E10, 0xD4BE70)
        case .orange: return Self.dyn(0x9A4B12, 0xE0AE85)
        case .purple: return Self.dyn(0x5E4290, 0xB9A3D6)
        case .teal: return Self.dyn(0x2A6B67, 0x94C8C4)
        case .grey: return Self.dyn(0x515A64, 0xA9B3BE)
        }
    }

    /// The tile and badge backgrounds inside a card of this tone.
    var tile: Color { Self.dyn(0xFFFFFF, 0x1B3550) }
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

private extension Color {
    static let techniqueBlue = Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)
    static let techniqueOrange = Color(red: 0xE0 / 255, green: 0x8A / 255, blue: 0x1E / 255)
    static let techniquePurple = Color(red: 0x7B / 255, green: 0x4F / 255, blue: 0xA8 / 255)
    static let techniqueTeal = Color(red: 0x1E / 255, green: 0x9A / 255, blue: 0x8A / 255)
    static let techniqueGrey = Color(red: 0x8D / 255, green: 0x99 / 255, blue: 0xA6 / 255)
    static let techniqueLight = Color(red: 0xCF / 255, green: 0xD6 / 255, blue: 0xDD / 255)
    static let terrainRed = Color(red: 0xC0 / 255, green: 0x39 / 255, blue: 0x2B / 255)
}

/// Colour per catalog state: techniques (V2, V1, ...) and terrain (UP, FLAT, ...).
private func stateColor(_ key: String) -> Color {
    switch key {
    case "V2", "DIA", "RUN": return .techniqueBlue
    case "V1", "KDP", "UP": return .techniqueOrange
    case "DP", "DOWN": return .techniquePurple
    case "V2A", "FLAT": return .techniqueTeal
    case "GLIDE", "WALK": return .techniqueGrey
    case "STEEP": return .terrainRed
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
    case "GLIDE": return L10n.get("strava_analysis_glide")
    case "OTHER": return L10n.get("strava_analysis_other")
    case "UP": return L10n.get("em_up")
    case "FLAT": return L10n.get("em_flat")
    case "DOWN": return L10n.get("em_down")
    case "STEEP": return L10n.get("em_steep")
    case "RUN": return L10n.get("em_run")
    case "WALK": return L10n.get("em_walk")
    default: return key
    }
}

/// The short code in the grid: GLIDE and OTHER in words, the rest as is.
private func stateShort(_ key: String) -> String {
    switch key {
    case "GLIDE", "OTHER", "UP", "FLAT", "DOWN", "STEEP": return stateName(key)
    default: return key
    }
}

private func clock(_ totalSeconds: Int) -> String {
    let h = totalSeconds / 3600, m = totalSeconds % 3600 / 60, s = totalSeconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
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

    private var isRun: Bool { view.kind == "run" }

    var body: some View {
        ToneGroup(title: L10n.get("em_title"),
                  subtitle: L10n.get(isRun ? "em_run_subtitle" : "em_subtitle"), tone: tone) {
            if !view.headline.isEmpty {
                section(L10n.get(isRun ? "em_run_eff_title" : "em_poling_title")) { tiles(view.headline) }
            }
            if isRun, !view.form.isEmpty || view.balanceLeft > 0 {
                section(L10n.get("em_form_title"), badge: sourceName) {
                    tiles(view.form)
                    if view.balanceLeft > 0 { balance(Double(view.balanceLeft)) }
                }
            }
            if isRun, !view.gait.isEmpty { section(L10n.get("em_gait_title")) { gaitBar } }
            if !view.shares.isEmpty {
                section(L10n.get(isRun ? "em_terrain_title" : "em_share_title"),
                        hint: L10n.get(isRun ? "em_terrain_desc" : "em_share_desc")) { donut }
            }
            if !view.rows.isEmpty {
                section(L10n.get(isRun ? "em_terrain_table_title" : "em_table_title"),
                        hint: L10n.get(isRun ? "em_terrain_table_desc" : "em_table_desc")) { grid }
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
            Button { explaining = true } label: {
                Label(L10n.get("em_explain_link"), systemImage: "info.circle")
            }
            .buttonStyle(.borderless)
            Text(L10n.get(isRun ? "em_run_footnote" : "em_footnote"))
                .font(.caption2).foregroundStyle(tone.subtitle)
        }
        .sheet(isPresented: $explaining) { explanation }
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)],
                  spacing: 8) {
            ForEach(values, id: \.key) { value in
                let texts = tileTexts(value.key)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value.value).font(.title.weight(.semibold))
                        if !value.unit.isEmpty { Text(value.unit).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Text(texts.abbreviation.map { "\(texts.name) (\($0))" } ?? texts.name)
                        .font(.footnote.weight(.semibold))
                    Text(texts.desc).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
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

    private var gaitBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(view.gait, id: \.key) { share in
                BarMark(x: .value("share", Double(share.percent)))
                    .foregroundStyle(stateColor(share.key))
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...100)
            .frame(height: 18)
            HStack {
                ForEach(view.gait, id: \.key) { share in
                    legendDot(stateColor(share.key),
                              "\(stateName(share.key)) \(Int(share.percent))% · \(clock(Int(share.seconds)))")
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text).font(.footnote)
        }
    }

    private var donut: some View {
        HStack(spacing: 14) {
            ZStack {
                Chart(view.shares, id: \.key) { share in
                    SectorMark(angle: .value("share", Double(max(share.percent, 0.1))), innerRadius: .ratio(0.62), angularInset: 0.5)
                        .foregroundStyle(stateColor(share.key))
                }
                .chartLegend(.hidden)
                .frame(width: 124, height: 124)
                .accessibilityLabel(L10n.get("em_share_a11y"))
                if view.totalSeconds > 0 {
                    VStack(spacing: 0) {
                        Text(clock(Int(view.totalSeconds))).font(.subheadline.weight(.semibold))
                        Text(L10n.get("em_share_tracked")).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(view.shares, id: \.key) { share in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(stateColor(share.key)).frame(width: 12, height: 12)
                        Text(stateName(share.key)).font(.footnote)
                        Spacer(minLength: 4)
                        Text("\(Int(share.percent))%").font(.footnote.weight(.bold))
                    }
                }
            }
        }
        .padding(12)
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
                gridRow([stateShort(row.key)] + row.cells.map { $0 }, header: false, color: stateColor(row.key))
                Divider().opacity(0.4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gridRow(_ cells: [String], header: Bool, color: Color?) -> some View {
        HStack(alignment: header ? .bottom : .center, spacing: 4) {
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
        isRun ? ["UP", "FLAT", "DOWN", "STEEP"] : view.shares.map { $0.key }.filter { $0 != "OTHER" }
    }

    private func stateDescription(_ key: String) -> String {
        switch key {
        case "V2": return L10n.get("em_desc_v2")
        case "V1": return L10n.get("em_desc_v1")
        case "V2A": return L10n.get("em_desc_v2a")
        case "DP": return L10n.get("em_desc_dp")
        case "DIA": return L10n.get("em_desc_dia")
        case "KDP": return L10n.get("em_desc_kdp")
        case "GLIDE": return L10n.get("em_desc_glide")
        case "UP": return L10n.get("em_desc_up")
        case "FLAT": return L10n.get("em_desc_flat")
        case "DOWN": return L10n.get("em_desc_down")
        case "STEEP": return L10n.get("em_desc_steep")
        default: return ""
        }
    }
}
