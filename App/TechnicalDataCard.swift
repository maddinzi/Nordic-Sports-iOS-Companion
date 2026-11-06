import SwiftUI

/// One number of the technical data: the value, its unit (may be empty), the name under it and the plain-language
/// line that says what it is (may be empty).
struct KeyFigure {
    let value: String
    let unit: String
    let name: String
    var description = ""
}

/// The technical data of an activity in the look of the Enhanced Metrics key data (Android: `TechnicalDataCard` in
/// `ActivityDetailScreen.kt`): tiles for the numbers in rows that belong together (a lone tile fills its row), then
/// the facts that are text (start, device, wrist, place) together in one tile. Dark blue, `CardTone.navy`.
struct TechnicalDataCard: View {
    let title: String
    let rows: [[KeyFigure]]
    let facts: [(label: String, value: String)]
    private let tone = CardTone.navy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(tone.title)
            // A Grid, not a LazyVGrid: both tiles of a row stretch to the taller one.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(rows.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, items in
                    GridRow {
                        if items.count == 1 {
                            tile(items[0]).gridCellColumns(2)
                        } else {
                            tile(items[0])
                            tile(items[1])
                        }
                    }
                }
            }
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fact.label).font(.caption.weight(.medium)).foregroundStyle(tone.subtitle)
                            Text(fact.value).font(.body)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func tile(_ figure: KeyFigure) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(figure.value).font(.title.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(1)
                if !figure.unit.isEmpty { Text(figure.unit).font(.footnote).foregroundStyle(.secondary) }
            }
            Text(figure.name).font(.footnote.weight(.semibold))
            if !figure.description.isEmpty { Text(figure.description).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(tone.tile, in: RoundedRectangle(cornerRadius: 12))
    }
}
