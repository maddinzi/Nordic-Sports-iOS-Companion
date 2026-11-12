import Darwin
import Foundation
import NordicSportsShared

/// The one clock this phone uses for everything matched against the watch (as Android's `PhoneClock`; Data Analysis
/// `docs/phone-imu-combined.md`, "One clock per device"): the monotonic `CLOCK_MONOTONIC_RAW` (keeps counting while
/// the phone sleeps), shown as epoch time through one anchor read once per process. The wall clock (`Date()`) can be
/// stepped by network time at any moment; read once here and never again, a step cannot split the message stamps.
/// Used for watch message arrivals, the phone time sent to the watch (`phoneS`, `phoneMs`), the Sensor Record
/// answer and clock pings. The anchor goes into each Sensor Record (meta `clock.phone`, shared `WatchClockLog`).
/// A future Core Motion record must convert its timestamps (`systemUptime`, which stops in sleep) to this clock.
enum PhoneClock {
    private static let anchor: (epochMs: Int64, monotonicNs: Int64) = {
        let ns = Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW))
        let epochMs = Int64(Date().timeIntervalSince1970 * 1000)
        WatchClockLog.shared.setPhoneClock(epochMs: epochMs, monotonicNs: ns)
        return (epochMs, ns)
    }()

    /// Now, as epoch ms on this clock.
    static func nowMs() -> Int64 {
        let a = anchor
        return a.epochMs + (Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) - a.monotonicNs) / 1_000_000
    }

    /// [message] with this phone's clock as it goes to the watch, Int32 values like every number the watch matches
    /// (shared `WatchActivityPayload.withPhoneClock`). A watch with `ClockSync.mc` stamps the arrival and echoes both
    /// in its next message (`clk`); older watches ignore the keys. A message that already carries them stays as it is.
    static func stamped(_ message: [String: Any]) -> [String: Any] {
        guard message["phoneS"] == nil else { return message }
        let now = nowMs()
        var out = message
        out["phoneS"] = NSNumber(value: Int32(truncatingIfNeeded: now / 1000))
        out["phoneMs"] = NSNumber(value: Int32(now % 1000))
        return out
    }
}
