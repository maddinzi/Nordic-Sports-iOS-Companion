import SwiftUI

/// A tap on a screen's title goes back to the activity list (Android `Modifier.goHomeOnTap` / `LocalGoHome`).
/// `.homeTitle(text)` replaces `.navigationTitle(text)`: the title is shown inline as a plain button that asks the root
/// view to start over on the Activities tab ([Companion.goHome]; the shared instance, so sheets need no environment object). Input forms (label, add, edit, feedback) keep a plain
/// title, so a stray tap never throws away what was typed.
private struct HomeTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button { Companion.shared.goHome() } label: {
                        Text(title).font(.headline).foregroundStyle(.primary).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(L10n.get("title_tap_home"))
                }
            }
    }
}

extension View {
    /// The screen's title; a tap on it goes back to the activity list.
    func homeTitle(_ title: String) -> some View { modifier(HomeTitle(title: title)) }
}
