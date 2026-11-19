import Combine
import CoreLocation
import Darwin
import Foundation
import NordicSportsShared
import SwiftUI
import UIKit

/// The iPhone's sensors for a paired recording (the Companion's `design/phone-in-recording.md` and
/// `design/coverage-declaration.md`; Android `recording/PairedRecordingCapture`): while the watch records, the phone
/// measures along and keeps its own route. Everything that decides and stores is shared Kotlin
/// (`PairedRecording`, reached as `core.pairedRecording`); this class only starts and stops Core Motion and Core
/// Location when the shared code asks, and hands the samples over.
///
/// What iOS allows, and what follows from it:
/// - The app asks for location "while using the app" only. With that permission iOS delivers a location to an app
///   in the background only if the updates were started while the app was on screen. A watch `activityStart` that
///   wakes the app in the pocket (Bluetooth) therefore gets no route.
/// - Running location updates are also the only thing that keeps the app alive in the background for a whole
///   activity. Without them iOS suspends the app seconds after the screen goes off, and the motion capture with it
///   (it continues when a watch message wakes the app, with gaps the records mark).
/// - So a paired recording on the iPhone is complete when the app is open at the moment the watch starts and "Route
///   from the phone" is on with location allowed. Opened later during the activity, it records from there
///   (`appBecameActive`). The switch texts say so (`paired_recording_ios_note`, `paired_track_body_ios`).
/// - "Always" location would lift the first limit; it is not requested (the athlete's decision, App Review).
// PRIVACY-SYNC: paired recording on iOS: motion (derived values per second only) and, with "Route from the phone", the position once a second, both only while a watch recording runs, stored on this phone with the activity, never sent. Notice: "The phone in the watch recording (from version 0.9.128)". Changing this? Re-check the Companion's design/privacy-notice-sync.md.
final class PairedRecordingSensors: NSObject, PairedSensors, CLLocationManagerDelegate {
    static let shared = PairedRecordingSensors()

    private static let hubId = "pairedRecording"

    private let hub = MotionHub.shared
    private let manager = CLLocationManager()
    private let lock = NSLock()
    /// The location permission as last reported (read on any thread).
    private var authorized = false
    /// A capture runs and wants the route.
    private var wantsLocation = false
    private var locationOn = false
    private var fixes = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// Called once from `Companion` on the main thread (Core Location wants its manager made there).
    private override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorized = Self.allows(manager.authorizationStatus)
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    private static func allows(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Set by [attach]; not read through `Companion.shared`, whose own start calls in here.
    private var recording: PairedRecording?

    /// App start (main thread): the shared code gets its sensors. A recording the watch announced earlier and that
    /// still runs gets its capture again right here.
    func attach(to core: CompanionCore) {
        recording = core.pairedRecording
        // The coverage declaration's changes go to the running watch apps (the shared class calls under its lock:
        // only hand on). Set before attach, which works the value out the first time.
        core.pairedRecording.onCoverageChanged = { bits in
            let value = bits.int32Value
            Task { @MainActor in WatchLinkSpike.shared.sendCoverage(value) }
        }
        // Background calibration requests (shared CalibrationRequests): to the watch app of that recording, the
        // log only, nothing shown. Also called under the shared lock: only hand on.
        core.pairedRecording.onCalibrate = { deviceId, reason in
            let id = deviceId.int64Value
            Task { @MainActor in WatchLinkSpike.shared.sendCalibrate(id, reason: reason) }
        }
        core.pairedRecording.attach(sensors: self)
    }

    var locationAuthorized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return authorized
    }

    /// Whether iOS has not been asked for the location yet (then the switch asks).
    var locationUndecided: Bool { manager.authorizationStatus == .notDetermined }

    func requestLocation() { manager.requestWhenInUseAuthorization() }

    // MARK: PairedSensors (called by the shared code, on any thread)

    func start(accelerometer: Bool, gyroscope: Bool, location: Bool) -> Bool {
        if accelerometer && !hub.accelerometerAvailable { return false }
        if gyroscope && !hub.gyroscopeAvailable { return false }
        guard let recording else { return false }
        if accelerometer || gyroscope {
            // Android's sign (iOS reports -1 g face up, Android +1 g), in g; the sample's own time on the phone's one clock.
            let accelHandler: MotionHub.Handler = { t, x, y, z in
                recording.addAccel(tEpochMs: Self.epochMs(t), xG: -x, yG: -y, zG: -z)
            }
            let gyroHandler: MotionHub.Handler = { t, x, y, z in
                recording.addGyro(tEpochMs: Self.epochMs(t), xRad: x, yRad: y, zRad: z)
            }
            hub.add(Self.hubId, accel: accelerometer ? accelHandler : nil, gyro: gyroscope ? gyroHandler : nil)
        } else {
            // The route alone: no handlers of an earlier start keep feeding samples.
            hub.remove(Self.hubId)
        }
        lock.lock()
        wantsLocation = location
        fixes = 0
        lock.unlock()
        DispatchQueue.main.async {
            let state = UIApplication.shared.applicationState
            let name = state == .active ? "open" : state == .background ? "in the background" : "inactive"
            // Bridges the seconds until the location updates keep the app running (or, without them, gives the
            // capture what iOS grants: about 30 s).
            self.endBackgroundTask()
            self.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PairedRecording") { [weak self] in
                self?.endBackgroundTask()
            }
            if location { self.startLocation() }
            var note = ""
            if state != .active {
                note = location
                    ? ": iOS gives no location to a capture that starts in the background, open the app to record from there"
                    : ": without the route iOS suspends the app soon"
            } else if !location {
                note = ": without the route the capture stops soon after the screen goes off"
            }
            WatchLinkSpike.shared.add("paired recording: sensors started with the app \(name) (motion \(accelerometer), gyroscope \(gyroscope), route \(location))\(note)")
        }
        return true
    }

    func stop() {
        hub.remove(Self.hubId)
        lock.lock()
        wantsLocation = false
        let count = fixes
        lock.unlock()
        DispatchQueue.main.async {
            if self.locationOn {
                self.manager.stopUpdatingLocation()
                self.manager.allowsBackgroundLocationUpdates = false
                self.manager.showsBackgroundLocationIndicator = false
                self.locationOn = false
            }
            self.endBackgroundTask()
            WatchLinkSpike.shared.add("paired recording: sensors stopped, \(count) fixes")
        }
    }

    func locationReady() -> Bool { locationAuthorized }

    func placement() -> String { PhoneMotionCapture.placement }

    func deviceName() -> String {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return "Apple \(model)"
    }

    func batteryPercent() -> Int32 {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? -1 : Int32((level * 100).rounded())
    }

    // MARK: Location (main thread)

    private func startLocation() {
        guard locationAuthorized else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        locationOn = true
    }

    /// The app came to the screen while a capture wants the route: updates started now are delivered, also after
    /// the screen goes off again. This is how a capture that began in the pocket gets its route from here on.
    @objc private func appBecameActive() {
        // The permission or the system's location may have changed while the app was away.
        recording?.refreshCoverage()
        lock.lock()
        let wanted = wantsLocation
        lock.unlock()
        guard wanted else { return }
        manager.stopUpdatingLocation()
        startLocation()
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let allowed = Self.allows(manager.authorizationStatus)
        lock.lock()
        authorized = allowed
        let wanted = wantsLocation
        lock.unlock()
        if allowed, wanted, !locationOn { startLocation() }
        recording?.refreshCoverage()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let recording else { return }
        for loc in locations where loc.horizontalAccuracy >= 0 {
            lock.lock()
            fixes += 1
            lock.unlock()
            recording.addFix(
                lat: loc.coordinate.latitude, lon: loc.coordinate.longitude,
                atEpochSec: Int64(loc.timestamp.timeIntervalSince1970),
                speedMps: loc.speed, altitudeM: loc.altitude, hasAltitude: loc.verticalAccuracy >= 0,
                accuracyM: loc.horizontalAccuracy
            )
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    /// A Core Motion timestamp (seconds of `CLOCK_UPTIME_RAW`) as epoch ms on the phone's one clock.
    private static func epochMs(_ timestamp: TimeInterval) -> Double {
        Double(PhoneClock.epochNs(uptimeNs: Int64(timestamp * 1e9))) / 1e6
    }
}

extension Notification.Name {
    /// "Paired recording" was switched: every copy of its rows (one per watch) and "Extended recording" read it again.
    static let pairedRecordingChanged = Notification.Name("pairedRecordingChanged")
}

/// Watch page, Recording card: "Paired recording" with "Route from the phone" (Android `PairedRecordingSwitch`,
/// `PairedTrackSwitch`). Phone settings, the same for every watch. Rows only; the caller's section holds them.
/// "Extended recording" stands in the Sensor Records card ([ExtendedRecordingSettingsRow]).
struct PairedRecordingSettingsRows: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.scenePhase) private var scenePhase
    @State private var paired = false
    @State private var track = false
    @State private var granted = false

    private var recording: PairedRecording { companion.core.pairedRecording }

    var body: some View {
        Group {
            Detail(SettingsItem.watchPairedRecording) {
                // A short line on what it does; the full text and the iPhone note behind the info button (2026-11-18).
                Toggle(isOn: Binding(
                    get: { paired },
                    set: {
                        paired = $0
                        recording.setEnabled(on: $0)
                        NotificationCenter.default.post(name: .pairedRecordingChanged, object: nil)
                    }
                )) {
                    SettingLabel(title: L10n.get("paired_recording_switch"), description: L10n.get("settings_desc_paired_recording"),
                                 info: L10n.get("paired_recording_body") + "\n\n" + L10n.get("paired_recording_ios_note"))
                }
                .settingsAnchor("PairedRecording")
            }
            Detail(SettingsItem.watchPairedTrack) {
                // Shown as off until iOS allows the location: switching it on asks for it.
                Toggle(isOn: Binding(
                    get: { track && granted },
                    set: { on in
                        track = on
                        recording.setTrackEnabled(on: on)
                        if on && !granted { askForLocation() }
                    }
                )) {
                    SettingLabel(title: L10n.get("paired_track_switch"), description: L10n.get("settings_desc_paired_track"),
                                 info: L10n.get("paired_track_body_ios"))
                }
                .settingsAnchor("PairedTrack")
                .disabled(!paired)
            }
        }
        .onAppear(perform: read)
        // Back from the permission sheet or from the Settings app.
        .onChange(of: scenePhase) { _, phase in if phase == .active { read() } }
        .onReceive(NotificationCenter.default.publisher(for: .pairedRecordingChanged)) { _ in read() }
    }

    private func read() {
        paired = recording.isEnabled()
        track = recording.isTrackEnabled()
        granted = PairedRecordingSensors.shared.locationAuthorized
    }

    /// Never asked: the system sheet. Refused earlier: only the Settings app can change it.
    private func askForLocation() {
        if PairedRecordingSensors.shared.locationUndecided {
            PairedRecordingSensors.shared.requestLocation()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Watch page, Sensor Records card: "Extended recording" (Android `ExtendedRecordingSwitch`, 2026-11-18 review): for
/// testing and learning, the phone also measures what the watch does. A phone setting; off while Paired recording is.
struct ExtendedRecordingSettingsRow: View {
    @EnvironmentObject var companion: Companion
    @State private var paired = false
    @State private var extended = false

    private var recording: PairedRecording { companion.core.pairedRecording }

    var body: some View {
        Detail(SettingsItem.watchExtendedRecording) {
            Toggle(isOn: Binding(
                get: { extended },
                set: { extended = $0; recording.setExtended(on: $0) }
            )) {
                SettingLabel(title: L10n.get("extended_recording_switch"), description: L10n.get("settings_desc_extended_recording"),
                             info: L10n.get("extended_recording_body"))
            }
            .settingsAnchor("ExtendedRecording")
            .disabled(!paired)
        }
        .onAppear {
            paired = recording.isEnabled()
            extended = recording.isExtended()
        }
        // Follows the Paired recording switch in the Recording card live (review 2026-11-18).
        .onReceive(NotificationCenter.default.publisher(for: .pairedRecordingChanged)) { _ in paired = recording.isEnabled() }
    }
}
