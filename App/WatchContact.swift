import SwiftUI

/// When each watch last talked to this phone and whether it can be reached now (Android `watch/WatchContact.kt`, same
/// rules): every message from a watch, Garmin's connection state for it and the result of every message the phone
/// sends. Garmin's "disconnected" ends the green at once; a failed send to a watch the mark shows as reachable turns it
/// red until the next contact. The time of the last contact is saved, so the mark keeps its age across app starts; the
/// link state is not. Nothing here leaves the phone.
@MainActor
final class WatchContact: ObservableObject {
    static let shared = WatchContact()

    enum Link { case unknown, connected, disconnected, sendFailed }

    /// The colour band of the home screen's mark.
    enum Mark { case fresh, today, older, stale, failed }

    struct Contact {
        var lastSeen: Date
        var link: Link = .unknown
        var failedAt: Date = .distantPast
        var connected: Bool { link == .connected }
        /// The latest thing known about this watch: its last contact or the last failed send.
        var lastNews: Date { max(lastSeen, failedAt) }
    }

    /// Per device id ([WatchLinkSpike.deviceId]); a watch never heard from is missing.
    @Published private(set) var contacts: [Int64: Contact] = [:]

    private let defaults = UserDefaults.standard
    private static let key = "watchContact.seen"

    static let fresh: TimeInterval = 15 * 60
    static let day: TimeInterval = 24 * 3600
    static let stale: TimeInterval = 3 * day

    private init() {
        let saved = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        for (id, at) in saved {
            if let id = Int64(id) { contacts[id] = Contact(lastSeen: Date(timeIntervalSince1970: at)) }
        }
    }

    /// A message from [deviceId] arrived.
    func heard(_ deviceId: Int64) {
        set(deviceId, Self.onHeard(contacts[deviceId], now: Date()))
    }

    /// Garmin reports [deviceId] connected or not.
    func connection(_ deviceId: Int64, connected: Bool) {
        set(deviceId, Self.onConnection(contacts[deviceId], connected: connected, now: Date()))
    }

    /// A message the phone sent to [deviceId] reached the watch ([delivered]) or not.
    func sendResult(_ deviceId: Int64, delivered: Bool) {
        set(deviceId, Self.onSendResult(contacts[deviceId], delivered: delivered, now: Date()))
    }

    private func set(_ deviceId: Int64, _ contact: Contact?) {
        guard let contact else { return }
        contacts[deviceId] = contact
        defaults.set(Dictionary(uniqueKeysWithValues: contacts.map { (String($0.key), $0.value.lastSeen.timeIntervalSince1970) }),
                     forKey: Self.key)
    }

    /// In contact now; a failed send or disconnect before it no longer counts. Only Garmin's own report makes the link
    /// connected, so a missed disconnect cannot keep the mark green for longer than [fresh].
    static func onHeard(_ c: Contact?, now: Date) -> Contact {
        Contact(lastSeen: now, link: c?.link == .connected ? .connected : .unknown)
    }

    /// Connected: in contact now. Disconnected: in contact up to now if it was connected; a failed send keeps its
    /// mark. A watch never heard from is not added by a disconnect.
    static func onConnection(_ c: Contact?, connected: Bool, now: Date) -> Contact? {
        if connected { return Contact(lastSeen: now, link: .connected) }
        guard var c else { return nil }
        switch c.link {
        case .sendFailed: return c
        case .connected: return Contact(lastSeen: now, link: .disconnected)
        default:
            c.link = .disconnected
            return c
        }
    }

    /// A failure counts only for a watch the mark shows as reachable (connected, or heard within [fresh]), so the role
    /// sent to every known watch on app start does not turn a watch left at home red.
    static func onSendResult(_ c: Contact?, delivered: Bool, now: Date) -> Contact? {
        if delivered { return onHeard(c, now: now) }
        guard var c else { return nil }
        if c.link == .connected || (c.link == .unknown && now.timeIntervalSince(c.lastSeen) < fresh) {
            c.link = .sendFailed
            c.failedAt = now
        }
        return c
    }

    /// The mark for all watches: the one with the latest news decides. Nil while no watch was ever heard from.
    static func mark(_ contacts: [Contact], now: Date) -> Mark? {
        guard let c = contacts.max(by: { $0.lastNews < $1.lastNews }) else { return nil }
        let age = now.timeIntervalSince(c.lastSeen)
        if c.link == .sendFailed { return .failed }
        if c.link == .connected || (c.link == .unknown && age < fresh) { return .fresh }
        return age < day ? .today : age < stale ? .older : .stale
    }

    var latest: Contact? { contacts.values.max(by: { $0.lastNews < $1.lastNews }) }

    /// "Connected" or "Last contact: 14:32" for the watch row in settings.
    func text(_ deviceId: Int64?) -> String? {
        guard let deviceId, let c = contacts[deviceId] else { return nil }
        if c.connected { return L10n.get("watch_contact_connected") }
        return String(format: L10n.get("watch_contact_last"), Format.dateOrTimeToday(Int64(c.lastSeen.timeIntervalSince1970)))
    }
}

/// The home screen's watch mark ([WatchContact.mark]): green connected (or heard within 15 minutes with nothing against
/// it), red at once when a message to it failed, otherwise by age: grey within a day, amber within three days, red
/// after that. Hidden while no watch was ever heard from. Re-checked every minute, so the colour ages without messages.
struct WatchContactMark: View {
    @ObservedObject private var contact = WatchContact.shared

    var body: some View {
        if let latest = contact.latest {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let mark = WatchContact.mark(Array(contact.contacts.values), now: timeline.date) ?? .stale
                let colour = Self.colour(mark)
                let state = mark == .failed ? L10n.get("watch_sync_failed")
                    : latest.connected ? L10n.get("watch_contact_connected")
                    : String(format: L10n.get("watch_contact_last"), Format.dateOrTimeToday(Int64(latest.lastSeen.timeIntervalSince1970)))
                Image(systemName: "applewatch")
                    .foregroundStyle(colour)
                    .accessibilityLabel(String(format: L10n.get("watch_contact_mark"), state))
            }
        }
    }

    private static func colour(_ mark: WatchContact.Mark) -> Color {
        switch mark {
        case .fresh: return Color(red: 0x2E / 255, green: 0x9E / 255, blue: 0x4F / 255)
        case .today: return .secondary
        case .older: return Color(red: 0xB2 / 255, green: 0x6A / 255, blue: 0x00 / 255)
        case .stale, .failed: return .red
        }
    }
}
