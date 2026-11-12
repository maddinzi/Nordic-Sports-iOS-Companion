import Darwin
import Foundation
import NordicSportsShared

/// The one clock this phone uses for everything matched against the watch (as Android's `PhoneClock`; Data Analysis
/// `docs/phone-imu-combined.md`, "One clock per device"): the monotonic `CLOCK_MONOTONIC_RAW` (keeps counting while
/// the phone sleeps), shown as epoch time through one anchor read once per process. The wall clock (`Date()`) can be
/// stepped by network time at any moment; read once here and never again, a step cannot split the message stamps.
/// Used for watch message arrivals, the phone time sent to the watch (`phoneS`, `phoneMs`), the Sensor Record
/// answer and clock pings. The anchor goes into each Sensor Record (meta `clock.phone`, shared `WatchClockLog`).
/// The phone motion record (`PhoneMotionCapture`) converts Core Motion's timestamps (`CLOCK_UPTIME_RAW`, which stops
/// in sleep) to this clock with [epochNs(uptimeNs:)].
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

    /// The anchor (epoch ms, CLOCK_MONOTONIC_RAW ns) for the phone motion record's header (`phoneClock`).
    static var anchorEpochMs: Int64 { anchor.epochMs }
    static var anchorMonotonicNs: Int64 { anchor.monotonicNs }

    /// A Core Motion timestamp ([uptimeNs]: CLOCK_UPTIME_RAW, `CMLogItem.timestamp` × 1e9) as epoch ns on this clock.
    /// Uptime stops while the phone sleeps and the monotonic clock does not, so their difference is read now: within a
    /// capture of seconds the phone is awake and it stays the same.
    static func epochNs(uptimeNs: Int64) -> Int64 {
        let a = anchor
        let monotonicMinusUptime = Int64(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) - Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        return a.epochMs * 1_000_000 + (uptimeNs + monotonicMinusUptime - a.monotonicNs)
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
