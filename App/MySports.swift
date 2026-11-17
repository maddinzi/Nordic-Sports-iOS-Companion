import NordicSportsShared
import SwiftUI

/// "My sports" on Settings > App (Companion `design/my-sports.md`): the athlete's sports in their order, then the
/// others. A long press drags a row inside "My sports" (the rank); the button at the end of a row moves the sport
/// to the other group. Every change is saved at once and goes to the watches (shared `CompanionCore`).
/// Android: `MySportsEditor`, where one list with a divider does both by dragging.
struct MySportsSections: View {
    @EnvironmentObject var companion: Companion

    private var mine: [MySportRowView] { companion.mySportRows.filter { $0.mine } }
    private var more: [MySportRowView] { companion.mySportRows.filter { !$0.mine } }

    var body: some View {
        Section {
            ForEach(mine, id: \.key) { row in
                HStack {
                    Text(L10n.get(row.labelKey))
                    Spacer()
                    // The last selected sport stays.
                    if row.removable {
                        Button {
                            companion.toggleMySport(row.key)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.get("my_sports_remove"))
                    }
                }
            }
            .onMove { source, destination in
                // SwiftUI names the place before the row is taken out; the core wants the row's new index.
                guard let from = source.first else { return }
                companion.moveMySport(from: from, to: destination > from ? destination - 1 : destination)
            }
        } header: {
            Text(L10n.get("my_sports_title"))
        } footer: {
            Text(L10n.get("my_sports_intro"))
        }
        if !more.isEmpty {
            Section {
                ForEach(more, id: \.key) { row in
                    HStack {
                        Text(L10n.get(row.labelKey)).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            companion.toggleMySport(row.key)
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.get("my_sports_add"))
                    }
                }
            } header: {
                Text(L10n.get("my_sports_other"))
            }
        }
        if !companion.mySportsAreDefault {
            Section {
                Button(L10n.get("my_sports_reset")) { companion.resetMySports() }
            }
        }
    }
}
