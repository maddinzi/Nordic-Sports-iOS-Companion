import NordicSportsShared
import SwiftUI

/// The Timeline theme of the Metrics screen (Android: `TimelineCharts.kt`): the recording in blocks of time. A ski
/// activity gets two stacked-column charts (heart rate zones per block, technique per block), a run one chart with
/// heart rate and pace per ten-minute block. A tap on a column reads that block in every chart of the theme.
struct TimelineSection: View {
    let view: EnhancedMetricsView
    private let tone = CardTone.blue
    @ObservedObject var pick: MetricsPick
    private var block: Binding<Int?> { Binding(get: { pick.block }, set: { pick.block = $0 }) }
    /// A zone ("Z3") or technique picked in a legend or any other chart; the other segments dim.
    private var zoneKey: Binding<String> {
        Binding(get: { pick.zone.map { "Z\($0 + 1)" } ?? "" },
                set: { pick.zone = $0.isEmpty ? nil : (Int($0.dropFirst()).map { $0 - 1 }) })
    }
    private var techKey: Binding<String> {
        Binding(get: { pick.key ?? "" }, set: { pick.key = $0.isEmpty ? nil : $0 })
    }
    /// The charts of this theme, for paging through them with a swipe while one is full screen.
    @State private var registry = ChartRegistry()
    @Environment(\.chartRegistry) private var outerRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let blocks = view.timeline {
                ChartFrame(title: L10n.get("tl_zones_title"), tone: tone) { space in
                    StackedBlocks(blocks: blocks.byZone, blockSec: Int(blocks.blockSec), block: block, pickedKey: zoneKey,
                                  color: { $0.isEmpty ? Color.techniqueLight : hrZoneColor(Int($0.dropFirst()) ?? 1) },
                                  name: { $0.isEmpty ? L10n.get("em_timeline_no_hr") : $0 }, space: space)
                }
                ChartFrame(title: L10n.get("tl_tech_title"), tone: tone) { space in
                    StackedBlocks(blocks: blocks.byTechnique, blockSec: Int(blocks.blockSec), block: block, pickedKey: techKey,
                                  color: { $0.isEmpty ? Color.techniqueLight : stateColor($0) },
                                  name: { $0.isEmpty ? L10n.get("em_timeline_none") : stateName($0) }, space: space)
                }
            }
            if view.runBlocks.count >= 2 {
                ChartFrame(title: L10n.get("tl_run_title"), tone: tone) { space in
                    RunBlocks(blocks: view.runBlocks, block: block, space: space)
                }
            }
        }
        .environment(\.chartRegistry, outerRegistry ?? registry)
    }
}

/// Stacked columns over time: each block's seconds split into segments; `clock(i * blockSec)` is the start of block i.
private struct StackedBlocks: View {
    let blocks: [[EmSeg]]
    let blockSec: Int
    @Binding var block: Int?
    @Binding var pickedKey: String
    let color: (String) -> Color
    let name: (String) -> String
    let space: ChartSpace
    private let tone = CardTone.blue

    var body: some View {
        if blocks.isEmpty || blockSec <= 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let slot = geo.size.width / CGFloat(blocks.count)
                    let height = geo.size.height - 16
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { i, segs in
                            let dimBlock = block != nil && block != i
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                ForEach(Array(segs.reversed().enumerated()), id: \.offset) { _, seg in
                                    let dim = dimBlock || (!pickedKey.isEmpty && seg.key != pickedKey)
                                    Rectangle().fill(color(seg.key).opacity(dim ? 0.3 : 1))
                                        .frame(height: height * min(CGFloat(seg.seconds) / CGFloat(blockSec), 1))
                                }
                            }
                            .frame(width: max(slot * 0.84, 1), height: height)
                            .position(x: slot * (CGFloat(i) + 0.5), y: height / 2)
                        }
                        ForEach(Array(blocks.indices), id: \.self) { i in
                            Text(clock(i * blockSec)).font(.system(size: 9)).foregroundStyle(tone.subtitle)
                                .position(x: slot * (CGFloat(i) + 0.5), y: height + 9)
                                .opacity(slot < 28 && i % 2 == 1 ? 0 : 1)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { drag in
                        let i = min(max(Int(drag.location.x / slot), 0), blocks.count - 1)
                        block = block == i ? nil : i
                    })
                }
                .frame(height: 180 * space.scale)
                .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
                Text(caption).font(.caption).foregroundStyle(tone.subtitle)
                legend
            }
        }
    }

    private var caption: String {
        guard let i = block, blocks.indices.contains(i) else { return L10n.get("tl_hint") }
        let segs = blocks[i]
        let total = segs.reduce(0) { $0 + Int($1.seconds) }
        return "\(clock(i * blockSec))–\(clock(i * blockSec + total)) · "
            + segs.sorted { $0.seconds > $1.seconds }.map { "\(name($0.key)) \(clock(Int($0.seconds)))" }.joined(separator: ", ")
    }

    /// The key: tapping a name picks it, the other segments dim.
    private var legend: some View {
        let keys = Array(Set(blocks.flatMap { $0.map { $0.key } })).sorted { name($0) < name($1) }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Button {
                    if !key.isEmpty { pickedKey = pickedKey == key ? "" : key }
                } label: {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(color(key)).frame(width: 10, height: 10)
                        Text(name(key)).font(.caption).fontWeight(pickedKey == key ? .bold : .regular)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Heart rate and pace of each ten-minute block of a run: two rows of columns, one tap reads both.
private struct RunBlocks: View {
    let blocks: [EmRunBlock]
    @Binding var block: Int?
    let space: ChartSpace
    private let tone = CardTone.blue
    private let blockSec = 600

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.get("activity_detail_avg_hr_label")).font(.caption).foregroundStyle(tone.subtitle)
            columns(blocks.map { $0.hr > 0 ? Double($0.hr) : nil }, color: .red)
            Text(L10n.get("dash_fig_pace")).font(.caption).foregroundStyle(tone.subtitle)
            // A faster block is taller: the column shows speed, the label reads as pace.
            columns(blocks.map { $0.paceSecPerKm > 0 ? 1000.0 / Double($0.paceSecPerKm) : nil }, color: .runBlue)
            Text(caption).font(.caption).foregroundStyle(tone.subtitle)
        }
    }

    private var caption: String {
        guard let i = block, blocks.indices.contains(i) else { return L10n.get("tl_hint") }
        let b = blocks[i]
        var parts = ["\(clock(i * blockSec))–\(clock(i * blockSec + Int(b.seconds)))"]
        if b.hr > 0 { parts.append("\(Int(b.hr.rounded())) bpm") }
        if b.paceSecPerKm > 0 { parts.append(ActivityFigures.shared.paceText(secPerKm: b.paceSecPerKm) + " /km") }
        return parts.joined(separator: " · ")
    }

    private func columns(_ values: [Double?], color: Color) -> some View {
        let present = values.compactMap { $0 }
        let hi = present.max() ?? 1
        let lo = max((present.min() ?? 0) * 0.85, 0)
        return GeometryReader { geo in
            let slot = geo.size.width / CGFloat(max(values.count, 1))
            let height = geo.size.height - 16
            ZStack(alignment: .topLeading) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    if let v {
                        let h = hi > lo ? min(max((v - lo) / (hi - lo), 0.08), 1) : 1
                        let dim = block != nil && block != i
                        RoundedRectangle(cornerRadius: 3).fill(color.opacity(dim ? 0.35 : 1))
                            .frame(width: max(slot * 0.82, 1), height: height * CGFloat(h))
                            .position(x: slot * (CGFloat(i) + 0.5), y: height - height * CGFloat(h) / 2)
                    }
                    Text(clock(i * blockSec)).font(.system(size: 9)).foregroundStyle(tone.subtitle)
                        .position(x: slot * (CGFloat(i) + 0.5), y: height + 9)
                        .opacity(slot < 28 && i % 2 == 1 ? 0 : 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { drag in
                let i = min(max(Int(drag.location.x / slot), 0), values.count - 1)
                if values[i] != nil { block = block == i ? nil : i }
            })
        }
        .frame(height: 110 * space.scale)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }
}
