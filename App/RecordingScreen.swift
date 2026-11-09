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
        .onChange(of: live == nil) { _, gone in if gone { dismiss() } }
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
                Section(String(format: L10n.get("activity_detail_boosts"), bursts.count)) {
                    if bursts.isEmpty {
                        Text(L10n.get("recording_records_none")).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(bursts, id: \.id) { burst in
                            Text(String(format: L10n.get("burst_open_item"),
                                        Date(timeIntervalSince1970: TimeInterval(burst.burstId)).formatted(date: .omitted, time: .shortened)))
                        }
                    }
                }
                if !live.discarded {
                    Section { Text(L10n.get("watch_live_hint")).font(.footnote).foregroundStyle(.secondary) }
                        .listRowBackground(Color.clear)
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
                        LiveTrackMap(lat: feed.trackLat.map { $0.doubleValue }, lon: feed.trackLon.map { $0.doubleValue },
                                     automatic: feed.baseMap)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text(String(format: L10n.get("recording_live_stats"), Int(feed.messages), Int(feed.missed)))
                    .font(.footnote).foregroundStyle(.secondary)
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

// MARK: - Live track map

/// The track so far on a map, after the Trail app's map concept (Android `LiveTrackMap`): swisstopo's winter map for snow
/// activities, its summer map for the others, OpenStreetMap outside Switzerland ([automatic], from the shared
/// `MapChoice`), a Summer / Winter switch for this screen only, the credit always visible. It follows the whole track
/// until the athlete drags or pinches; the button brings the following back.
struct LiveTrackMap: View {
    let lat: [Double]
    let lon: [Double]
    let automatic: String
    @State private var chosen: String?
    @State private var following = true

    private var style: String { chosen ?? automatic }

    var body: some View {
        ZStack {
            TrackMapView(lat: lat, lon: lon, style: style, following: $following)
            VStack {
                HStack {
                    Spacer()
                    if style != "OSM" { seasonSwitch }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Text(style == "OSM" ? "(c) OpenStreetMap contributors" : "(c) swisstopo")
                        .font(.system(size: 10)).foregroundStyle(.black)
                        .padding(.horizontal, 4).background(Color.white.opacity(0.7))
                    Spacer()
                    if !following {
                        Button { following = true } label: {
                            Image(systemName: "location.fill").padding(10).background(.white.opacity(0.9), in: Circle())
                        }
                        .accessibilityLabel(L10n.get("recording_map_follow"))
                    }
                }
            }
            .padding(8)
        }
    }

    private var seasonSwitch: some View {
        HStack(spacing: 0) {
            ForEach([("SUMMER", "recording_map_summer"), ("WINTER", "recording_map_winter")], id: \.0) { key, label in
                Button { chosen = key } label: {
                    Text(L10n.get(label)).font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(style == key ? Color.white : Color.accentColor)
                        .background(style == key ? Color.accentColor : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.9), in: Capsule())
    }
}

/// MKMapView with a tile overlay replacing Apple's map (so the map is the same as on Android), the track as a line, the
/// start as a ring and the position now as a dot.
private struct TrackMapView: UIViewRepresentable {
    let lat: [Double]
    let lon: [Double]
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
        let points = zip(lat, lon).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) }
        if c.drawnCount != points.count {
            c.drawnCount = points.count
            if let line = c.line { map.removeOverlay(line) }
            if points.count >= 2 {
                let line = MKPolyline(coordinates: points, count: points.count)
                c.line = line
                map.addOverlay(line, level: .aboveLabels)
            }
            map.removeAnnotations(map.annotations)
            if let first = points.first { map.addAnnotation(Dot(coordinate: first, isStart: true)) }
            if let last = points.last, points.count > 1 { map.addAnnotation(Dot(coordinate: last, isStart: false)) }
            c.followed = false
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
        var line: MKPolyline?
        var drawnCount = -1
        var followed = false

        init(_ parent: TrackMapView) { self.parent = parent }

        @objc func userMoved(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began { parent.following = false; followed = false }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = UIColor.systemBlue
                r.lineWidth = 4
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
