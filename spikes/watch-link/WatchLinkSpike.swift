import ConnectIQ
import Foundation
import NordicSportsShared
import UIKit
import UserNotifications

/// Spike 1 (roadmap step 1, throw-away): does the Connect IQ iOS SDK deliver what the
/// Companion needs? Device selection through Garmin Connect Mobile, activities from both
/// watch app ids, a receipt back, a settings request, and what arrives while the app is in
/// the background or was closed. Everything is logged with timestamps and kept across app
/// starts, so the log itself is the finding.
final class WatchLinkSpike: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate, WatchMessenger {
    static let shared = WatchLinkSpike()

    /// Registered in project.yml (CFBundleURLTypes); Garmin Connect Mobile calls back with it.
    static let urlScheme = "nordicsports-ciq"

    /// Public listing and the Preview (Garmin Beta App) id, as in the Android `WATCH_APP_IDS`.
    static let watchApps: [(name: String, id: String)] = [
        ("public", "b6fcbabd-6cd5-4013-8316-b702464253ce"),
        ("preview", "fc04cefc-1273-4499-8430-16c50a611823"),
    ]

    @Published private(set) var devices: [IQDevice] = []
    @Published private(set) var statuses: [UUID: String] = [:]
    @Published private(set) var log: [String] = []

    /// Read from the shared code's threads (`sendToWatch`), reassigned on the main thread.
    private var appsStorage: [IQApp] = []
    private let appsLock = NSLock()
    private var apps: [IQApp] {
        get {
            appsLock.lock()
            defer { appsLock.unlock() }
            return appsStorage
        }
        set {
            appsLock.lock()
            defer { appsLock.unlock() }
            appsStorage = newValue
        }
    }
    private let defaults = UserDefaults.standard
    private let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    private override init() {
        super.init()
        log = defaults.stringArray(forKey: "spike.log") ?? []
    }

    // MARK: - Start-up

    /// Called once at app launch. The restoration identifier lets iOS relaunch the app in the
    /// background for Bluetooth activity (part of what this spike measures).
    func start() {
        let state = UIApplication.shared.applicationState
        add("launch (state \(Self.name(of: state)))")
        ConnectIQ.sharedInstance().initialize(
            withUrlScheme: Self.urlScheme,
            uiOverrideDelegate: nil,
            stateRestorationIdentifier: Self.urlScheme
        )
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.add("notifications \(granted ? "allowed" : "not allowed")")
        }
        devices = loadDevices()
        registerAll()
    }

    func chooseWatch() {
        add("opening Garmin Connect for device selection")
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Garmin Connect Mobile returns the athlete's selection through our URL scheme.
    func handle(url: URL) {
        guard url.scheme == Self.urlScheme else { return }
        // No device in the answer (the athlete backed out, or an unrelated call): keep the saved watches.
        guard let parsed = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice], !parsed.isEmpty else {
            add("device selection: no device in the response, the saved watches are kept")
            return
        }
        add("device selection: \(parsed.count) device(s): \(parsed.map { $0.friendlyName ?? "?" }.joined(separator: ", "))")
        ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
        ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
        devices = parsed
        saveDevices(parsed)
        registerAll()
    }

    private func registerAll() {
        var registered: [IQApp] = []
        for device in devices {
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
            let status = ConnectIQ.sharedInstance().getDeviceStatus(device)
            statuses[device.uuid] = Self.name(of: status)
            for watchApp in Self.watchApps {
                // The SDK headers carry no nullability, so its factories return `IQApp!`.
                guard let uuid = UUID(uuidString: watchApp.id) else { continue }
                let made: IQApp? = IQApp(uuid: uuid, store: uuid, device: device)
                guard let app = made else { continue }
                registered.append(app)
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
            }
        }
        apps = registered
        if !devices.isEmpty {
            add("listening on \(devices.count) device(s) x \(Self.watchApps.count) app ids")
        }
    }

    // MARK: - Actions

    /// Which of the two watch apps is installed, and in which version.
    func checkApps() {
        for app in apps {
            ConnectIQ.sharedInstance().getAppStatus(app) { status in
                let text = status.map { $0.isInstalled ? "installed v\($0.version)" : "not installed" } ?? "no answer"
                self.add("app status \(self.label(app)): \(text)")
            }
        }
    }

    /// `{"type": "settings"}` asks the watch app for its settings snapshot.
    func requestSettings() {
        for app in apps {
            send(["type": "settings"], to: app, what: "settings request")
        }
    }

    func clearLog() {
        log = []
        defaults.removeObject(forKey: "spike.log")
    }

    // MARK: - Delegates

    // The exact Objective-C selectors, so the SDK finds them whatever Swift calls them.
    @objc(deviceStatusChanged:status:)
    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        let name = Self.name(of: status)
        let deviceUuid = device.uuid
        let deviceId = Self.deviceId(device)
        let watchName = device.friendlyName
        add("device \(watchName ?? "?"): \(name)")
        // Asynchronous on the main queue (no blocking wait on the SDK's thread).
        Task { @MainActor in
            let changed = self.statuses[deviceUuid] != name
            self.statuses[deviceUuid] = name
            // As Android: a watch that connects again keeps its name, and is asked to resend what
            // it still has queued (an activity sent while the link was down), at most once a minute.
            guard status == .connected, changed else { return }
            let appId = Companion.shared.core.watchConnected(deviceId: deviceId, watchName: watchName)
            guard !appId.isEmpty,
                  let app = self.apps.first(where: { Self.deviceId($0.device) == deviceId && $0.uuid.uuidString.lowercased() == appId.lowercased() })
            else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self.send(["type": "resend"], to: app, what: "resend request") { result in
                let status = Self.name(of: result)
                Task { @MainActor in Companion.shared.core.resendRequested(deviceId: deviceId, status: status) }
            }
        }
    }

    @objc(receivedMessage:fromApp:)
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        let dict = message as? [String: Any]
        let type = dict?["type"] as? String ?? (dict?["startTime"] != nil ? "activity" : "?")
        // Type and size only: the payload (coordinates, heart rate) stays out of the log.
        let source = label(app)
        let size = Self.describe(message)
        Task { @MainActor in
            let state = UIApplication.shared.applicationState
            self.add("received \(type) from \(source) in \(Self.name(of: state)): \(size)")
            if state != .active {
                self.add("\(type) arrived in the \(Self.name(of: state))")
            }
        }

        // Activities (and the chunks of a Recording Boost burst) go to the shared core, which stores them; only then does a payload with
        // `"rx": 1` get `{"type": "receipt", "startTime": <Int>}` back, as on Android, so
        // the watch keeps anything that could not be stored and sends it again. The start
        // time goes out as a 32-bit Int like Android's (`receiptMessage`): the watch drops a
        // receipt whose startTime is not a Monkey C Number/Long, and an Int64 NSNumber from
        // iOS was never accepted (log3: every receipt "success", the watch resent them all).
        if let dict, type == "activity" || type == "recordingBoostBurst" {
            let variant = variantName(app)
            Task { @MainActor in
                let startTime = await Companion.shared.receive(message: dict, variant: variant)
                if startTime > 0 {
                    let receiptTime = NSNumber(value: Int32(truncatingIfNeeded: startTime))
                    self.send(["type": "receipt", "startTime": receiptTime], to: app, what: "receipt \(startTime)") { result in
                        let sent = result.rawValue == 0
                        let status = Self.name(of: result)
                        Task { @MainActor in
                            Companion.shared.core.watchReceiptResult(startTime: startTime, variant: variant, sent: sent, status: status)
                        }
                    }
                }
            }
        }
        // Everything else goes to the shared core too: the settings snapshot (sent at every
        // watch app start; WatchSettingsSync stores it and resends changes still waiting), a
        // recording that started or was discarded, and a crash report.
        if let dict, type != "activity", type != "recordingBoostBurst", JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            let deviceId = Self.deviceId(app.device)
            let watchName = app.device.friendlyName ?? "?"
            let appId = app.uuid.uuidString.lowercased()
            Task { @MainActor in
                if !Companion.shared.core.watchMessage(deviceId: deviceId, watchName: watchName, appId: appId, json: json) {
                    self.add("message of type \(type) not handled")
                }
                Companion.shared.refreshWatchSettings()
                Companion.shared.refreshWatchCards()
            }
        }
    }

    // MARK: - Helpers

    private func send(_ message: [String: Any], to app: IQApp, what: String, done: ((IQSendMessageResult) -> Void)? = nil) {
        ConnectIQ.sharedInstance().sendMessage(message, to: app, progress: { _, _ in }) { result in
            self.add("\(what) to \(self.label(app)): \(Self.name(of: result))")
            done?(result)
        }
    }

    // MARK: - WatchMessenger (settings from the shared core)

    /// A settings message from the shared WatchSettingsSync, as JSON. Numbers go out as
    /// 32-bit Ints like Android's (the watch ignored Int64 NSNumbers in the receipt), true
    /// and false as booleans. The result goes back to the core under [requestId].
    func sendToWatch(requestId: Int32, deviceId: Int64, appId: String, json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let message = Self.watchValue(object) as? [String: Any],
              let app = apps.first(where: { Self.deviceId($0.device) == deviceId && $0.uuid.uuidString.lowercased() == appId.lowercased() })
        else {
            add("settings for an unknown watch or app (\(appId)) not sent")
            return false
        }
        send(message, to: app, what: "settings") { result in
            let sent = result.rawValue == 0
            let status = Self.name(of: result)
            Task { @MainActor in
                Companion.shared.core.watchMessageResult(requestId: requestId, sent: sent, status: status)
                Companion.shared.refreshWatchSettings()
            }
        }
        return true
    }

    /// The Companion's id for a watch: the first 8 bytes of its Connect IQ UUID (stable).
    static func deviceId(_ device: IQDevice) -> Int64 {
        var value: UInt64 = 0
        withUnsafeBytes(of: device.uuid.uuid) { raw in
            for byte in raw.prefix(8) { value = value << 8 | UInt64(byte) }
        }
        return Int64(bitPattern: value)
    }

    private static func watchValue(_ value: Any) -> Any {
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return NSNumber(value: number.boolValue) }
            if CFNumberIsFloatType(number) { return NSNumber(value: number.floatValue) }
            return NSNumber(value: Int32(truncatingIfNeeded: number.int64Value))
        }
        if let list = value as? [Any] { return list.map(watchValue) }
        if let dict = value as? [String: Any] { return dict.mapValues(watchValue) }
        return value
    }

    private func label(_ app: IQApp) -> String {
        "\(variantName(app))@\(app.device.friendlyName ?? "?")"
    }

    /// "public" or "preview": which of the two watch app ids sent it.
    private func variantName(_ app: IQApp) -> String {
        Self.watchApps.first { $0.id.lowercased() == app.uuid.uuidString.lowercased() }?.name ?? "?"
    }

    /// Adds a timestamped line to the log the screen shows (also used by the other spikes).
    func add(_ line: String) {
        let entry = "\(timeFormat.string(from: Date())) \(line)"
        NSLog("[spike] %@", entry)
        let update = {
            self.log.insert(entry, at: 0)
            if self.log.count > 500 { self.log.removeLast(self.log.count - 500) }
            self.defaults.set(self.log, forKey: "spike.log")
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    private func saveDevices(_ devices: [IQDevice]) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
        defaults.set(data, forKey: "spike.devices")
    }

    private func loadDevices() -> [IQDevice] {
        guard let data = defaults.data(forKey: "spike.devices") else { return [] }
        return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: data)) ?? []
    }

    /// The size of a watch message, never its content.
    private static func describe(_ message: Any?) -> String {
        guard let message else { return "no payload" }
        if JSONSerialization.isValidJSONObject(message), let data = try? JSONSerialization.data(withJSONObject: message) {
            return "\(data.count) bytes"
        }
        return "payload of an unreadable kind"
    }

    // The SDK's enums by raw value, so the log does not depend on how Swift imports their names.
    private static func name(of status: IQDeviceStatus) -> String {
        ["invalid device", "Bluetooth not ready", "not found", "not connected", "connected"][safe: status.rawValue] ?? "status \(status.rawValue)"
    }

    private static func name(of result: IQSendMessageResult) -> String {
        ["success", "unknown failure", "internal error", "device not available", "app not found", "device busy",
         "unsupported type", "insufficient memory", "timeout", "max retries", "prompt not displayed",
         "app already running"][safe: result.rawValue] ?? "result \(result.rawValue)"
    }

    private static func name(of state: UIApplication.State) -> String {
        switch state {
        case .active: return "foreground"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
