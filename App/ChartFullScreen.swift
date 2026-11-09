import SwiftUI
import UIKit

/// The interface orientations the app allows right now: portrait, and landscape while a chart is open full screen.
/// The Info.plist declares landscape too (iOS needs that for the turn); `AppOrientationDelegate` hands this mask to the
/// system, so every other screen stays in portrait.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    /// Turns the screen to landscape, or back to portrait. A failed turn (no scene yet, the user's rotation lock) leaves
    /// the chart readable in portrait: nothing depends on it.
    static func set(landscape: Bool) {
        mask = landscape ? .landscape : .portrait
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }
        var controller = scene.keyWindow?.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

final class AppOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}

/// The room a chart has: [inline] in its card, or the whole landscape screen (`maximized`, with the `size` it may fill).
/// Text grows with the full-screen view's Dynamic Type; a chart that draws its own sizes reads `scale`.
struct ChartSpace {
    var maximized = false
    var size = CGSize.zero

    /// Spacing and bar factor: the maximized chart is read at arm's length (Android: `ChartSpace.scale`).
    var scale: CGFloat { maximized ? 1.4 : 1 }

    static let inline = ChartSpace()
}

/// The charts of one card in the order they appeared (top to bottom): while a chart is full screen, a swipe left or right
/// pages to the next or the previous one (Android: `ChartGroup`). A `ChartFrame` registers itself here; the card puts the
/// registry into the environment.
final class ChartRegistry {
    struct Page: Identifiable {
        let id: String
        let title: String
        let tone: CardTone
        let content: (ChartSpace) -> AnyView
    }

    private(set) var pages: [Page] = []

    func register(_ page: Page) {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            pages[index] = page
        } else {
            pages.append(page)
        }
    }
}

private struct ChartRegistryKey: EnvironmentKey {
    static let defaultValue: ChartRegistry? = nil
}

extension EnvironmentValues {
    var chartRegistry: ChartRegistry? {
        get { self[ChartRegistryKey.self] }
        set { self[ChartRegistryKey.self] = newValue }
    }
}

/// A chart with its title and an expand button at the top right (Android: `ChartFrame`). The chart is drawn by `content`
/// twice over: in the card (told `.inline`) and, after the button, on the whole screen turned to landscape, with the
/// same state, so a selection made in one shows in the other. What belongs to the chart (legend, caption) is part of
/// `content` and goes with it.
struct ChartFrame<Content: View>: View {
    let title: String
    var hint: String? = nil
    var tone: CardTone = .blue
    /// How to read the chart, behind an (i) next to the expand button instead of as text in the card (Android: the same).
    var info: String? = nil
    @ViewBuilder let content: (ChartSpace) -> Content
    @State private var expanded = false
    @Environment(\.chartRegistry) private var registry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tone.title)
                Spacer()
                if let info { ChartInfoButton(title: title, text: info) }
                ExpandChartButton(tone: tone) { expanded = true }
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(tone.subtitle) }
            content(.inline)
        }
        .onAppear {
            registry?.register(ChartRegistry.Page(id: title, title: title, tone: tone, content: { space in AnyView(content(space)) }))
        }
        .fullScreenCover(isPresented: $expanded) {
            FullScreenChart(title: title, tone: tone, onClose: { expanded = false },
                            pages: registry?.pages ?? [], startId: title, content: content)
        }
    }
}

/// An (i) that shows how to read a chart or a control in an alert (Android `ChartInfoButton`).
struct ChartInfoButton: View {
    let title: String
    let text: String
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.get("chart_info"))
            .alert(title, isPresented: $open) {
                Button(L10n.get("common_ok"), role: .cancel) {}
            } message: { Text(text) }
    }
}

/// The expand icon for a chart's title row.
struct ExpandChartButton: View {
    let tone: CardTone
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone.title)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.get("chart_expand"))
    }
}

/// `content` on the whole screen in landscape: the screen is turned while this is open (and back after), and the chart
/// gets every point below a title row with the close button. The view uses the safe area, so a notch or the home
/// indicator never covers it.
struct FullScreenChart<Content: View>: View {
    let title: String
    let tone: CardTone
    let onClose: () -> Void
    /// The card's other charts; with two or more, a swipe pages through them and `startId` is the one that was opened.
    var pages: [ChartRegistry.Page] = []
    var startId = ""
    @ViewBuilder let content: (ChartSpace) -> Content
    @State private var currentId: String?

    private var paged: Bool { pages.count > 1 && pages.contains(where: { $0.id == startId }) }
    private var selection: Binding<String> {
        Binding(get: { currentId ?? startId }, set: { currentId = $0 })
    }
    private var shownPage: ChartRegistry.Page? { pages.first(where: { $0.id == selection.wrappedValue }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(paged ? (shownPage?.title ?? title) : title).font(.headline).foregroundStyle(tone.title).lineLimit(1)
                Spacer()
                if paged {
                    // Page dots: where this chart stands among the card's charts.
                    HStack(spacing: 6) {
                        ForEach(pages) { page in
                            Circle()
                                .fill(tone.title.opacity(page.id == selection.wrappedValue ? 1 : 0.35))
                                .frame(width: page.id == selection.wrappedValue ? 9 : 7, height: page.id == selection.wrappedValue ? 9 : 7)
                                .onTapGesture { withAnimation { currentId = page.id } }
                        }
                    }
                    .padding(.trailing, 8)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.title)
                        .frame(width: 44, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.get("chart_close"))
            }
            GeometryReader { box in
                if paged {
                    TabView(selection: selection) {
                        ForEach(pages) { page in
                            page.content(ChartSpace(maximized: true, size: box.size))
                                .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
                                .tag(page.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(width: box.size.width, height: box.size.height)
                } else {
                    content(ChartSpace(maximized: true, size: box.size))
                        .frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground).ignoresSafeArea())
        // The text of the maximized chart is read at arm's length: at least "extra extra large".
        .dynamicTypeSize(.xxLarge ... .accessibility2)
        .onAppear { OrientationLock.set(landscape: true) }
        .onDisappear { OrientationLock.set(landscape: false) }
    }
}
