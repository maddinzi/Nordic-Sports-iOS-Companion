import NordicSportsShared
import SwiftUI

// The time view of the Metrics screen's Timeline theme (Android `ActivityTimeView.kt`, Companion
// design/activity-metrics.md): the stored track on the map, coloured by what the recording has (technique, speed or
// pace, altitude, grade), then one chart of the chosen values over time with a time window to narrow or widen, the
// Sensor Records marked. Map and chart share the window and the picked moment; both open full screen. The series come
// from the shared `ActivityTimeSeries` (`LiveFeedView.series`); this file draws.

/// What the chart can show, in chip order.
enum TimeKind: CaseIterable, Hashable {
    case speed, altitude, grade, technique
}

/// What the map and the chart share (Android `TimeViewState`): the time window in seconds from the start (nil = all),
/// the picked moment, the chosen lines and whether the Sensor Records are marked.
final class TimeViewState: ObservableObject {
    @Published var from: Double?
    @Published var to: Double?
    @Published var cursor: Int?
    @Published var shown: Set<TimeKind>?
    @Published var records = true

    func setWindow(_ a: Double?, _ b: Double?, total: Double) {
        if let a, let b, a > 0.5 || b < total - 0.5 { from = a; to = b } else { from = nil; to = nil }
    }

    var windowSeconds: ClosedRange<Int>? {
        guard let from, let to else { return nil }
        return Int(from)...Int(to)
    }
}

/// A stored track's series as Swift arrays (NaN = no value, "" = no technique).
struct TimeSeriesData {
    let seconds: [Int]
    let distanceM: [Double]
    let values: [TimeKind: [Double]]
    let technique: [String]
    let breaks: Set<Int>
    let kinds: [TimeKind]

    init(_ s: TrackSeriesView) {
        seconds = s.seconds.map { $0.intValue }
        distanceM = s.distanceM.map { $0.doubleValue }
        values = [
            .speed: s.speedKmh.map { $0.doubleValue },
            .altitude: s.altitudeM.map { $0.doubleValue },
            .grade: s.gradePct.map { $0.doubleValue },
        ]
        technique = s.technique
        breaks = Set(s.breaks.map { $0.intValue })
        var k: [TimeKind] = []
        if s.hasSpeed { k.append(.speed) }
        if s.hasAltitude { k.append(.altitude) }
        if s.hasGrade { k.append(.grade) }
        if s.hasTechnique { k.append(.technique) }
        kinds = k
    }

    var count: Int { seconds.count }
    var total: Double { Double(seconds.last ?? 0) }

    /// The sample nearest to [second].
    func index(at second: Double) -> Int {
        guard !seconds.isEmpty else { return -1 }
        var lo = 0, hi = seconds.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if Double(seconds[mid]) < second { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(Double(seconds[lo - 1]) - second) <= abs(Double(seconds[lo]) - second) { return lo - 1 }
        return lo
    }

    /// Lowest, mean and highest value of [kind] between [from] and [to] seconds; nil without a value there. Values below
    /// [atLeast] are left out: a pace range passes 2 km/h (30:00/km), so standing does not make its slow end "–".
    func stats(_ kind: TimeKind, _ from: Double, _ to: Double, atLeast: Double = -Double.infinity) -> (min: Double, mean: Double, max: Double)? {
        guard let v = values[kind] else { return nil }
        var n = 0.0, sum = 0.0, lo = Double.infinity, hi = -Double.infinity
        for i in seconds.indices where Double(seconds[i]) >= from && Double(seconds[i]) <= to {
            let x = v[i]
            if x.isNaN || x < atLeast { continue }
            n += 1; sum += x; lo = min(lo, x); hi = max(hi, x)
        }
        if n == 0 { return nil }
        return (min: lo, mean: sum / n, max: hi)
    }
}

/// The map card and the chart card of a saved activity's track ([track] has a `series`). [showMap] is false for the
/// copy composed out of sight (the full-screen chart pages through every chart), so no hidden map loads tiles.
struct ActivityTimeSection: View {
    let item: ActivityItem
    let track: LiveFeedView
    let bursts: [RecordingBoostView]
    var showMap = true
    @ObservedObject var view: TimeViewState
    @StateObject private var mapChoices = LiveMapChoices()
    @State private var mapFull = false

    var body: some View {
        if let series = track.series {
            let data = TimeSeriesData(series)
            VStack(alignment: .leading, spacing: 12) {
                if showMap {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.get("activity_detail_section_map")).font(.subheadline.weight(.semibold)).foregroundStyle(CardTone.blue.title)
                        trackMap(fullScreen: false)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .fullScreenCover(isPresented: $mapFull) {
                        ZStack(alignment: .topTrailing) {
                            trackMap(fullScreen: true)
                            Button { mapFull = false } label: {
                                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(LiveTrackMap.ink)
                                    .frame(width: 44, height: 44).background(LiveTrackMap.plate, in: Circle())
                            }
                            .accessibilityLabel(L10n.get("chart_close"))
                            .padding(.trailing, 12).padding(.top, 56)
                        }
                        .onAppear { OrientationLock.allowTurning() }
                        .onDisappear { OrientationLock.set(landscape: false) }
                    }
                }
                ChartFrame(title: L10n.get("time_chart_title"), tone: .blue, info: L10n.get("time_chart_info")) { space in
                    TimeChart(data: data, item: item, bursts: bursts, view: view, space: space)
                }
            }
        }
    }

    private func trackMap(fullScreen: Bool) -> some View {
        LiveTrackMap(points: TrackPoints(track), automatic: track.baseMap, choices: mapChoices,
                     onExpand: fullScreen ? nil : { mapFull = true }, fullScreen: fullScreen, withGrade: true,
                     window: view.windowSeconds, cursor: view.cursor,
                     onPick: { view.cursor = $0 })
    }
}

/// The overview bar, the chart, the readout and the chips.
private struct TimeChart: View {
    let data: TimeSeriesData
    let item: ActivityItem
    let bursts: [RecordingBoostView]
    @ObservedObject var view: TimeViewState
    let space: ChartSpace
    @Environment(\.colorScheme) private var scheme
    @State private var pinchStart: (from: Double, to: Double)?

    private var run: Bool { ActivityFigures.shared.usesPace(art: item.sportArt) }
    private var shown: Set<TimeKind> { view.shown ?? Set(data.kinds.filter { $0 != .grade }) }
    private var from: Double { view.from ?? 0 }
    private var to: Double { view.to ?? data.total }
    private var recordTimes: [Int] {
        bursts.map { Int($0.burstId - Int64(item.startEpochSec)) }.filter { $0 >= 0 && Double($0) <= data.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WindowBar(data: data, view: view, slim: space.maximized)
            chart
                .frame(height: space.maximized ? max(120, space.size.height - 160) : 210)
            if let readout { Text(readout).font(.footnote.weight(.semibold)).foregroundStyle(CardTone.blue.title) }
            chips
            if shown.contains(.technique), data.kinds.contains(.technique), !space.maximized { techniqueKey }
        }
    }

    // MARK: chart

    private func colour(_ kind: TimeKind) -> Color {
        let dark = scheme == .dark
        switch kind {
        case .speed: return dark ? Color(red: 0x6C / 255, green: 0xB4 / 255, blue: 0xF5 / 255) : Color(red: 0x1F / 255, green: 0x6F / 255, blue: 0xB5 / 255)
        case .altitude: return dark ? Color(red: 0xB7 / 255, green: 0x9C / 255, blue: 0xF7 / 255) : Color(red: 0x7C / 255, green: 0x3A / 255, blue: 0xED / 255)
        case .grade: return dark ? Color(red: 0xF5 / 255, green: 0xB5 / 255, blue: 0x4A / 255) : Color(red: 0xD2 / 255, green: 0x7A / 255, blue: 0x00 / 255)
        case .technique: return .gray
        }
    }

    private var lineKinds: [TimeKind] { data.kinds.filter { $0 != .technique && shown.contains($0) } }

    private var chart: some View {
        GeometryReader { box in
            let w = box.size.width
            Canvas { ctx, size in
                let axis: CGFloat = 16
                let band: CGFloat = shown.contains(.technique) && data.kinds.contains(.technique) ? 10 : 0
                let top: CGFloat = 10
                let bottom = size.height - axis - band - (band > 0 ? 4 : 0)
                let span = max(to - from, 1)
                func x(_ s: Double) -> CGFloat { CGFloat((s - from) / span) * size.width }

                // time ticks and faint grid lines, kept off the rounded corners
                let step = tickStep(span, slots: Double(size.width / 64))
                var t = (from / step).rounded(.up) * step
                while t <= to {
                    let xt = x(t)
                    var grid = Path(); grid.move(to: CGPoint(x: xt, y: top)); grid.addLine(to: CGPoint(x: xt, y: bottom))
                    ctx.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
                    let label = ctx.resolve(Text(clock(Int(t))).font(.caption2).foregroundColor(.secondary))
                    let lw = label.measure(in: size).width
                    ctx.draw(label, at: CGPoint(x: min(max(xt, lw / 2 + 6), size.width - lw / 2 - 6), y: size.height - axis / 2), anchor: .center)
                    t += step
                }
                // the technique band at the foot
                if band > 0 {
                    let y = bottom + 4
                    for i in 0..<(data.count - 1) {
                        let key = data.technique[i + 1]
                        if key.isEmpty || data.breaks.contains(i + 1) { continue }
                        if Double(data.seconds[i + 1]) < from || Double(data.seconds[i]) > to { continue }
                        let x0 = x(Double(data.seconds[i])), x1 = x(Double(data.seconds[i + 1]))
                        ctx.fill(Path(CGRect(x: x0, y: y, width: x1 - x0 + 0.5, height: band)), with: .color(stateColor(key)))
                    }
                }
                // each line on its own scale over the window
                for kind in lineKinds {
                    guard let st = data.stats(kind, from, to), let v = data.values[kind] else { continue }
                    let pad = max((st.max - st.min) * 0.08, kind == .grade ? 1 : 0.5)
                    let lo = st.min - pad, hi = st.max + pad
                    func y(_ value: Double) -> CGFloat { bottom - CGFloat((value - lo) / (hi - lo)) * (bottom - top) }
                    if kind == .grade, lo < 0, hi > 0 {
                        var zero = Path(); zero.move(to: CGPoint(x: 0, y: y(0))); zero.addLine(to: CGPoint(x: size.width, y: y(0)))
                        ctx.stroke(zero, with: .color(colour(kind).opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                    }
                    var path = Path()
                    var open = false
                    for i in 0..<data.count {
                        let value = v[i]
                        let s = Double(data.seconds[i])
                        if value.isNaN || data.breaks.contains(i) { open = false }
                        if value.isNaN { continue }
                        // one point beyond each end, so the line reaches the edges
                        if s < from, i + 1 < data.count, Double(data.seconds[i + 1]) < from { continue }
                        if s > to, i > 0, Double(data.seconds[i - 1]) > to { break }
                        let p = CGPoint(x: x(s), y: y(value))
                        if open { path.addLine(to: p) } else { path.move(to: p); open = true }
                    }
                    ctx.stroke(path, with: .color(colour(kind)), style: StrokeStyle(lineWidth: 2 * space.scale, lineJoin: .round))
                }
                // Sensor Records: a mark at the top where each one started
                if view.records {
                    for sec in recordTimes {
                        let xr = x(Double(sec))
                        if xr < 0 || xr > size.width { continue }
                        var mark = Path(); mark.move(to: CGPoint(x: xr, y: top)); mark.addLine(to: CGPoint(x: xr, y: bottom))
                        ctx.stroke(mark, with: .color(CardTone.blue.title.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                        var tri = Path(); tri.move(to: CGPoint(x: xr - 5, y: 0)); tri.addLine(to: CGPoint(x: xr + 5, y: 0)); tri.addLine(to: CGPoint(x: xr, y: 8)); tri.closeSubpath()
                        ctx.fill(tri, with: .color(CardTone.blue.title))
                    }
                }
                // the picked moment
                if let sec = view.cursor {
                    let xc = x(Double(sec))
                    if xc >= 0 && xc <= size.width {
                        var line = Path(); line.move(to: CGPoint(x: xc, y: top)); line.addLine(to: CGPoint(x: xc, y: bottom + band))
                        ctx.stroke(line, with: .color(.primary.opacity(0.7)), lineWidth: 1.5)
                        let i = data.index(at: Double(sec))
                        for kind in lineKinds {
                            guard i >= 0, let st = data.stats(kind, from, to), let value = data.values[kind]?[i], !value.isNaN else { continue }
                            let pad = max((st.max - st.min) * 0.08, kind == .grade ? 1 : 0.5)
                            let lo = st.min - pad, hi = st.max + pad
                            let p = CGPoint(x: x(Double(data.seconds[i])), y: bottom - CGFloat((value - lo) / (hi - lo)) * (bottom - top))
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)), with: .color(.white))
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(colour(kind)))
                        }
                    }
                }
            }
            .background(Color(.systemBackground).opacity(scheme == .dark ? 0.15 : 1), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            // A tap or a sideways drag picks a moment; an up-and-down drag is left to the screen's scrolling.
            .onTapGesture(coordinateSpace: .local) { p in view.cursor = Int(second(at: p.x, width: w)) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { g in
                        if abs(g.translation.width) > abs(g.translation.height) { view.cursor = Int(second(at: g.location.x, width: w)) }
                    }
            )
            // Two fingers narrow or widen the window around its middle.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { g in
                        let start: (from: Double, to: Double) = pinchStart ?? (from: from, to: to)
                        if pinchStart == nil { pinchStart = start }
                        let total = data.total
                        let width = min(max((start.to - start.from) / g.magnification, min(60, total)), total)
                        let mid = (start.from + start.to) / 2
                        let a = min(max(mid - width / 2, 0), total - width)
                        view.setWindow(a, a + width, total: total)
                    }
                    .onEnded { _ in pinchStart = nil }
            )
            .accessibilityLabel(L10n.get("time_chart_desc"))
        }
    }

    private func second(at px: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(from + Double(px / width) * (to - from), 0), data.total)
    }

    private func tickStep(_ span: Double, slots: Double) -> Double {
        let steps: [Double] = [30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 10800]
        return steps.first { span / $0 <= max(slots, 2) } ?? steps.last!
    }

    // MARK: readout and chips

    /// Time, distance and the technique at the picked moment.
    private var readout: String? {
        guard let sec = view.cursor else { return nil }
        let i = data.index(at: Double(sec))
        guard i >= 0 else { return nil }
        var parts = [clock(data.seconds[i]), String(format: "%.2f km", data.distanceM[i] / 1000)]
        if !data.technique[i].isEmpty { parts.append(stateShort(data.technique[i])) }
        return parts.joined(separator: " · ")
    }

    private func name(_ kind: TimeKind) -> String {
        switch kind {
        case .speed: return L10n.get(run ? "watch_data_field_pace" : "recording_map_colour_speed")
        case .altitude: return L10n.get("recording_map_colour_altitude")
        case .grade: return L10n.get("recording_live_grade")
        case .technique: return L10n.get("recording_map_colour_technique")
        }
    }

    private func valueText(_ kind: TimeKind, _ v: Double) -> String {
        switch kind {
        case .speed: return run ? (paceText(kmh: v).map { "\($0) /km" } ?? "–") : String(format: "%.1f km/h", v)
        case .altitude: return String(format: "%.0f m", v)
        case .grade: return String(format: "%+.0f %%", v)
        case .technique: return ""
        }
    }

    /// The chip's value: at the picked moment, or the range in the window.
    private func chipValue(_ kind: TimeKind) -> String? {
        if kind == .technique { return nil }
        if let sec = view.cursor {
            let i = data.index(at: Double(sec))
            guard i >= 0, let v = data.values[kind]?[i], !v.isNaN else { return "–" }
            return valueText(kind, v)
        }
        if kind == .speed && run {
            // only speeds that have a pace (Android ActivityTimeView)
            guard let st = data.stats(kind, from, to, atLeast: 2) else { return "–" }
            return "\(valueText(kind, st.min).replacingOccurrences(of: " /km", with: ""))–\(valueText(kind, st.max))"
        }
        guard let st = data.stats(kind, from, to) else { return nil }
        return "\(valueText(kind, st.min)) – \(valueText(kind, st.max))"
    }

    private var chips: some View {
        // Maximized, the chips keep their size on one row; inline they wrap.
        let layout = space.maximized ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(FlowLayout(spacing: 8))
        return layout {
            ForEach(data.kinds, id: \.self) { kind in
                let on = shown.contains(kind)
                Button {
                    var next = shown
                    if on { next.remove(kind) } else { next.insert(kind) }
                    view.shown = next
                } label: {
                    HStack(spacing: 6) {
                        if kind == .technique {
                            RoundedRectangle(cornerRadius: 2).fill(stateColor(data.technique.first { !$0.isEmpty } ?? "V2")).frame(width: 10, height: 10)
                        } else {
                            Circle().fill(colour(kind).opacity(on ? 1 : 0.35)).frame(width: 10, height: 10)
                        }
                        Text([name(kind), chipValue(kind)].compactMap { $0 }.joined(separator: "  ")).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(on ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(on ? 0 : 0.5)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            if !recordTimes.isEmpty {
                Button { view.records.toggle() } label: {
                    Text("\(L10n.get("time_chart_records"))  \(recordTimes.count)").font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(view.records ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(view.records ? 0 : 0.5)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The techniques of the band in the window.
    private var techniqueKey: some View {
        var used: [String] = []
        for i in data.seconds.indices where Double(data.seconds[i]) >= from && Double(data.seconds[i]) <= to {
            let k = data.technique[i]
            if !k.isEmpty && !used.contains(k) { used.append(k) }
        }
        return FlowLayout(spacing: 10) {
            ForEach(used, id: \.self) { key in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(stateColor(key)).frame(width: 9, height: 9)
                    Text(stateShort(key)).font(.caption2)
                }
            }
        }
    }
}

/// The whole activity as a small profile (altitude, or speed without one) with the time window on it: drag either end,
/// or the window itself, to change it; "All" shows the whole activity again (as the Sensor Record screen's crop bar).
private struct WindowBar: View {
    let data: TimeSeriesData
    @ObservedObject var view: TimeViewState
    var slim = false
    @State private var dragFrom: Double?
    @State private var dragTo: Double?
    @State private var part = 0
    @State private var lastX: CGFloat = 0

    private var total: Double { data.total }
    private var from: Double { dragFrom ?? view.from ?? 0 }
    private var to: Double { dragTo ?? view.to ?? total }
    private var minWindow: Double { min(60, total) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.get("burst_crop_title")).font(.caption).foregroundStyle(CardTone.blue.subtitle)
                Spacer()
                Text("\(clock(Int(from)))–\(clock(Int(to))) · \(clock(Int(to - from)))").font(.caption).foregroundStyle(CardTone.blue.title)
                if view.from != nil {
                    Button(L10n.get("burst_crop_all")) { view.setWindow(nil, nil, total: total) }
                        .font(.caption).buttonStyle(.bordered).controlSize(.mini)
                }
            }
            GeometryReader { box in
                let pad: CGFloat = 8
                let w = box.size.width - 2 * pad
                let x = { (s: Double) -> CGFloat in pad + w * CGFloat(s / max(total, 1)) }
                Canvas { ctx, size in
                    // the profile as a filled area
                    let profile = data.kinds.contains(.altitude) ? data.values[.altitude] : data.values[.speed]
                    if let values = profile {
                        let present = values.filter { !$0.isNaN }
                        if let lo = present.min(), var hi = present.max() {
                            if hi - lo < 1e-6 { hi = lo + 1 }
                            let base = size.height - 4, tall = size.height - 10
                            var area = Path()
                            var started = false
                            var lastPx: CGFloat = 0
                            for i in values.indices where !values[i].isNaN {
                                let px = x(Double(data.seconds[i]))
                                let py = base - CGFloat((values[i] - lo) / (hi - lo)) * tall
                                if !started { area.move(to: CGPoint(x: px, y: base)); started = true }
                                area.addLine(to: CGPoint(x: px, y: py))
                                lastPx = px
                            }
                            if started {
                                area.addLine(to: CGPoint(x: lastPx, y: base)); area.closeSubpath()
                                ctx.fill(area, with: .color(.secondary.opacity(0.45)))
                            }
                        }
                    }
                    if let sec = view.cursor {
                        var line = Path(); line.move(to: CGPoint(x: x(Double(sec)), y: 0)); line.addLine(to: CGPoint(x: x(Double(sec)), y: size.height))
                        ctx.stroke(line, with: .color(.primary.opacity(0.6)), lineWidth: 1)
                    }
                    // outside the window dimmed, the window framed with two handles
                    let a = x(from), b = x(to)
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: a, height: size.height)), with: .color(Color(.systemBackground).opacity(0.7)))
                    ctx.fill(Path(CGRect(x: b, y: 0, width: size.width - b, height: size.height)), with: .color(Color(.systemBackground).opacity(0.7)))
                    ctx.stroke(Path(roundedRect: CGRect(x: a, y: 1, width: b - a, height: size.height - 2), cornerRadius: 6), with: .color(.accentColor), lineWidth: 2)
                    ctx.fill(Path(roundedRect: CGRect(x: a - 3, y: 8, width: 6, height: size.height - 16), cornerRadius: 3), with: .color(.accentColor))
                    ctx.fill(Path(roundedRect: CGRect(x: b - 3, y: 8, width: 6, height: size.height - 16), cornerRadius: 3), with: .color(.accentColor))
                }
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            if dragFrom == nil {
                                // which part the touch takes: the start handle, the end handle, or the window itself
                                let ds = abs(g.startLocation.x - x(from)), de = abs(g.startLocation.x - x(to))
                                part = ds <= 28 && ds <= de ? 1 : de <= 28 ? 2 : (g.startLocation.x > x(from) && g.startLocation.x < x(to)) ? 3 : 0
                                dragFrom = from; dragTo = to; lastX = g.startLocation.x
                            }
                            let seconds = Double((g.location.x - lastX) / max(w, 1)) * total
                            lastX = g.location.x
                            guard let f = dragFrom, let t = dragTo else { return }
                            switch part {
                            case 1: dragFrom = min(max(f + seconds, 0), t - minWindow)
                            case 2: dragTo = min(max(t + seconds, f + minWindow), total)
                            case 3:
                                let len = t - f
                                let start = min(max(f + seconds, 0), total - len)
                                dragFrom = start; dragTo = start + len
                            default: break
                            }
                        }
                        .onEnded { _ in
                            if part != 0, let f = dragFrom, let t = dragTo { view.setWindow(f, t, total: total) }
                            dragFrom = nil; dragTo = nil; part = 0
                        }
                )
                .accessibilityLabel(L10n.get("burst_crop_title"))
            }
            .frame(height: slim ? 34 : 44)
        }
    }
}

/// The Timeline theme's line for an activity without a track.
struct NoTrackNote: View {
    var body: some View {
        Text(L10n.get("time_chart_no_track")).font(.footnote).foregroundStyle(.secondary)
    }
}

/// Children in rows, wrapping to the next row when the width is used up (the chart's chips and technique key).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}