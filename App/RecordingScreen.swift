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
            .navigationTitle(L10n.get("recording_title"))
            .navigationBarTitleDisplayMode(.inline)
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
        .fullScreenCover(isPresented: $mapFull) {
            if let feed, !feed.trackLat.isEmpty {
                LiveMapFullScreen(feed: feed, startEpochSec: startEpochSec, choices: mapChoices, latestRecord: bursts.last) { mapFull = false }
            } else {
                Color.clear.onAppear { mapFull = false }
            }
        }
    }

    private func content(_ live: LiveActivityView) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: L10n.get(live.discarded ? "watch_live_discarded_title" : "watch_live_title"), live.watchName))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(live.title).font(.headline)
                        let running = max(0, Int(context.date.timeIntervalSince1970) - Int(live.startEpochSec))
                        Text(Self.clockText(running)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(live.discarded ? CardTone.grey.container : CardTone.blue.container)
                if !live.discarded { liveSection(live) }
                Section {
                    LabeledContent(L10n.get("recording_detail_watch"), value: live.watchName)
                    LabeledContent(L10n.get("recording_detail_started"),
                                   value: Date(timeIntervalSince1970: TimeInterval(live.startEpochSec)).formatted(date: .abbreviated, time: .shortened))
                    if live.hasPosition {
                        LabeledContent(L10n.get("recording_detail_position"), value: String(format: "%.4f, %.4f", live.lat, live.lon))
                    }
                }
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

    /// Instant mode's values (or the hint to switch it on): heart rate, speed, technique now and so far, the track.
    @ViewBuilder
    private func liveSection(_ live: LiveActivityView) -> some View {
        Section(L10n.get("recording_live_title")) {
            if let feed {
                let age = Int(feed.ageSeconds)
                Text(String(format: L10n.get(age > 30 ? "recording_live_stale" : "recording_live_age"), age))
                    .font(.footnote).foregroundStyle(age > 30 ? .red : .secondary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        value(L10n.get("recording_live_hr"), feed.heartRate >= 0 ? "\(feed.heartRate) bpm" : "–")
                        value(L10n.get("recording_live_speed"), feed.speedKmh.isNaN ? "–" : String(format: "%.1f km/h", feed.speedKmh))
                        value(L10n.get("recording_live_technique"), feed.techniqueKey.isEmpty ? "–" : stateShort(feed.techniqueKey))
                    }
                    GridRow {
                        value(L10n.get("recording_live_grade"), feed.gradePct.isNaN ? "–" : String(format: "%+.1f %%", feed.gradePct))
                        value(L10n.get("recording_live_distance"), feed.distanceM >= 0 ? String(format: "%.2f km", Double(feed.distanceM) / 1000) : "–")
                        value("", feed.poleRate >= 0 ? "\(feed.poleRate) / min" : "")
                    }
                }
                if !feed.shares.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.get("recording_live_shares")).font(.caption.weight(.semibold))
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                ForEach(feed.shares, id: \.key) { share in
                                    stateColor(share.key).frame(width: geo.size.width * CGFloat(share.percent) / 100)
                                }
                            }
                        }
                        .frame(height: 14).clipShape(Capsule())
                        Text(feed.shares.map { "\(stateShort($0.key)) \(Int($0.percent)) %" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !feed.trackLat.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.get("recording_live_track")).font(.caption.weight(.semibold))
                        LiveTrackMap(points: TrackPoints(feed), automatic: feed.baseMap, choices: mapChoices,
                                     onExpand: { mapFull = true })
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Text(L10n.get("recording_live_hint")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func value(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            if !label.isEmpty { Text(label).font(.caption2).foregroundStyle(.secondary) }
        }
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

/// What the track is coloured by (Android `TrackColour`).
enum TrackColour: CaseIterable {
    case technique, speed, altitude

    var label: String {
        switch self {
        case .technique: return L10n.get("recording_map_colour_technique")
        case .speed: return L10n.get("recording_map_colour_speed")
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

    init(_ feed: LiveFeedView) {
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
        let colours = TrackColours(points, choices.colourBy)
        ZStack {
            TrackMapView(points: points, colours: colours, mode: choices.colourBy, style: style, following: $following)
                .ignoresSafeArea(edges: fullScreen ? .all : [])
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    colourSwitch
                    Spacer(minLength: 8)
                    if style != "OSM" { seasonSwitch }
                }
                .padding(.top, topInset)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        legend(colours)
                        Text(style == "OSM" ? "(c) OpenStreetMap contributors" : "(c) swisstopo")
                            .font(.system(size: 10)).foregroundStyle(.black)
                            .padding(.horizontal, 4).background(Color.white.opacity(0.7))
                    }
                    Spacer()
                    if !following {
                        Button { following = true } label: {
                            Image(systemName: "location.fill").padding(10).background(.white.opacity(0.9), in: Circle())
                        }
                        .accessibilityLabel(L10n.get("recording_map_follow"))
                    }
                    if let onExpand {
                        Button(action: onExpand) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").padding(10).background(.white.opacity(0.9), in: Circle())
                        }
                        .accessibilityLabel(L10n.get("chart_expand"))
                    }
                }
            }
            .padding(8)
        }
    }

    private func pill<Key: Equatable>(_ items: [(Key, String)], selected: Key, onPick: @escaping (Key) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let (key, label) = items[i]
                Button { onPick(key) } label: {
                    Text(label).font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .foregroundStyle(selected == key ? Color.white : Color.accentColor)
                        .background(selected == key ? Color.accentColor : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.9), in: Capsule())
    }

    private var colourSwitch: some View {
        pill(TrackColour.allCases.map { ($0, $0.label) }, selected: choices.colourBy) { choices.colourBy = $0 }
    }

    private var seasonSwitch: some View {
        pill([("SUMMER", L10n.get("recording_map_summer")), ("WINTER", L10n.get("recording_map_winter"))], selected: style) {
            choices.season = $0
        }
    }

    /// The techniques that occur, or the ramp with the track's lowest and highest value (one value when flat).
    @ViewBuilder
    private func legend(_ c: TrackColours) -> some View {
        let text = Color(red: 0x1F / 255, green: 0x29 / 255, blue: 0x37 / 255)
        if choices.colourBy == .technique {
            if !c.used.isEmpty {
                HStack(spacing: 8) {
                    ForEach(c.used, id: \.self) { key in
                        HStack(spacing: 3) {
                            Circle().fill(stateColor(key)).frame(width: 8, height: 8)
                            Text(stateShort(key)).font(.system(size: 10)).foregroundStyle(text)
                        }
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            }
        } else if let low = c.low, let high = c.high {
            let speed = choices.colourBy == .speed
            let unit = speed ? "km/h" : "m"
            let fmt = speed ? "%.1f" : "%.0f"
            let (a, b) = TrackColours.ramp(choices.colourBy)
            HStack(spacing: 5) {
                if c.flat {
                    Circle().fill(Color(c.colours.first { $0 != TrackColours.noValue } ?? TrackColours.noValue)).frame(width: 8, height: 8)
                    Text(String(format: "\(fmt) %@", (low + high) / 2, unit)).font(.system(size: 10)).foregroundStyle(text)
                } else {
                    Text(String(format: fmt, low)).font(.system(size: 10)).foregroundStyle(text)
                    LinearGradient(colors: [Color(a), Color(b)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 56, height: 7).clipShape(Capsule())
                    Text(String(format: "\(fmt) %@", high, unit)).font(.system(size: 10)).foregroundStyle(text)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// The live map on the whole screen (Android `LiveMapFullScreen`): the screen may turn with the phone while it is open,
/// the key data in a bar over the map's top, and a close button back to the Recording screen.
struct LiveMapFullScreen: View {
    let feed: LiveFeedView
    let startEpochSec: Int64
    @ObservedObject var choices: LiveMapChoices
    /// The newest Sensor Record of this recording, as a pill above the legend; nil when there is none.
    var latestRecord: RecordingBoostView? = nil
    let onClose: () -> Void
    @State private var barHeight: CGFloat = 52
    @State private var openRecord: String?

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
                            .padding(.bottom, 56)
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

    private func dataBar(running: Int) -> some View {
        let ink = Color(red: 0x1F / 255, green: 0x29 / 255, blue: 0x37 / 255)
        let values: [String] = ([
            RecordingScreen.clockText(running),
            feed.heartRate >= 0 ? "\(feed.heartRate) bpm" : nil,
            feed.speedKmh.isNaN ? nil : String(format: "%.1f km/h", feed.speedKmh),
            feed.techniqueKey.isEmpty ? nil : stateShort(feed.techniqueKey),
            feed.distanceM >= 0 ? String(format: "%.2f km", Double(feed.distanceM) / 1000) : nil,
            feed.gradePct.isNaN ? nil : String(format: "%+.1f %%", feed.gradePct),
        ] as [String?]).compactMap { $0 }
        return HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(ink)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.get("chart_close"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(values.indices, id: \.self) { i in
                        Text(values[i])
                            .font(i == 0 ? .title2.weight(.bold) : .headline)
                            .monospacedDigit().foregroundStyle(ink).lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 14))
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
                let casing = TrackLine(coordinates: points, count: points.count)
                casing.colour = .white
                casing.width = 7
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
                        line.width = 4
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

        init(_ parent: TrackMapView) { self.parent = parent }

        @objc func userMoved(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began { parent.following = false; followed = false }
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
