import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

// The "Out there" tab of an activity's Entry (Android `OutThereContent.kt`): the track with its export, the weather
// (design/activity-weather.md) and the snow classification (design/snow-condition.md).

/// The stored track as a GPX or FIT file, written only when the athlete shares it (`Companion.trackFile`).
struct TrackFile: Transferable {
    let companion: Companion
    let item: ActivityItem
    let fit: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { file in
            SentTransferredFile(try await file.companion.trackFile(of: file.item, fit: file.fit))
        }
    }
}

/// The track card's export: GPX or FIT through the share sheet (Android: the share icon's menu on the Track card).
struct TrackExportMenu: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem

    var body: some View {
        Menu {
            ShareLink(item: TrackFile(companion: companion, item: item, fit: false),
                      preview: SharePreview(L10n.get("activity_track_export_gpx"))) {
                Label(L10n.get("activity_track_export_gpx"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
            ShareLink(item: TrackFile(companion: companion, item: item, fit: true),
                      preview: SharePreview(L10n.get("activity_track_export_fit"))) {
                Label(L10n.get("activity_track_export_fit"), systemImage: "doc")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(L10n.get("activity_track_export"))
    }
}

// MARK: - Weather

private func degrees(_ c: Double) -> String { "\(Int(c.rounded())) °C" }

private func oneDecimal(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }

/// The sky symbol (SF Symbols: the same on every iPhone, unlike emoji).
private func weatherSymbol(_ symbol: WeatherSymbol?) -> String {
    switch symbol?.name {
    case "SUN": return "sun.max"
    case "PART_CLOUD": return "cloud.sun"
    case "CLOUD": return "cloud"
    case "FOG": return "cloud.fog"
    case "RAIN": return "cloud.rain"
    case "SNOW": return "cloud.snow"
    case "THUNDER": return "cloud.bolt"
    default: return "thermometer.medium"
    }
}

/// "MeteoSwiss, station Samedan, 4.3 km away, 96 m lower", or the model's name.
private func sourceLine(_ r: WeatherReading) -> String {
    guard r.source == WeatherSource.meteoswiss else { return L10n.get("weather_source_model") }
    let base = String(format: L10n.get("weather_station_line"), L10n.get("weather_source_meteoswiss"),
                      r.stationName ?? r.stationId ?? "", oneDecimal(r.distanceKm?.doubleValue ?? 0))
    guard let diff = r.heightDiffM.map({ Int($0.doubleValue.rounded()) }), abs(diff) >= 10 else { return base }
    return base + ", " + (diff < 0 ? String(format: L10n.get("weather_station_lower"), -diff)
                                   : String(format: L10n.get("weather_station_higher"), diff))
}

/// Wind chill shows only from this many degrees below the air temperature.
private let feelsLikeGapC = 3.0

/// The weather at the start and end (Android `WeatherCard`): sky and temperature from start to end, the stronger wind
/// with an arrow the way it blows, precipitation over the activity, feels like, the source; (i) opens the details.
struct WeatherSection: View {
    let readings: [WeatherReading]
    @State private var details = false

    private var start: WeatherReading? { readings.first { $0.moment == WeatherMoment.start } }
    private var end: WeatherReading? { readings.first { $0.moment == WeatherMoment.end } }
    private var moments: [WeatherReading] { [start, end].compactMap { $0 } }

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { sky; wind; rain }
                VStack(alignment: .leading, spacing: 6) {
                    sky
                    HStack(spacing: 16) { wind; rain }
                }
            }
            if let cold = moments.filter({ r in
                guard let f = r.feelsLikeC?.doubleValue, let t = r.temperatureC?.doubleValue else { return false }
                return f <= t - feelsLikeGapC
            }).min(by: { $0.feelsLikeC!.doubleValue < $1.feelsLikeC!.doubleValue }), let feels = cold.feelsLikeC?.doubleValue {
                Text(String(format: L10n.get("weather_feels_like"), degrees(feels)))
            }
            // One line per station (or the model): start and end at the same station differ only a little in distance.
            ForEach(moments.filter { r in r.moment == WeatherMoment.start || r.source != start?.source || r.stationId != start?.stationId }.map(sourceLine), id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text(L10n.get("weather_title"))
                Spacer()
                Button { details = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(L10n.get("weather_details"))
            }
        }
        .sheet(isPresented: $details) { WeatherDetailsSheet(readings: moments) }
    }

    private var sky: some View {
        HStack(spacing: 6) {
            ForEach(Array(moments.enumerated()), id: \.offset) { index, r in
                if index > 0 { Text("→") }
                Label(r.temperatureC.map { degrees($0.doubleValue) } ?? "–", systemImage: weatherSymbol(r.symbol))
            }
        }
    }

    @ViewBuilder private var wind: some View {
        if let w = moments.filter({ $0.windKmh != nil }).max(by: { $0.windKmh!.doubleValue < $1.windKmh!.doubleValue }),
           let kmh = w.windKmh?.doubleValue {
            HStack(spacing: 4) {
                Label("\(Int(kmh.rounded())) km/h", systemImage: "wind")
                if let dir = w.windDirDeg?.doubleValue {
                    Image(systemName: "arrow.down").font(.caption).rotationEffect(.degrees(dir))
                }
            }
        }
    }

    @ViewBuilder private var rain: some View {
        if let mm = end?.precipitationMm?.doubleValue {
            Label(mm < 0.05 ? L10n.get("weather_dry") : "\(oneDecimal(mm)) mm", systemImage: "drop")
        }
    }
}

/// The (i) details: every value per moment, the source and its attribution.
private struct WeatherDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let readings: [WeatherReading]

    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                    Section {
                        Text(String(format: L10n.get("weather_observed"),
                                    Date(timeIntervalSince1970: TimeInterval(r.observedAtEpochSec)).formatted(date: .omitted, time: .shortened))
                             + " · " + sourceLine(r))
                            .font(.footnote).foregroundStyle(.secondary)
                        line("weather_temperature", r.temperatureC.map { "\(oneDecimal($0.doubleValue)) °C" })
                        if let f = r.feelsLikeC?.doubleValue {
                            Text(String(format: L10n.get("weather_feels_like"), "\(oneDecimal(f)) °C"))
                        }
                        line("weather_humidity", r.humidityPct.map { "\(Int($0.doubleValue.rounded())) %" })
                        line("weather_wind", r.windKmh.map { w in
                            "\(Int(w.doubleValue.rounded())) km/h" + (r.windDirDeg.map { " (\(Int($0.doubleValue.rounded()))°)" } ?? "")
                        })
                        line("weather_gusts", r.gustKmh.map { "\(Int($0.doubleValue.rounded())) km/h" })
                        line("weather_pressure", r.pressureHpa.map { "\(Int($0.doubleValue.rounded())) hPa" })
                        line("weather_sunshine", r.sunshineMin.map { "\(Int($0.doubleValue.rounded())) min" })
                        line("weather_snow_depth", r.snowDepthCm.map { "\(Int($0.doubleValue.rounded())) cm" })
                        line("weather_precipitation", r.precipitationMm.map { "\(oneDecimal($0.doubleValue)) mm" })
                    } header: {
                        Text(L10n.get(r.moment == WeatherMoment.start ? "weather_start" : "weather_end"))
                    }
                }
                Section {
                    if readings.contains(where: { $0.source == WeatherSource.meteoswiss }) {
                        Text(L10n.get("weather_attribution_meteoswiss")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if readings.contains(where: { $0.source != WeatherSource.meteoswiss }) {
                        Text(L10n.get("weather_attribution_open_meteo")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .homeTitle(L10n.get("weather_details"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L10n.get("em_sheet_close")) { dismiss() } }
            }
        }
    }

    @ViewBuilder private func line(_ key: String, _ value: String?) -> some View {
        if let value { LabeledContent(L10n.get(key), value: value) }
    }
}

// MARK: - Snow

/// The snow classification (Android `SnowCard`): three rows of chips, one tap each, a tap on the chosen chip clears
/// it; "Same as last time" while nothing is chosen; the snow temperature is optional. Every change is stored at once.
struct SnowSection: View {
    @EnvironmentObject var companion: Companion
    let item: ActivityItem
    @State private var age: String
    @State private var grain: String
    @State private var moisture: String
    @State private var tempText: String
    @State private var last: SnowView?
    @FocusState private var tempFocused: Bool

    init(item: ActivityItem) {
        self.item = item
        _age = State(initialValue: item.snowAge)
        _grain = State(initialValue: item.snowGrain)
        _moisture = State(initialValue: item.snowMoisture)
        _tempText = State(initialValue: item.snowTempText)
    }

    private static let ages = [("FRESH", "snow_age_fresh"), ("SETTLED", "snow_age_settled"),
                               ("TRANSFORMED", "snow_age_transformed"), ("ARTIFICIAL", "snow_age_artificial")]
    private static let grains = [("FINE_POWDER", "snow_grain_fine"), ("COARSE", "snow_grain_coarse"), ("FROZEN_ICE", "snow_grain_icy")]
    private static let moistures = [("DRY", "snow_moisture_dry"), ("MOIST", "snow_moisture_moist"),
                                    ("WET", "snow_moisture_wet"), ("SLUSH", "snow_moisture_slush")]

    /// As the shared `SnowCondition.parseTemp`: comma or point, no sign means below zero, -40 to 0 °C.
    private var tempValid: Bool {
        let text = tempText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return true }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{2212}", with: "-")) else { return false }
        return -abs(value) >= -40
    }

    private var isEmpty: Bool { age.isEmpty && grain.isEmpty && moisture.isEmpty && tempText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Section(L10n.get("snow_title")) {
            Text(L10n.get("snow_hint")).font(.footnote).foregroundStyle(.secondary)
            if let last, isEmpty {
                Button(L10n.get("snow_same_as_last")) {
                    age = last.age; grain = last.grain; moisture = last.moisture; tempText = last.tempText
                    save()
                }
            }
            axis("snow_age_label", Self.ages, $age)
            axis("snow_grain_label", Self.grains, $grain)
            axis("snow_moisture_label", Self.moistures, $moisture)
            TextField(L10n.get("snow_temp_label"), text: $tempText)
                .keyboardType(.numbersAndPunctuation)
                .focused($tempFocused)
                .onSubmit { save() }
                .onChange(of: tempFocused) { _, focused in if !focused { save() } }
            if !tempValid {
                Text(L10n.get("snow_temp_invalid")).font(.footnote).foregroundStyle(.red)
            }
        }
        .task(id: item.id) { last = await companion.lastSnow(of: item) }
    }

    private func axis(_ label: String, _ options: [(String, String)], _ selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.get(label)).font(.subheadline.weight(.semibold))
            ChipFlow(spacing: 8) {
                ForEach(options.indices, id: \.self) { index in
                    let key = options[index].0
                    let text = options[index].1
                    let on = selection.wrappedValue == key
                    Button {
                        selection.wrappedValue = on ? "" : key
                        save()
                    } label: {
                        Text(L10n.get(text)).font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(on ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                            .overlay(Capsule().stroke(on ? Color.accentColor : Color(.separator), lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func save() {
        guard tempValid else { return }
        let snapshot = (age, grain, moisture, tempText)
        Task { await companion.saveSnow(item, age: snapshot.0, grain: snapshot.1, moisture: snapshot.2, tempText: snapshot.3) }
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full (the snow chips).
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
