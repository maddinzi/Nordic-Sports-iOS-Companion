import NordicSportsShared
import SwiftUI

/// The key figures at the top of every Metrics theme but All data (Android: `KeyFigures`): compact tiles, three to a row,
/// each leading to the theme behind it. With [typical] set a tile also says how this activity differs from the athlete's usual.
struct KeyFiguresStrip: View {
    let item: ActivityItem
    let typical: TrendTypical?
    let jump: (MetricsTheme) -> Void
    private let tone = CardTone.navy

    private struct Fig {
        let value: String
        let unit: String
        let label: String
        let theme: MetricsTheme
        var delta: String?
    }

    private func percent(_ current: Double, _ usual: Double) -> String? {
        guard typical != nil, current > 0, usual > 0 else { return nil }
        let value = Int(((current - usual) / usual * 100).rounded())
        return String(format: "%+d %%", value)
    }

    private var figures: [Fig] {
        let figs = ActivityFigures.shared
        var out: [Fig] = [
            Fig(value: Format.duration(item.elapsedSec), unit: "", label: L10n.get("activity_detail_moving_time_label"),
                theme: .enhanced(.overview), delta: percent(Double(item.elapsedSec), Double(typical?.seconds ?? 0))),
        ]
        if item.distanceM > 0 {
            out.append(Fig(value: String(format: "%.1f", Double(item.distanceM) / 1000), unit: "km", label: L10n.get("activity_detail_distance_label"),
                           theme: .enhanced(.overview), delta: percent(Double(item.distanceM), Double(typical?.distanceM ?? 0))))
        }
        if item.totalAscentM > 0 {
            out.append(Fig(value: String(format: "%.0f", Double(item.totalAscentM)), unit: "m", label: L10n.get("activity_detail_ascent_label"),
                           theme: .enhanced(.terrain), delta: percent(Double(item.totalAscentM), Double(typical?.ascentM ?? 0))))
        }
        if item.avgHeartRate > 0 {
            let usual = Int(typical?.avgHr ?? 0)
            out.append(Fig(value: "\(item.avgHeartRate)", unit: "bpm", label: L10n.get("activity_detail_avg_hr_label"),
                           theme: .enhanced(.heartRate), delta: typical != nil && usual > 0 ? String(format: "%+d bpm", Int(item.avgHeartRate) - usual) : nil))
        }
        if item.avgSpeedMps > 0 {
            if figs.usesPace(art: item.sportArt) {
                if let pace = figs.paceSecPerKm(speedMps: item.avgSpeedMps)?.int32Value {
                    out.append(Fig(value: figs.paceText(secPerKm: pace), unit: "/km", label: L10n.get("dash_fig_pace"),
                                   theme: .enhanced(.terrain), delta: percent(Double(item.avgSpeedMps), typical?.speedMps ?? 0)))
                }
            } else {
                out.append(Fig(value: String(format: "%.1f", Double(item.avgSpeedMps) * 3.6), unit: "km/h", label: L10n.get("dash_fig_speed"),
                               theme: .enhanced(.technique), delta: percent(Double(item.avgSpeedMps), typical?.speedMps ?? 0)))
            }
        }
        if item.calories > 0 {
            out.append(Fig(value: "\(item.calories)", unit: "kcal", label: L10n.get("activity_detail_calories_label"), theme: .allData))
        }
        return out
    }

    var body: some View {
        let rows = stride(from: 0, to: figures.count, by: 3).map { Array(figures[$0 ..< min($0 + 3, figures.count)]) }
        VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, fig in
                        Button { jump(fig.theme) } label: { tile(fig) }.buttonStyle(.plain)
                    }
                    ForEach(0 ..< (3 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private func tile(_ fig: Fig) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fig.value).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                if !fig.unit.isEmpty { Text(fig.unit).font(.system(size: 11)).foregroundStyle(tone.subtitle) }
            }
            Text(fig.label).font(.system(size: 10)).foregroundStyle(tone.subtitle).lineLimit(1)
            if let delta = fig.delta { Text(delta).font(.system(size: 12, weight: .semibold)).foregroundStyle(tone.title).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }
}
