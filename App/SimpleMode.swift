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
