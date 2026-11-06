import NordicSportsShared
import SwiftUI

/// Where a tap on an activity card goes: an Entry tab or a Metrics tab (Android: `ActivityTarget`).
enum ActivityTarget: String, Hashable {
    case diary, strava, data, technique
}

/// The tabs of the Entry screen: what goes to the diary, and what goes to Strava.
enum EntryTab: Hashable {
    case diary, strava
}

/// The tabs of the Metrics screen: the technical data, and the watch's technique analysis.
enum MetricsTab: Hashable {
    case data, technique
}

/// What the Entry lane of an activity card says; the colour family is the card's status colour.
enum EntryStatus {
    case attention, review, written, open, imported
}

extension ActivityItem {
    var entryStatus: EntryStatus {
        if conflict || stravaConflict || stravaUnavailable { return .attention }
        if reviewPending { return .review }
        if diaryWritten || !stravaActivityId.isEmpty { return origin == "strava" ? .imported : .written }
        return origin == "strava" ? .imported : .open
    }

    /// True when the watch recorded the activity: the Metrics lane then has numbers behind it.
    var hasWatchMetrics: Bool { origin == "watch" }

    /// True when the Technique tab has something to show (Enhanced Metrics, running analysis, technique shares).
    var hasTechniqueMetrics: Bool {
        enhancedMetrics != nil || !techniqueSharePercent.isEmpty || !analysisLines.isEmpty
            || (!watch.isEmpty && ["running", "poleRunning", "trailrun", "mountainRun", "track"].contains(preset))
    }
}

/// The activity list's card (Android: `ActivityEventCard`): the identity on top (title, the blue watch tick with source,
/// start, duration, distance) and two lanes below. The Entry lane is what the athlete declares for the diary and Strava,
/// in the status colour (yellow to review, green written, orange action needed); its chips open the Entry screen on
/// that tab. The Metrics lane is the read-only numbers; its chips open the Metrics screen on that tab. A tap on the top
/// opens the Entry screen while something waits for the athlete, the Metrics screen otherwise.
struct ActivityCard: View {
    let item: ActivityItem
    let onOpen: (ActivityTarget) -> Void

    private enum Tick { case none, todo, done, problem }

    private static let metricsColor = Color(red: 0x2F / 255, green: 0x5F / 255, blue: 0x85 / 255)

    private var entryColor: Color {
        switch item.entryStatus {
        case .attention: return .orange
        case .review: return SyncChip.diary
        case .written: return .green
        case .open, .imported: return .gray
        }
    }

    private var entryText: String {
        switch item.entryStatus {
        case .attention: return L10n.get("card_status_attention")
        case .review: return L10n.get("card_status_review")
        case .written: return L10n.get("card_status_written")
        case .open: return L10n.get("card_status_open")
        case .imported: return L10n.get("card_status_imported")
        }
    }

    var body: some View {
        let bodyTarget: ActivityTarget = item.entryStatus == .written && item.hasWatchMetrics ? .data : .diary
        VStack(alignment: .leading, spacing: 10) {
            Button { onOpen(bodyTarget) } label: { identity }
                .buttonStyle(.plain)
            HStack(alignment: .top, spacing: 8) {
                entryLane
                metricsLane
            }
        }
        .padding(.vertical, 4)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title.isEmpty ? L10n.get("activity_detail_title_fallback") : item.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if item.isDemo {
                    Text(L10n.get("demo_badge"))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2), in: Capsule())
                }
            }
            // The blue watch tick stays in front of the source line, as the Watch badge was.
            HStack(spacing: 4) {
                Image(systemName: item.origin == "watch" ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(item.origin == "watch" ? SyncChip.watch : Color.secondary)
                    .accessibilityLabel(L10n.get("sync_presence_destination_watch"))
                Text(Format.summary(item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var entryLane: some View {
        lane(title: L10n.get("card_lane_entry"), symbol: "square.and.pencil", color: entryColor,
             onHeader: { onOpen(.diary) }) {
            Text(entryText).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                chip(L10n.get("sync_presence_destination_diary"), symbol: "book.closed",
                     tick: item.diaryWritten ? .done : .todo, tickColor: SyncChip.diary) { onOpen(.diary) }
                chip("Strava", symbol: "chevron.up.2",
                     tick: item.stravaConflict || item.stravaUnavailable ? .problem
                         : (item.stravaActivityId.isEmpty ? .todo : .done),
                     tickColor: SyncChip.strava) { onOpen(.strava) }
            }
        }
    }

    @ViewBuilder private var metricsLane: some View {
        if item.hasWatchMetrics {
            lane(title: L10n.get("card_lane_metrics"), symbol: "chart.bar.fill", color: Self.metricsColor,
                 onHeader: { onOpen(.data) }) {
                HStack(alignment: .top, spacing: 10) {
                    if item.distanceM > 0 { number(String(format: "%.1f", Double(item.distanceM) / 1000), "km") }
                    if item.avgHeartRate > 0 { number("\(item.avgHeartRate)", "bpm") }
                    if item.avgSpeedMps > 0 { number(String(format: "%.1f", Double(item.avgSpeedMps) * 3.6), "km/h") }
                }
                VStack(alignment: .leading, spacing: 5) {
                    chip(L10n.get("card_chip_data"), symbol: "list.bullet") { onOpen(.data) }
                    if item.hasTechniqueMetrics {
                        chip(L10n.get("card_chip_technique"), symbol: "waveform.path.ecg") { onOpen(.technique) }
                    }
                }
            }
        } else {
            lane(title: L10n.get("card_lane_metrics"), symbol: "chart.bar.fill", color: .gray, onHeader: nil) {
                Text(L10n.get("card_no_watch_data")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func number(_ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// One lane: a tinted, framed box with an icon title; [onHeader] makes the title a link.
    private func lane<Content: View>(title: String, symbol: String, color: Color, onHeader: (() -> Void)?,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let onHeader {
                Button(action: onHeader) { laneHeader(title, symbol, color, link: true) }.buttonStyle(.plain)
            } else {
                laneHeader(title, symbol, color, link: false)
            }
            content()
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: 1.5))
    }

    private func laneHeader(_ title: String, _ symbol: String, _ color: Color, link: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color)
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.primary)
            Spacer(minLength: 0)
            if link { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(color) }
        }
        .contentShape(Rectangle())
    }

    private func chip(_ label: String, symbol: String, tick: Tick = .none, tickColor: Color = .green,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
                Text(label).font(.caption)
                switch tick {
                case .none: EmptyView()
                case .done: Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(tickColor)
                case .todo: Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
                case .problem: Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
        }
        .buttonStyle(.borderless)
    }
}
