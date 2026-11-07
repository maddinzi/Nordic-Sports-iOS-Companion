import NordicSportsShared
import SwiftUI

/// The time -> technique -> heart rate zone Sankey of one ski activity (Android: `TechniqueSankeyChart.kt`): time slices
/// on the left (or laps, when the watch marked some: a switch chooses), the techniques in the middle, the zones on the
/// right. A tap on a bar highlights its bands. The layout is the shared `TechniqueSankey`; this only draws it.
struct TechniqueSankeyChart: View {
    let byTime: TechniqueSankey
    let byLap: TechniqueSankey?
    @State private var lapMode = false
    @State private var selected = ""
    private let tone = CardTone.blue

    private var sankey: TechniqueSankey { lapMode ? (byLap ?? byTime) : byTime }

    var body: some View {
        ChartFrame(title: L10n.get("em_timeline_title"), tone: tone) { space in
            VStack(alignment: .leading, spacing: 8) {
                if space.maximized {
                    // Full screen is short and wide: one slim row (the switch and the caption) above the chart and one
                    // legend line below it; the chart keeps the rest. A swipe on the chart switches time and lap too.
                    HStack(spacing: 12) {
                        if byLap != nil { modePicker.frame(maxWidth: 220) }
                        Text(caption).font(.caption).foregroundStyle(tone.subtitle).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    canvas(space)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(DragGesture(minimumDistance: 40).onEnded { drag in
                            guard byLap != nil, abs(drag.translation.width) > abs(drag.translation.height) else { return }
                            lapMode = drag.translation.width < 0
                            selected = ""
                        })
                    legend
                } else {
                    if byLap != nil { modePicker }
                    canvas(space).frame(maxWidth: .infinity, minHeight: 240, maxHeight: 240)
                    Text(caption).font(.caption).foregroundStyle(tone.subtitle)
                }
            }
        }
    }

    private func canvas(_ space: ChartSpace) -> some View {
        SankeyCanvas(sankey: sankey, selected: selected, textScale: space.scale, onSelect: { key in
            selected = selected == key ? "" : key
        })
    }

    /// The Time / Lap switch: one segmented control, in the card and full screen alike.
    private var modePicker: some View {
        Picker("", selection: $lapMode) {
            Text(L10n.get("em_timeline_by_time")).tag(false)
            Text(L10n.get("em_timeline_by_lap")).tag(true)
        }
        .pickerStyle(.segmented)
        .onChange(of: lapMode) { _, _ in selected = "" }
    }

    private var caption: String {
        guard let node = sankey.nodes.first(where: { $0.key == selected }), sankey.totalSeconds > 0 else {
            return L10n.get("em_timeline_hint")
        }
        let percent = Int((Double(node.seconds) * 100 / Double(sankey.totalSeconds)).rounded())
        return "\(sankeyLabel(node)) · \(clock(Int(node.seconds))) · \(percent)%"
    }

    /// What each technique colour means, on ONE line (the zones name themselves at the right of the chart). A long name
    /// shrinks and is cut rather than wrapping to a second line.
    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(sankey.nodes.filter { $0.column == 1 }, id: \.key) { node in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).fill(sankeyColor(node)).frame(width: 12, height: 12)
                    Text(sankeyLabel(node)).font(.footnote).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

/// The name of a bar: the technique, `Z1`..`Z5`, the lap numbers or the start of the time slice.
private func sankeyLabel(_ node: SankeyNode) -> String {
    let key = node.key
    if key == "tech:NONE" { return L10n.get("em_timeline_none") }
    if key.hasPrefix("tech:") { return stateShort(String(key.dropFirst(5))) }
    if key == "zone:0" { return L10n.get("em_timeline_no_hr") }
    if key.hasPrefix("zone:") { return "Z" + key.dropFirst(5) }
    if key.hasPrefix("lap:") {
        let first = Int(node.startLap), count = Int(node.lapCount)
        return count > 1 ? "\(first)–\(first + count - 1)" : "\(first)"
    }
    return clock(Int(node.startSec))
}

/// Time bars are neutral, so the colour stays with the techniques and the zones; "no technique" and "no heart rate" are grey.
private func sankeyColor(_ node: SankeyNode) -> Color {
    switch node.column {
    case 0: return .techniqueGrey
    case 1:
        let state = String(node.key.dropFirst(5))
        return state == "NONE" ? .techniqueLight : stateColor(state)
    default:
        if let zone = Int(node.key.dropFirst(5)), (1...5).contains(zone) { return hrZoneColor(zone) }
        return .techniqueLight
    }
}

/// Whether text on `color` is white (a dark fill) or dark (a light one).
private func isDark(_ color: Color) -> Bool {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.5
}

/// Where the three columns and their labels sit, in points (Android: `SankeyFrame`).
private struct SankeyFrame {
    let width: CGFloat
    let height: CGFloat
    let k: CGFloat
    /// Full screen: the time next to a zone's share and a line under a technique name, so both bars get more room.
    let detail: Bool

    private var leftLabel: CGFloat { 40 * k }
    private var rightLabel: CGFloat { (detail ? 88 : 62) * k }
    private var thin: CGFloat { 8 * k }
    private var wide: CGFloat { (detail ? 60 : 40) * k }
    private let top: CGFloat = 6
    private var usable: CGFloat { height - 12 }
    private var timeX: CGFloat { leftLabel }
    private var zoneX: CGFloat { width - rightLabel - thin }
    private var techX: CGFloat { timeX + (zoneX - timeX) / 2 - wide / 2 }
    let hitSlop: CGFloat = 6

    func x(_ column: Int32) -> CGFloat { column == 0 ? timeX : column == 1 ? techX : zoneX }
    func barWidth(_ column: Int32) -> CGFloat { column == 1 ? wide : thin }
    func y(_ fraction: Float) -> CGFloat { top + CGFloat(fraction) * usable }

    func rect(_ node: SankeyNode) -> CGRect {
        CGRect(x: x(node.column), y: y(node.y0), width: barWidth(node.column), height: y(node.y1) - y(node.y0))
    }
}

private struct SankeyCanvas: View {
    let sankey: TechniqueSankey
    let selected: String
    let textScale: CGFloat
    let onSelect: (String) -> Void
    private let tone = CardTone.blue

    var body: some View {
        GeometryReader { geo in
            let frame = SankeyFrame(width: geo.size.width, height: geo.size.height, k: textScale, detail: textScale > 1)
            Canvas { context, _ in draw(&context, frame) }
                .contentShape(Rectangle())
                .onTapGesture { point in
                    let hit = sankey.nodes.first { frame.rect($0).insetBy(dx: -frame.hitSlop, dy: -frame.hitSlop).contains(point) }
                    onSelect(hit?.key ?? "")
                }
        }
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.get("em_timeline_desc"))
    }

    private func draw(_ context: inout GraphicsContext, _ frame: SankeyFrame) {
        let nodes = sankey.nodes
        let colors = nodes.map(sankeyColor)
        let heartRateSeconds = max(1, nodes.filter { $0.column == 2 && $0.key != "zone:0" }.reduce(0) { $0 + Int($1.seconds) })
        // Bands first, so the bars sit on top of them.
        for link in sankey.links {
            guard let source = nodes[safe: Int(link.source)], let target = nodes[safe: Int(link.target)] else { continue }
            let active = selected.isEmpty || source.key == selected || target.key == selected
            context.fill(band(frame, source, target, link), with: .color(colors[Int(link.target)].opacity(active ? 0.55 : 0.10)))
        }
        for (index, node) in nodes.enumerated() {
            let rect = frame.rect(node)
            let dim = !selected.isEmpty && node.key != selected
            context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(colors[index].opacity(dim ? 0.45 : 1)))
            drawLabel(&context, frame, node, rect, colors[index], heartRateSeconds)
        }
    }

    private func band(_ frame: SankeyFrame, _ from: SankeyNode, _ to: SankeyNode, _ link: SankeyLink) -> Path {
        let x0 = frame.x(from.column) + frame.barWidth(from.column)
        let x1 = frame.x(to.column)
        let mid = (x0 + x1) / 2
        let sy = frame.y(link.sy0)
        let ty = frame.y(link.ty0)
        let th = CGFloat(link.thickness) * (frame.y(1) - frame.y(0))
        var path = Path()
        path.move(to: CGPoint(x: x0, y: sy))
        path.addCurve(to: CGPoint(x: x1, y: ty), control1: CGPoint(x: mid, y: sy), control2: CGPoint(x: mid, y: ty))
        path.addLine(to: CGPoint(x: x1, y: ty + th))
        path.addCurve(to: CGPoint(x: x0, y: sy + th), control1: CGPoint(x: mid, y: ty + th), control2: CGPoint(x: mid, y: sy + th))
        path.closeSubpath()
        return path
    }

    private func drawLabel(_ context: inout GraphicsContext, _ frame: SankeyFrame, _ node: SankeyNode, _ rect: CGRect, _ fill: Color, _ heartRateSeconds: Int) {
        let text = sankeyLabel(node)
        if text.isEmpty { return }
        let small = Font.system(size: 10 * textScale)
        switch node.column {
        case 0:
            context.draw(Text(text).font(small).foregroundStyle(tone.subtitle), at: CGPoint(x: rect.minX - 4, y: rect.midY), anchor: .trailing)
        case 2:
            // Zones 1..5 as a share of the time with a heart rate, like the donut; "no heart rate" of all time.
            let share = node.key == "zone:0" ? Int(sankey.totalSeconds) : heartRateSeconds
            let percent = share > 0 ? Int((Double(node.seconds) * 100 / Double(share)).rounded()) : 0
            let timeText = frame.detail ? " · \(clock(Int(node.seconds)))" : ""
            context.draw(Text("\(text) \(percent)%\(timeText)").font(small).foregroundStyle(tone.subtitle),
                         at: CGPoint(x: rect.maxX + 4, y: rect.midY), anchor: .leading)
        default:
            // Inside the bar, only when the bar is tall enough to hold a line and the name fits.
            if rect.height < 14 { return }
            let ink: Color = isDark(fill) ? .white : Color(red: 0x1B / 255, green: 0x2A / 255, blue: 0x38 / 255)
            let label = Text(text).font(.system(size: 11 * textScale, weight: .bold)).foregroundStyle(ink)
            let size = context.resolve(label).measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
            if size.width > rect.width { return }
            // Full screen: the share and the time under the name, when the bar has the height and the width for them.
            if frame.detail, sankey.totalSeconds > 0 {
                let percent = Int((Double(node.seconds) * 100 / Double(sankey.totalSeconds)).rounded())
                let sub = Text("\(percent)% · \(clock(Int(node.seconds)))").font(.system(size: 9 * textScale)).foregroundStyle(ink)
                let subSize = context.resolve(sub).measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                if subSize.width <= rect.width, rect.height >= size.height + subSize.height + 6 {
                    let gap = (size.height + subSize.height) / 2
                    context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY - gap + size.height / 2), anchor: .center)
                    context.draw(sub, at: CGPoint(x: rect.midX, y: rect.midY + gap - subSize.height / 2), anchor: .center)
                    return
                }
            }
            context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
