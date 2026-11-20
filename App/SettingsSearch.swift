import NordicSportsShared
import SwiftUI

// The one settings search (Companion's shared `SettingsSearchIndex`, as Android's overview, 2026-11-18): the hits are
// settings, and a tap opens the page, the section and the row, which glows for a moment.

private struct SettingsFocusKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The row a search hit leads to on this page (`SettingsSearchHitView.id`), or nil.
    var settingsFocus: String? {
        get { self[SettingsFocusKey.self] }
        set { self[SettingsFocusKey.self] = newValue }
    }
}

/// Marks a settings row as a search target: an id for `ScrollViewReader`, and a short glow when the search led here.
private struct SettingsAnchorModifier: ViewModifier {
    let id: String
    @Environment(\.settingsFocus) private var focus
    @State private var glow = false

    func body(content: Content) -> some View {
        content
            .id(id)
            .listRowBackground(glow ? Color.accentColor.opacity(0.18) : nil)
            .onAppear {
                guard focus == id else { return }
                glow = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                    withAnimation(.easeOut(duration: 1.2)) { glow = false }
                }
            }
    }
}

extension View {
    func settingsAnchor(_ id: String) -> some View { modifier(SettingsAnchorModifier(id: id)) }

    /// Scrolls a settings page to the row the search led to, once it is laid out.
    func scrollsToSettingsFocus(_ proxy: ScrollViewProxy, _ focus: String?) -> some View {
        onAppear {
            guard let focus else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { proxy.scrollTo(focus, anchor: .center) }
            }
        }
    }
}

/// One setting the search found: its name, where it lives, and what it does.
struct SettingsSearchHitRow: View {
    let hit: SettingsSearchHitView

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.title)
            if !hit.place.isEmpty {
                Text(hit.place).font(.caption).foregroundStyle(Color.accentColor)
            }
            if !hit.description_.isEmpty {
                Text(hit.description_).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

/// The page a hit opens, focused on its row.
@ViewBuilder
func settingsSearchDestination(_ hit: SettingsSearchHitView) -> some View {
    switch hit.page {
    case "WATCH": WatchSettingsScreen(focus: hit.id).environment(\.settingsFocus, hit.id)
    case "APP": SettingsAppPage().environment(\.settingsFocus, hit.id)
    case "LOGS": SettingsLogsPage().environment(\.detailsRevealed, true)
    // The Testing tools page (2026-11-20): its watch cards, sources and diagnostics logs.
    case "TESTING": WatchSettingsScreen(focus: hit.id, testingPart: true).environment(\.settingsFocus, hit.id)
    default: SettingsPrivacyPage().environment(\.settingsFocus, hit.id)
    }
}
