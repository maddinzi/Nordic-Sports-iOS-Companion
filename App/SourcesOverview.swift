import NordicSportsShared
import SwiftUI

/// "Sources and calibration" on the watch page (Companion `design/multi-source-metrics.md`; Android `SourcesSection`):
/// the athlete's contact-time factor and the cadence agreement with what they rest on, and whether the data that
/// feeds them arrives: the newest run's strap, the phone's motion switch and position. Read from the stored runs
/// each time the rows appear (shared `CompanionCore.sourcesOverview`).
struct SourcesOverviewRows: View {
    @EnvironmentObject var companion: Companion
    @State private var overview: SourcesOverviewView?

    var body: some View {
        Group {
            Text(L10n.get("sources_title")).font(.subheadline.weight(.semibold))
            if let o = overview {
                Text(gctLine(o))
                if o.gctStale {
                    Text(L10n.get("sources_gct_refresh")).font(.footnote).foregroundStyle(.secondary)
                }
                Text(cadenceLine(o))
                if o.lastRunEpochSec >= 0 {
                    Text(String(format: L10n.get(lastRunKey(o)), date(o.lastRunEpochSec)))
                }
                Text(String(
                    format: L10n.get(PhoneMotionCapture.isEnabled ? "sources_phone_on" : "sources_phone_off"),
                    L10n.get("phone_motion_placement_\(PhoneMotionCapture.placement)")
                ))
                // The last paired recording in numbers (Android alike): what the phone kept and what it cost.
                if let last = companion.core.pairedRecording.lastCapture() {
                    Text(String(
                        format: L10n.get("sources_paired_last"),
                        date(last.startTimeEpochSec), Int(last.minutes), Int(last.records),
                        last.batteryStart >= 0 ? "\(last.batteryStart)" : "?", last.batteryEnd >= 0 ? "\(last.batteryEnd)" : "?"
                    ))
                    if last.trackPoints > 0 {
                        Text(String(format: L10n.get("sources_paired_track"), Int(last.trackPoints)))
                    }
                }
            }
            Text(L10n.get("sources_intro")).font(.footnote).foregroundStyle(.secondary)
        }
        .task { overview = await companion.sourcesOverview() }
    }

    private func gctLine(_ o: SourcesOverviewView) -> String {
        if o.gctRuns > 0, o.gctNewestEpochSec >= 0 {
            return String(format: L10n.get("sources_gct_model"),
                          String(format: "%.2f", locale: Locale.current, o.gctFactor), Int(o.gctRuns), date(o.gctNewestEpochSec))
        }
        return String(format: L10n.get("sources_gct_waiting"), Int(o.gctStrapRuns))
    }

    private func cadenceLine(_ o: SourcesOverviewView) -> String {
        let compared = Int(o.cadenceCompared)
        guard compared > 0 else { return L10n.get("sources_cadence_waiting") }
        return String(format: L10n.get("sources_cadence_model"),
                      Int(o.cadenceWithin) * 100 / compared, compared / 60,
                      Int(o.cadenceHalf) * 100 / compared, Int(o.cadenceDouble) * 100 / compared)
    }

    private func lastRunKey(_ o: SourcesOverviewView) -> String {
        if o.lastRunStrap { return "sources_last_strap_yes" }
        return o.lastRunSensorState == "none" ? "sources_last_strap_not_found" : "sources_last_strap_no"
    }

    private func date(_ epochSec: Int64) -> String {
        Date(timeIntervalSince1970: Double(epochSec)).formatted(date: .abbreviated, time: .omitted)
    }
}
