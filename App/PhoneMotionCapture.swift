import CoreMotion
import Darwin
import Foundation
import SwiftUI
import UIKit

/// Watch settings, battery section below the Sensor Record switch: the switch, where the phone is carried and what it
/// does (the Android Companion's texts). Rows only; the caller's section holds them.
struct PhoneMotionSettingsRows: View {
    @State private var on = PhoneMotionCapture.isEnabled
    @State private var placement = PhoneMotionCapture.placement

    var body: some View {
        Group {
            Toggle(L10n.get("phone_motion_switch"), isOn: Binding(
                get: { on },
                set: { on = $0; PhoneMotionCapture.setEnabled($0) }
            ))
            if on {
                Picker(L10n.get("phone_motion_placement"), selection: Binding(
                    get: { placement },
                    set: { placement = $0; PhoneMotionCapture.placement = $0 }
                )) {
                    ForEach(PhoneMotionCapture.placements, id: \.self) { key in
                        Text(L10n.get("phone_motion_placement_\(key)")).tag(key)
                    }
                }
            }
            Text(L10n.get("phone_motion_body")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// The phone's own motion record alongside a watch Sensor Record (iOS port of the Android Companion's
/// `recording/PhoneMotionCapture.kt`; Data Analysis `docs/phone-imu-combined.md`). Step 1 of the iOS port: capture only,
/// to find out whether it records reliably while the app is in the background (the watch's heads-up mostly arrives
/// then). Upload and the chart overlay follow once it does.
///
/// It starts when the watch's heads-up (`sensorRecordStart`, sent as its 3-2-1 countdown starts) arrives and stops when
/// the first chunk of the next record arrives (the watch sends after its 20 s), or after [maxCaptureS]. Accelerometer
/// and gyroscope at 100 Hz, raw (not fused), each sample on the phone's one clock (`PhoneClock.epochNs(uptimeNs:)`).
/// A background task keeps the app running for the capture; the header says what iOS granted.
///
/// File (format 1, the same as Android's, so `src/phone_watch_align.py` and the Android overlay read it): a first line
/// `# phoneRecord {json}`, then `tEpochNs,type,x,y,z` rows: `a` accelerometer in m/s² with Android's sign (iOS reports
/// -1 g face up, Android +9.81, so x -9.80665), `g` gyroscope in rad/s. Saved in Documents/recording-boost (Files: On My
/// iPhone > Nordic Sports). TestFlight builds only, behind a switch (watch settings, battery section), off by default. It leaves the phone
/// only when the athlete sends it with its Sensor Record in the feedback form (`FeedbackBoost.swift`, kind phone_motion).
// PRIVACY-SYNC: phone motion (accelerometer and gyroscope, no position) recorded on the athlete's switch (TestFlight builds), saved on this phone, sent only with its Sensor Record in a feedback message. Notice: feedback paragraph, "Phone motion record". Changing this? Re-check the Companion's design/privacy-notice-sync.md.
final class PhoneMotionCapture {
    static let shared = PhoneMotionCapture()

    static let placements = ["chest", "belt", "pocket", "backpack", "hand"]
    static let maxCaptureS = 90.0
    /// Next to the Sensor Record files (`Companion.boostFolder`, main-actor isolated, so named here again).
    private static let folder = "recording-boost"
    private static let keyOn = "phoneMotion.on"
    private static let keyPlacement = "phoneMotion.placement"
    private static let samplingS = 0.01
    private static let g = 9.80665

    /// TestFlight builds only (their receipt is the sandbox one); never in the App Store build.
    static var isAvailable: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }

    static var isEnabled: Bool { isAvailable && UserDefaults.standard.bool(forKey: keyOn) }

    static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: keyOn)
        if !on { shared.stop(burstId: 0, reason: "switched off") }
    }

    static var placement: String {
        get { UserDefaults.standard.string(forKey: keyPlacement).flatMap { placements.contains($0) ? $0 : nil } ?? "belt" }
        set { UserDefaults.standard.set(newValue, forKey: keyPlacement) }
    }

    /// The phone motion record of Sensor Record [burstId] (watch id) in Documents/recording-boost, nil when there is none.
    static func storedURL(burstId: Int64) -> URL? {
        guard burstId > 0, let dir = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent(Self.folder, isDirectory: true),
            let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        return names.first { $0.hasSuffix("-\(burstId)-phone.csv") }.map { dir.appendingPathComponent($0) }
    }

    /// Every phone motion record in Documents/recording-boost by its Sensor Record's id, from one folder listing.
    static func storedAll() -> [Int64: URL] {
        guard let dir = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent(Self.folder, isDirectory: true),
            let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [:] }
        var out: [Int64: URL] = [:]
        for name in names where name.hasSuffix("-phone.csv") {
            let id = burstId(fileName: name)
            if id > 0 { out[id] = dir.appendingPathComponent(name) }
        }
        return out
    }

    static func storedText(burstId: Int64) -> String? {
        storedURL(burstId: burstId).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// The watch's record id in a Sensor Record file name ("…_recording-boost-1794516072.csv"), 0 when there is none.
    static func burstId(fileName: String) -> Int64 {
        guard let range = fileName.range(of: #"recording-boost-(\d+)"#, options: .regularExpression) else { return 0 }
        return Int64(fileName[range].dropFirst("recording-boost-".count)) ?? 0
    }

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "PhoneMotionCapture"
        return q
    }()
    private let lock = NSLock()
    private var session: Session?

    private final class Session {
        let at: Int64
        let headsUpMs: Int64
        let startsAtMs: Int64
        let headsUpWallMs: Int64
        let placement: String
        let appState: String
        var backgroundTask: UIBackgroundTaskIdentifier = .invalid
        var backgroundTimeS: Double = -1
        var rows = ""
        var count = 0
        var lagMinNs = Int64.max
        var lagMaxNs = Int64.min
        var done = false

        init(at: Int64, headsUpMs: Int64, placement: String, appState: String) {
            self.at = at
            self.headsUpMs = headsUpMs
            self.startsAtMs = headsUpMs + 3_000
            self.headsUpWallMs = Int64(Date().timeIntervalSince1970 * 1000)
            self.placement = placement
            self.appState = appState
            rows.reserveCapacity(1 << 20)
        }
    }

    /// The watch announced a Sensor Record (heads-up `"at"`, epoch s), arriving at [arrivedAtMs] (PhoneClock).
    func onHeadsUp(at: Int64, arrivedAtMs: Int64) {
        guard Self.isEnabled else { return }
        DispatchQueue.main.async {
            let state = UIApplication.shared.applicationState
            let name = state == .active ? "active" : state == .background ? "background" : "inactive"
            self.lock.lock()
            let previous = self.session
            if let previous, previous.at == at {
                // The watch tries its heads-up again while its line is busy: one capture per Sensor Record.
                self.lock.unlock()
                return
            }
            self.lock.unlock()
            if previous != nil { self.stop(burstId: 0, reason: "next heads-up") }
            guard self.motion.isAccelerometerAvailable, self.motion.isGyroAvailable else {
                WatchLinkSpike.shared.add("phone motion: no accelerometer or gyroscope")
                return
            }
            let s = Session(at: at, headsUpMs: arrivedAtMs, placement: Self.placement, appState: name)
            // Keeps the app running in the background for the capture (iOS grants about 30 s); its end saves the file.
            s.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PhoneMotionCapture") { [weak self] in
                self?.stop(burstId: 0, reason: "background time over")
            }
            s.backgroundTimeS = UIApplication.shared.backgroundTimeRemaining
            self.lock.lock()
            self.session = s
            self.lock.unlock()
            self.motion.accelerometerUpdateInterval = Self.samplingS
            self.motion.gyroUpdateInterval = Self.samplingS
            self.motion.startAccelerometerUpdates(to: self.queue) { [weak self] data, _ in
                guard let data else { return }
                let a = data.acceleration
                self?.add(s, "a", data.timestamp, -a.x * Self.g, -a.y * Self.g, -a.z * Self.g)
            }
            self.motion.startGyroUpdates(to: self.queue) { [weak self] data, _ in
                guard let data else { return }
                let r = data.rotationRate
                self?.add(s, "g", data.timestamp, r.x, r.y, r.z)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.maxCaptureS) { [weak self] in
                self?.stop(session: s, burstId: 0, reason: "time cap")
            }
            let granted = s.backgroundTimeS < 100_000 ? "\(Int(s.backgroundTimeS)) s" : "unlimited"
            WatchLinkSpike.shared.add("phone motion: capture started for heads-up \(at) in \(name), background time \(granted), placement \(s.placement)")
        }
    }

    /// The first chunk of record [burstId] arrived: the watch's 20 s are over, so the phone stops.
    func onRecordChunk(burstId: Int64) {
        lock.lock()
        let s = session
        lock.unlock()
        // Only a record that ended after this capture began belongs to it (burstId = its end, watch epoch s); both
        // sides are wall clocks, as on Android.
        guard let s, burstId * 1000 >= s.headsUpWallMs else { return }
        stop(session: s, burstId: burstId, reason: "first chunk")
    }

    private func stop(burstId: Int64, reason: String) {
        lock.lock()
        let s = session
        lock.unlock()
        if let s { stop(session: s, burstId: burstId, reason: reason) }
    }

    private func stop(session s: Session, burstId: Int64, reason: String) {
        lock.lock()
        if session === s { session = nil }
        lock.unlock()
        // After the samples already queued, on the capture queue; then the file, then the background task ends.
        queue.addOperation { [weak self] in
            guard let self, !s.done else { return }
            s.done = true
            DispatchQueue.main.sync {
                // A capture that started meanwhile (the next heads-up) has its own handlers on the same manager: its
                // updates keep running; only with no capture left are they stopped.
                self.lock.lock()
                let newer = self.session
                self.lock.unlock()
                if newer == nil {
                    self.motion.stopAccelerometerUpdates()
                    self.motion.stopGyroUpdates()
                }
            }
            self.write(s, burstId: burstId, reason: reason)
            DispatchQueue.main.async {
                if s.backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(s.backgroundTask)
                    s.backgroundTask = .invalid
                }
            }
        }
    }

    /// One sample (on the capture queue): its Core Motion time on the phone's one clock.
    private func add(_ s: Session, _ type: String, _ timestamp: TimeInterval, _ x: Double, _ y: Double, _ z: Double) {
        guard !s.done else { return }
        let uptimeNs = Int64(timestamp * 1e9)
        let lag = Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) - uptimeNs
        if lag < s.lagMinNs { s.lagMinNs = lag }
        if lag > s.lagMaxNs { s.lagMaxNs = lag }
        // Fixed notation: Swift writes small values as "1e-05", which the server's format check (Android's "1.0E-5" only)
        // refuses, and with it the whole feedback message.
        s.rows += "\(PhoneClock.epochNs(uptimeNs: uptimeNs)),\(type),\(String(format: "%.6f", x)),\(String(format: "%.6f", y)),\(String(format: "%.6f", z))\n"
        s.count += 1
    }

    private func write(_ s: Session, burstId: Int64, reason: String) {
        let ended = PhoneClock.nowMs()
        let id = burstId > 0 ? burstId : s.at
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let head: [String: Any] = [
            "format": 1,
            "platform": "ios",
            "burstAt": s.at,
            "burstId": burstId,
            "headsUpEpochMs": s.headsUpMs,
            "startsAtEpochMs": s.startsAtMs,
            "endedEpochMs": ended,
            "stoppedBy": reason,
            "placement": s.placement,
            "device": "Apple \(model)",
            "ios": UIDevice.current.systemVersion,
            "samplingUs": Int(Self.samplingS * 1_000_000),
            "appState": s.appState,
            // In the foreground iOS reports the largest double (no limit): -1 here.
            "backgroundTimeS": s.backgroundTimeS >= 0 && s.backgroundTimeS < 100_000 ? Int(s.backgroundTimeS) : -1,
            "accelSign": "android",
            "phoneClock": [
                "anchorEpochMs": PhoneClock.anchorEpochMs,
                "anchorElapsedNs": PhoneClock.anchorMonotonicNs,
                "wallMinusClockMs": Int64(Date().timeIntervalSince1970 * 1000) - PhoneClock.nowMs(),
            ],
            "sensorLagNs": s.count > 0 ? ["min": s.lagMinNs, "max": s.lagMaxNs] : ["min": NSNull(), "max": NSNull()],
            "rows": s.count,
            "gpsFixes": 0,
            "sensors": [
                ["type": 1, "name": "CoreMotion accelerometer"],
                ["type": 4, "name": "CoreMotion gyroscope"],
            ],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: head), let headText = String(data: json, encoding: .utf8) else { return }
        let text = "# phoneRecord \(headText)\ntEpochNs,type,x,y,z\n\(s.rows)"
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd_HHmm"
        let name = "\(stamp.string(from: Date(timeIntervalSince1970: TimeInterval(id))))_recording-boost-\(id)-phone.csv"
        do {
            let folder = try FileManager.default
                .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(Self.folder, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            let seconds = (ended - s.headsUpMs) / 1000
            WatchLinkSpike.shared.add("phone motion: saved \(name): \(s.count) rows, \(seconds) s, stopped by \(reason), started in \(s.appState)")
        } catch {
            WatchLinkSpike.shared.add("phone motion: could not save \(name): \(error.localizedDescription)")
        }
    }
}
