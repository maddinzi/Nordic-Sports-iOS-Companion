import NordicSportsShared
import SwiftUI

/// Where a tap on an activity card goes: an Entry tab or a Metrics tab (Android: `ActivityTarget`).
enum ActivityTarget: String, Hashable {
    case diary, strava, data, technique, sensor
}

/// The tabs of the Entry screen: what goes to the diary, what it was like outside, and what goes to Strava.
enum EntryTab: Hashable {
    case diary, outThere, strava
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

    /// True when the app recorded the activity (watch, phone, by hand): the Metrics lane then has numbers behind it
    /// (Android `hasWatchMetrics`, `ActivitySource.isAppRecorded`).
    var hasWatchMetrics: Bool { appRecorded }

    /// True when the Technique tab has something to show (Enhanced Metrics, running analysis, technique shares).
    var hasTechniqueMetrics: Bool {
        enhancedMetrics != nil || !techniqueSharePercent.isEmpty || !analysisLines.isEmpty
            || (!watch.isEmpty && ["running", "poleRunning", "trailrun", "mountainRun", "track"].contains(preset))
    }
}

/// The compact list row (Android: `CompactActivityRow`): two text lines and two icon links, to the Entry screen
/// (tinted in the entry's status colour) and to the Metrics screen.
struct CompactActivityRow: View {
    let item: ActivityItem
    let onOpen: (ActivityTarget) -> Void

    private var entryColor: Color {
        switch item.entryStatus {
        case .attention: return .orange
        case .review: return SyncChip.diary
        case .written: return .green
        case .open, .imported: return .gray
        }
    }

    var body: some View {
        let bodyTarget: ActivityTarget = item.entryStatus == .written && item.hasWatchMetrics ? .data : .diary
        HStack(spacing: 4) {
            Button { onOpen(bodyTarget) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title.isEmpty ? L10n.get("activity_detail_title_fallback") : item.title)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(Format.summary(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { onOpen(.diary) } label: {
                Image(systemName: "square.and.pencil").foregroundStyle(entryColor).frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.get("card_lane_entry"))
            if item.hasWatchMetrics {
                Button { onOpen(.data) } label: {
                    Image(systemName: "chart.bar.fill").foregroundStyle(Color(red: 0x2F / 255, green: 0x5F / 255, blue: 0x85 / 255)).frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.get("card_lane_metrics"))
            }
        }
    }
}

/// The activity list's card (Android: `ActivityEventCard`): the identity on top (title, the blue watch tick with source,
/// start, duration, distance) and two lanes below. The Entry lane is what the athlete declares for the diary and Strava,
/// in the status colour (yellow to review, green written, orange action needed); its chips open the Entry screen on
/// that tab. The Metrics lane is the read-only numbers; its chips open the Metrics screen on that tab. A tap on the top
/// opens the Entry screen while something waits for the athlete, the Metrics screen otherwise.
struct ActivityCard: View {
    let item: ActivityItem
    var stravaConnected = false
    var diaryConnected = false
    let onOpen: (ActivityTarget) -> Void

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
            // The bottom row (Android `ActivityEventCard`, 2026-11-10): the black origin icon first, then the tappable
            // chips with their word (status, Diary, Strava), the metrics numbers and the Sensor Records; on two lines
            // when one is too narrow.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { OriginMark(item: item).padding(.horizontal, 2); entryChips; metricsItems }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { OriginMark(item: item).padding(.horizontal, 2); entryChips }
                    HStack(spacing: 6) { metricsItems }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// What waits for the athlete (only then a word), then the diary and Strava chips: the icon in the destination's
    /// colour when it has the activity, grey while on its way, red on a problem; no chip for a destination it never goes to.
    @ViewBuilder private var entryChips: some View {
        if item.entryStatus == .review || item.entryStatus == .attention {
            chip(entryText, symbol: "square.and.pencil", accent: entryColor) { onOpen(.diary) }
        }
        if let mark = item.diaryMark(connected: diaryConnected) {
            chip(L10n.get("sync_presence_destination_diary"), symbol: "book.closed",
                 symbolColor: markColor(mark, done: SyncChip.diary)) { onOpen(.diary) }
        }
        if let mark = item.stravaMark(connected: stravaConnected) {
            chip("Strava", symbol: "chevron.up.2", symbolColor: markColor(mark, done: SyncChip.strava)) { onOpen(.strava) }
        }
    }

    /// The Metrics link: one chip with the Metrics symbol and the key numbers ("8.0 km · 158 bpm · 10.4 km/h",
    /// "Metrics" without numbers), then the Sensor Records.
    @ViewBuilder private var metricsItems: some View {
        if item.hasWatchMetrics {
            let numbers = [
                item.distanceM > 0 ? String(format: "%.1f km", Double(item.distanceM) / 1000) : nil,
                item.avgHeartRate > 0 ? "\(item.avgHeartRate) bpm" : nil,
                // pace for runs and walks, as the key figures (ActivityFigures.usesPace)
                item.avgSpeedMps <= 0 ? nil : ActivityFigures.shared.usesPace(art: item.sportArt)
                    ? ActivityFigures.shared.paceSecPerKm(speedMps: item.avgSpeedMps).map { ActivityFigures.shared.paceText(secPerKm: $0.int32Value) + " /km" }
                    : Optional(String(format: "%.1f km/h", Double(item.avgSpeedMps) * 3.6)),
            ].compactMap { $0 }.joined(separator: " · ")
            chip(numbers.isEmpty ? L10n.get("card_lane_metrics") : numbers, symbol: "chart.bar.fill") { onOpen(.data) }
        }
        if item.sensorRecordCount > 0 {
            chip("\(item.sensorRecordCount)", symbol: "dot.radiowaves.left.and.right") { onOpen(.sensor) }
        }
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
            // The source line as text only: the origin icon leads the bottom row.
            Text(Format.summary(item))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// A tappable chip with its word; [symbolColor] tints the icon (a destination's mark), an [accent] marks a status chip.
    private func chip(_ label: String, symbol: String, symbolColor: Color = .secondary,
                      accent: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption).foregroundStyle(symbolColor)
                Text(label).font(.caption)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(accent?.opacity(0.18) ?? Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent ?? Color(.separator), lineWidth: accent != nil ? 1.5 : 1))
        }
        .buttonStyle(.borderless)
    }
}
