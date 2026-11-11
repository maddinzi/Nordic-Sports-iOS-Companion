import SwiftUI
import MapKit
import NordicSportsShared

/// The zoom into the live card (Android `RecordingScreen`): everything the phone knows about the recording that runs on
/// the watch now. Instant mode's live values and the track on a map (watch setting, off by default; else a hint),
/// the start, and the Sensor Records captured so far. It closes itself when the recording ends; "x" closes it, the
/// recording runs on.
struct RecordingScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let startEpochSec: Int64
    @State private var feed: LiveFeedView?
    @State private var bursts: [RecordingBoostView] = []
    /// The map on the whole screen (it may turn with the phone there); its colouring and Summer/Winter are shared.
    @State private var mapFull = false
    @StateObject private var mapChoices = LiveMapChoices()

    /// The card's data, live: nil once the recording is over (saved, or discarded and shown for a few seconds).
    private var live: LiveActivityView? { companion.liveActivities.first { $0.startEpochSec == startEpochSec } }

    var body: some View {
        NavigationStack {
            Group {
                if let live { content(live) } else { Color.clear }
            }
            .homeTitle(L10n.get("recording_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L10n.get("recording_close"))
                }
            }
        }
        // Once a second: the clock, the feed (one message about every 5 s) and the Sensor Records.
        .task(id: startEpochSec) {
            var tick = 0
            while !Task.isCancelled {
                if let live { feed = companion.core.liveFeed(startEpochSec: startEpochSec, preset: live.preset) }
                if tick % 10 == 0, let all = try? await companion.core.recordingBoosts() {
                    bursts = all.filter { $0.burstId >= startEpochSec }.sorted { $0.burstId < $1.burstId }
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .onChange(of: live == nil) { _, gone in if gone { mapFull = false; dismiss() } }
        // Discarded on the watch: the full-screen map closes at once, the screen after a moment showing "Discarded"
        // (Android: RecordingScreen DISCARDED_CLOSE_MS).
        .onChange(of: live?.discarded ?? false) { _, discarded in
            guard discarded else { return }
            mapFull = false
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $mapFull) {
            if let feed, !feed.trackLat.isEmpty {
                LiveMapFullScreen(feed: feed, startEpochSec: startEpochSec, watchName: live?.watchName ?? "", choices: mapChoices,
                                  latestRecord: bursts.last) { mapFull = false }
            } else {
                Color.clear.onAppear { mapFull = false }
            }
        }
    }

    private func content(_ live: LiveActivityView) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                // What the athlete reads at a glance: source, clock and the live values in one card (Android
                // `RecordingHero`).
                Section {
                    // Discarded on the watch: the clock stops at that moment.
                    hero(live, running: max(0, (live.discardedEpochSec > 0 ? Int(live.discardedEpochSec) : Int(context.date.timeIntervalSince1970)) - Int(live.startEpochSec)))
                        .padding(.vertical, 4)
                }
                .listRowBackground(live.discarded ? CardTone.grey.container : CardTone.blue.container)
                // The track so far, high up; its height follows the screen.
                if !live.discarded, let feed, !feed.trackLat.isEmpty {
                    Section {
                        LiveTrackMap(points: TrackPoints(feed), automatic: feed.baseMap, choices: mapChoices,
                                     onExpand: { mapFull = true })
                            .frame(height: min(360, max(260, UIScreen.main.bounds.height * 0.42)))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .listRowInsets(EdgeInsets())
                    }
                }
                // The recording's details right under the map: start, place, position (tap copies it).
                Section { detailChips(live) }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                // The Sensor Records of this recording, only once one has arrived: a pill per record opens its charts.
                if !bursts.isEmpty {
                    Section {
                        FlowPills(bursts: bursts)
                    } header: {
                        Label(String(format: L10n.get("activity_detail_boosts"), bursts.count), systemImage: "waveform.path.ecg")
                    }
                }
            }
        }
    }

    /// Seconds since the last live message counted as stale: about two missed messages (Android `STALE_AFTER_S`).
    static let staleAfter = 15

    /// The top card: the activity, the recording source (the watch, with a dot that turns amber when the live data is
    /// stale), the running clock large, then instant mode's six values and the technique shares, or the hint.
    @ViewBuilder
    private func hero(_ live: LiveActivityView, running: Int) -> some View {
        let tone = live.discarded ? CardTone.grey : CardTone.blue
        let age = feed.map { Int($0.ageSeconds) }
        let stale = (age ?? 0) >= Self.staleAfter
        // Compact (Android alike): the clock shares the first row with the recording source (the watch icon says where
        // it records) and never gives way, hours included; the watch's name does. The activity keeps its own row.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "watch.analog").font(.footnote)
                    Text(live.discarded ? String(format: L10n.get("watch_live_discarded_title"), live.watchName) : live.watchName)
                        .font(.footnote).lineLimit(1)
                    if let age, !live.discarded {
                        Circle().fill(stale ? Self.staleColour : Self.freshColour).frame(width: 8, height: 8)
                        if stale {
                            Text(String(format: L10n.get("recording_live_ago"), age)).font(.caption).foregroundStyle(Self.staleColour)
                        }
                    }
                }
                .foregroundStyle(tone.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.clockText(running)).font(.system(size: 36, weight: .bold)).monospacedDigit()
                    .lineLimit(1).fixedSize()
            }
            Text(live.title).font(.headline).lineLimit(2)
            if !live.discarded {
                if let feed {
                    VStack(alignment: .leading, spacing: 8) {
                        // Three a row, missing values (no pole rate, no technique on inline) left out, the last row padded.
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            let figures = Self.figures(feed).compactMap { $0 }
                            ForEach(Array(stride(from: 0, to: figures.count, by: 3)), id: \.self) { start in
                                GridRow {
                                    ForEach(start..<start + 3, id: \.self) { i in stat(i < figures.count ? figures[i] : nil) }
                                }
                            }
                        }
                        if !feed.shares.isEmpty {
                            GeometryReader { geo in
                                HStack(spacing: 0) {
                                    ForEach(feed.shares, id: \.key) { share in
                                        stateColor(share.key).frame(width: geo.size.width * CGFloat(share.percent) / 100)
                                    }
                                }
                            }
                            .frame(height: 10).clipShape(Capsule())
                            Text(feed.shares.map { "\(stateShort($0.key)) \(Int($0.percent)) %" }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    // Stale: the values fade, so an old number is never read as now.
                    .opacity(stale ? 0.5 : 1)
                } else {
                    Text(L10n.get("recording_live_hint")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    static let freshColour = Color(red: 0x2E / 255, green: 0x9E / 255, blue: 0x5B / 255)
    static let staleColour = Color(red: 0xC7 / 255, green: 0x77 / 255, blue: 0x00 / 255)

    /// A live value's number, unit (nil for text like a technique) and label; nil for a missing pole rate.
    struct Figure {
        let value: String
        let unit: String?
        let label: String
    }

    /// The six live values of [feed] (Android `liveFigures`), "–" where the watch had no reading.
    static func figures(_ feed: LiveFeedView) -> [Figure?] {
        [
            Figure(value: feed.heartRate >= 0 ? "\(feed.heartRate)" : "–", unit: "bpm", label: L10n.get("recording_live_hr")),
            // A run reads pace and walk/run; the other sports speed and technique (Android alike).
            feed.isRun
                ? Figure(value: paceText(kmh: feed.speedKmh) ?? "–", unit: "/km", label: L10n.get("watch_data_field_pace"))
                : Figure(value: feed.speedKmh.isNaN ? "–" : String(format: "%.1f", feed.speedKmh), unit: "km/h", label: L10n.get("recording_live_speed")),
            // No technique on inline (the watch classifies none): left out, not a lasting "–".
            feed.hasTechnique
                ? Figure(value: feed.techniqueKey.isEmpty ? "–" : stateShort(feed.techniqueKey), unit: nil,
                         label: L10n.get(feed.isRun ? "trends_v_walkrun" : "recording_live_technique"))
                : nil,
            Figure(value: feed.distanceM >= 0 ? String(format: "%.2f", Double(feed.distanceM) / 1000) : "–", unit: "km", label: L10n.get("recording_live_distance")),
            Figure(value: feed.gradePct.isNaN ? "–" : String(format: "%+.1f", feed.gradePct), unit: "%", label: L10n.get("recording_live_grade")),
            feed.poleRate >= 0 ? Figure(value: "\(feed.poleRate)", unit: "/min", label: L10n.get("recording_live_pole_rate")) : nil,
        ]
    }

    /// One live value: the number large with a smaller unit, the label under it.
    @ViewBuilder
    private func stat(_ figure: Figure?) -> some View {
        if let figure {
            VStack(alignment: .leading, spacing: 1) {
                (Text(figure.value).font(.system(size: 24, weight: .semibold))
                    + Text(figure.unit.map { $0 == "%" ? $0 : " \($0)" } ?? "").font(.system(size: 14, weight: .medium)))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(figure.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    /// The recording's details as small chips: start (the date only when not today), place, position (tap copies it).
    private func detailChips(_ live: LiveActivityView) -> some View {
        let start = Date(timeIntervalSince1970: TimeInterval(live.startEpochSec))
        let startText = Calendar.current.isDateInToday(start)
            ? start.formatted(date: .omitted, time: .shortened)
            : start.formatted(date: .numeric, time: .shortened)
        // Two decimals (about 1 km) on the chip; a tap copies the exact position.
        let position = live.hasPosition ? String(format: "%.2f, %.2f", live.lat, live.lon) : nil
        let exact = live.hasPosition ? String(format: "%.4f, %.4f", live.lat, live.lon) : nil
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips(startText, position, exact) }
            VStack(alignment: .leading, spacing: 8) { chips(startText, position, exact) }
        }
    }

    @ViewBuilder
    private func chips(_ startText: String, _ position: String?, _ exact: String?) -> some View {
        chip("\(L10n.get("recording_detail_started")) \(startText)")
        if let position {
            Button { UIPasteboard.general.string = exact ?? position } label: { chip(position) }.buttonStyle(.plain)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    /// "1:05:09" / "5:09": the running time, to the second.
    static func clockText(_ total: Int) -> String {
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Sensor Record pills

/// One Sensor Record as a pill (Android `SensorRecordPill`): a sensor mark, its time, "Charts" and an arrow.
struct SensorRecordPill: View {
    let burst: RecordingBoostView
    var onMap = false

    var body: some View {
        let time = Date(timeIntervalSince1970: TimeInterval(burst.burstId)).formatted(date: .omitted, time: .shortened)
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
            Text(time).font(.subheadline.weight(.semibold))
            Text(L10n.get("burst_charts_button")).font(.caption).opacity(0.75)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }
        .foregroundStyle(onMap ? Color(red: 0x1B / 255, green: 0x4F / 255, blue: 0x8F / 255) : Color.accentColor)
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
        .background(onMap ? Color.white.opacity(0.9) : Color.accentColor.opacity(0.10), in: Capsule())
        .accessibilityLabel(String(format: L10n.get("burst_open_item"), time))
    }
}

/// The records of the Recording screen as pills that wrap, each linking to its charts.
private struct FlowPills: View {
    let bursts: [RecordingBoostView]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pills }
            VStack(alignment: .leading, spacing: 8) { pills }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var pills: some View {
        ForEach(bursts, id: \.id) { burst in
            NavigationLink { SensorRecordView(burstId: burst.id) } label: { SensorRecordPill(burst: burst) }
                .buttonStyle(.plain)
        }
    }
}

// MARK: - Live track map

/// "4:58": minutes per km at [kmh]; nil when slower than 30:00/km or no reading (Android `paceText`).
func paceText(kmh: Double) -> String? {
    if kmh.isNaN || kmh < 2 { return nil }
    let seconds = Int(3600 / kmh)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

/// What the track is coloured by (Android `TrackColour`).
enum TrackColour: CaseIterable {
    case technique, speed, altitude

    func label(run: Bool) -> String {
        switch self {
        case .technique: return L10n.get("recording_map_colour_technique")
        case .speed: return L10n.get(run ? "watch_data_field_pace" : "recording_map_colour_speed")
        case .altitude: return L10n.get("recording_map_colour_altitude")
        }
    }
}

/// The map's choices (colouring, Summer/Winter), shared by the small map and its full screen so both show the same.
final class LiveMapChoices: ObservableObject {
    @Published var colourBy: TrackColour = .technique
    /// Summer / Winter picked by hand; nil follows the automatic map.
    @Published var season: String?
}

/// The track as plain arrays: per point the technique key ("" none), speed in km/h and altitude in m (NaN none).
struct TrackPoints {
    let lat: [Double]
    let lon: [Double]
    let technique: [String]
    let speedKmh: [Double]
    let altitudeM: [Double]
    /// A run: the speed colouring reads as pace.
    let isRun: Bool
    /// The watch reports a technique live (not on inline).
    let hasTechnique: Bool

    init(_ feed: LiveFeedView) {
        isRun = feed.isRun
        hasTechnique = feed.hasTechnique
        lat = feed.trackLat.map { $0.doubleValue }
        lon = feed.trackLon.map { $0.doubleValue }
        technique = feed.trackTechnique
        speedKmh = feed.trackSpeedKmh.map { $0.doubleValue }
        altitudeM = feed.trackAltitudeM.map { $0.doubleValue }
    }

    var count: Int { min(lat.count, lon.count) }
}

/// The colour of each track point (the stretch that ends there) and what the legend shows (Android `trackColours`):
/// the technique's colour, or a step of the mode's ramp between the track's lowest and highest value. Speed runs blue
/// to red, altitude pink to deep purple, so the two never look alike; missing values are grey.
struct TrackColours {
    let colours: [UIColor]
    let used: [String]
    let low: Double?
    let high: Double?
    /// Lowest and highest hardly differ (a flat track, a steady pace): one colour and one value in the legend.
    var flat: Bool { if let low, let high { return high - low < 1 } else { return false } }

    static let steps = 10
    static let noValue = UIColor(red: 0x9A / 255, green: 0xA4 / 255, blue: 0xAE / 255, alpha: 1)
    static func ramp(_ mode: TrackColour) -> (UIColor, UIColor) {
        mode == .altitude
            ? (UIColor(red: 0xF4 / 255, green: 0x8F / 255, blue: 0xC8 / 255, alpha: 1), UIColor(red: 0x5B / 255, green: 0x21 / 255, blue: 0xB6 / 255, alpha: 1))
            : (UIColor(red: 0x2F / 255, green: 0x6F / 255, blue: 0xDB / 255, alpha: 1), UIColor(red: 0xD6 / 255, green: 0x45 / 255, blue: 0x45 / 255, alpha: 1))
    }

    init(_ t: TrackPoints, _ mode: TrackColour) {
        let n = t.count
        if mode == .technique {
            let keys = Array(t.technique.prefix(n))
            colours = keys.map { $0.isEmpty ? Self.noValue : UIColor(stateColor($0)) }
            var seen: [String] = []
            for k in keys where !k.isEmpty && !seen.contains(k) { seen.append(k) }
            used = seen; low = nil; high = nil
            return
        }
        let values = Array((mode == .speed ? t.speedKmh : t.altitudeM).prefix(n))
        let present = values.filter { !$0.isNaN }
        let lo = present.min(), hi = present.max()
        let span = (lo != nil && hi != nil) ? hi! - lo! : 0
        let (a, b) = Self.ramp(mode)
        colours = values.map { v in
            guard !v.isNaN, let lo else { return Self.noValue }
            let step = span < 1 ? Self.steps / 2 : min(Self.steps - 1, max(0, Int((v - lo) / span * Double(Self.steps - 1))))
            return Self.mix(a, b, CGFloat(step) / CGFloat(Self.steps - 1))
        }
        used = []; low = lo; high = hi
    }

    /// Same colour by its components (UIColor objects made from SwiftUI colours are not equal by identity).
    static func same(_ a: UIColor, _ b: UIColor) -> Bool {
        var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.002 && abs(g1 - g2) < 0.002 && abs(b1 - b2) < 0.002
    }

    static func mix(_ a: UIColor, _ b: UIColor, _ f: CGFloat) -> UIColor {
        var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f, blue: b1 + (b2 - b1) * f, alpha: 1)
    }
}

/// The track so far on a map, after the Trail app's map concept (Android `LiveTrackMap`): swisstopo's winter map for snow
/// activities, its summer map for the others, OpenStreetMap outside Switzerland ([automatic], from the shared
/// `MapChoice`), a Summer / Winter switch, the credit always visible. The track is coloured by technique, speed or
/// altitude (switch top left, legend bottom left). It follows the whole track until the athlete drags or pinches; the
/// button brings the following back. [onExpand] shows the button to the full screen; [topInset] keeps room for the
/// full screen's data bar; [fullScreen] lets the map run under the notch and home indicator (the controls do not).
struct LiveTrackMap: View {
    let points: TrackPoints
    let automatic: String
    @ObservedObject var choices: LiveMapChoices
    var onExpand: (() -> Void)? = nil
    var topInset: CGFloat = 0
    var fullScreen = false
    @State private var following = true

    private var style: String { choices.season ?? automatic }

    var body: some View {
        let colours = TrackColours(points, colourBy)
        ZStack {
            TrackMapView(points: points, colours: colours, mode: colourBy, style: style, following: $following)
                .ignoresSafeArea(edges: fullScreen ? .all : [])
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    colourSwitch
                    Spacer(minLength: 8)
                    // Summer / Winter only on the full-screen map; the small one follows the activity type (Android alike).
                    if style != "OSM" && onExpand == nil { seasonSwitch }
                }
                .padding(.top, topInset)
                Spacer()
                HStack(alignment: .bottom) {
                    // The legend and the credit share one plate (the credit always visible).
                    VStack(alignment: .leading, spacing: 3) {
                        legend(colours)
                        Text(style == "OSM" ? "(c) OpenStreetMap contributors" : "(c) swisstopo")
                            .font(.system(size: 10)).foregroundStyle(Self.ink.opacity(0.75))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Self.plate, in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    if !following {
                        Button { following = true } label: {
                            Image(systemName: "location.fill").frame(width: 48, height: 48).background(Self.plate, in: Circle())
                        }
                        .accessibilityLabel(L10n.get("recording_map_follow"))
                    }
                    if let onExpand {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 48, height: 48).background(Self.plate, in: Circle())
                        }
                        .accessibilityLabel(L10n.get("chart_expand"))
                    }
                }
            }
            .padding(8)
        }
    }

    /// Map overlays stay light on the map in both themes (readable in sunlight): a near-white plate, dark ink.
    static let plate = Color.white.opacity(0.95)
    static let ink = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255)

    /// A segmented switch over the map: 40 points high, 13 pt, for gloves (Android `MapSwitch`).
    private func pill<Key: Equatable>(_ items: [(Key, String)], selected: Key, onPick: @escaping (Key) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let (key, label) = items[i]
                Button { onPick(key) } label: {
                    Text(label).font(.system(size: 13, weight: selected == key ? .semibold : .medium)).lineLimit(1)
                        .padding(.horizontal, 11).frame(minHeight: 40)
                        .foregroundStyle(selected == key ? Color.white : Color.accentColor)
                        .background(selected == key ? Color.accentColor : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Self.plate, in: Capsule())
    }

    /// What the track is coloured by: the choice, but speed on inline (no technique there; Android alike).
    private var colourBy: TrackColour {
        !points.hasTechnique && choices.colourBy == .technique ? .speed : choices.colourBy
    }

    private var colourSwitch: some View {
        pill(TrackColour.allCases.filter { $0 != .technique || points.hasTechnique }.map { ($0, $0.label(run: points.isRun)) },
             selected: colourBy) { choices.colourBy = $0 }
    }

    private var seasonSwitch: some View {
        pill([("SUMMER", L10n.get("recording_map_summer")), ("WINTER", L10n.get("recording_map_winter"))], selected: style) {
            choices.season = $0
        }
    }

    /// The techniques that occur, or the ramp with the track's lowest and highest value (one value when flat).
    @ViewBuilder
    private func legend(_ c: TrackColours) -> some View {
        let text = Self.ink
        if colourBy == .technique {
            if !c.used.isEmpty {
                HStack(spacing: 10) {
                    ForEach(c.used, id: \.self) { key in
                        HStack(spacing: 4) {
                            Circle().fill(stateColor(key)).frame(width: 10, height: 10)
                            Text(stateShort(key)).font(.system(size: 12)).foregroundStyle(text)
                        }
                    }
                }
            }
        } else if let low = c.low, let high = c.high {
            let speed = colourBy == .speed
            // On a run the speed ends read as pace: slowest left, fastest right, as the ramp runs.
            let pace = speed && points.isRun
            let unit = pace ? "/km" : speed ? "km/h" : "m"
            let fmt = speed ? "%.1f" : "%.0f"
            let label = { (v: Double) in pace ? (paceText(kmh: v) ?? "–") : String(format: fmt, v) }
            let (a, b) = TrackColours.ramp(colourBy)
            HStack(spacing: 6) {
                if c.flat {
                    Circle().fill(Color(c.colours.first { $0 != TrackColours.noValue } ?? TrackColours.noValue)).frame(width: 10, height: 10)
                    Text("\(label((low + high) / 2)) \(unit)").font(.system(size: 12)).foregroundStyle(text)
                } else {
                    Text(label(low)).font(.system(size: 12)).foregroundStyle(text)
                    LinearGradient(colors: [Color(a), Color(b)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 80, height: 8).clipShape(Capsule())
                    Text("\(label(high)) \(unit)").font(.system(size: 12)).foregroundStyle(text)
                }
            }
        }
    }
}

/// The live map on the whole screen (Android `LiveMapFullScreen`): the screen may turn with the phone while it is open,
/// the key data in a bar over the map's top, and a close button back to the Recording screen.
struct LiveMapFullScreen: View {
    let feed: LiveFeedView
    let startEpochSec: Int64
    /// The recording source, first in the data bar with a watch icon.
    let watchName: String
    @ObservedObject var choices: LiveMapChoices
    /// The newest Sensor Record of this recording, as a pill above the legend; nil when there is none.
    var latestRecord: RecordingBoostView? = nil
    let onClose: () -> Void
    @State private var barHeight: CGFloat = 52
    @State private var openRecord: String?
    /// Compact height: the phone is turned, the data bar takes one row.
    @Environment(\.verticalSizeClass) private var verticalSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .top) {
                LiveTrackMap(points: TrackPoints(feed), automatic: feed.baseMap, choices: choices,
                             topInset: barHeight + 8, fullScreen: true)
                dataBar(running: max(0, Int(context.date.timeIntervalSince1970) - Int(startEpochSec)))
                    .background(GeometryReader { g in Color.clear.preference(key: BarHeightKey.self, value: g.size.height) })
                    .padding(8)
                if let record = latestRecord {
                    VStack {
                        Spacer()
                        Button { openRecord = record.id } label: { SensorRecordPill(burst: record, onMap: true) }
                            .buttonStyle(.plain)
                            .padding(.bottom, 76)
                    }
                }
            }
        }
        // The full-screen cover has no navigation stack: the record's charts open in a sheet over the map.
        .sheet(isPresented: Binding(get: { openRecord != nil }, set: { if !$0 { openRecord = nil } })) {
            if let id = openRecord {
                NavigationStack { SensorRecordView(burstId: id) }
            }
        }
        .onPreferenceChange(BarHeightKey.self) { barHeight = $0 }
        .background(Color(.systemBackground).ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear { OrientationLock.allowTurning() }
        .onDisappear { OrientationLock.set(landscape: false) }
    }

    /// The key data over the map's top (Android `LiveMapFullScreen`): upright two rows (close, watch, clock; then five
    /// values), turned one row. Never scrolls sideways; the safe area keeps it clear of the notch.
    private func dataBar(running: Int) -> some View {
        let ink = Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255)
        let wide = verticalSize == .compact
        let figures = RecordingScreen.figures(feed).prefix(5).compactMap { $0 }
        let top = HStack(spacing: 6) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.get("chart_close"))
            // The recording source: the watch it runs on.
            Label(watchName, systemImage: "watch.analog")
                .font(.subheadline).foregroundStyle(ink).lineLimit(1)
                .frame(maxWidth: wide ? 180 : .infinity, alignment: .leading)
            Text(RecordingScreen.clockText(running))
                .font(.system(size: 28, weight: .bold)).monospacedDigit().foregroundStyle(ink).lineLimit(1)
                .layoutPriority(1)
        }
        return VStack(spacing: 2) {
            if wide {
                HStack(spacing: 12) {
                    top
                    ForEach(figures.indices, id: \.self) { i in figure(figures[i], ink: ink, size: 22) }
                }
            } else {
                top
                HStack(spacing: 4) {
                    ForEach(figures.indices, id: \.self) { i in figure(figures[i], ink: ink, size: 20) }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.leading, 2).padding(.trailing, 12).padding(.vertical, 2)
        .background(Color.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.12), lineWidth: 1))
    }

    /// A value of the data bar: the number over its unit (or its label for a technique), centred.
    private func figure(_ f: RecordingScreen.Figure, ink: Color, size: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(f.value).font(.system(size: size, weight: .semibold)).monospacedDigit().foregroundStyle(ink).lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(f.unit ?? f.label).font(.system(size: size >= 22 ? 13 : 11)).foregroundStyle(ink.opacity(0.7)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 52
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// MKMapView with a tile overlay replacing Apple's map (so the map is the same as on Android), the track as a white
/// casing under runs of one colour each, the start as a ring and the position now as a dot.
private struct TrackMapView: UIViewRepresentable {
    let points: TrackPoints
    let colours: TrackColours
    let mode: TrackColour
    let style: String
    @Binding var following: Bool

    // Never closer than this while following (a short track would otherwise fill the map at street level).
    private static let minSpanMeters: CLLocationDistance = 700

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        // A drag or pinch by the athlete stops the following.
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userMoved(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userMoved(_:)))
        let recognizers: [UIGestureRecognizer] = [pan, pinch]
        recognizers.forEach { $0.delegate = context.coordinator; map.addGestureRecognizer($0) }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.style != style {
            c.style = style
            if let old = c.tiles { map.removeOverlay(old) }
            let tiles = Self.tileOverlay(style)
            c.tiles = tiles
            map.insertOverlay(tiles, at: 0, level: .aboveLabels)
        }
        let points = zip(self.points.lat, self.points.lon).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        if c.drawnCount != points.count || c.drawnMode != mode {
            let moved = c.drawnCount != points.count
            c.drawnCount = points.count
            c.drawnMode = mode
            map.removeOverlays(c.lines)
            c.lines = []
            if points.count >= 2 {
                // A thin dark edge, the white casing and the coloured line on top (Android `LiveTrackMap`; field test
                // 2026-11-10: the line read too thin).
                let edge = TrackLine(coordinates: points, count: points.count)
                edge.colour = UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.55)
                edge.width = 10
                c.lines.append(edge)
                let casing = TrackLine(coordinates: points, count: points.count)
                casing.colour = .white
                casing.width = 8
                c.lines.append(casing)
                // The stretch into point i has point i's colour; a run ends where the colour changes.
                var runStart = 0
                for i in 2...points.count {
                    let colour = colours.colours.indices.contains(runStart + 1) ? colours.colours[runStart + 1] : TrackColours.noValue
                    let next = i < points.count && colours.colours.indices.contains(i) ? colours.colours[i] : nil
                    if i == points.count || next.map({ !TrackColours.same($0, colour) }) ?? true {
                        let run = Array(points[runStart..<i])
                        let line = TrackLine(coordinates: run, count: run.count)
                        line.colour = colour
                        line.width = 5
                        c.lines.append(line)
                        runStart = i - 1
                    }
                }
                c.lines.forEach { map.addOverlay($0, level: .aboveLabels) }
            }
            if moved {
                map.removeAnnotations(map.annotations)
                if let first = points.first { map.addAnnotation(Dot(coordinate: first, isStart: true)) }
                if let last = points.last, points.count > 1 { map.addAnnotation(Dot(coordinate: last, isStart: false)) }
                c.followed = false
            }
        }
        if following && !c.followed, !points.isEmpty {
            c.followed = true
            var rect = MKMapRect.null
            for p in points {
                let mp = MKMapPoint(p)
                rect = rect.union(MKMapRect(x: mp.x, y: mp.y, width: 0, height: 0))
            }
            let minSize = Self.minSpanMeters * MKMapPointsPerMeterAtLatitude(points[0].latitude)
            if rect.size.width < minSize || rect.size.height < minSize {
                let center = MKMapPoint(x: rect.midX, y: rect.midY)
                rect = MKMapRect(x: center.x - minSize / 2, y: center.y - minSize / 2, width: minSize, height: minSize)
            }
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24), animated: false)
        }
    }

    /// swisstopo's free web map tiles (Switzerland, "(c) swisstopo") or OpenStreetMap; same URLs as Android.
    private static func tileOverlay(_ style: String) -> MKTileOverlay {
        let template: String
        switch style {
        case "SUMMER": template = "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe/default/current/3857/{z}/{x}/{y}.jpeg"
        case "WINTER": template = "https://wmts.geo.admin.ch/1.0.0/ch.swisstopo.pixelkarte-farbe-winter/default/current/3857/{z}/{x}/{y}.jpeg"
        default: template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        }
        let overlay = AppTileOverlay(urlTemplate: template)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = style == "OSM" ? 19 : 17
        overlay.minimumZ = style == "OSM" ? 0 : 7
        return overlay
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TrackMapView
        var style: String?
        var tiles: MKTileOverlay?
        var lines: [TrackLine] = []
        var drawnMode: TrackColour?
        var drawnCount = -1
        var followed = false
        /// Following comes back by itself 20 s after the last drag or pinch (Android `REFOLLOW_AFTER_MS`).
        private var refollow: DispatchWorkItem?

        init(_ parent: TrackMapView) { self.parent = parent }

        @objc func userMoved(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                parent.following = false
                followed = false
                refollow?.cancel()
            }
            if gesture.state == .ended || gesture.state == .cancelled {
                refollow?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.followed = false
                    self.parent.following = true
                }
                refollow = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: item)
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let line = overlay as? TrackLine {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = line.colour
                r.lineWidth = line.width
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let dot = annotation as? Dot else { return nil }
            let view = MKAnnotationView(annotation: dot, reuseIdentifier: nil)
            let size: CGFloat = dot.isStart ? 14 : 16
            let circle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
            circle.layer.cornerRadius = size / 2
            circle.backgroundColor = dot.isStart ? .white : .systemBlue
            circle.layer.borderColor = (dot.isStart ? UIColor.systemBlue : UIColor.white).cgColor
            circle.layer.borderWidth = 3
            view.addSubview(circle)
            view.frame = circle.frame
            view.centerOffset = .zero
            return view
        }
    }
}

/// One stretch of the track in one colour (or the white casing under it).
private final class TrackLine: MKPolyline {
    var colour: UIColor = .systemBlue
    var width: CGFloat = 4
}

/// The track's start (a ring) or the position now (a dot).
private final class Dot: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool
    init(coordinate: CLLocationCoordinate2D, isStart: Bool) {
        self.coordinate = coordinate
        self.isStart = isStart
    }
}

/// A tile overlay that names the app to the tile servers (OpenStreetMap's tile policy asks for an app-specific
/// User-Agent).
// PRIVACY-SYNC: The live track map loads map tiles around the athlete's position from swisstopo or OpenStreetMap while the Recording screen shows a live track (instant mode, off by default). Notice section: Live track map. Changing this? Re-check the Companion's design/privacy-notice-sync.md.
private final class AppTileOverlay: MKTileOverlay {
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        var request = URLRequest(url: url(forTilePath: path))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        request.setValue("NordicSportsCompanion-iOS/\(version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        URLSession.shared.dataTask(with: request) { data, _, error in result(data, error) }.resume()
    }
}
