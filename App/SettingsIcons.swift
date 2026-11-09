import SwiftUI

/// The generic Strava mark of the activity cards (Android `CardIcons.Strava`): two chevrons pointing up, not the brand
/// logo. Drawn on a 24-point grid and scaled to the frame.
struct StravaMark: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 24, sy = rect.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(10, 3)); path.addLine(to: p(16, 15)); path.addLine(to: p(12.6, 15)); path.addLine(to: p(10, 9.8))
        path.addLine(to: p(7.4, 15)); path.addLine(to: p(4, 15)); path.closeSubpath()
        path.move(to: p(14.5, 15)); path.addLine(to: p(16.5, 19)); path.addLine(to: p(18.5, 15)); path.addLine(to: p(21.5, 15))
        path.addLine(to: p(16.5, 22)); path.addLine(to: p(14, 18)); path.closeSubpath()
        return path
    }
}

/// What a Settings row is about (Android `SettingsRowIcon`).
enum SettingsIconKind {
    case watch, strava, diary, files, sync, app, privacy, logs
}

/// The small icon on the left of a Settings row. A connection (watch, Strava, diary, files) is drawn in the colour the
/// activity cards use for it while [connected], and very light grey while it is not or needs attention; the general
/// rows are plain grey.
struct SettingsRowIcon: View {
    let kind: SettingsIconKind
    var connected = true

    private var off: Color { Color(.systemGray4) }

    var body: some View {
        Group {
            switch kind {
            case .strava:
                StravaMark().fill(connected ? SyncChip.strava : off)
            case .watch:
                Image(systemName: "watch.analog").foregroundStyle(connected ? SyncChip.watch : off)
            case .diary:
                Image(systemName: "book.closed.fill").foregroundStyle(connected ? SyncChip.diary : off)
            case .files:
                Image(systemName: "line.3.horizontal").foregroundStyle(connected ? SyncChip.diary : off)
            case .sync:
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
            case .app:
                Image(systemName: "gearshape.fill").foregroundStyle(.secondary)
            case .privacy:
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            case .logs:
                Image(systemName: "doc.text").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 17))
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

extension View {
    /// The row content with its Settings icon in front.
    func settingsIcon(_ kind: SettingsIconKind, connected: Bool = true) -> some View {
        HStack(spacing: 14) {
            SettingsRowIcon(kind: kind, connected: connected)
            self
        }
    }
}
