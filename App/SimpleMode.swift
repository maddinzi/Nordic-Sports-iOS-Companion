import NordicSportsShared
import SwiftUI

// Simple and expert mode (Companion repo, design/simple-and-expert-mode.md): one switch, "Show all details" in
// Settings › App. The level of each block is declared once in the shared `SettingsItem` / `WatchSetting` tables;
// these views only read it. Hidden is not off: a hidden setting keeps its value and its effect.

private struct DetailsRevealedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// A page's "Show details" (plan section 5), or a search hit: the page's expert blocks are shown until it is left.
    var detailsRevealed: Bool {
        get { self[DetailsRevealedKey.self] }
        set { self[DetailsRevealedKey.self] = newValue }
    }
}

/// Shows [content] only while [item] is shown: in expert mode, at the simple level, or on a revealed page
/// (Android `Detail(item) { }`).
struct Detail<Content: View>: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.detailsRevealed) private var revealed
    let item: SettingsItem
    let content: () -> Content

    init(_ item: SettingsItem, @ViewBuilder content: @escaping () -> Content) {
        self.item = item
        self.content = content
    }

    var body: some View {
        if revealed || companion.showAllDetails || companion.shows(item) {
            content()
        }
    }
}

extension Companion {
    /// How many of [items] the page leaves out in the current mode (for "Show details (n more)").
    func hiddenCount(_ items: [SettingsItem]) -> Int {
        showAllDetails ? 0 : items.filter { !shows($0) }.count
    }
}

/// "Show details (n more[, m changed])" at the end of a simplified page (plan section 5): only in simple mode and
/// only while something is left out; once tapped it reads "Show fewer details".
struct ShowDetailsButton: View {
    @EnvironmentObject var companion: Companion
    @Binding var revealed: Bool
    let hidden: Int
    var changed: Int = 0

    var body: some View {
        if !companion.showAllDetails && (revealed || hidden > 0) {
            Button(title) { revealed.toggle() }
        }
    }

    private var title: String {
        if revealed { return L10n.get("settings_hide_details") }
        if changed > 0 { return String(format: L10n.get("settings_show_details_changed"), hidden, changed) }
        return String(format: L10n.get("settings_show_details"), hidden)
    }
}

private struct ShowAllDetailsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// "Show all details" for views that do not hold the Companion (cards, charts); set at the root. The default shows
    /// everything, so a view outside the root never hides anything.
    var showAllDetails: Bool {
        get { self[ShowAllDetailsKey.self] }
        set { self[ShowAllDetailsKey.self] = newValue }
    }
}

extension SettingsItem {
    /// Whether this block is shown: always with all details, else only at the simple level.
    func shown(all: Bool) -> Bool { level.shownAt(current: all ? UiLevel.expert : UiLevel.simple) }
}

/// The busy line (plan section 7, Android `BusyBanner`): while the app works with another system, one short line rotates
/// through the kind's variants every 2.5 s (`busy_<kind>`, variants split by "|", the plain one first); then the plain
/// result for 3 s when something changed. Screen readers get the plain variant only.
struct BusyBanner: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        if let key = companion.busyKind {
            let variants = L10n.get(key).split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let plain = variants.first ?? ""
            HStack(spacing: 12) {
                ProgressView()
                TimelineView(.periodic(from: .now, by: 2.5)) { context in
                    let index = variants.count > 1 ? Int(context.date.timeIntervalSinceReferenceDate / 2.5) % variants.count : 0
                    Text(variants.isEmpty ? "" : variants[index])
                        .contentTransition(.opacity)
                        .animation(.easeInOut, value: index)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(plain)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } else if let changes = companion.busyResult {
            Label(String(format: L10n.get("busy_done_changes"), changes), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.vertical, 4)
        }
    }
}

/// "Details" under a plain problem sentence (plan section 6): the exact technical text on a tap; nothing when empty.
struct ProblemDetails: View {
    let text: String
    @State private var open = false

    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Button(L10n.get(open ? "problem_details_hide" : "problem_details")) { open.toggle() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                if open {
                    Text(text).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }
}