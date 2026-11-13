import SwiftUI

/// When each watch last talked to this phone (Android `watch/WatchContact.kt`): every message from a watch and Garmin's
/// connection state for it. While connected the watch counts as in contact now; the time is kept when it disconnects,
/// and saved, so the mark keeps its age across app starts. Nothing here leaves the phone.
@MainActor
final class WatchContact: ObservableObject {
    static let shared = WatchContact()

    struct Contact { var lastSeen: Date; var connected: Bool }

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
            if let id = Int64(id) { contacts[id] = Contact(lastSeen: Date(timeIntervalSince1970: at), connected: false) }
        }
    }

    /// A message from [deviceId] arrived.
    func heard(_ deviceId: Int64) {
        set(deviceId, Contact(lastSeen: Date(), connected: contacts[deviceId]?.connected ?? false))
    }

    /// Garmin reports [deviceId] connected or not; either way it was in contact up to now.
    func connection(_ deviceId: Int64, connected: Bool) {
        if !connected && contacts[deviceId]?.connected != true { return }
        set(deviceId, Contact(lastSeen: Date(), connected: connected))
    }

    private func set(_ deviceId: Int64, _ contact: Contact) {
        contacts[deviceId] = contact
        defaults.set(Dictionary(uniqueKeysWithValues: contacts.map { (String($0.key), $0.value.lastSeen.timeIntervalSince1970) }),
                     forKey: Self.key)
    }

    var anyConnected: Bool { contacts.values.contains { $0.connected } }
    var lastSeen: Date? { contacts.values.map(\.lastSeen).max() }

    /// "Connected" or "Last contact: 14:32" for the watch row in settings.
    func text(_ deviceId: Int64?) -> String? {
        guard let deviceId, let c = contacts[deviceId] else { return nil }
        if c.connected { return L10n.get("watch_contact_connected") }
        return String(format: L10n.get("watch_contact_last"), Format.dateOrTimeToday(Int64(c.lastSeen.timeIntervalSince1970)))
    }
}

/// The home screen's watch mark, coloured by how long ago a watch last talked to the phone: green connected or within
/// 15 minutes, grey within a day, amber within three days, red after that. Hidden while no watch was ever heard from.
/// Re-checked every minute, so the colour ages without new messages.
struct WatchContactMark: View {
    @ObservedObject private var contact = WatchContact.shared

    var body: some View {
        if let last = contact.lastSeen {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let age = timeline.date.timeIntervalSince(last)
                let colour: Color = contact.anyConnected || age < WatchContact.fresh ? Color(red: 0x2E / 255, green: 0x9E / 255, blue: 0x4F / 255)
                    : age < WatchContact.day ? .secondary
                    : age < WatchContact.stale ? Color(red: 0xB2 / 255, green: 0x6A / 255, blue: 0x00 / 255)
                    : .red
                let state = contact.anyConnected ? L10n.get("watch_contact_connected")
                    : String(format: L10n.get("watch_contact_last"), Format.dateOrTimeToday(Int64(last.timeIntervalSince1970)))
                Image(systemName: "applewatch")
                    .foregroundStyle(colour)
                    .accessibilityLabel(String(format: L10n.get("watch_contact_mark"), state))
            }
        }
    }
}
