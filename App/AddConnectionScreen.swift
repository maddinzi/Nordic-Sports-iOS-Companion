import NordicSportsShared
import SwiftUI

/// "+ Add connection" (Android `AddConnectionDialog`): the Swiss Ski Diary as a tile on its own row, the two file
/// formats side by side (expert level, `SettingsItem.addFiles`), then Strava's own Connect button while Strava is not
/// connected. A watch is not added here; it appears once it reports.
struct AddConnectionScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.detailsRevealed) private var revealed
    @Environment(\.showAllDetails) private var showAll

    private var files: Bool { revealed || showAll || companion.shows(SettingsItem.addFiles) }
    private var strava: Bool { companion.stravaConfigured && !companion.stravaConnected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.get("settings_add_connection_body")).font(.body)
                NavigationLink {
                    DiaryLocationsScreen()
                } label: {
                    AddConnectionTile(title: L10n.get("settings_add_connection_diary_long"),
                                      help: L10n.get("settings_add_connection_diary_short")) {
                        Image(systemName: "book.closed.fill").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
                if files {
                    // Both tiles as high as the taller one (the CSV help wraps to two lines).
                    HStack(alignment: .top, spacing: 10) {
                        fileTile(format: "JSON_PER_ACTIVITY", name: "JSON", help: "settings_add_connection_json_short")
                        fileTile(format: "CSV_MONTHLY", name: "CSV", help: "settings_add_connection_csv_short")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                Text(L10n.get("settings_add_connection_storage_note")).font(.footnote).foregroundStyle(.secondary)
                if strava {
                    Divider().padding(.vertical, 4)
                    StravaConnectButton { companion.connectStrava() }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L10n.get("settings_add_connection_strava_help")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .homeTitle(L10n.get("settings_add_connection"))
    }

    private func fileTile(format: String, name: String, help: String) -> some View {
        NavigationLink {
            AddFolderDestinationScreen(format: format)
        } label: {
            AddConnectionTile(title: name, help: L10n.get(help)) { FileFormatBadge(name: name) }
                .frame(maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}

/// One "Add connection" choice as a tile: symbol, title and a short help line, centred.
struct AddConnectionTile<Symbol: View>: View {
    let title: String
    let help: String
    @ViewBuilder let symbol: () -> Symbol

    var body: some View {
        VStack(spacing: 4) {
            symbol().frame(width: 36, height: 36)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
            Text(help).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separator), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A file symbol for a format: a page with a folded corner and the format's name on it (Android `FileFormatBadge`).
struct FileFormatBadge: View {
    let name: String

    var body: some View {
        ZStack {
            FoldedPage().stroke(Color.accentColor, lineWidth: 2)
            Text(name).font(.system(size: 8, weight: .bold)).foregroundStyle(Color.accentColor).offset(y: 4)
        }
        .frame(width: 30, height: 36)
        .accessibilityHidden(true)
    }
}

private struct FoldedPage: Shape {
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * 0.32
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        p.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        return p
    }
}
