import ConnectIQ
import Foundation
import UIKit
import UserNotifications

/// Spike 1 (roadmap step 1, throw-away): does the Connect IQ iOS SDK deliver what the
/// Companion needs? Device selection through Garmin Connect Mobile, activities from both
/// watch app ids, a receipt back, a settings request, and what arrives while the app is in
/// the background or was closed. Everything is logged with timestamps and kept across app
/// starts, so the log itself is the finding.
final class WatchLinkSpike: NSObject, ObservableObject, IQDeviceEventDelegate, IQAppMessageDelegate {
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

    private var apps: [IQApp] = []
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
        let parsed = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice] ?? []
        add("device selection: \(parsed.count) device(s): \(parsed.map { $0.friendlyName ?? "?" }.joined(separator: ", "))")
        ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
        ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
        devices = parsed
        saveDevices(parsed)
        registerAll()
    }

    private func registerAll() {
        apps = []
        for device in devices {
            ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
            let status = ConnectIQ.sharedInstance().getDeviceStatus(device)
            statuses[device.uuid] = Self.name(of: status)
            for watchApp in Self.watchApps {
                // The SDK headers carry no nullability, so its factories return `IQApp!`.
                guard let uuid = UUID(uuidString: watchApp.id) else { continue }
                let made: IQApp? = IQApp(uuid: uuid, store: uuid, device: device)
                guard let app = made else { continue }
                apps.append(app)
                ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
            }
        }
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
        DispatchQueue.main.async { self.statuses[device.uuid] = name }
        add("device \(device.friendlyName ?? "?"): \(name)")
    }

    @objc(receivedMessage:fromApp:)
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        let state = Thread.isMainThread
            ? UIApplication.shared.applicationState
            : DispatchQueue.main.sync { UIApplication.shared.applicationState }
        let dict = message as? [String: Any]
        let type = dict?["type"] as? String ?? (dict?["startTime"] != nil ? "activity" : "?")
        add("received \(type) from \(label(app)) in \(Self.name(of: state)): \(Self.describe(message))")

        // An activity that asks for a receipt (`"rx": 1`) gets `{"type": "receipt",
        // "startTime": <Int>}` back, exactly as the Android Companion answers it.
        if let dict, (dict["rx"] as? NSNumber)?.intValue == 1, type != "recordingBoostBurst",
           let startTime = (dict["startTime"] as? NSNumber)?.int64Value {
            send(["type": "receipt", "startTime": NSNumber(value: startTime)], to: app, what: "receipt \(startTime)")
        }
        if state != .active {
            notify("Watch: \(type) arrived in the \(Self.name(of: state))")
        }
    }

    // MARK: - Helpers

    private func send(_ message: [String: Any], to app: IQApp, what: String) {
        ConnectIQ.sharedInstance().sendMessage(message, to: app, progress: { _, _ in }) { result in
            self.add("\(what) to \(self.label(app)): \(Self.name(of: result))")
        }
    }

    private func label(_ app: IQApp) -> String {
        let name = Self.watchApps.first { $0.id.lowercased() == app.uuid.uuidString.lowercased() }?.name ?? "?"
        return "\(name)@\(app.device.friendlyName ?? "?")"
    }

    private func add(_ line: String) {
        let entry = "\(timeFormat.string(from: Date())) \(line)"
        NSLog("[spike] %@", entry)
        let update = {
            self.log.insert(entry, at: 0)
            if self.log.count > 500 { self.log.removeLast(self.log.count - 500) }
            self.defaults.set(self.log, forKey: "spike.log")
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    private func notify(_ text: String) {
        let content = UNMutableNotificationContent()
        content.title = "Nordic Sports spike"
        content.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func saveDevices(_ devices: [IQDevice]) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: devices, requiringSecureCoding: true)
        defaults.set(data, forKey: "spike.devices")
    }

    private func loadDevices() -> [IQDevice] {
        guard let data = defaults.data(forKey: "spike.devices") else { return [] }
        return (try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: IQDevice.self, from: data)) ?? []
    }

    private static func describe(_ message: Any?) -> String {
        guard let message else { return "nil" }
        if JSONSerialization.isValidJSONObject(message),
           let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text.count > 600 ? String(text.prefix(600)) + "... (\(text.count) chars)" : text
        }
        return String(describing: message)
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
