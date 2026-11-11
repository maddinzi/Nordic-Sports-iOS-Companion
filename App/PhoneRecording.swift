import AudioToolbox
import CoreLocation
import NordicSportsShared
import SwiftUI

// Recording on the phone (Companion design/phone-recording.md, step 9): CoreLocation fixes go into the shared
// recorder (`CompanionCore.startPhoneRecording` ... `savePhoneRecording`), which keeps the points safe in
// `activity_tracks` while it runs; the screens show `PhoneRecordingView`.
// PRIVACY-SYNC: GPS positions of a recording the athlete starts on the phone, stored on the phone only (Strava only through
// the athlete's upload switch). Uses location "when in use" with the background mode location while recording. Changing
// this? Re-check the Companion's design/privacy-notice-sync.md.

/** The recording on this phone (Android `PhoneRecordingService` + `AndroidPhoneRecorder`). */
@MainActor
final class PhoneRecorderModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// The running or unsaved recording; nil without one.
    @Published private(set) var view: PhoneRecordingView?
    /// The newest horizontal accuracy in metres while the start screen or a recording listens; nil before the first fix.
    @Published private(set) var accuracy: Double?
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published var saving = false

    private let manager = CLLocationManager()
    private weak var companion: Companion?
    private var timer: Timer?
    private var recording = false
    private var listening = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var allowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }

    /// Hooks the model to the app's core and gives back an unfinished recording an earlier run left.
    func attach(_ companion: Companion) async {
        self.companion = companion
        if (try? await companion.core.recoverPhoneRecording())?.boolValue == true { refresh() }
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    /// The start screen listens for the GPS state.
    func listen() {
        guard allowed, !listening else { return }
        listening = true
        manager.startUpdatingLocation()
    }

    func stopListening() {
        guard listening, !recording else { return }
        listening = false
        manager.stopUpdatingLocation()
    }

    /// Starts the recording and, where the preset records with GPS, the location; false (the error posted) when the
    /// shared recorder refused it. [guideId] is a plan or routine from the start screen ("free" for none).
    @discardableResult
    func start(
        preset: String, purpose: String, uploadToStrava: Bool,
        guideId: String = "free", autoNext: Bool = false, autoLapM: Int = 0, autoPause: Bool = false
    ) async -> Bool {
        guard let core = companion?.core else { return false }
        do {
            try await core.startGuidedPhoneRecording(
                preset: preset, trainingType: purpose, uploadToStrava: uploadToStrava, guideId: guideId,
                autoNext: autoNext, autoLapM: Int32(autoLapM), autoPause: autoPause
            )
        } catch {
            companion?.post(error.localizedDescription)
            return false
        }
        recording = true
        // Strength and the other training presets record without GPS, as on the watch.
        if PhoneRecordingCatalog.shared.usesGps(preset: preset) {
            listening = true
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
            manager.startUpdatingLocation()
        } else {
            listening = false
            manager.stopUpdatingLocation()
        }
        timer?.invalidate()
        // Once a second: auto pause and lap, the plan or the sets by the clock, each step cued.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        refresh()
        return true
    }

    private func tick() async {
        if let cue = try? await companion?.core.phoneRecordingTick() { GuideCues.play(cue) }
        refresh()
    }

    /// The lap key of a guided recording: next interval step, or start / end a strength set.
    func guideNext() async {
        if let cue = try? await companion?.core.phoneRecordingGuideNext() { GuideCues.play(cue) }
        refresh()
    }

    /// Corrects the last strength set, as the watch's set menu after a set does.
    func correctLastSet(exercise: Int32, reps: Int32, weightTenthKg: Int32) async {
        _ = try? await companion?.core.correctLastPhoneSet(exercise: exercise, reps: reps, weightTenthKg: weightTenthKg)
        refresh()
    }

    var exercises: [PhoneExerciseView] { companion?.core.phoneExercises() ?? [] }

    func pause() async { _ = try? await companion?.core.pausePhoneRecording(); refresh() }

    func resume() async { _ = try? await companion?.core.resumePhoneRecording(); refresh() }

    /// "Hold to stop": the recording waits for Save or Discard (the watch's menu), the GPS goes off.
    func stop() async {
        _ = try? await companion?.core.stopPhoneRecording()
        endLocation()
        refresh()
    }

    /// Stores the activity; returns the id to open (the watch activity's when the recording went into it).
    func save() async -> String? {
        guard let companion else { return nil }
        saving = true
        defer { saving = false }
        do {
            let id = try await companion.core.savePhoneRecording()
            endLocation()
            view = nil
            companion.post(L10n.get("main_toast_activity_saved"))
            await companion.refresh()
            // The upload and the diary follow like for any other activity.
            Task { await companion.sync() }
            return id
        } catch {
            companion.post(error.localizedDescription)
            return nil
        }
    }

    func discard() async {
        _ = try? await companion?.core.discardPhoneRecording()
        endLocation()
        view = nil
    }

    private func endLocation() {
        recording = false
        listening = false
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    private func refresh() { view = companion?.core.phoneRecordingView() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.allowed && !self.listening && self.view == nil { self.listen() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fixes = locations.filter { $0.horizontalAccuracy >= 0 }
        guard !fixes.isEmpty else { return }
        Task { @MainActor in
            self.accuracy = fixes.last?.horizontalAccuracy
            guard self.recording, let core = self.companion?.core else { return }
            for loc in fixes {
                _ = try? await core.phoneRecordingFix(
                    atEpochMillis: Int64(loc.timestamp.timeIntervalSince1970 * 1000),
                    lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, accuracyM: loc.horizontalAccuracy,
                    altitudeM: loc.verticalAccuracy >= 0 ? loc.altitude : .nan,
                    speedMps: loc.speed >= 0 ? loc.speed : .nan
                )
            }
            self.refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Cues

/// Vibration and a sound per cue of the shared recorder (Android `GuideCues`, the watch's `Feedback`): a step change and
/// an auto lap once, the 3-2-1 a short tick, "Go!", the end of the plan and auto pause twice.
enum GuideCues {
    static func play(_ cue: String) {
        switch cue {
        case "":
            return
        case "COUNTDOWN":
            AudioServicesPlaySystemSound(1104) // keyboard tick
        case "STEP", "LAP", "AUTO_RESUME":
            AudioServicesPlayAlertSound(SystemSoundID(1057))
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        default: // GO, DONE, AUTO_PAUSE
            AudioServicesPlayAlertSound(SystemSoundID(1005))
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { AudioServicesPlaySystemSound(kSystemSoundID_Vibrate) }
        }
    }
}

// MARK: - Formatting

private func clock(_ seconds: Int64) -> String {
    let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/** Speed in km/h, or pace in min/km for a run; "–" without a value. */
private func speedText(_ kmh: Double, run: Bool) -> (String, String) {
    guard !kmh.isNaN, kmh > 0.5 else { return ("–", run ? "/km" : "km/h") }
    if run {
        let secPerKm = Int((3600 / kmh).rounded())
        return (String(format: "%d:%02d", secPerKm / 60, secPerKm % 60), "/km")
    }
    return (kmh.formatted(.number.precision(.fractionLength(1))), "km/h")
}

// MARK: - Start screen

/// "Record on the phone" (Android `PhoneRecordStartScreen`): activity, style and purpose (the last ones preselected),
/// the plan (Intervals, Sprints) or routine (Strength, Stabi), "Next set starts by itself", auto lap and auto pause
/// (the watch's values for the sport), the Strava switch, the GPS state and Start; asks for the location first. The
/// training presets record without GPS and start at once. The choices come from `CompanionCore.phoneStartView`.
struct PhoneRecordStartScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var phone: PhoneRecorderModel
    let onStarted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("phone_preset") private var preset = "rollskiSkating"
    @AppStorage("phone_purpose") private var endurancePurpose = "endurance"
    @AppStorage("phone_strength_purpose") private var strengthPurpose = "hypertrophy"
    @AppStorage("phone_plan") private var planId = "free"
    @AppStorage("phone_routine") private var routineId = "free"
    @AppStorage("phone_auto_next") private var autoNext = false
    @AppStorage("phone_auto_lap") private var lastAutoLap = 0
    @AppStorage("phone_auto_pause") private var lastAutoPause = false
    /// This recording's auto lap and auto pause, nil while they follow [start]'s defaults.
    @State private var autoLapChoice: Int?
    @State private var autoPauseChoice: Bool?
    @State private var toStrava = true
    @State private var openedAt = Date()
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let readyM = 15.0
    private static let anywayAfter: TimeInterval = 30

    private var catalog: PhoneRecordingCatalog { PhoneRecordingCatalog.shared }
    private var family: PhoneRecordingCatalog.Family { catalog.familyOf(preset: preset) ?? catalog.families[0] }
    private var ready: Bool { (phone.accuracy ?? .infinity) <= Self.readyM }
    private var strengthPurposes: Bool { preset == PhoneRecordingCatalog.shared.STRENGTH }
    private var purpose: String { strengthPurposes ? strengthPurpose : endurancePurpose }
    private var start: PhoneStartView {
        companion.core.phoneStartView(preset: preset, trainingType: purpose, lastAutoLapM: Int32(lastAutoLap), lastAutoPause: lastAutoPause)
    }
    private var logsSets: Bool { PhoneRecordingCatalog.shared.logsStrength(preset: preset) }
    private var guideId: String {
        let wanted = logsSets ? routineId : planId
        let guides = start.guides
        return guides.first { $0.id == wanted }?.id ?? guides.first?.id ?? "free"
    }
    private var startAnyway: Bool { phone.allowed && !ready && now.timeIntervalSince(openedAt) >= Self.anywayAfter }

    var body: some View {
        NavigationStack {
            Form {
                if !companion.liveActivities.isEmpty {
                    Section { Text(L10n.get("phone_start_watch_recording")).font(.subheadline) }
                        .listRowBackground(CardTone.yellow.container)
                }
                Section(L10n.get("phone_start_activity")) {
                    ChipFlow(spacing: 8) {
                        ForEach(catalog.families.indices, id: \.self) { i in
                            let f = catalog.families[i]
                            chip(L10n.get(f.labelKey), on: f.key == family.key) {
                                if f.key != family.key { preset = f.styles[0].preset; resetAuto() }
                            }
                        }
                    }
                }
                if family.styles.count > 1 {
                    Section(L10n.get("phone_start_style")) {
                        ChipFlow(spacing: 8) {
                            ForEach(family.styles.indices, id: \.self) { i in
                                let s = family.styles[i]
                                chip(L10n.get(s.labelKey), on: s.preset == preset) { preset = s.preset; resetAuto() }
                            }
                        }
                    }
                }
                let s = start
                // Walk and the training presets but Strength have no purpose (as on the watch): Endurance.
                if s.hasPurpose {
                    Section(L10n.get("phone_start_purpose")) {
                        ChipFlow(spacing: 8) {
                            ForEach(s.purposes, id: \.id) { p in
                                chip(p.label, on: p.id == purpose) {
                                    if strengthPurposes { strengthPurpose = p.id } else { endurancePurpose = p.id }
                                }
                            }
                        }
                    }
                }
                // The plan (Intervals, Sprints) or routine (Strength, Stabi), as the watch's picker: Free first.
                if !s.guideTitle.isEmpty {
                    Section(s.guideTitle) {
                        ForEach(s.guides, id: \.id) { g in
                            Button {
                                if logsSets { routineId = g.id } else { planId = g.id }
                            } label: {
                                HStack {
                                    Text(g.label).foregroundStyle(Color.primary)
                                    Spacer()
                                    if g.id == guideId { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                                }
                            }
                        }
                    }
                }
                if s.offersAutoNext {
                    Section { Toggle(L10n.get("phone_start_auto_next"), isOn: $autoNext) }
                }
                if s.offersAuto {
                    Section {
                        HStack {
                            Text(L10n.get("watch_setting_auto_lap"))
                            Spacer()
                            ForEach(s.autoLapChoices, id: \.id) { c in
                                chip(c.label, on: Int(c.id) == autoLap(s)) { autoLapChoice = Int(c.id) ?? 0 }
                            }
                        }
                        Toggle(L10n.get("watch_setting_auto_pause"), isOn: Binding(get: { autoPause(s) }, set: { autoPauseChoice = $0 }))
                    } footer: {
                        if s.autoFromWatch { Text(L10n.get("phone_start_auto_from_watch")) }
                    }
                }
                if companion.stravaConnected {
                    Section { Toggle(L10n.get("phone_start_strava"), isOn: $toStrava) }
                }
                Section {
                    if !s.usesGps {
                        Text(L10n.get("phone_start_strength_no_gps")).font(.subheadline).foregroundStyle(.secondary)
                        startButton(s)
                    } else if !phone.allowed {
                        Text(L10n.get("phone_start_permission_needed"))
                        if phone.authorization == .denied || phone.authorization == .restricted {
                            Button(L10n.get("phone_start_permission_settings")) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        } else {
                            Button(L10n.get("phone_start_permission_button")) { phone.requestPermission() }
                        }
                    } else {
                        HStack(spacing: 8) {
                            if ready {
                                Circle().fill(Color.green).frame(width: 10, height: 10)
                            } else {
                                ProgressView()
                            }
                            Text(gpsText).foregroundStyle(ready ? Color.green : Color.secondary)
                        }
                        startButton(s)
                    }
                }
            }
            .homeTitle(L10n.get("phone_start_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.get("common_cancel")) { dismiss() } }
            }
            .onAppear {
                toStrava = companion.core.stravaUploadPhoneRecordings()
                openedAt = Date()
                if phone.allowed { phone.listen() } else if phone.authorization == .notDetermined { phone.requestPermission() }
            }
            .onDisappear { phone.stopListening() }
            .onReceive(tick) { now = $0 }
        }
    }

    private func autoLap(_ s: PhoneStartView) -> Int { autoLapChoice ?? Int(s.autoLapM) }

    private func autoPause(_ s: PhoneStartView) -> Bool { autoPauseChoice ?? s.autoPause }

    /// Another sport: auto lap and auto pause follow its own values again.
    private func resetAuto() {
        autoLapChoice = nil
        autoPauseChoice = nil
    }

    private func startButton(_ s: PhoneStartView) -> some View {
        Button {
            Task {
                let lap = s.offersAuto ? autoLap(s) : 0
                let pause = s.offersAuto && autoPause(s)
                if s.offersAuto {
                    lastAutoLap = lap
                    lastAutoPause = pause
                }
                // A refused start stays here with its message, instead of an empty live screen.
                if await phone.start(
                    preset: preset, purpose: s.hasPurpose ? purpose : "endurance", uploadToStrava: companion.stravaConnected && toStrava,
                    guideId: guideId, autoNext: s.offersAutoNext && autoNext, autoLapM: lap, autoPause: pause
                ) {
                    dismiss()
                    onStarted()
                }
            }
        } label: {
            Label(L10n.get(startAnyway && s.usesGps ? "phone_start_anyway" : "phone_start_button"), systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(s.usesGps && !(ready || startAnyway))
    }

    private var gpsText: String {
        guard let accuracy = phone.accuracy else { return L10n.get("phone_start_gps_waiting") }
        return String(format: L10n.get(ready ? "phone_start_gps_ready" : "phone_start_gps_weak"), Int(accuracy.rounded()))
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(on ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.accentColor : Color(.separator), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Live screen

/// The live screen of a recording on the phone (Android `PhoneRecordingScreen`): the clock, four values and the map,
/// Pause / Resume and Stop (held); Stop asks Save / Resume / Discard; an unfinished recording asks at once.
struct PhoneRecordingLiveScreen: View {
    @EnvironmentObject var companion: Companion
    @ObservedObject var phone: PhoneRecorderModel
    let onSaved: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mapChoices: LiveMapChoices = {
        let c = LiveMapChoices()
        c.colourBy = .speed
        return c
    }()
    @State private var askStop = false
    @State private var askDiscard = false
    @State private var correcting = false

    var body: some View {
        NavigationStack {
            Group {
                if let v = phone.view {
                    content(v)
                } else {
                    ProgressView()
                }
            }
            .homeTitle(L10n.get("phone_recording_notification_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .confirmationDialog(L10n.get("phone_stop_title"), isPresented: $askStop, titleVisibility: .visible) {
                Button(L10n.get("phone_stop_save")) {
                    Task {
                        if let id = await phone.save() {
                            dismiss()
                            onSaved(id)
                        }
                    }
                }
                if phone.view?.status != "STOPPED" {
                    Button(L10n.get("phone_recording_action_resume")) { Task { await phone.resume() } }
                }
                Button(L10n.get("phone_stop_discard"), role: .destructive) { askDiscard = true }
            } message: {
                if phone.view?.status == "STOPPED" { Text(L10n.get("phone_unfinished_body")) }
            }
            .alert(L10n.get("phone_discard_confirm"), isPresented: $askDiscard) {
                Button(L10n.get("phone_stop_discard"), role: .destructive) {
                    Task {
                        await phone.discard()
                        dismiss()
                    }
                }
                Button(L10n.get("common_cancel"), role: .cancel) {}
            }
            .overlay { if phone.saving { BusyOverlayView(text: L10n.get("phone_saving")) } }
            .onAppear { if phone.view?.status == "STOPPED" { askStop = true } }
            .sheet(isPresented: $correcting) {
                if let g = phone.view?.guide {
                    CorrectSetSheet(phone: phone, exercise: g.lastExercise, reps: g.lastReps, weightTenthKg: g.lastWeightTenthKg)
                }
            }
        }
    }

    @ViewBuilder private func content(_ v: PhoneRecordingView) -> some View {
        let speed = speedText(v.speedKmh, run: v.isRun)
        let avg = speedText(v.avgKmh, run: v.isRun)
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(Format.presetWord(v.preset), systemImage: "iphone").font(.headline)
                Spacer()
                if v.status == "PAUSED" {
                    Text(L10n.get(v.autoPaused ? "phone_auto_paused" : "phone_recording_notification_paused"))
                        .font(.subheadline).foregroundStyle(.orange)
                } else if v.usesGps && !v.hasFix {
                    Text(L10n.get("phone_recording_notification_waiting_gps")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text(clock(v.movingSec)).font(.system(size: v.guide == nil ? 48 : 32, weight: .semibold).monospacedDigit())
            if let g = v.guide {
                GuidePanel(guide: g, running: v.status == "RECORDING", onNext: { Task { await phone.guideNext() } }, onCorrect: { correcting = true })
            }
            if v.usesGps {
                Grid(horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        value(speed.0, speed.1, L10n.get(v.isRun ? "watch_data_field_pace" : "recording_live_speed"))
                        value(avg.0, avg.1, L10n.get("phone_live_avg"))
                    }
                    GridRow {
                        value((v.distanceM / 1000).formatted(.number.precision(.fractionLength(2))), "km", L10n.get("recording_live_distance"))
                        value("\(Int(v.ascentM.rounded()))", "m", L10n.get("activity_detail_ascent_label"))
                    }
                }
            }
            if v.usesGps, let map = v.map {
                LiveTrackMap(points: TrackPoints(map), automatic: map.baseMap, choices: mapChoices)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Spacer()
            }
            HStack(spacing: 12) {
                if v.status == "PAUSED" {
                    Button { Task { await phone.resume() } } label: {
                        Label(L10n.get("phone_recording_action_resume"), systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else if v.status == "RECORDING" {
                    Button { Task { await phone.pause() } } label: {
                        Label(L10n.get("phone_recording_action_pause"), systemImage: "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                // Stop by press-and-hold, so a pocket tap never ends the recording (as the watch's menu).
                Label(L10n.get("phone_live_stop_hold"), systemImage: "stop.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.red)
                    .onLongPressGesture(minimumDuration: 1) {
                        Task {
                            if v.status != "STOPPED" { await phone.pause() }
                            askStop = true
                        }
                    }
            }
            .controlSize(.large)
        }
        .padding()
    }

    private func value(_ number: String, _ unit: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(number).font(.title2.weight(.semibold).monospacedDigit())
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The guided part of the live screen (Android `PhoneGuidePanel`): the step or set in large type with its progress, what
/// comes next, the lap key as a large button, and the last set with "Correct".
private struct GuidePanel: View {
    let guide: PhoneGuidePanelView
    let running: Bool
    let onNext: () -> Void
    let onCorrect: () -> Void

    var body: some View {
        let counting = guide.countdown > 0
        let accent: Color = counting ? .green : .accentColor
        VStack(alignment: .leading, spacing: 8) {
            Text(guide.heading).font(.headline).foregroundStyle(accent)
            if !guide.main.isEmpty {
                Text(counting ? "\(guide.countdown)" : guide.main)
                    .font(.system(size: 52, weight: .bold).monospacedDigit())
                    .foregroundStyle(counting ? accent : Color.primary)
            }
            if guide.progress > 0 {
                ProgressView(value: Double(guide.progress)).tint(accent)
            }
            if !guide.below.isEmpty { Text(guide.below).font(.body) }
            if !guide.action.isEmpty && running {
                Button(action: onNext) {
                    Text(guide.action).font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            if !guide.lastSet.isEmpty {
                HStack {
                    Text(guide.lastSet).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.get("watch_intervals_edit"), action: onCorrect).font(.subheadline)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent, lineWidth: 1.5))
    }
}

/// Exercise, reps (or seconds) and weight of the last set, as the watch's set menu offers them (Android `CorrectSetDialog`).
private struct CorrectSetSheet: View {
    @ObservedObject var phone: PhoneRecorderModel
    @State var exercise: Int32
    @State var reps: Int32
    @State var weightTenthKg: Int32
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let exercises = phone.exercises
        let hold = exercises.first { $0.id == exercise }?.isHold ?? false
        NavigationStack {
            Form {
                Picker(L10n.get("watch_strength_exercise"), selection: $exercise) {
                    ForEach(exercises, id: \.id) { e in Text(e.label).tag(e.id) }
                }
                Stepper(value: $reps, in: 1...999) {
                    HStack {
                        Text(L10n.get(hold ? "watch_strength_seconds" : "watch_strength_reps"))
                        Spacer()
                        Text("\(reps)").monospacedDigit()
                    }
                }
                Stepper(value: $weightTenthKg, in: 0...3000, step: 25) {
                    HStack {
                        Text(L10n.get("watch_strength_weight"))
                        Spacer()
                        Text(weightTenthKg == 0 ? L10n.get("watch_strength_bodyweight") : "\((Double(weightTenthKg) / 10).formatted()) kg").monospacedDigit()
                    }
                }
            }
            .navigationTitle(L10n.get("phone_guide_correct_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.get("common_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("watch_intervals_save")) {
                        Task {
                            await phone.correctLastSet(exercise: exercise, reps: reps, weightTenthKg: weightTenthKg)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The running recording on the activity list (Android `PhoneRecordingCard`): a tap opens the live screen.
struct PhoneRecordingCard: View {
    let view: PhoneRecordingView
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "iphone").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.get(view.status == "STOPPED" ? "phone_unfinished_title" : "phone_recording_notification_title"))
                        .font(.headline)
                    Text("\(Format.presetWord(view.preset)) · \(clock(view.movingSec)) · \((view.distanceM / 1000).formatted(.number.precision(.fractionLength(2)))) km")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The list's section for the recording on this phone; empty without one.
struct PhoneRecordingSection: View {
    @ObservedObject var phone: PhoneRecorderModel
    let onOpen: () -> Void

    var body: some View {
        if let view = phone.view {
            Section { PhoneRecordingCard(view: view, onOpen: onOpen) }
                .listRowBackground(CardTone.green.container)
        }
    }
}
