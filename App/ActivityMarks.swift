import NordicSportsShared
import SwiftUI

/// The state of a destination mark (Android `MarkState`): there, on its way, or a problem.
enum MarkState { case done, pending, problem }

extension ActivityItem {
    /// The Strava mark (Android `stravaMark`): red on a conflict or a missing activity, in colour when linked, grey while
    /// a connected Strava will get it; none otherwise. A phone recording waits only for its upload, which iOS has not yet.
    func stravaMark(connected: Bool) -> MarkState? {
        if stravaConflict || stravaUnavailable { return .problem }
        if !stravaActivityId.isEmpty || origin == "strava" { return .done }
        if connected && appRecorded && !isDemo && source != "phone" { return .pending }
        return nil
    }

    /// The diary mark (Android `diaryMark`): in colour when written, grey while a connected diary will get it.
    func diaryMark(connected: Bool) -> MarkState? {
        if diaryWritten { return .done }
        if connected && !isDemo { return .pending }
        return nil
    }
}

func markColor(_ state: MarkState, done: Color) -> Color {
    switch state {
    case .done: return done
    case .pending: return .secondary
    case .problem: return .red
    }
}

/// The black origin icon at the start of a card's bottom row and in the detail header (Android `OriginMark`): watch,
/// phone, keyboard (by hand), diary book (taken from the diary) or the Strava chevrons.
struct OriginMark: View {
    let item: ActivityItem
    var font: Font = .subheadline

    private var symbol: (String, String) {
        switch item.source {
        case "phone": return ("iphone", L10n.get("activity_source_phone_long"))
        case "manual": return ("keyboard", L10n.get("activity_source_manual_long"))
        case "diary_backport": return ("book.closed", L10n.get("sync_presence_destination_diary"))
        case "strava": return ("chevron.up.2", "Strava")
        default: return ("applewatch", L10n.get("sync_presence_destination_watch"))
        }
    }

    var body: some View {
        Image(systemName: symbol.0)
            .font(font)
            .foregroundStyle(.primary)
            .accessibilityLabel(symbol.1)
    }
}
