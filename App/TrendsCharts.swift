import NordicSportsShared
import SwiftUI

// The charts of the Trends tab (Android: `TrendsCharts.kt`). They draw what the shared `Trends` computed and call back
// with a tap; the screen owns the selection. Nothing here sums or filters by itself, except what is plain arithmetic
// on one chart's own points.

// MARK: - Small helpers

private func niceTicks(_ max: Double, _ count: Int) -> (top: Double, ticks: [Double]) {
    if max <= 0 { return (1, [0, 1]) }
    let raw = max / Double(count)
    let p = pow(10, floor(log10(raw)))
    let f = raw / p
    let step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * p
    let top = ceil(max / step) * step
    var ticks: [Double] = []
    var v = 0.0
    while v <= top + step * 1e-6 { ticks.append(v); v += step }
    return (top, ticks)
}

private func trim(_ v: Double) -> String { v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v) }

private func put(_ ctx: inout GraphicsContext, _ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, color: Color,
                 anchor: UnitPoint = .center, bold: Bool = false) {
    ctx.draw(Text(s).font(.system(size: size, weight: bold ? .bold : .regular)).foregroundStyle(color), at: CGPoint(x: x, y: y), anchor: anchor)
}

private func chartFrame(_ space: ChartSpace) -> (minHeight: CGFloat, maxHeight: CGFloat) {
    space.maximized ? (160, .infinity) : (230, 230)
}

private func ints(_ list: [KotlinInt]) -> [Int] { list.map { $0.intValue } }

private func techniqueNameColor(_ key: String) -> Color { stateColor(key) }

private struct TrendToggle: View {
    let options: [String]
    let current: Int
    let id: String
    let data: TrendsData

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, name in
                Button { data.onView(id, i) } label: {
                    Text(name).font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(i == current ? data.tone.title : data.tone.title.opacity(0.12), in: Capsule())
                        .foregroundStyle(i == current ? Color(.systemBackground) : data.tone.title)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct TrendLegend: View {
    let items: [(key: String, name: String, color: Color)]
    let selected: String
    let data: TrendsData
    var onTap: ((String) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(items, id: \.key) { item in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 10, height: 10)
                    Text(item.name).font(.caption).fontWeight(selected == item.key ? .bold : .regular).lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(selected == item.key ? Color.primary.opacity(0.1) : Color.clear, in: Capsule())
                .contentShape(Rectangle())
                .onTapGesture { onTap?(item.key) }
            }
        }
    }
}

private func caption(_ text: String, _ data: TrendsData) -> some View {
    Group {
        if !text.isEmpty { Text(text).font(.caption).foregroundStyle(data.tone.subtitle) }
    }
}

private func emptyChart(_ data: TrendsData) -> some View {
    Text(L10n.get("trends_empty_chart")).font(.footnote).foregroundStyle(data.tone.subtitle).padding(.vertical, 24)
}

// MARK: - Stacked columns: load, intensity, technique mix

private struct TSeg { let color: Color; let value: Double; var alpha = 1.0 }
private struct TCol { let index: Int; let label: String; let segs: [TSeg]; var mark: Double? = nil }

private struct TrendColumns: View {
    let columns: [TCol]
    let fixedTop: Double?
    let tickLabel: (Double) -> String
    let data: TrendsData
    let space: ChartSpace
    var totalLabel: ((Double) -> String)? = nil

    private let left: CGFloat = 42

    var body: some View {
        let frame = chartFrame(space)
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size) }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    guard !columns.isEmpty else { return }
                    let w = (geo.size.width - left - 8) / CGFloat(columns.count)
                    let i = Int((point.x - left) / w)
                    if columns.indices.contains(i) { data.onBucket(columns[i].index) }
                }
        }
        .frame(maxWidth: .infinity, minHeight: frame.minHeight, maxHeight: frame.maxHeight)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let s = space.scale
        let fs = 10.5 * s
        let topValue: Double
        let ticks: [Double]
        if let fixedTop {
            topValue = fixedTop
            ticks = [0, fixedTop / 4, fixedTop / 2, fixedTop * 3 / 4, fixedTop]
        } else {
            let peak = max(columns.map { $0.segs.reduce(0) { $0 + $1.value } }.max() ?? 0, columns.compactMap { $0.mark }.max() ?? 0, 0.1)
            let nice = niceTicks(peak, 4)
            topValue = nice.top
            ticks = nice.ticks
        }
        let topPad: CGFloat = 10, bottom: CGFloat = 26
        let plotH = size.height - topPad - bottom
        func y(_ v: Double) -> CGFloat { topPad + CGFloat(1 - v / topValue) * plotH }
        for t in ticks {
            var line = Path()
            line.move(to: CGPoint(x: left, y: y(t)))
            line.addLine(to: CGPoint(x: size.width - 8, y: y(t)))
            ctx.stroke(line, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            put(&ctx, tickLabel(t), left - 6, y(t), size: fs, color: data.tone.subtitle, anchor: .trailing)
        }
        let w = (size.width - left - 8) / CGFloat(max(columns.count, 1))
        for (k, col) in columns.enumerated() {
            let cx = left + w * (CGFloat(k) + 0.5)
            let bw = min(w * 0.64, space.maximized ? 64 : 38)
            let dim = data.dimBucket(col.index)
            var base = y(0)
            for seg in col.segs where seg.value > 0 {
                let h = y(0) - y(seg.value)
                let rect = CGRect(x: cx - bw / 2, y: base - h, width: bw, height: max(h - 1, 0))
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(seg.color.opacity(seg.alpha * dim)))
                base -= h
            }
            if let mark = col.mark {
                var m = Path()
                m.move(to: CGPoint(x: cx - bw / 2 - 3, y: y(mark)))
                m.addLine(to: CGPoint(x: cx + bw / 2 + 3, y: y(mark)))
                ctx.stroke(m, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, dash: [5, 3]))
            }
            let selected = data.bucket == col.index
            put(&ctx, col.label, cx, size.height - bottom / 2, size: fs, color: selected ? data.tone.title : data.tone.subtitle, bold: selected)
            if space.maximized, let totalLabel {
                let total = col.segs.reduce(0) { $0 + $1.value }
                if total > 0 { put(&ctx, totalLabel(total), cx, base - 8, size: fs, color: .primary) }
            }
        }
    }
}

struct TrendLoadChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let view = data.view("load")
        let groups = Array(Set(data.buckets.flatMap { Array($0.groups.keys) })).sorted()
        func value(_ a: TrendAmount) -> Double {
            view == 0 ? Double(a.seconds) / 3600 : view == 1 ? Double(a.distanceM) / 1000 : Double(a.ascentM)
        }
        let previous = Dictionary(uniqueKeysWithValues: data.prevBuckets.map { (Int($0.index), $0) })
        let columns = data.buckets.map { b -> TCol in
            let prevTotal = previous[Int(b.index)].map { $0.groups.values.reduce(0) { $0 + value($1) } }
            return TCol(
                index: Int(b.index), label: trendBucketLabel(Int(b.index), data.periodDays),
                segs: groups.compactMap { g in b.groups[g].map { TSeg(color: trendGroupColor(g), value: value($0)) } },
                mark: data.compare ? prevTotal : nil
            )
        }
        let tick: (Double) -> String = { v in view == 0 ? "\(trim(v)) h" : view == 1 ? "\(trim(v)) km" : "\(trim(v)) m" }
        return VStack(alignment: .leading, spacing: 6) {
            TrendToggle(options: [L10n.get("trends_v_time"), L10n.get("trends_v_distance"), L10n.get("trends_v_climb")], current: view, id: "load", data: data)
            TrendColumns(columns: columns, fixedTop: nil, tickLabel: tick, data: data, space: space, totalLabel: { v in
                view == 0 ? String(format: "%.1f h", v) : view == 1 ? "\(Int(v.rounded())) km" : "\(Int(v.rounded())) m"
            })
            TrendLegend(items: groups.map { ($0, trendGroupName($0), trendGroupColor($0)) }, selected: "", data: data)
            if data.bucket >= 0 {
                let n = data.cur.filter { Int(data.periodDays <= 7 ? $0.daysAgo : $0.daysAgo / 7) == data.bucket }.count
                caption(String(format: L10n.get("trends_selected_column"), trendBucketLabel(data.bucket, data.periodDays), n), data)
            } else {
                caption(L10n.get("trends_hint_load"), data)
            }
        }
    }
}

struct TrendIntensityChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let percent = data.view("int") == 1
        let columns = data.buckets.map { b -> TCol in
            let zs = ints(b.zones)
            let total = Double(zs.reduce(0, +))
            return TCol(
                index: Int(b.index), label: trendBucketLabel(Int(b.index), data.periodDays),
                segs: zs.enumerated().map { z, sec in
                    TSeg(color: hrZoneColor(z + 1), value: percent ? (total > 0 ? Double(sec) / total * 100 : 0) : Double(sec) / 3600, alpha: data.dimZone(z + 1))
                }
            )
        }
        let zones = (0..<5).map { z in data.cur.reduce(0) { $0 + $1.zones[z].intValue } }
        let total = Double(zones.reduce(0, +))
        return VStack(alignment: .leading, spacing: 6) {
            TrendToggle(options: [L10n.get("trends_v_hours"), L10n.get("trends_v_share")], current: data.view("int"), id: "int", data: data)
            TrendColumns(columns: columns, fixedTop: percent ? 100 : nil, tickLabel: { v in percent ? "\(Int(v.rounded()))%" : "\(trim(v)) h" }, data: data, space: space)
            if total > 0 {
                polarisation(zones, total)
                Text(L10n.get("trends_polarisation_hint")).font(.caption2).foregroundStyle(data.tone.subtitle)
            }
            TrendLegend(items: (0..<5).map { ("\($0 + 1)", "Z\($0 + 1)", hrZoneColor($0 + 1)) }, selected: data.zone > 0 ? "\(data.zone)" : "", data: data) { key in
                if let z = Int(key) { data.onZone(z) }
            }
        }
    }

    private func polarisation(_ zones: [Int], _ total: Double) -> some View {
        let parts: [(Int, Color, String)] = [
            (zones[0] + zones[1], Color(red: 0, green: 0.33, blue: 1), L10n.get("trends_low")),
            (zones[2], Color(red: 0, green: 0.67, blue: 0), L10n.get("trends_mid")),
            (zones[3] + zones[4], Color(red: 1, green: 0.42, blue: 0), L10n.get("trends_high")),
        ]
        return HStack(spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if part.0 > 0 {
                    let z = data.zone
                    let inPart = z == 0 || (i == 0 && z <= 2) || (i == 1 && z == 3) || (i == 2 && z >= 4)
                    let share = Int((Double(part.0) / total * 100).rounded())
                    ZStack {
                        part.1.opacity(inPart ? 1 : 0.25)
                        if share >= 12 {
                            Text("\(share)% \(space.maximized ? part.2 : String(part.2.split(separator: " ").first ?? ""))")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(Double(part.0))
                }
            }
        }
        .frame(height: 22 * space.scale)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TrendMixChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let hasTech = data.cur.contains { !$0.techniques.isEmpty }
        let hasRun = data.cur.contains { !$0.terrain.isEmpty }
        // Technique when there are ski activities, else terrain or walk/run (toggle).
        let mode = hasTech ? 0 : (data.view("mix") == 1 ? 2 : 1)
        let keys: [String] = mode == 0
            ? ["KLAEBO", "V2", "DIA", "V2A", "KDP", "V1", "DP", "GLIDE", "OTHER"]
            : mode == 1 ? ["STEEP", "UP", "FLAT", "DOWN", "STEEP_DOWN"] : ["RUN", "WALK"]
        func seconds(_ b: TrendBucket, _ k: String) -> Int {
            switch mode {
            case 0: return b.techniqueSeconds[k]?.intValue ?? 0
            case 1: return b.terrainSeconds[k]?.intValue ?? 0
            default: return b.gaitSeconds[k]?.intValue ?? 0
            }
        }
        let present = keys.filter { k in data.buckets.contains { seconds($0, k) > 0 } }
        let columns = data.buckets.map { b -> TCol in
            let total = Double(present.reduce(0) { $0 + seconds(b, $1) })
            return TCol(
                index: Int(b.index), label: trendBucketLabel(Int(b.index), data.periodDays),
                segs: present.compactMap { k in
                    let sec = seconds(b, k)
                    return sec > 0 ? TSeg(color: stateColor(k), value: Double(sec) / total * 100, alpha: mode == 0 ? data.dimTech(k) : 1) : nil
                }
            )
        }
        return VStack(alignment: .leading, spacing: 6) {
            if !hasTech && hasRun {
                TrendToggle(options: [L10n.get("trends_v_terrain"), L10n.get("trends_v_walkrun")], current: data.view("mix"), id: "mix", data: data)
            }
            TrendColumns(columns: columns, fixedTop: 100, tickLabel: { "\(Int($0.rounded()))%" }, data: data, space: space)
            TrendLegend(
                items: present.map { k in (k, mode == 2 ? (k == "RUN" ? L10n.get("em_run") : L10n.get("em_walk")) : stateShort(k), stateColor(k)) },
                selected: mode == 0 ? data.tech : "", data: data, onTap: mode == 0 ? { data.onTech($0) } : nil
            )
            caption(L10n.get("trends_hint_tech"), data)
        }
    }
}

// MARK: - Climb

struct TrendClimbChart: View {
    let data: TrendsData
    let space: ChartSpace
    private let left: CGFloat = 42

    var body: some View {
        let frame = chartFrame(space)
        let asc = data.cur.reduce(0) { $0 + Int($1.ascentM) }
        let hours = Double(data.cur.reduce(0) { $0 + Int($1.seconds) }) / 3600
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                Canvas { ctx, size in draw(&ctx, size) }
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        let n = max(data.buckets.count, 1)
                        let w = (geo.size.width - left - 8) / CGFloat(n)
                        let i = Int((point.x - left) / w)
                        if data.buckets.indices.contains(i) { data.onBucket(Int(data.buckets[i].index)) }
                    }
            }
            .frame(maxWidth: .infinity, minHeight: frame.minHeight, maxHeight: frame.maxHeight)
            HStack(spacing: 12) {
                Text("▲ \(L10n.get("trends_ascent"))").foregroundStyle(Color(red: 0.306, green: 0.396, blue: 0.502))
                Text("▼ \(L10n.get("trends_descent"))").foregroundStyle(Color(red: 0.639, green: 0.710, blue: 0.788))
                if hours > 0 { Text(String(format: L10n.get("trends_vert_per_hour"), Int((Double(asc) / hours).rounded()))).foregroundStyle(data.tone.subtitle) }
            }
            .font(.caption)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let fs = 10.5 * space.scale
        let peak = Double(data.buckets.map { max(Int($0.ascentM), Int($0.descentM)) }.max() ?? 0)
        let nice = niceTicks(max(peak, 10), 3)
        let topPad: CGFloat = 8, bottom: CGFloat = 26
        let half = (size.height - topPad - bottom) / 2
        let mid = topPad + half
        let w = (size.width - left - 8) / CGFloat(max(data.buckets.count, 1))
        for t in nice.ticks {
            let up = mid - CGFloat(t / nice.top) * half
            put(&ctx, "\(Int(t)) m", left - 6, up, size: fs, color: data.tone.subtitle, anchor: .trailing)
            var line = Path()
            line.move(to: CGPoint(x: left, y: up)); line.addLine(to: CGPoint(x: size.width - 8, y: up))
            ctx.stroke(line, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            if t > 0 {
                let dn = mid + CGFloat(t / nice.top) * half
                put(&ctx, "-\(Int(t))", left - 6, dn, size: fs, color: data.tone.subtitle, anchor: .trailing)
                var l2 = Path()
                l2.move(to: CGPoint(x: left, y: dn)); l2.addLine(to: CGPoint(x: size.width - 8, y: dn))
                ctx.stroke(l2, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            }
        }
        for (k, b) in data.buckets.enumerated() {
            let cx = left + w * (CGFloat(k) + 0.5)
            let bw = min(w * 0.56, space.maximized ? 54 : 32)
            let dim = data.dimBucket(Int(b.index))
            let hu = CGFloat(Double(b.ascentM) / nice.top) * half
            let hd = CGFloat(Double(b.descentM) / nice.top) * half
            ctx.fill(Path(roundedRect: CGRect(x: cx - bw / 2, y: mid - hu, width: bw, height: hu), cornerRadius: 2),
                     with: .color(Color(red: 0.306, green: 0.396, blue: 0.502).opacity(dim)))
            ctx.fill(Path(roundedRect: CGRect(x: cx - bw / 2, y: mid, width: bw, height: hd), cornerRadius: 2),
                     with: .color(Color(red: 0.639, green: 0.710, blue: 0.788).opacity(dim)))
            let selected = data.bucket == Int(b.index)
            put(&ctx, trendBucketLabel(Int(b.index), data.periodDays), cx, size.height - bottom / 2, size: fs,
                color: selected ? data.tone.title : data.tone.subtitle, bold: selected)
            if space.maximized && b.ascentM > 0 { put(&ctx, "\(b.ascentM) m", cx, mid - hu - 8, size: fs, color: .primary) }
        }
    }
}

// MARK: - Technique x zone matrix

struct TrendMatrixChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let running = !data.cur.contains { !$0.techniques.isEmpty } && data.cur.contains { !$0.terrain.isEmpty }
        let totals = Trends.shared.stateTotals(list: data.cur, running: running)
        if totals.isEmpty {
            emptyChart(data)
        } else {
            let maxShare = max(0.01, totals.map { t -> Double in
                t.seconds == 0 ? 0 : (t.zones.map { $0.doubleValue / Double(t.seconds) }.max() ?? 0)
            }.max() ?? 0.01)
            VStack(alignment: .leading, spacing: 3 * space.scale) {
                HStack(spacing: 3) {
                    Color.clear.frame(maxWidth: .infinity).layoutPriority(1.3)
                    ForEach(0..<5, id: \.self) { z in
                        Text("Z\(z + 1)").font(.caption2.weight(data.zone == z + 1 ? .bold : .regular))
                            .foregroundStyle(data.zone == z + 1 ? data.tone.title : data.tone.subtitle)
                            .frame(maxWidth: .infinity).layoutPriority(1)
                    }
                    Color.clear.frame(maxWidth: .infinity).layoutPriority(0.8)
                }
                ForEach(totals, id: \.key) { t in
                    HStack(spacing: 3) {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(stateColor(t.key)).frame(width: 9, height: 9)
                            Text(stateShort(t.key)).font(.caption).fontWeight(data.tech == t.key ? .bold : .regular).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1.3)
                        ForEach(0..<5, id: \.self) { z in
                            let sec = t.zones[z].intValue
                            let share = t.seconds > 0 ? Double(sec) / Double(t.seconds) : 0
                            let strength = sec > 0 ? 0.12 + 0.88 * (share / maxShare).squareRoot() : 0.04
                            ZStack {
                                RoundedRectangle(cornerRadius: 5).fill(hrZoneColor(z + 1).opacity(strength * max(data.dimTech(t.key) * data.dimZone(z + 1), 0.35)))
                                if sec > 0 {
                                    Text("\(Int((share * 100).rounded()))%").font(.caption2.weight(.semibold))
                                        .foregroundStyle(strength > 0.55 ? Color.white : Color.primary)
                                }
                            }
                            .frame(height: space.maximized ? 30 : 22)
                            .frame(maxWidth: .infinity).layoutPriority(1)
                            .contentShape(Rectangle())
                            .onTapGesture { data.onTech(t.key); data.onZone(z + 1) }
                        }
                        Text(trendDuration(Int(t.seconds))).font(.caption2).foregroundStyle(data.tone.subtitle).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing).layoutPriority(0.8)
                    }
                }
                caption(L10n.get("trends_hint_cell"), data)
            }
        }
    }
}

// MARK: - Scatter charts: poling map and technique by slope

private struct TDot {
    let id: String
    let x: Double
    let y: Double
    let seconds: Int
    let color: Color
    let key: String
    let alpha: Double
    let title: String
    let detail: String
}

private struct TrendScatter: View {
    let dots: [TDot]
    let means: [TDot]
    let xStep: Double
    let xLabel: (Double) -> String
    let yLabel: (Double) -> String
    let yFloor: Double?
    let axisTitle: String
    let curves: [Double]
    let curveY: ((Double, Double) -> Double)?
    let data: TrendsData
    let space: ChartSpace

    private let left: CGFloat = 44, topPad: CGFloat = 22, bottom: CGFloat = 24, right: CGFloat = 10

    private var x0: Double { (floor((dots.map { $0.x }.min() ?? 0) / xStep)) * xStep - xStep * 0.5 }
    private var x1: Double { (ceil((dots.map { $0.x }.max() ?? 1) / xStep)) * xStep + xStep * 0.5 }
    private var yLow: Double { yFloor ?? 0 }
    private var yTop: Double { yLow + niceTicks(max(1, (dots.map { $0.y }.max() ?? 1) * 1.1 - yLow), 4).top }

    private func px(_ x: Double, _ w: CGFloat) -> CGFloat { left + CGFloat((x - x0) / (x1 - x0)) * (w - left - right) }
    private func py(_ y: Double, _ h: CGFloat) -> CGFloat { topPad + CGFloat(1 - (y - yLow) / (yTop - yLow)) * (h - topPad - bottom) }

    var body: some View {
        let frame = chartFrame(space)
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size) }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    let hit = dots.min { a, b in
                        let da = hypot(px(a.x, geo.size.width) - point.x, py(a.y, geo.size.height) - point.y)
                        let db = hypot(px(b.x, geo.size.width) - point.x, py(b.y, geo.size.height) - point.y)
                        return da < db
                    }
                    if let hit, hypot(px(hit.x, geo.size.width) - point.x, py(hit.y, geo.size.height) - point.y) < 32, data.picked != hit.id {
                        data.onPick(hit.id)
                    } else {
                        data.onPick("")
                    }
                }
        }
        .frame(maxWidth: .infinity, minHeight: frame.minHeight, maxHeight: frame.maxHeight)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let fs = 10.5 * space.scale
        let ticks = niceTicks(max(1, (dots.map { $0.y }.max() ?? 1) * 1.1 - yLow), 4).ticks
        for t in ticks {
            let y = yLow + t
            var line = Path()
            line.move(to: CGPoint(x: left, y: py(y, size.height))); line.addLine(to: CGPoint(x: size.width - right, y: py(y, size.height)))
            ctx.stroke(line, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            put(&ctx, yLabel(y), left - 6, py(y, size.height), size: fs, color: data.tone.subtitle, anchor: .trailing)
        }
        // At most 5 labels in the card (8 full screen): the step grows by 1, 2, 5, 10 ... times xStep, so labels never
        // overlap (impulse in ms spans hundreds at a 5 ms step). As Android's ScatterCanvas.
        let maxLabels: Double = space.maximized ? 8 : 5
        let labelStep = [1.0, 2, 5, 10, 20, 50, 100, 200, 500, 1000].map { $0 * xStep }
            .first { (x1 - x0) / $0 <= maxLabels } ?? xStep * 1000
        var gx = ceil(x0 / labelStep) * labelStep
        while gx <= x1 {
            put(&ctx, xLabel(gx), px(gx, size.width), size.height - bottom / 2, size: fs, color: data.tone.subtitle)
            gx += labelStep
        }
        put(&ctx, axisTitle, left, topPad - 12, size: fs, color: data.tone.title, anchor: .leading, bold: true)
        if let curveY {
            for c in curves {
                var path = Path()
                var started = false
                var x = max(x0, 1)
                while x <= x1 {
                    let y = curveY(c, x)
                    if y >= yLow && y <= yTop {
                        let p = CGPoint(x: px(x, size.width), y: py(y, size.height))
                        if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                    }
                    x += (x1 - x0) / 80
                }
                ctx.stroke(path, with: .color(data.tone.subtitle.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                let xr = x1 - (x1 - x0) * 0.02
                let yr = curveY(c, xr)
                let labelX = (yr >= yLow && yr <= yTop) ? xr : c * 60 / (yTop * 0.96)
                let labelY = (yr >= yLow && yr <= yTop) ? yr : yTop * 0.96
                if labelX >= x0 && labelX <= x1 {
                    put(&ctx, "\(trim(c)) m/s", px(labelX, size.width) - 4, py(labelY, size.height) - 7, size: fs * 0.85, color: data.tone.subtitle, anchor: .trailing)
                }
            }
        }
        for d in dots {
            let r = max(3 * min(space.scale, 1.3), CGFloat(Double(d.seconds).squareRoot() / 6) * min(space.scale, 1.3))
            let center = CGPoint(x: px(d.x, size.width), y: py(d.y, size.height))
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(d.color.opacity(0.55 * d.alpha)))
            let selected = data.picked == d.id
            ctx.stroke(Path(ellipseIn: rect), with: .color(selected ? Color.primary : d.color.opacity(d.alpha)), lineWidth: selected ? 2.4 : 1)
        }
        for d in means {
            let r = 6 * min(space.scale, 1.3)
            let center = CGPoint(x: px(d.x, size.width), y: py(d.y, size.height))
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(d.color.opacity(d.alpha)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(data.tone.container), lineWidth: 2)
            if space.maximized { put(&ctx, d.key, center.x, center.y - 12, size: fs, color: data.tone.title, bold: true) }
        }
    }
}

struct TrendPolingChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let view = data.view("pol")
        var dots: [TDot] = []
        for a in data.cur {
            for t in a.techniques {
                let rate = t.rate?.intValue, dps = t.dps?.doubleValue, imp = t.impulseMs?.intValue
                let duty = t.dutyPercent?.intValue, hr = t.hr?.intValue, speed = t.speedMps?.doubleValue
                var xy: (Double, Double)?
                switch view {
                case 0: if let rate, let dps { xy = (Double(rate), dps) }
                case 1: if rate != nil, let imp, let duty { xy = (Double(imp), Double(duty)) }
                default: if let hr, let speed { xy = (Double(hr), speed * 3.6) }
                }
                guard let xy else { continue }
                let detail = String(format: "%.1f km/h · %d/min · %.1f m · %@", (speed ?? 0) * 3.6, rate ?? 0, dps ?? 0, trendDuration(Int(t.seconds)))
                dots.append(TDot(id: "\(a.id)|\(t.key)", x: xy.0, y: xy.1, seconds: Int(t.seconds), color: stateColor(t.key), key: stateShort(t.key),
                                 alpha: data.dimTech(t.key), title: a.title, detail: detail))
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            TrendToggle(options: [L10n.get("trends_ax_rate"), L10n.get("trends_ax_imp"), L10n.get("trends_ax_hr")], current: view, id: "pol", data: data)
            if dots.isEmpty {
                emptyChart(data)
            } else {
                TrendScatter(
                    dots: dots, means: [], xStep: view == 2 ? 10 : 5, xLabel: { trim($0) }, yLabel: { trim($0) },
                    // Puls × Tempo has speed (km/h) on the y axis: no floor (100 put every dot below the chart).
                    yFloor: nil,
                    axisTitle: view == 0 ? L10n.get("trends_ay_rate") : view == 1 ? L10n.get("trends_ay_imp") : L10n.get("trends_ay_hr"),
                    curves: view == 0 ? [3, 4, 5, 6, 7] : [], curveY: view == 0 ? { v, x in v * 60 / x } : nil, data: data, space: space
                )
                let keys = Array(Set(dots.map { $0.key })).sorted()
                TrendLegend(items: keys.map { k in (k, k, stateColor(k)) }, selected: data.tech, data: data) { data.onTech($0) }
                if let d = dots.first(where: { $0.id == data.picked }) {
                    caption("\(d.key) · \(d.title) · \(d.detail)", data)
                } else {
                    caption(L10n.get("trends_hint_dot"), data)
                }
            }
        }
    }
}

struct TrendSlopeChart: View {
    let data: TrendsData
    let space: ChartSpace

    var body: some View {
        let running = !data.cur.contains { !$0.techniques.isEmpty } && data.cur.contains { !$0.terrain.isEmpty }
        let hr = data.view("slope") == 1
        var dots: [TDot] = []
        for a in data.cur {
            for t in (running ? a.terrain : a.techniques) {
                guard let grade = t.gradePct?.doubleValue else { continue }
                let y: Double? = hr ? t.hr.map { Double($0.intValue) } : t.speedMps.map { $0.doubleValue * 3.6 }
                guard let y else { continue }
                let detail = String(format: "%@%.1f%% · %.1f km/h · %d bpm · %@", grade > 0 ? "+" : "", grade, (t.speedMps?.doubleValue ?? 0) * 3.6, t.hr?.intValue ?? 0, trendDuration(Int(t.seconds)))
                dots.append(TDot(id: "\(a.id)|\(t.key)", x: grade, y: y, seconds: Int(t.seconds), color: stateColor(t.key), key: stateShort(t.key),
                                 alpha: running ? 1 : data.dimTech(t.key), title: a.title, detail: detail))
            }
        }
        // The time-weighted mean of each technique or terrain: the larger dot.
        let means: [TDot] = Dictionary(grouping: dots, by: { $0.key }).map { key, list in
            let w = Double(list.reduce(0) { $0 + $1.seconds })
            return TDot(id: "mean|\(key)", x: list.reduce(0) { $0 + $1.x * Double($1.seconds) } / w, y: list.reduce(0) { $0 + $1.y * Double($1.seconds) } / w,
                        seconds: Int(w), color: list[0].color, key: key, alpha: list[0].alpha, title: "", detail: "")
        }
        return VStack(alignment: .leading, spacing: 6) {
            TrendToggle(options: [L10n.get("trends_y_speed"), L10n.get("trends_y_hr")], current: data.view("slope"), id: "slope", data: data)
            if dots.isEmpty {
                emptyChart(data)
            } else {
                TrendScatter(
                    dots: dots, means: means, xStep: 4, xLabel: { ($0 > 0 ? "+" : "") + trim($0) + "%" }, yLabel: { trim($0) },
                    yFloor: hr ? 80 : nil, axisTitle: hr ? "bpm" : "km/h", curves: [], curveY: nil, data: data, space: space
                )
                if !running {
                    let keys = Array(Set(dots.map { $0.key })).sorted()
                    TrendLegend(items: keys.map { k in (k, k, stateColor(k)) }, selected: data.tech, data: data) { data.onTech($0) }
                }
                if let d = dots.first(where: { $0.id == data.picked }) {
                    caption("\(d.key) · \(d.title) · \(d.detail)", data)
                } else {
                    caption(L10n.get("trends_hint_dot"), data)
                }
            }
        }
    }
}

// MARK: - Trend lines: efficiency and recovery

struct TrendEfficiencyChart: View {
    let data: TrendsData
    let space: ChartSpace
    private let left: CGFloat = 40, topPad: CGFloat = 22, bottom: CGFloat = 24, right: CGFloat = 10

    private var fadeAvailable: Bool { data.window.contains { $0.fadePercent != nil } }

    private func points() -> [(TrendActivity, Double)] {
        let fade = data.view("eff") == 1 && fadeAvailable
        return data.window.compactMap { a in
            if fade { return a.fadePercent.map { (a, $0.doubleValue) } }
            return a.efficiency > 0 ? (a, a.efficiency) : nil
        }
    }

    var body: some View {
        let pts = points()
        let frame = chartFrame(space)
        let fade = data.view("eff") == 1 && fadeAvailable
        return VStack(alignment: .leading, spacing: 6) {
            if fadeAvailable {
                TrendToggle(options: [L10n.get("trends_v_eff"), L10n.get("trends_v_fade")], current: data.view("eff"), id: "eff", data: data)
            }
            if pts.count < 3 {
                Text(L10n.get("trends_needs_three")).font(.footnote).foregroundStyle(data.tone.subtitle).padding(.vertical, 24)
            } else {
                GeometryReader { geo in
                    Canvas { ctx, size in draw(&ctx, size, pts, fade) }
                        .contentShape(Rectangle())
                        .onTapGesture { point in
                            let days = Double(data.periodDays * 2 - 1)
                            let plotW = geo.size.width - left - right
                            let hit = pts.min { abs(left + CGFloat(1 - Double($0.0.daysAgo) / days) * plotW - point.x) < abs(left + CGFloat(1 - Double($1.0.daysAgo) / days) * plotW - point.x) }
                            if let hit, abs(left + CGFloat(1 - Double(hit.0.daysAgo) / days) * plotW - point.x) < 30, data.picked != "a|\(hit.0.id)" {
                                data.onPick("a|\(hit.0.id)")
                            } else {
                                data.onPick("")
                            }
                        }
                }
                .frame(maxWidth: .infinity, minHeight: frame.minHeight, maxHeight: frame.maxHeight)
                if let a = data.window.first(where: { "a|\($0.id)" == data.picked }) {
                    caption("\(a.title) · \(trendDuration(Int(a.seconds))) · \(a.avgHr) bpm · " + (fade ? String(format: "%.1f%%", a.fadePercent?.doubleValue ?? 0) : String(format: "%.2f", a.efficiency)), data)
                } else if let change = trendChange(pts) {
                    caption(String(format: L10n.get("trends_eff_trend"), (change >= 0 ? "+" : "") + String(format: "%.1f", change) + "%", data.periodDays * 2), data)
                }
                caption(L10n.get("trends_eff_note"), data)
            }
        }
    }

    /// Least-squares slope per day of days-ago, and the change it gives from the oldest to the newest day in percent.
    private func fit(_ pts: [(TrendActivity, Double)]) -> (slope: Double, meanX: Double, meanY: Double)? {
        guard pts.count >= 3 else { return nil }
        let n = Double(pts.count)
        let mx = pts.reduce(0) { $0 + Double($1.0.daysAgo) } / n
        let my = pts.reduce(0) { $0 + $1.1 } / n
        let sxx = pts.reduce(0) { $0 + (Double($1.0.daysAgo) - mx) * (Double($1.0.daysAgo) - mx) }
        guard sxx > 0 else { return nil }
        return (pts.reduce(0) { $0 + (Double($1.0.daysAgo) - mx) * ($1.1 - my) } / sxx, mx, my)
    }

    private func trendChange(_ pts: [(TrendActivity, Double)]) -> Double? {
        guard let f = fit(pts) else { return nil }
        let days = Double(data.periodDays * 2 - 1)
        let now = f.meanY + f.slope * (0 - f.meanX)
        let old = f.meanY + f.slope * (days - f.meanX)
        return old != 0 ? (now - old) / abs(old) * 100 : nil
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ pts: [(TrendActivity, Double)], _ fade: Bool) {
        let fs = 10.5 * space.scale
        let days = Double(data.periodDays * 2 - 1)
        let lo0 = pts.map { $0.1 }.min() ?? 0, hi0 = pts.map { $0.1 }.max() ?? 1
        let pad = (hi0 - lo0) * 0.15 + 0.01
        let lo = lo0 - pad, hi = hi0 + pad
        let plotW = size.width - left - right, plotH = size.height - topPad - bottom
        func px(_ d: Double) -> CGFloat { left + CGFloat(1 - d / days) * plotW }
        func py(_ v: Double) -> CGFloat { topPad + CGFloat(1 - (v - lo) / (hi - lo)) * plotH }
        for k in 0...4 {
            let v = lo + (hi - lo) * Double(k) / 4
            var line = Path()
            line.move(to: CGPoint(x: left, y: py(v))); line.addLine(to: CGPoint(x: size.width - right, y: py(v)))
            ctx.stroke(line, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            put(&ctx, String(format: fade ? "%.1f" : "%.2f", v), left - 6, py(v), size: fs, color: data.tone.subtitle, anchor: .trailing)
        }
        for d in [days, (days / 2).rounded(), 0] {
            put(&ctx, d == 0 ? "0" : "-\(Int(d))", px(d), size.height - bottom / 2, size: fs, color: data.tone.subtitle)
        }
        for (group, list) in Dictionary(grouping: pts, by: { $0.0.group }) {
            let color = trendGroupColor(group)
            let sorted = list.sorted { $0.0.daysAgo > $1.0.daysAgo }
            if sorted.count > 1 {
                var path = Path()
                for (i, p) in sorted.enumerated() {
                    let pt = CGPoint(x: px(Double(p.0.daysAgo)), y: py(p.1))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 1.2)
            }
            for p in sorted {
                let r: CGFloat = data.picked == "a|\(p.0.id)" ? 6 : 4
                let c = CGPoint(x: px(Double(p.0.daysAgo)), y: py(p.1))
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
                ctx.stroke(Path(ellipseIn: rect), with: .color(data.tone.container), lineWidth: 1.5)
            }
        }
        if let f = fit(pts) {
            var trend = Path()
            trend.move(to: CGPoint(x: px(days), y: py(f.meanY + f.slope * (days - f.meanX))))
            trend.addLine(to: CGPoint(x: px(0), y: py(f.meanY + f.slope * (0 - f.meanX))))
            ctx.stroke(trend, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, dash: [8, 5]))
        }
        put(&ctx, fade ? L10n.get("trends_v_fade") : L10n.get("trends_eff_axis"), left, topPad - 12, size: fs, color: data.tone.title, anchor: .leading, bold: true)
    }
}

struct TrendRecoveryChart: View {
    let data: TrendsData
    let space: ChartSpace
    private let left: CGFloat = 40, topPad: CGFloat = 22, bottom: CGFloat = 24, right: CGFloat = 10

    var body: some View {
        let withHrv = data.window.filter { $0.rmssd > 0 }.sorted { $0.daysAgo > $1.daysAgo }
        let frame = chartFrame(space)
        return VStack(alignment: .leading, spacing: 6) {
            if withHrv.count < 2 {
                Text(L10n.get("trends_needs_hrv")).font(.footnote).foregroundStyle(data.tone.subtitle).padding(.vertical, 24)
            } else {
                GeometryReader { geo in
                    Canvas { ctx, size in draw(&ctx, size, withHrv) }
                        .contentShape(Rectangle())
                        .onTapGesture { point in
                            let days = data.periodDays * 2
                            let w = (geo.size.width - left - right) / CGFloat(days)
                            func x(_ a: TrendActivity) -> CGFloat { left + (CGFloat(days - 1 - Int(a.daysAgo)) + 0.5) * w }
                            let hit = withHrv.min { abs(x($0) - point.x) < abs(x($1) - point.x) }
                            if let hit, abs(x(hit) - point.x) < 30, data.picked != "a|\(hit.id)" { data.onPick("a|\(hit.id)") } else { data.onPick("") }
                        }
                }
                .frame(maxWidth: .infinity, minHeight: frame.minHeight, maxHeight: frame.maxHeight)
                let mean = withHrv.reduce(0) { $0 + $1.rmssd } / Double(withHrv.count)
                if let a = withHrv.first(where: { "a|\($0.id)" == data.picked }) {
                    caption("\(a.title) · RMSSD \(String(format: "%.1f", a.rmssd)) ms" + (a.rpe > 0 ? " · RPE \(a.rpe)" : ""), data)
                } else {
                    caption(String(format: L10n.get("trends_rec_note"), Int(mean.rounded())), data)
                }
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ withHrv: [TrendActivity]) {
        let fs = 10.5 * space.scale
        let days = data.periodDays * 2
        let loadByDay = Dictionary(grouping: data.window, by: { Int($0.daysAgo) }).mapValues { $0.reduce(0) { $0 + $1.load } }
        let maxLoad = max(loadByDay.values.max() ?? 1, 1)
        let lo = floor((withHrv.map { $0.rmssd }.min() ?? 0) - 3), hi = ceil((withHrv.map { $0.rmssd }.max() ?? 1) + 3)
        let mean = withHrv.reduce(0) { $0 + $1.rmssd } / Double(withHrv.count)
        let plotW = size.width - left - right, plotH = size.height - topPad - bottom
        let w = plotW / CGFloat(days)
        func px(_ d: Int) -> CGFloat { left + (CGFloat(days - 1 - d) + 0.5) * w }
        func py(_ v: Double) -> CGFloat { topPad + CGFloat(1 - (v - lo) / (hi - lo)) * plotH }
        for k in 0...4 {
            let v = lo + (hi - lo) * Double(k) / 4
            var line = Path()
            line.move(to: CGPoint(x: left, y: py(v))); line.addLine(to: CGPoint(x: size.width - right, y: py(v)))
            ctx.stroke(line, with: .color(data.tone.subtitle.opacity(0.25)), lineWidth: 1)
            put(&ctx, "\(Int(v.rounded()))", left - 6, py(v), size: fs, color: data.tone.subtitle, anchor: .trailing)
        }
        for (d, l) in loadByDay {
            let h = CGFloat(l / maxLoad) * plotH * 0.4
            ctx.fill(Path(CGRect(x: px(d) - w * 0.32, y: topPad + plotH - h, width: w * 0.64, height: h)), with: .color(data.tone.subtitle.opacity(0.3)))
        }
        var path = Path()
        for (i, a) in withHrv.enumerated() {
            let p = CGPoint(x: px(Int(a.daysAgo)), y: py(a.rmssd))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        ctx.stroke(path, with: .color(data.tone.title), lineWidth: 2)
        for a in withHrv {
            let r: CGFloat = data.picked == "a|\(a.id)" ? 6.5 : 4
            let c = CGPoint(x: px(Int(a.daysAgo)), y: py(a.rmssd))
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(trendGroupColor(a.group)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(data.tone.container), lineWidth: 1.5)
        }
        var meanLine = Path()
        meanLine.move(to: CGPoint(x: left, y: py(mean))); meanLine.addLine(to: CGPoint(x: size.width - right, y: py(mean)))
        ctx.stroke(meanLine, with: .color(Color.primary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
        for d in [days - 1, (days - 1) / 2, 0] {
            put(&ctx, d == 0 ? "0" : "-\(d)", px(d), size.height - bottom / 2, size: fs, color: data.tone.subtitle)
        }
        put(&ctx, "RMSSD ms", left, topPad - 12, size: fs, color: data.tone.title, anchor: .leading, bold: true)
    }
}
