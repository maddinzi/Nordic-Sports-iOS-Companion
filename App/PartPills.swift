import SwiftUI

/// One pill of a `PartPills` row.
struct PartPill: Identifiable {
    let id: String
    let label: String
    let selected: Bool
    let action: () -> Void
}

/// Level 3 of the navigation (Android `PartPills`): which part of a screen, as one row of pills. When the pills do not
/// fit, the row shows that it continues: its edges fade where more pills hide, the selected pill scrolls to the middle
/// (its neighbours on both sides stay in reach), and a "⋯" menu at the right end lists every part, one tap to any of them.
/// All in the same single row (field feedback 2026-11-11: the themes that hid on the right were not found).
struct PartPills: View {
    let pills: [PartPill]
    /// The pill colour: the screen's accent (Metrics) or its card tone (Trends).
    var tint: Color = .accentColor
    /// The Sensor mode's lighter look: a tinted fill instead of a solid one, smaller text.
    var light = false

    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { contentWidth > viewportWidth + 1 }
    private var selectedId: String? { pills.first(where: { $0.selected })?.id }

    var body: some View {
        HStack(spacing: 4) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pills) { pill in
                            Button(action: pill.action) { label(pill) }
                                .buttonStyle(.plain)
                                .id(pill.id)
                                .accessibilityAddTraits(pill.selected ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 1)
                    .background(GeometryReader { g in
                        Color.clear
                            .preference(key: PillContentWidth.self, value: g.size.width)
                            .preference(key: PillOffset.self, value: g.frame(in: .named("pills")).minX)
                    })
                }
                .coordinateSpace(name: "pills")
                .background(GeometryReader { g in Color.clear.preference(key: PillViewport.self, value: g.size.width) })
                .onPreferenceChange(PillContentWidth.self) { contentWidth = $0 }
                .onPreferenceChange(PillViewport.self) { viewportWidth = $0 }
                .onPreferenceChange(PillOffset.self) { offset = $0 }
                .mask(fadeMask)
                // The open part in the middle: at once when the screen opens, gliding after a tap or swipe.
                .onAppear {
                    // after the first layout, so the row knows its pills' places
                    if let id = selectedId { DispatchQueue.main.async { reader.scrollTo(id, anchor: .center) } }
                }
                .onChange(of: selectedId) { _, id in
                    if let id { withAnimation(.easeInOut(duration: 0.25)) { reader.scrollTo(id, anchor: .center) } }
                }
            }
            if overflows { allPartsMenu }
        }
    }

    private func label(_ pill: PartPill) -> some View {
        Text(pill.label)
            .font(light ? .footnote.weight(pill.selected ? .semibold : .regular) : .subheadline.weight(pill.selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, light ? 10 : 12).padding(.vertical, 6)
            .background(pill.selected ? (light ? tint.opacity(0.2) : tint) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(light ? Color.secondary.opacity(0.4) : tint, lineWidth: light ? 1 : 1.5))
            .foregroundStyle(pill.selected && !light ? Color(.systemBackground) : (light ? Color.primary : tint))
    }

    /// Fades the row out towards an edge behind which more pills hide.
    private var fadeMask: some View {
        let fade: CGFloat = 28
        let atStart = offset >= -1
        let atEnd = contentWidth + offset <= viewportWidth + 1
        return HStack(spacing: 0) {
            LinearGradient(colors: [atStart ? .black : .clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: fade)
            Color.black
            LinearGradient(colors: [.black, atEnd ? .black : .clear], startPoint: .leading, endPoint: .trailing).frame(width: fade)
        }
    }

    /// Every part in a menu, the open one ticked.
    private var allPartsMenu: some View {
        Menu {
            ForEach(pills) { pill in
                Button(action: pill.action) {
                    if pill.selected { Label(pill.label, systemImage: "checkmark") } else { Text(pill.label) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .accessibilityLabel(L10n.get("part_pills_all"))
    }
}

private struct PillContentWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PillViewport: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PillOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
