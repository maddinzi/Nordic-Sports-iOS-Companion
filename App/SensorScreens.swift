import SwiftUI
import NordicSportsShared

// The Sensor mode of an activity and the charts of one Sensor Record (Android `ActivitySensor.kt`, `BurstScreen.kt`,
// `BurstCrop.kt`). Everything is computed in the shared `BurstAnalysis` (`CompanionCore.burstView`); this file draws.

extension KotlinFloatArray {
    var swiftArray: [Float] { (0..<Int(size)).map { get(index: Int32($0)) } }
}

extension KotlinDoubleArray {
    var swiftArray: [Double] { (0..<Int(size)).map { get(index: Int32($0)) } }
}

/// The Sensor mode: the Sensor Records of this activity, one at a time with all their charts; with several, chips on top
/// (number, time, technique) pick one and a swipe pages through them in capture order.
struct SensorModeView: View {
    let bursts: [RecordingBoostView]
    @State private var page = 0

    private var sorted: [RecordingBoostView] { bursts.sorted { $0.burstId < $1.burstId } }

    var body: some View {
        VStack(spacing: 0) {
            if sorted.count > 1 {
                // The shared pill row: the open record centred, a menu with all of them when they do not fit.
                PartPills(pills: sorted.enumerated().map { i, b in
                    PartPill(id: b.id, label: chipLabel(i, b), selected: page == i) { withAnimation { page = i } }
                }, light: true)
                .padding(.horizontal, 12).padding(.vertical, 4)
            } else if let only = sorted.first {
                Text(chipLabel(-1, only)).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 2)
            }
            TabView(selection: $page) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { i, b in
                    SensorRecordView(burstId: b.id).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    /// "2 · 10:06 · DP"; [index] -1 leaves out the number (a single record).
    private func chipLabel(_ index: Int, _ b: RecordingBoostView) -> String {
        var parts: [String] = []
        if index >= 0 { parts.append("\(index + 1)") }
        parts.append(Date(timeIntervalSince1970: TimeInterval(b.burstId)).formatted(date: .omitted, time: .shortened))
        if !b.labelTechnique.isEmpty { parts.append(stateShort(b.labelTechnique)) }
        return parts.joined(separator: " · ")
    }
}

private enum BurstPage: String, CaseIterable {
    case stroke, rhythm, path, context
    var label: String { L10n.get("burst_page_\(rawValue)") }
}

/// The charts of one Sensor Record: the time window, the page pills, the summary card and the open page.
struct SensorRecordView: View {
    @EnvironmentObject var companion: Companion
    let burstId: String
    /// An Upload button in the bar that opens "Send Recording Boost data" with this record chosen (Android `BurstScreen`
    /// onUpload); off where the view is part of an activity's Sensor mode.
    var showUpload = false
    @State private var uploading = false
    /// The phone's motion record of this Sensor Record (`PhoneMotionCapture`), nil for the watch alone.
    @State private var phoneText: String?
    /// The phone's curves are shown unless its chip hides them (the chips exist only with a phone record).
    @State private var showPhone = true
    @State private var full: BurstView?
    @State private var shown: BurstView?
    /// The time window in seconds; nil = the whole record (Android `BurstScreen` from/to).
    @State private var window: BurstWindow?
    @State private var page: BurstPage = .stroke
    @State private var failed = false
    @State private var facts: BurstFacts?
    /// The record's label and technique choices (its sport only), for the technique menu.
    @State private var record: RecordingBoostView?

    /// Saves [code] as the declared technique ("" clears it). The rest of a label stays; a first label also takes
    /// the record's terrain and poles suggestion, as the label sheet does (Android `BurstScreen` onTechnique).
    private func pickTechnique(_ code: String) {
        guard let r = record else { return }
        let first = r.labelSummary.isEmpty
        let terrain = first && r.terrainOptions.contains(r.suggestedTerrain) ? r.suggestedTerrain : r.labelTerrain
        let poles: Int32 = first ? (r.askPoles ? r.suggestedPoles : -1) : r.labelPoles
        Task {
            do {
                try await companion.labelBoost(id: r.id, technique: code, terrain: terrain, poles: poles, note: r.labelNote, surface: r.labelSurface)
                record = try? await companion.core.recordingBoosts().first { $0.id == burstId }
            } catch {
                if !error.isCancellation { WatchLinkSpike.shared.add("Sensor Record technique not saved: \(error.localizedDescription)") }
            }
        }
    }

    var body: some View {
        Group {
            if let v = shown ?? full {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let overlay = full?.phone {
                            SourceRow(phone: overlay, shown: $showPhone)
                        }
                        if let full {
                            CropBar(view: full, window: $window, phoneEnvelope: showPhone ? full.phone?.envelope.swiftArray : nil) {
                                if let record, !record.techniqueOptions.isEmpty {
                                    TechniqueMenu(options: record.techniqueOptions, current: record.labelTechnique, onPick: pickTechnique)
                                }
                            }
                        }
                        Picker("", selection: $page) {
                            ForEach(BurstPage.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        BurstHero(v: v)
                        switch page {
                        case .stroke: StrokePage(v: v, phone: showPhone ? v.phone : nil)
                        case .rhythm: RhythmPage(v: v, phone: showPhone ? v.phone : nil)
                        case .path: PathPage(v: v)
                        case .context: ContextPage(v: v, facts: facts)
                        }
                        Text(L10n.get("burst_caveat")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
            } else {
                Text(L10n.get(failed ? "burst_no_data" : "burst_computing")).padding(24)
            }
        }
        .task(id: burstId) {
            record = try? await companion.core.recordingBoosts().first { $0.id == burstId }
            // The phone's file is found by the watch's record id (its name ends in "-<id>-phone.csv").
            if let r = record { phoneText = PhoneMotionCapture.storedText(burstId: r.burstId) }
            full = try? await companion.core.burstView(id: burstId, fromS: -1, toS: -1, phoneText: phoneText)
            facts = try? await companion.core.burstFacts(id: burstId)
            failed = full == nil
        }
        .task(id: window) {
            guard let window else { shown = nil; return }
            shown = try? await companion.core.burstView(id: burstId, fromS: window.from, toS: window.to, phoneText: phoneText)
        }
        .toolbar {
            if showUpload {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.get("feedback_boost_reminder_upload")) { uploading = true }
                }
            }
        }
        .modifier(UploadDestination(on: showUpload, presented: $uploading, burstId: burstId))
    }
}

/// The Upload button's target, attached only where the button exists: an activity's Sensor mode pages through its
/// records in a lazy container, where SwiftUI ignores (and warns about) a navigation destination.
private struct UploadDestination: ViewModifier {
    let on: Bool
    @Binding var presented: Bool
    let burstId: String

    func body(content: Content) -> some View {
        if on {
            content.navigationDestination(isPresented: $presented) {
                FeedbackScreen(startCategory: "boost", preselectActivityId: "burst:\(burstId)")
            }
        } else {
            content
        }
    }
}

/// The phone's curves: one colour everywhere, dashed, so they read as the second device (Android `PHONE_COLOR`).
let phoneColor = Color(red: 0x1E / 255, green: 0x9E / 255, blue: 0x8A / 255)

/// Which devices the charts show (Android `SourceRow`): the watch always, the phone with where it was carried. A tap on
/// the phone hides or shows its curves; the line under it says how the two clocks were matched.
private struct SourceRow: View {
    let phone: PhoneOverlay
    @Binding var shown: Bool

    private var placement: String {
        ["chest", "belt", "pocket", "backpack", "hand"].contains(phone.placement)
            ? L10n.get("phone_motion_placement_\(phone.placement)") : phone.placement
    }

    /// The name for a `PhoneTrunkTechnique.Verdict` (by its Kotlin name: DP, V1, SKATING).
    private func trunkName(_ verdict: String) -> String {
        switch verdict {
        case "DP": return L10n.get("technique_name_dp")
        case "V1": return L10n.get("technique_name_v1")
        default: return L10n.get("burst_phone_trunk_skating")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Label(L10n.get("burst_source_watch"), systemImage: "applewatch")
                    .font(.subheadline).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                Button { shown.toggle() } label: {
                    Label([L10n.get("burst_source_phone"), placement].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "iphone")
                        .font(.subheadline).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(shown ? phoneColor : .secondary)
                        .background((shown ? phoneColor : Color.secondary).opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if shown {
                Text(phone.byMotion ? String(format: L10n.get("burst_phone_by_motion"), String(format: "%.2f", phone.r))
                                    : L10n.get("burst_phone_by_clock"))
                    .font(.caption2).foregroundStyle(.secondary)
                // What the phone alone makes of the technique (Android `SourceRow`): skating records with the phone
                // on the trunk only; double pole, V1, or no more than "skating". Experimental.
                if let trunk = phone.trunk {
                    Text(String(format: L10n.get("burst_phone_trunk"), trunkName(trunk.verdict.name)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A legend entry with the device's symbol in front: which curve is the watch's and which the phone's.
private struct DeviceLegend: View {
    let symbol: String
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(text).font(.caption)
        }
    }
}

/// A part of a Sensor Record, in seconds from its start.
struct BurstWindow: Equatable {
    var from: Double
    var to: Double
}

/// The time window (Android `CropBar`): the movement strength over the record with the arm cycles marked and the window
/// framed. Drag either end, or the window itself, to change it; "All" or "One cycle" with the arrows to the previous
/// and next cycle. The charts follow when a drag ends or a button is pressed.
private struct CropBar<Trailing: View>: View {
    let view: BurstView
    @Binding var window: BurstWindow?
    /// The phone's strength over time (same tenth-of-a-second bins), a line over the watch's bars; nil = watch only.
    var phoneEnvelope: [Float]? = nil
    /// At the right end of the All / One cycle row: the technique menu.
    @ViewBuilder var trailing: () -> Trailing
    /// The window shown while dragging (follows [window] otherwise).
    @State private var dragFrom = 0.0
    @State private var dragTo = 0.0
    /// What the touch took: 1 the start, 2 the end, 3 the window, 0 nothing; nil before the drag.
    @State private var part: Int?
    @State private var lastX: CGFloat = 0
    /// Computed: a generic type cannot hold a stored static.
    private static var minWindow: Double { 1.0 }

    private var total: Double { max(view.seconds, 0.1) }
    private var bounds: [(Double, Double)] {
        view.cycleBoundsS.map { (($0.first as? KotlinDouble)?.doubleValue ?? 0, ($0.second as? KotlinDouble)?.doubleValue ?? 0) }
    }
    /// The cycle the window is on, -1 for none.
    private var cycle: Int {
        guard let window else { return -1 }
        return bounds.firstIndex { abs($0.0 - window.from) < 0.06 && abs($0.1 - window.to) < 0.06 } ?? -1
    }

    private func setCycle(_ i: Int) {
        let all = bounds
        guard i >= 0, i < all.count else { return }
        window = BurstWindow(from: all[i].0, to: all[i].1)
    }

    private func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    /// The x position of second [s] on a bar [w] wide with [pad] at each side.
    private func xOf(_ s: Double, _ w: CGFloat, _ pad: CGFloat) -> CGFloat { pad + w * CGFloat(s / total) }

    private func drag(_ g: DragGesture.Value, _ w: CGFloat, _ pad: CGFloat) {
        if part == nil {
            let hit: CGFloat = 28
            let ds = abs(g.startLocation.x - xOf(dragFrom, w, pad))
            let de = abs(g.startLocation.x - xOf(dragTo, w, pad))
            if ds <= hit && ds <= de {
                part = 1
            } else if de <= hit {
                part = 2
            } else if g.startLocation.x >= xOf(dragFrom, w, pad) && g.startLocation.x <= xOf(dragTo, w, pad) {
                part = 3
            } else {
                part = 0
            }
            lastX = g.startLocation.x
        }
        let seconds = Double((g.location.x - lastX) / w) * total
        lastX = g.location.x
        switch part {
        case 1: dragFrom = min(max(dragFrom + seconds, 0), dragTo - Self.minWindow)
        case 2: dragTo = min(max(dragTo + seconds, dragFrom + Self.minWindow), total)
        case 3:
            let len = dragTo - dragFrom
            dragFrom = min(max(dragFrom + seconds, 0), total - len)
            dragTo = dragFrom + len
        default: break
        }
    }

    private func dragEnded() {
        if let p = part, p != 0 {
            window = dragFrom <= 0.05 && dragTo >= total - 0.05 ? nil : BurstWindow(from: dragFrom, to: dragTo)
        }
        part = nil
    }

    var body: some View {
        let envelope = view.envelope.swiftArray
        let top = max(envelope.max() ?? 1, 0.2)
        let all = bounds
        let current = cycle
        let best = Int(view.bestCycle)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.get("burst_crop_title")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: L10n.get("burst_crop_range"), f1(dragFrom), f1(dragTo), f1(dragTo - dragFrom)))
                    .font(.caption).monospacedDigit()
                ChartInfoButton(title: L10n.get("burst_crop_title"), text: L10n.get("burst_crop_hint"))
            }
            GeometryReader { geo in
                let pad: CGFloat = 8
                let w = max(geo.size.width - 2 * pad, 1)
                Canvas { ctx, size in
                    let base = size.height - 6
                    let tall = size.height - 16
                    let bar = w / CGFloat(max(envelope.count, 1))
                    for (i, v) in envelope.enumerated() {
                        let h = tall * CGFloat(min(max(v / top, 0.02), 1))
                        ctx.fill(Path(CGRect(x: pad + CGFloat(i) * bar, y: base - h, width: max(bar - 0.5, 0.5), height: h)),
                                 with: .color(.secondary.opacity(0.55)))
                    }
                    // The phone's strength on its own scale, a line through the bars' centres.
                    if let pe = phoneEnvelope, pe.count > 1 {
                        let ptop = max(pe.max() ?? 1, 0.05)
                        let pbar = w / CGFloat(pe.count)
                        var line = Path()
                        for (i, v) in pe.enumerated() {
                            let pt = CGPoint(x: pad + (CGFloat(i) + 0.5) * pbar, y: base - tall * CGFloat(min(max(v / ptop, 0), 1)))
                            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                        }
                        ctx.stroke(line, with: .color(phoneColor), lineWidth: 1.5)
                    }
                    // The arm cycles: a tick at each start, the proposed one stronger.
                    for (i, c) in all.enumerated() {
                        let xs = xOf(c.0, w, pad)
                        var tick = Path()
                        tick.move(to: CGPoint(x: xs, y: 4))
                        tick.addLine(to: CGPoint(x: xs, y: base))
                        ctx.stroke(tick, with: .color(.accentColor.opacity(i == best ? 0.9 : 0.45)), lineWidth: i == best ? 2 : 1)
                    }
                    // Outside the window dimmed, the window framed, a handle at each end.
                    let a = xOf(dragFrom, w, pad)
                    let b = xOf(dragTo, w, pad)
                    let dim = Color(.secondarySystemBackground).opacity(0.7)
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: a, height: size.height)), with: .color(dim))
                    ctx.fill(Path(CGRect(x: b, y: 0, width: size.width - b, height: size.height)), with: .color(dim))
                    ctx.stroke(Path(roundedRect: CGRect(x: a, y: 1, width: b - a, height: size.height - 2), cornerRadius: 6),
                               with: .color(.accentColor), lineWidth: 2)
                    for edge in [a, b] {
                        ctx.fill(Path(roundedRect: CGRect(x: edge - 3, y: 8, width: 6, height: size.height - 16), cornerRadius: 3),
                                 with: .color(.accentColor))
                    }
                }
                .contentShape(Rectangle())
                // Over the ScrollView's own drag: the bar is short, the page still scrolls above and below it.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag($0, w, pad) }
                        .onEnded { _ in dragEnded() }
                )
            }
            .frame(height: 64)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement()
            .accessibilityLabel(L10n.get("burst_crop_title"))
            HStack(spacing: 8) {
                Button(L10n.get("burst_crop_all")) { window = nil }
                    .buttonStyle(.bordered).tint(window == nil ? .accentColor : .secondary)
                Button(L10n.get("burst_crop_cycle")) { setCycle(current >= 0 ? current : max(best, 0)) }
                    .buttonStyle(.bordered).tint(current >= 0 ? .accentColor : .secondary).disabled(all.isEmpty)
                if current >= 0 {
                    Button { setCycle(current - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(current <= 0).accessibilityLabel(L10n.get("burst_crop_prev"))
                    Button { setCycle(current + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(current >= all.count - 1).accessibilityLabel(L10n.get("burst_crop_next"))
                }
                Spacer(minLength: 4)
                trailing()
            }
        }
        // Outside a drag the shown window is the chosen one (the whole record for nil).
        .onChange(of: window, initial: true) { _, chosen in
            dragFrom = chosen?.from ?? 0
            dragTo = chosen?.to ?? total
        }
    }
}

/// Declare the technique on the go (Android `TechniqueDropdown`): a small button with the declared technique (or
/// "Technique"), its list limited to this record's sport, plus "mixed" and "–" to clear.
private struct TechniqueMenu: View {
    let options: [String]
    let current: String
    let onPick: (String) -> Void

    private func name(_ code: String) -> String { code == "MIXED" ? L10n.get("recording_boost_label_mixed") : stateName(code) }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { code in
                Button { if code != current { onPick(code) } } label: {
                    if code == current { Label(name(code), systemImage: "checkmark") } else { Text(name(code)) }
                }
            }
            if !current.isEmpty {
                Divider()
                Button("–") { onPick("") }
            }
        } label: {
            HStack(spacing: 2) {
                Text(current.isEmpty ? L10n.get("recording_boost_label_technique") : name(current))
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .tint(current.isEmpty ? .secondary : .accentColor)
    }
}

/// The answer first: four numbers; the sentence that spells them out sits behind (i).
private struct BurstHero: View {
    let v: BurstView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if v.rhythmic && v.cycleCount > 0 {
                HStack(spacing: 8) {
                    tile(String(format: "%.2f s", v.cycleS), L10n.get("burst_tile_cycle"))
                    tile("\(v.swingsPerMin)", L10n.get("burst_tile_rate"))
                    tile("\(Int((v.steadiness * 100).rounded())) %", L10n.get("burst_tile_steady"))
                    tile(String(format: "%.1f g", v.peakAccelG), L10n.get("burst_tile_peak"))
                }
            } else {
                Text(L10n.get("burst_no_rhythm")).font(.subheadline)
            }
            HStack {
                Text(String(format: L10n.get("burst_evidence"), Int(v.seconds.rounded()), Int(v.cycleCount)))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if v.rhythmic && v.cycleCount > 0 {
                    ChartInfoButton(title: L10n.get("burst_tile_cycle"),
                                    text: String(format: L10n.get("burst_sentence"), String(format: "%.2f", v.cycleS),
                                                 Int(v.swingsPerMin), Int(v.cycleCount), steadyWord(v.steadiness)))
                }
            }
        }
        .padding(12)
        .background(CardTone.blue.container, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CardTone.blue.border))
    }

    private func steadyWord(_ s: Double) -> String {
        L10n.get(s >= 0.9 ? "burst_steady_high" : s >= 0.75 ? "burst_steady_mid" : "burst_steady_low")
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// How to read a page (its first chart's (i)), followed by how to read a single value.
private func pageInfo(_ keys: [String]) -> String {
    (keys.map { L10n.get($0) } + [L10n.get("burst_sel_hint")]).joined(separator: "\n\n")
}

private func burstCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 8) { content() }
        .padding(12)
        .background(CardTone.blue.container, in: RoundedRectangle(cornerRadius: 14))
}

/// What a tap picked, empty until something is picked.
private struct Readout: View {
    let text: String?
    var body: some View {
        if let text { Text(text).font(.caption.weight(.semibold)) }
    }
}

private struct LegendSwatch: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 10)
            Text(text).font(.caption)
        }
    }
}

/// The height of a chart's drawing: [inline] in its card, nearly all of it full screen (legend and readout below).
private func chartHeight(_ space: ChartSpace, _ inline: CGFloat) -> CGFloat {
    space.maximized ? max(space.size.height - 90, inline) : inline
}

/// Dotted guides up from the time labels, so the numbers read as the time axis.
private func timeGuides(_ ctx: GraphicsContext, xs: [CGFloat], top: CGFloat, bottom: CGFloat) {
    for x in xs {
        var p = Path(); p.move(to: CGPoint(x: x, y: top)); p.addLine(to: CGPoint(x: x, y: bottom + 2))
        ctx.stroke(p, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
    }
}

// MARK: Stroke

private struct StrokePage: View {
    let v: BurstView
    /// The phone over the same arm cycles (dashed, own scale); nil = watch only.
    var phone: PhoneOverlay? = nil
    @State private var selA: Int?
    @State private var selG: Int?

    var body: some View {
        if let a = v.strokeAccel, let g = v.strokeGyro {
            burstCard {
                ChartFrame(title: L10n.get("burst_stroke_accel"),
                           info: pageInfo(phone != nil ? ["burst_read_stroke", "burst_read_phone"] : ["burst_read_stroke"])) { space in
                    BandChart(band: a, cycleS: v.cycleS, color: .accentColor, unit: "g", space: space, selected: $selA, phone: phone?.strokeAccel)
                }
                ChartFrame(title: L10n.get("burst_stroke_gyro")) { space in
                    BandChart(band: g, cycleS: v.cycleS, color: .accentColor, unit: "°/s", space: space, selected: $selG,
                              phone: phone?.strokeGyro, phoneGyro: true)
                }
            }
        } else {
            burstCard { Text(L10n.get("burst_no_rhythm")).font(.footnote) }
        }
    }
}

/// The average cycle (line) and the middle half of all cycles (band); a tap reads one point.
private struct BandChart: View {
    let band: StrokeBand
    let cycleS: Double
    let color: Color
    let unit: String
    let space: ChartSpace
    @Binding var selected: Int?
    /// The phone's median over the same cycles: dashed, on its own scale (right edge), so its timing compares.
    var phone: StrokeBand? = nil
    /// The phone's curve is its rotation speed |ω| (the watch's is the arm's turn about Z).
    var phoneGyro = false

    var body: some View {
        let median = band.median.swiftArray, q1 = band.q1.swiftArray, q3 = band.q3.swiftArray
        let n = median.count
        let pm = phone.map { $0.median.swiftArray }.flatMap { $0.count == n ? $0 : nil }
        let lo = min(q1.min() ?? 0, median.min() ?? 0), hi = max(q3.max() ?? 1, median.max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let left: CGFloat = 36, top: CGFloat = 10, bottom = geo.size.height - 16
                let w = geo.size.width - left - 8
                let x = { (i: Int) -> CGFloat in left + w * CGFloat(i) / CGFloat(max(n - 1, 1)) }
                let y = { (v: Float) -> CGFloat in bottom - (bottom - top) * CGFloat((v - lo) / max(hi - lo, 1e-6)) }
                Canvas { ctx, size in
                    timeGuides(ctx, xs: [x(0), x(n - 1)], top: top, bottom: bottom)
                    var area = Path()
                    area.move(to: CGPoint(x: x(0), y: y(q3[0])))
                    for i in 1..<n { area.addLine(to: CGPoint(x: x(i), y: y(q3[i]))) }
                    for i in stride(from: n - 1, through: 0, by: -1) { area.addLine(to: CGPoint(x: x(i), y: y(q1[i]))) }
                    area.closeSubpath()
                    ctx.fill(area, with: .color(color.opacity(0.18)))
                    var line = Path()
                    line.move(to: CGPoint(x: x(0), y: y(median[0])))
                    for i in 1..<n { line.addLine(to: CGPoint(x: x(i), y: y(median[i]))) }
                    ctx.stroke(line, with: .color(color), lineWidth: 2.5)
                    let fmt = hi - lo < 20 ? "%.1f" : "%.0f"
                    ctx.draw(Text(String(format: fmt, hi)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 2, y: top), anchor: .leading)
                    ctx.draw(Text(String(format: fmt, lo)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 2, y: bottom), anchor: .leading)
                    ctx.draw(Text("0 s").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: left, y: bottom + 8), anchor: .leading)
                    ctx.draw(Text(String(format: "%.1f s", cycleS)).font(.system(size: 10)).foregroundColor(.secondary),
                             at: CGPoint(x: size.width - 8, y: bottom + 8), anchor: .trailing)
                    if let pm, let plo = pm.min(), let phi = pm.max() {
                        let py = { (v: Float) -> CGFloat in bottom - (bottom - top) * CGFloat((v - plo) / max(phi - plo, 1e-6)) }
                        var pline = Path()
                        pline.move(to: CGPoint(x: x(0), y: py(pm[0])))
                        for i in 1..<n { pline.addLine(to: CGPoint(x: x(i), y: py(pm[i]))) }
                        ctx.stroke(pline, with: .color(phoneColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        let pfmt = phi - plo < 20 ? "%.1f" : "%.0f"
                        ctx.draw(Text(String(format: pfmt, phi)).font(.system(size: 10)).foregroundColor(phoneColor),
                                 at: CGPoint(x: size.width - 2, y: top), anchor: .trailing)
                        ctx.draw(Text(String(format: pfmt, plo)).font(.system(size: 10)).foregroundColor(phoneColor),
                                 at: CGPoint(x: size.width - 2, y: bottom - 8), anchor: .trailing)
                    }
                    if let s = selected, s < n {
                        var mark = Path(); mark.move(to: CGPoint(x: x(s), y: top)); mark.addLine(to: CGPoint(x: x(s), y: bottom))
                        ctx.stroke(mark, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
                        ctx.fill(Path(ellipseIn: CGRect(x: x(s) - 5, y: y(median[s]) - 5, width: 10, height: 10)), with: .color(.primary))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { p in
                    let i = Int(((p.x - left) / w * CGFloat(n - 1)).rounded())
                    let pick = min(max(i, 0), n - 1)
                    selected = selected == pick ? nil : pick
                }
            }
            .frame(height: chartHeight(space, 150))
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            if pm == nil {
                HStack(spacing: 14) {
                    LegendSwatch(color: color, text: L10n.get("burst_legend_median"))
                    LegendSwatch(color: color.opacity(0.3), text: L10n.get("burst_legend_band"))
                }
            } else {
                ViewThatFits {
                    HStack(spacing: 14) { legendWithPhone }
                    VStack(alignment: .leading, spacing: 4) { legendWithPhone }
                }
            }
            Readout(text: selected.flatMap { s in
                s < n ? String(format: L10n.get("burst_sel_band"), String(format: "%.2f", cycleS * Double(s) / Double(max(n - 1, 1))),
                               Int((100.0 * Double(s) / Double(max(n - 1, 1))).rounded()), String(format: "%.1f", median[s]), unit,
                               String(format: "%.1f", q1[s]), String(format: "%.1f", q3[s])) : nil
            })
            if let s = selected, let pm, s < pm.count {
                Text(String(format: L10n.get("burst_sel_phone"), String(format: "%.1f", pm[s]), phoneGyro ? "°/s" : "g"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

extension BandChart {
    /// The legend with the devices' symbols (only with the phone's curve).
    @ViewBuilder var legendWithPhone: some View {
        DeviceLegend(symbol: "applewatch", color: color, text: L10n.get("burst_legend_median"))
        LegendSwatch(color: color.opacity(0.3), text: L10n.get("burst_legend_band"))
        DeviceLegend(symbol: "iphone", color: phoneColor, text: L10n.get(phoneGyro ? "burst_legend_phone_gyro" : "burst_legend_phone_accel"))
    }
}

// MARK: Rhythm

private struct RhythmPage: View {
    let v: BurstView
    /// The phone's movement spectrum next to the arm's (dashed); nil = watch only.
    var phone: PhoneOverlay? = nil
    @State private var sel: Int?

    var body: some View {
        if v.spectrumGyro == nil && v.spectrumAccel == nil {
            burstCard { Text(L10n.get("burst_no_rhythm")).font(.footnote) }
        } else {
            burstCard {
                ChartFrame(title: L10n.get("burst_rhythm_title"),
                           info: pageInfo(phone?.spectrumAccel != nil ? ["burst_read_rhythm", "burst_read_phone_rhythm"] : ["burst_read_rhythm"])) { space in
                    SpectrumChart(gyro: v.spectrumGyro, accel: v.spectrumAccel, rhythmic: v.rhythmic, space: space, selected: $sel,
                                  phone: phone?.spectrumAccel)
                }
            }
        }
    }
}

private struct SpectrumChart: View {
    let gyro: Spectrum?
    let accel: Spectrum?
    let rhythmic: Bool
    let space: ChartSpace
    @Binding var selected: Int?
    /// The phone's movement (|a|) spectrum, dashed: the trunk's rhythm next to the arm's.
    var phone: Spectrum? = nil
    private let accColor = Color(red: 0x9A / 255, green: 0x6B / 255, blue: 0x2F / 255)

    var body: some View {
        let grid = (gyro ?? accel)!.freqHz.swiftArray
        let gPower = gyro?.power.swiftArray, aPower = accel?.power.swiftArray
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let left: CGFloat = 8, top: CGFloat = 10, bottom = geo.size.height - 18
                let w = geo.size.width - left - 8
                let x = { (f: Float) -> CGFloat in left + w * CGFloat((f - 0.3) / (5 - 0.3)) }
                let y = { (p: Float) -> CGFloat in bottom - (bottom - top) * CGFloat(p) }
                Canvas { ctx, size in
                    for hz in 1...5 {
                        var l = Path(); l.move(to: CGPoint(x: x(Float(hz)), y: top)); l.addLine(to: CGPoint(x: x(Float(hz)), y: bottom))
                        ctx.stroke(l, with: .color(.secondary.opacity(0.25)))
                        ctx.draw(Text("\(hz) Hz").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: x(Float(hz)), y: bottom + 9))
                    }
                    func draw(_ s: Spectrum?, _ power: [Float]?, _ color: Color, dot: Bool) {
                        guard let s, let power else { return }
                        let f = s.freqHz.swiftArray
                        var line = Path()
                        for (i, fr) in f.enumerated() {
                            let pt = CGPoint(x: x(fr), y: y(power[i]))
                            if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                        }
                        ctx.stroke(line, with: .color(color), lineWidth: 2)
                        if dot {
                            ctx.fill(Path(ellipseIn: CGRect(x: x(s.peakHz) - 5, y: y(1) - 5, width: 10, height: 10)), with: .color(color))
                            ctx.draw(Text("\(Int((s.peakHz * 60).rounded()))/min").font(.system(size: 10)).foregroundColor(.secondary),
                                     at: CGPoint(x: min(x(s.peakHz) + 8, size.width - 40), y: top), anchor: .leading)
                        }
                    }
                    draw(accel, aPower, accColor, dot: false)
                    draw(gyro, gPower, .accentColor, dot: rhythmic)
                    if let phone {
                        let pf = phone.freqHz.swiftArray, pp = phone.power.swiftArray
                        var pline = Path()
                        for (i, fr) in pf.enumerated() where i < pp.count {
                            let pt = CGPoint(x: x(fr), y: y(pp[i]))
                            if i == 0 { pline.move(to: pt) } else { pline.addLine(to: pt) }
                        }
                        ctx.stroke(pline, with: .color(phoneColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        ctx.fill(Path(ellipseIn: CGRect(x: x(phone.peakHz) - 4, y: y(1) - 4, width: 8, height: 8)), with: .color(phoneColor))
                    }
                    if let s = selected, s < grid.count {
                        var m = Path(); m.move(to: CGPoint(x: x(grid[s]), y: top)); m.addLine(to: CGPoint(x: x(grid[s]), y: bottom))
                        ctx.stroke(m, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { p in
                    let f = Float(0.3 + (p.x - left) / w * (5 - 0.3))
                    let i = grid.indices.min { abs(grid[$0] - f) < abs(grid[$1] - f) } ?? 0
                    selected = selected == i ? nil : i
                }
            }
            .frame(height: chartHeight(space, 170))
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            if phone == nil {
                HStack(spacing: 14) {
                    LegendSwatch(color: .accentColor, text: L10n.get("burst_legend_arm"))
                    LegendSwatch(color: accColor, text: L10n.get("burst_legend_accel"))
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 14) {
                        DeviceLegend(symbol: "applewatch", color: .accentColor, text: L10n.get("burst_legend_arm"))
                        DeviceLegend(symbol: "applewatch", color: accColor, text: L10n.get("burst_legend_accel"))
                    }
                    DeviceLegend(symbol: "iphone", color: phoneColor, text: L10n.get("burst_legend_phone_accel"))
                }
            }
            Readout(text: selected.flatMap { s in
                guard s < grid.count else { return nil }
                return String(format: L10n.get("burst_sel_spectrum"), String(format: "%.2f", grid[s]), Int((grid[s] * 60).rounded()),
                              Int(((gPower?[s] ?? 0) * 100).rounded()), Int(((aPower?[s] ?? 0) * 100).rounded()))
            })
        }
    }
}

// MARK: 3D path

private struct PathPage: View {
    let v: BurstView
    @State private var sel: Int?

    var body: some View {
        if v.path.count < 3 {
            burstCard { Text(L10n.get("burst_no_rhythm")).font(.footnote) }
        } else {
            burstCard {
                ChartFrame(title: L10n.get("burst_path_title"), info: pageInfo(["burst_read_path"])) { space in
                    PathChart(v: v, space: space, selected: $sel)
                }
            }
        }
    }
}

/// The acceleration vector over the first seconds, turned by a drag (it turns by itself until touched); colour =
/// rotation speed. A tap picks the nearest point.
private struct PathChart: View {
    let v: BurstView
    let space: ChartSpace
    @Binding var selected: Int?
    @State private var yaw: CGFloat = 0.7
    @State private var pitch: CGFloat = 0.45
    @State private var touched = false
    @State private var dragStart: CGSize = .zero
    private let cool = Color(red: 0x5B / 255, green: 0x9B / 255, blue: 0xE0 / 255)
    private let hot = Color(red: 0xD6 / 255, green: 0x45 / 255, blue: 0x45 / 255)

    private func project(_ x: Float, _ y: Float, _ z: Float, _ size: CGSize) -> CGPoint {
        let unit = min(size.width, size.height) * 0.27 / CGFloat(v.pathLimitG)
        let rx = CGFloat(x) * cos(yaw) - CGFloat(y) * sin(yaw)
        let ry = CGFloat(x) * sin(yaw) + CGFloat(y) * cos(yaw)
        return CGPoint(x: size.width / 2 + rx * unit, y: size.height / 2 - (CGFloat(z) * cos(pitch) - ry * sin(pitch)) * unit)
    }

    private func mix(_ t: CGFloat) -> Color {
        Color(red: 0x5B / 255 * (1 - t) + 0xD6 / 255 * t, green: 0x9B / 255 * (1 - t) + 0x45 / 255 * t, blue: 0xE0 / 255 * (1 - t) + 0x45 / 255 * t)
    }

    var body: some View {
        let path = v.path
        let lim = v.pathLimitG
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.animation(paused: touched)) { timeline in
                GeometryReader { geo in
                    Canvas { ctx, size in
                        let corners: [Float] = [-lim, lim]
                        var cube: [(Float, Float, Float)] = []
                        for a in corners { for b in corners { for d in corners { cube.append((a, b, d)) } } }
                        for p in cube { for q in cube {
                            let diff = (p.0 != q.0 ? 1 : 0) + (p.1 != q.1 ? 1 : 0) + (p.2 != q.2 ? 1 : 0)
                            if diff == 1 && (p.0 < q.0 || p.1 < q.1 || p.2 < q.2) {
                                var l = Path(); l.move(to: project(p.0, p.1, p.2, size)); l.addLine(to: project(q.0, q.1, q.2, size))
                                ctx.stroke(l, with: .color(.secondary.opacity(0.3)))
                            }
                        } }
                        for (name, e) in [("X", (lim, Float(0), Float(0))), ("Y", (Float(0), lim, Float(0))), ("Z", (Float(0), Float(0), lim))] {
                            var l = Path(); l.move(to: project(0, 0, 0, size)); l.addLine(to: project(e.0, e.1, e.2, size))
                            ctx.stroke(l, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                            ctx.draw(Text(name).font(.caption2).foregroundColor(.secondary), at: project(e.0, e.1, e.2, size))
                        }
                        for i in 1..<path.count {
                            let a = path[i - 1], b = path[i]
                            let t = min(max(CGFloat((a.omega + b.omega) / 2 / max(v.omegaMax, 1)), 0), 1)
                            var l = Path(); l.move(to: project(a.x, a.y, a.z, size)); l.addLine(to: project(b.x, b.y, b.z, size))
                            ctx.stroke(l, with: .color(mix(t)), lineWidth: 3)
                        }
                        if let s = selected, s < path.count {
                            let o = project(path[s].x, path[s].y, path[s].z, size)
                            ctx.fill(Path(ellipseIn: CGRect(x: o.x - 6, y: o.y - 6, width: 12, height: 12)), with: .color(.primary))
                            ctx.fill(Path(ellipseIn: CGRect(x: o.x - 3, y: o.y - 3, width: 6, height: 6)), with: .color(.white))
                        }
                        ctx.draw(Text(String(format: "± %.1f g", lim)).font(.caption2).foregroundColor(.secondary),
                                 at: CGPoint(x: 8, y: size.height - 10), anchor: .leading)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 4)
                        .onChanged { g in
                            touched = true
                            let d = CGSize(width: g.translation.width - dragStart.width, height: g.translation.height - dragStart.height)
                            dragStart = g.translation
                            yaw += d.width * 0.01
                            pitch = min(max(pitch + d.height * 0.01, -1.4), 1.4)
                        }
                        .onEnded { _ in dragStart = .zero })
                    .onTapGesture { p in
                        touched = true
                        var best = -1, bestDistance = CGFloat.greatestFiniteMagnitude
                        for (i, pt) in path.enumerated() {
                            let o = project(pt.x, pt.y, pt.z, geo.size)
                            let dist = hypot(o.x - p.x, o.y - p.y)
                            if dist < bestDistance { bestDistance = dist; best = i }
                        }
                        selected = best >= 0 && bestDistance < 56 && best != selected ? best : nil
                    }
                }
                .onChange(of: timeline.date) { _, _ in if !touched { yaw += 0.35 / 60 } }
            }
            .frame(height: chartHeight(space, 300))
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 6) {
                Text("0").font(.caption2).foregroundStyle(.secondary)
                LinearGradient(colors: [cool, hot], startPoint: .leading, endPoint: .trailing).frame(height: 8).clipShape(Capsule())
                Text("\(Int(v.omegaMax.rounded())) °/s").font(.caption2).foregroundStyle(.secondary)
            }
            Text(L10n.get("burst_path_colour")).font(.caption2).foregroundStyle(.secondary)
            Readout(text: selected.flatMap { i in
                guard i < path.count else { return nil }
                let p = path[i]
                return String(format: L10n.get("burst_sel_path"), String(format: "%.2f", v.pathStartS + Double(i) * v.pathStepS),
                              String(format: "%.2f", sqrt(Double(p.x * p.x + p.y * p.y + p.z * p.z))), Int(p.omega.rounded()),
                              String(format: "%.2f", p.x), String(format: "%.2f", p.y), String(format: "%.2f", p.z))
            })
        }
    }
}

// MARK: Context

private struct ContextLine {
    let label: String
    let values: [Double]
    let color: Color
}

private struct ContextPage: View {
    let v: BurstView
    let facts: BurstFacts?
    @State private var sel: Int?

    /// Where the record sits (complete records): its start, the distance into the activity and the activity's own time.
    private func whereLine(_ ctx: BurstContext) -> String? {
        guard let start = facts?.startEpochSec?.int64Value else { return nil }
        let km = ctx.distanceM.swiftArray.first { !$0.isNaN }.map { String(format: "%.2f", $0 / 1000) } ?? "?"
        let timer = facts?.activityTimerMs.map { ms -> String in
            let t = ms.int64Value / 1000
            return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
        } ?? "?"
        let time = Date(timeIntervalSince1970: TimeInterval(start)).formatted(date: .omitted, time: .standard)
        return String(format: L10n.get("burst_ctx_where"), time, km, timer)
    }

    var body: some View {
        let ctx = v.context
        let series = [
            ContextLine(label: L10n.get("burst_ctx_speed"), values: ctx.speedKmh.swiftArray, color: Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)),
            ContextLine(label: L10n.get("burst_ctx_hr"), values: ctx.heartRate.swiftArray, color: Color(red: 0xE5 / 255, green: 0x48 / 255, blue: 0x4D / 255)),
            ContextLine(label: L10n.get("burst_ctx_grade"), values: ctx.gradePct.swiftArray, color: Color(red: 0x8D / 255, green: 0x6A / 255, blue: 0x2E / 255)),
        ].filter { $0.values.contains { !$0.isNaN } }
        let inputs: [ContextLine] = [
            ("burst_feat_energy", "energyG", Color(red: 0x7A / 255, green: 0x4F / 255, blue: 0xB5 / 255)),
            ("burst_feat_regularity", "regularityPct", Color(red: 0x2E / 255, green: 0x8B / 255, blue: 0x6E / 255)),
            ("burst_feat_half", "halfSym", Color(red: 0xB5 / 255, green: 0x52 / 255, blue: 0x4F / 255)),
            ("burst_feat_rest", "restPct", Color(red: 0x8D / 255, green: 0x6A / 255, blue: 0x2E / 255)),
            ("burst_feat_pole", "poleRate", Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)),
        ].compactMap { key, feature, color in ctx.features[feature].map { ContextLine(label: L10n.get(key), values: $0.swiftArray, color: color) } }
            // A channel the watch sent but never filled gets no chart (Android BurstScreen, 2026-11-11).
            .filter { $0.values.contains { !$0.isNaN } }
        // What the FIT record of each second got (complete records, burst schema 3).
        let recorded: [ContextLine] = [
            ("burst_met_impulse", "impulseMs", Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)),
            ("burst_met_duty", "dutyPct", Color(red: 0x2E / 255, green: 0x8B / 255, blue: 0x6E / 255)),
            ("burst_met_push", "pushMs", Color(red: 0x7A / 255, green: 0x4F / 255, blue: 0xB5 / 255)),
            ("burst_met_swing", "swingDeg", Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)),
            ("burst_met_swing_cv", "swingCvPct", Color(red: 0x8D / 255, green: 0x6A / 255, blue: 0x2E / 255)),
            ("burst_met_step_balance", "stepBalancePct", Color(red: 0x2E / 255, green: 0x8B / 255, blue: 0x6E / 255)),
            ("burst_met_impact_balance", "impactBalancePct", Color(red: 0xB5 / 255, green: 0x52 / 255, blue: 0x4F / 255)),
            ("burst_met_wrist_gct", "wristGctMs", Color(red: 0x7A / 255, green: 0x4F / 255, blue: 0xB5 / 255)),
            ("burst_met_vertical", "verticalMh", Color(red: 0x8D / 255, green: 0x6A / 255, blue: 0x2E / 255)),
        ].compactMap { key, metric, color in ctx.metrics[metric].map { ContextLine(label: L10n.get(key), values: $0.swiftArray, color: color) } }
            .filter { $0.values.contains { !$0.isNaN } }
        let watchKeys = ctx.stateKeys
        let hasWatch = watchKeys.contains { !$0.isEmpty }
        let hasReplay = v.replayKeys.contains { !$0.isEmpty }
        let info = pageInfo((hasReplay ? ["burst_read_replay"] : []) + ["burst_read_context"])
        let offset = Int(v.ctxOffsetS)
        burstCard {
            if let line = whereLine(ctx) { Text(line).font(.caption).foregroundStyle(.secondary) }
            if hasWatch || hasReplay {
                let watchLabel = ctx.algorithm.isEmpty ? L10n.get("burst_replay_watch_plain") : String(format: L10n.get("burst_replay_watch"), ctx.algorithm)
                let rows: [(String, [String])] = (hasWatch ? [(watchLabel, watchKeys)] : [])
                    + (hasReplay ? [(String(format: L10n.get("burst_replay_app"), v.replayVersion), v.replayKeys)] : [])
                ChartFrame(title: L10n.get(hasReplay ? "burst_replay_title" : "burst_ctx_state"), info: info) { space in
                    StateRows(rows: rows, offset: offset, scale: space.scale, selected: $sel)
                }
            }
            if !series.isEmpty {
                ChartFrame(title: series.map { $0.label.components(separatedBy: " (").first ?? $0.label }.joined(separator: " · "),
                           info: hasWatch || hasReplay ? nil : info) { space in
                    MultiSeriesChart(lines: series, offset: offset, space: space, selected: $sel)
                }
            }
            if !inputs.isEmpty {
                Text(L10n.get("burst_feat_heading")).font(.caption).foregroundStyle(.secondary)
                ForEach(inputs.indices, id: \.self) { i in
                    ChartFrame(title: inputs[i].label) { space in
                        MultiSeriesChart(lines: [inputs[i]], offset: offset, space: space, selected: $sel, axis: true)
                    }
                }
            }
            if !recorded.isEmpty {
                Text(L10n.get("burst_met_heading")).font(.caption).foregroundStyle(.secondary)
                ForEach(recorded.indices, id: \.self) { i in
                    ChartFrame(title: recorded[i].label) { space in
                        MultiSeriesChart(lines: [recorded[i]], offset: offset, space: space, selected: $sel, axis: true)
                    }
                }
            }
            if series.isEmpty && !hasWatch && !hasReplay && recorded.isEmpty {
                Text(L10n.get("burst_ctx_none")).font(.footnote)
            }
        }
    }
}

/// The technique verdict per second as coloured cells, one strip per row (the watch's, the app's replay); a tap marks a
/// second in every chart of the page.
private struct StateRows: View {
    let rows: [(String, [String])]
    let offset: Int
    let scale: CGFloat
    @Binding var selected: Int?

    var body: some View {
        let count = max(rows.map { $0.1.count }.max() ?? 1, 1)
        let used = Array(Set(rows.flatMap { $0.1 }.filter { !$0.isEmpty })).sorted()
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                let keys = rows[r].1
                Text(rows[r].0).font(.caption.weight(.semibold))
                GeometryReader { geo in
                    Canvas { ctx, size in
                        let w = size.width / CGFloat(count)
                        for (i, k) in keys.enumerated() {
                            let color = k.isEmpty ? Color(red: 0xC9 / 255, green: 0xD0 / 255, blue: 0xD8 / 255) : stateColor(k)
                            ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w - 1, height: size.height)),
                                     with: .color(color.opacity(selected == nil || selected == i ? 1 : 0.35)))
                        }
                    }
                    .contentShape(Rectangle())
                    // A tap marks that second in every strip and chart of the page.
                    .onTapGesture { p in
                        let i = min(max(Int(p.x / (geo.size.width / CGFloat(count))), 0), count - 1)
                        selected = selected == i ? nil : i
                    }
                }
                .frame(height: 26 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                let shares = Dictionary(grouping: keys.filter { !$0.isEmpty }, by: { $0 }).mapValues { $0.count }
                    .sorted { $0.value > $1.value }
                Text(shares.map { "\(stateShort($0.key)) \($0.value) s" }.joined(separator: " · ")).font(.caption)
            }
            HStack(spacing: 10) {
                ForEach(used, id: \.self) { k in LegendSwatch(color: stateColor(k), text: stateShort(k)) }
            }
            if let s = selected {
                Text(String(format: L10n.get("burst_sel_value"), offset + s,
                            rows.map { "\($0.0.components(separatedBy: " (").first ?? $0.0): \(s < $0.1.count && !$0.1[s].isEmpty ? stateShort($0.1[s]) : "–")" }
                                .joined(separator: " · ")))
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

/// Values per second: several lines on their own scales (the legend gives each range) or, with [axis], one line with
/// its scale on the left; dotted guides up from the time labels. A tap marks a second.
private struct MultiSeriesChart: View {
    let lines: [ContextLine]
    let offset: Int
    let space: ChartSpace
    @Binding var selected: Int?
    var axis = false

    var body: some View {
        let count = lines.map { $0.values.count }.max() ?? 0
        let last = max(count - 1, 1)
        let ranges = lines.map { l -> (Double, Double) in
            let p = l.values.filter { !$0.isNaN }
            return (p.min() ?? 0, p.max() ?? 0)
        }
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let left: CGFloat = axis ? 34 : 10, top: CGFloat = 8, bottom = geo.size.height - 18
                let w = geo.size.width - left - 10
                let x = { (i: Int) -> CGFloat in left + w * CGFloat(i) / CGFloat(last) }
                Canvas { ctx, size in
                    timeGuides(ctx, xs: [x(0), x(last)], top: top, bottom: bottom)
                    for (k, l) in lines.enumerated() {
                        let (lo, hi) = ranges[k]
                        let y = { (v: Double) -> CGFloat in hi > lo ? bottom - (bottom - top) * CGFloat((v - lo) / (hi - lo)) : (top + bottom) / 2 }
                        var path = Path()
                        var started = false
                        for (i, v) in l.values.enumerated() {
                            if v.isNaN { started = false; continue }
                            let pt = CGPoint(x: x(i), y: y(v))
                            if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
                        }
                        ctx.stroke(path, with: .color(l.color), lineWidth: 2)
                        if let s = selected, s < l.values.count, !l.values[s].isNaN {
                            ctx.fill(Path(ellipseIn: CGRect(x: x(s) - 4, y: y(l.values[s]) - 4, width: 8, height: 8)), with: .color(l.color))
                        }
                        if axis {
                            ctx.draw(Text(String(format: "%.0f", hi)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 2, y: top), anchor: .leading)
                            ctx.draw(Text(String(format: "%.0f", lo)).font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: 2, y: bottom), anchor: .leading)
                        }
                    }
                    ctx.draw(Text("\(offset) s").font(.system(size: 10)).foregroundColor(.secondary), at: CGPoint(x: left, y: bottom + 9), anchor: .leading)
                    ctx.draw(Text("\(offset + count - 1) s").font(.system(size: 10)).foregroundColor(.secondary),
                             at: CGPoint(x: size.width - 10, y: bottom + 9), anchor: .trailing)
                    if let s = selected, s < count {
                        var m = Path(); m.move(to: CGPoint(x: x(s), y: top)); m.addLine(to: CGPoint(x: x(s), y: bottom))
                        ctx.stroke(m, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { p in
                    let i = min(max(Int(((p.x - left) / w * CGFloat(last)).rounded()), 0), max(count - 1, 0))
                    selected = selected == i ? nil : i
                }
            }
            .frame(height: chartHeight(space, axis ? 96 : 140))
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            if !axis {
                // Each line with its range; a picked second shows its values instead.
                ForEach(lines.indices, id: \.self) { k in
                    let l = lines[k]
                    let lo = ranges[k].0
                    let hi = ranges[k].1
                    let whole = l.values.allSatisfy { $0.isNaN || $0 == $0.rounded() }
                    let fmt = hi - lo < 10 && !whole ? "%.1f" : "%.0f"
                    let text: String = {
                        if let s = selected, s < l.values.count {
                            return "\(l.label): " + (l.values[s].isNaN ? "–" : String(format: "%.1f", l.values[s]))
                        }
                        return "\(l.label) " + String(format: "\(fmt) … \(fmt)", lo, hi)
                    }()
                    LegendSwatch(color: l.color, text: text)
                }
            } else if let s = selected, s < count, let v = lines.first?.values[s] {
                Text(String(format: L10n.get("burst_sel_value"), offset + s, v.isNaN ? "–" : String(format: "%.1f", v)))
                    .font(.caption.weight(.semibold))
            }
        }
    }
}
