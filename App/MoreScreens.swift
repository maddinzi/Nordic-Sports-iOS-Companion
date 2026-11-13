import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

// Roadmap step 5.3, 5.4 and 5.6 on iOS: the watch app's settings, adding an activity by
// hand, the transparency logs and feedback. Logic and texts come from the shared core
// (CompanionCore); these views only show and forward.

// MARK: - Watch settings

struct WatchSettingsScreen: View {
    @EnvironmentObject var companion: Companion
    /// Watch settings that cost extra watch battery (Sensor Records, Instant Mode): their own section.
    static let batteryKeys: Set<String> = ["RecordingBoostEnabled", "InstantMode"]

    var body: some View {
        Form {
            Section { Text(L10n.get("settings_intro_watch")).font(.footnote).foregroundStyle(.secondary) }
            if companion.watchSettings.isEmpty {
                Text(L10n.get("watch_settings_none")).foregroundStyle(.secondary)
            }
            ForEach(companion.watchSettings, id: \.deviceId) { watch in
                Section {
                    Text(String(format: L10n.get("watch_settings_as_of"), Format.dateOrTimeToday(watch.reportedAtEpochSec)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if watch.pendingCount > 0 {
                        Text(L10n.plural("watch_settings_waiting", Int(watch.pendingCount)))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        // Changes wait and the watch has been silent for hours: the link is probably stuck.
                        if Date().timeIntervalSince1970 - TimeInterval(watch.reportedAtEpochSec) > 3600 {
                            Text(L10n.get("watch_settings_stale_hint"))
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    Button(L10n.get("watch_settings_refresh")) { companion.askWatchAgain(deviceId: watch.deviceId) }
                    if let sync = watch.sync {
                        WatchSyncRow(sync: sync)
                    }
                    if !watch.dataFieldGroups.isEmpty {
                        NavigationLink(L10n.get("watch_data_fields_title")) { WatchDataFieldsScreen(deviceId: watch.deviceId) }
                    }
                    if !watch.intervalSlots.isEmpty {
                        NavigationLink(L10n.get("watch_interval_menu")) { WatchPlansScreen(deviceId: watch.deviceId, routines: false) }
                    }
                    if !watch.routineSlots.isEmpty {
                        NavigationLink(L10n.get("watch_strength_routines")) { WatchPlansScreen(deviceId: watch.deviceId, routines: true) }
                    }
                    // Skill level per sport right after the strength routines (a watch that reports them, 0.9.118+).
                    if let skillLevel = watch.skillLevel {
                        NavigationLink(skillLevel.title) { WatchSkillLevelScreen(deviceId: watch.deviceId) }
                    }
                    if !watch.dataFieldGroups.isEmpty || !watch.intervalSlots.isEmpty || !watch.routineSlots.isEmpty {
                        NavigationLink { WatchShareScreen(deviceId: watch.deviceId) } label: {
                            Label(L10n.get("watch_share_title"), systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text(watch.watchName)
                }
                if let hr = watch.hrStrap {
                    Section(hr.title) {
                        Text(hr.status).foregroundStyle(hr.notFound ? Color.red : Color.primary)
                        Text(hr.checked).font(.footnote).foregroundStyle(.secondary)
                        ForEach(hr.lines, id: \.label) { line in
                            LabeledContent(line.label, value: line.value)
                        }
                    }
                }
                ForEach(watch.groups, id: \.title) { group in
                    let instantOn = watch.groups.flatMap { $0.items }.contains { $0.key == "InstantMode" && $0.value != 0 }
                    let battery = group.items.filter { Self.batteryKeys.contains($0.key) }
                    Section(group.title) {
                        ForEach(group.items.filter { !Self.batteryKeys.contains($0.key) }, id: \.key) { item in
                            WatchSettingRow(deviceId: watch.deviceId, item: item, instantModeOn: instantOn)
                        }
                        // Auto lap and auto pause per sport end the Recording group, next to the main settings
                        // (only a watch that reports per-sport values, 0.9.117+).
                        if group.title == L10n.get("watch_group_recording"), let auto = watch.sportAuto {
                            NavigationLink(auto.title) { WatchSportAutoScreen(deviceId: watch.deviceId) }
                        }
                    }
                    // The settings that cost extra watch battery in a section of their own, right after their
                    // group, under a battery heading (Android `BatteryFrame`).
                    if !battery.isEmpty {
                        Section {
                            ForEach(battery, id: \.key) { item in
                                WatchSettingRow(deviceId: watch.deviceId, item: item, instantModeOn: instantOn)
                                // The phone's own motion record runs alongside each watch Sensor Record, so its
                                // switch stands right below that one (a phone setting, the same for every watch).
                                if item.key == "RecordingBoostEnabled" && PhoneMotionCapture.isAvailable {
                                    PhoneMotionSettingsRows()
                                }
                            }
                        } header: {
                            Label(L10n.get("watch_settings_battery_note"), systemImage: "battery.50")
                                .foregroundStyle(Color(red: 0xB2 / 255, green: 0x6A / 255, blue: 0x00 / 255))
                        }
                    }
                }
            }
        }
        .homeTitle(L10n.get("settings_tile_watch"))
        .onAppear { companion.refreshWatchSettings() }
    }
}

/// The last settings message to or from the watch (Android's sync strip): direction, what
/// happened and when, and what it means.
private struct WatchSyncRow: View {
    let sync: WatchSyncView

    var body: some View {
        let color: Color = sync.kind == "failed" ? .red : (sync.kind == "received" ? .green : .accentColor)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Image(systemName: sync.kind == "failed" ? "exclamationmark.triangle"
                      : (sync.toWatch ? "arrow.right" : "arrow.left"))
                    .foregroundStyle(color)
                Image(systemName: "applewatch")
                Text(sync.direction).font(.footnote).foregroundStyle(.secondary)
            }
            let at = Date(timeIntervalSince1970: TimeInterval(sync.atEpochMillis) / 1000).formatted(date: .omitted, time: .shortened)
            Text("\(sync.title) · \(at)").font(.subheadline).foregroundStyle(color)
            Text(sync.detail).font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Auto lap and auto pause per sport (Android's SportAutoBlock): "All sports" sets the main
/// setting and lets every sport follow it again; below, each sport can have its own value.
struct WatchSportAutoScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64

    var body: some View {
        let auto = companion.watchSettings.first { $0.deviceId == deviceId }?.sportAuto
        Form {
            if let auto {
                Section { Text(auto.intro).font(.footnote).foregroundStyle(.secondary) }
                Section {
                    Picker(auto.lapTitle, selection: Binding(
                        get: { auto.mainLap },
                        set: { companion.setWatchSportAutoAll(deviceId: deviceId, lap: $0, pause: -1) }
                    )) {
                        ForEach(auto.allLapChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Picker(auto.pauseTitle, selection: Binding(
                        get: { auto.mainPause },
                        set: { companion.setWatchSportAutoAll(deviceId: deviceId, lap: -1, pause: $0) }
                    )) {
                        ForEach(auto.allPauseChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Text(auto.allHint).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(auto.allTitle)
                }
                ForEach(auto.rows, id: \.sport) { row in
                    Section {
                        Picker(auto.lapTitle, selection: Binding(
                            get: { row.lap },
                            set: { companion.changeWatchSportAuto(deviceId: deviceId, key: row.lapKey, value: $0) }
                        )) {
                            ForEach(auto.lapChoices, id: \.value) { Text($0.label).tag($0.value) }
                        }
                        Picker(auto.pauseTitle, selection: Binding(
                            get: { row.pause },
                            set: { companion.changeWatchSportAuto(deviceId: deviceId, key: row.pauseKey, value: $0) }
                        )) {
                            ForEach(auto.pauseChoices, id: \.value) { Text($0.label).tag($0.value) }
                        }
                        if !row.note.isEmpty {
                            Text(row.note).font(.footnote).foregroundStyle(row.pending ? Color.orange : Color.red)
                        }
                    } header: {
                        Text(row.title)
                    }
                }
            }
        }
        .homeTitle(auto?.title ?? "")
    }
}

/// Self-declared skill level per sport (Android's SkillLevelBlock): "All sports" sets the main
/// setting and lets every sport follow it again; below, each sport can have its own value. Not
/// a verdict on technique, a plain self-report that pre-fills Recording Boost's own competence
/// picker. Same shape as [WatchSportAutoScreen].
struct WatchSkillLevelScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64

    var body: some View {
        let skillLevel = companion.watchSettings.first { $0.deviceId == deviceId }?.skillLevel
        Form {
            if let skillLevel {
                Section { Text(skillLevel.intro).font(.footnote).foregroundStyle(.secondary) }
                Section {
                    Picker(skillLevel.levelTitle, selection: Binding(
                        get: { skillLevel.mainLevel },
                        set: { companion.setWatchSkillLevelAll(deviceId: deviceId, level: $0) }
                    )) {
                        ForEach(skillLevel.allChoices, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    Text(skillLevel.allHint).font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text(skillLevel.allTitle)
                }
                ForEach(skillLevel.rows, id: \.sport) { row in
                    Section {
                        Picker(skillLevel.levelTitle, selection: Binding(
                            get: { row.level },
                            set: { companion.changeWatchSkillLevel(deviceId: deviceId, key: row.key, value: $0) }
                        )) {
                            ForEach(skillLevel.choices, id: \.value) { Text($0.label).tag($0.value) }
                        }
                        if !row.note.isEmpty {
                            Text(row.note).font(.footnote).foregroundStyle(row.pending ? Color.orange : Color.red)
                        }
                    } header: {
                        Text(row.title)
                    }
                }
            }
        }
        .homeTitle(skillLevel?.title ?? "")
    }
}

/// One watch's data fields, grouped by activity type like the watch menu: per screen the
/// left, right and bottom field, each a choice of the watch's field catalog.
struct WatchDataFieldsScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    @State private var pickingPreset = false

    var body: some View {
        let watch = companion.watchSettings.first { $0.deviceId == deviceId }
        Form {
            ForEach(watch?.dataFieldGroups ?? [], id: \.key) { group in
                Section {
                    ForEach(Array(group.screens.enumerated()), id: \.offset) { _, screen in
                        if !screen.title.isEmpty {
                            Text(screen.title).font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(screen.slots, id: \.index) { slot in
                            Picker(slot.label, selection: Binding(
                                get: { slot.field },
                                set: { companion.changeWatchDataField(deviceId: deviceId, key: group.key, index: slot.index, field: $0) }
                            )) {
                                // The fields this sport offers on this watch; a hint
                                // ("Needs Enhanced Metrics") under the name.
                                ForEach(group.options, id: \.value) { option in
                                    VStack(alignment: .leading) {
                                        Text(option.label)
                                        if !option.hint.isEmpty {
                                            Text(option.hint).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                    .tag(option.value)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                    }
                    if !group.note.isEmpty {
                        HStack {
                            Text(group.note).font(.footnote).foregroundStyle(group.pending ? Color.orange : Color.red)
                            if !group.pending {
                                Spacer()
                                Button(L10n.get("watch_settings_note_dismiss")) {
                                    companion.dismissWatchNote(deviceId: deviceId, key: group.key)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }
            // Migrations (phone only): every sport's data fields at once. Pace fields (lap pace too) to speed or
            // back, and "For all …" with a programmed configuration (shared WatchDataFieldPresets).
            let presets = watch?.dataFieldPresets ?? []
            if watch?.canPaceToSpeed == true || watch?.canSpeedToPace == true || !presets.isEmpty {
                Section {
                    if watch?.canPaceToSpeed == true {
                        Button(L10n.get("watch_data_fields_to_speed")) { companion.switchWatchPaceSpeed(deviceId: deviceId, toSpeed: true) }
                    }
                    if watch?.canSpeedToPace == true {
                        Button(L10n.get("watch_data_fields_to_pace")) { companion.switchWatchPaceSpeed(deviceId: deviceId, toSpeed: false) }
                    }
                    if !presets.isEmpty {
                        Button(L10n.get("watch_migrations_for_all")) { pickingPreset = true }
                    }
                } header: {
                    Text(L10n.get("watch_migrations_title"))
                }
            }
        }
        .homeTitle(L10n.get("watch_data_fields_title"))
        .confirmationDialog(L10n.get("watch_migrations_for_all_title"), isPresented: $pickingPreset, titleVisibility: .visible) {
            ForEach(watch?.dataFieldPresets ?? [], id: \.id) { preset in
                Button(preset.label) { companion.applyWatchDataFieldPreset(deviceId: deviceId, presetId: preset.id) }
            }
            Button(L10n.get("common_cancel"), role: .cancel) {}
        } message: {
            Text(L10n.get("watch_migrations_for_all_hint"))
        }
    }
}

/// Share and import of data fields, interval plans and strength routines (shared
/// WatchSettingsShare, as Android's WatchSettingsShareUi): pick the sets, share the message
/// through the share sheet; or paste a received message and choose a slot per set.
struct WatchShareScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    @State private var sets: [ShareSetView] = []
    @State private var picked: Set<Int32> = []

    var body: some View {
        let text = companion.watchShareText(deviceId: deviceId, ids: sets.map(\.id).filter { picked.contains($0) })
        Form {
            Section { Text(L10n.get("watch_share_intro")).font(.footnote).foregroundStyle(.secondary) }
            Section(L10n.get("watch_share_pick")) {
                if sets.isEmpty {
                    Text(L10n.get("watch_share_nothing")).foregroundStyle(.secondary)
                }
                ForEach(sets, id: \.id) { set in
                    Toggle(isOn: Binding(
                        get: { picked.contains(set.id) },
                        set: { on in if on { picked.insert(set.id) } else { picked.remove(set.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title)
                            Text(set.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                ShareLink(item: text) { Label(L10n.get("watch_share_send"), systemImage: "square.and.arrow.up") }
                    .disabled(text.isEmpty)
            }
            Section {
                NavigationLink { WatchImportScreen(deviceId: deviceId) } label: {
                    Label(L10n.get("watch_import_title"), systemImage: "square.and.arrow.down")
                }
            }
        }
        .homeTitle(L10n.get("watch_share_title"))
        .onAppear {
            sets = companion.shareableWatchSets(deviceId: deviceId)
            picked = Set(sets.map(\.id))
        }
    }
}

/// Step 1: paste the received message. Step 2: per set the slot it goes to, or "Don't import".
struct WatchImportScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let deviceId: Int64
    @State private var text = ""
    @State private var invalid = false
    @State private var sets: [ImportSetView]?
    @State private var targets: [String] = []
    /// Per set, the other sports a data field set goes to as well ("Also apply to").
    @State private var also: [Set<String>] = []

    var body: some View {
        Form {
            if let sets {
                Section { Text(L10n.get("watch_import_choose")).font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(sets.enumerated()), id: \.offset) { i, set in
                    Section {
                        Text(set.summary).font(.footnote).foregroundStyle(.secondary)
                        if set.targets.isEmpty {
                            Text(L10n.get("watch_import_no_slot")).font(.footnote).foregroundStyle(.red)
                        } else {
                            Picker(L10n.get("watch_import_goes_to"), selection: $targets[i]) {
                                Text(L10n.get("watch_import_skip")).tag("")
                                ForEach(set.targets, id: \.key) { target in
                                    Text(target.label).tag(target.key)
                                }
                            }
                            .pickerStyle(.navigationLink)
                        }
                        // A data field set can go to further sports too (e.g. a running set to Langlauf).
                        let extra = set.alsoTargets.filter { $0.key != targets[i] }
                        if !extra.isEmpty {
                            Text(L10n.get("watch_import_also_apply")).font(.footnote).foregroundStyle(.secondary)
                            ForEach(extra, id: \.key) { target in
                                Toggle(target.label, isOn: Binding(
                                    get: { also[i].contains(target.key) },
                                    set: { on in if on { also[i].insert(target.key) } else { also[i].remove(target.key) } }
                                ))
                            }
                        }
                    } header: {
                        Text(set.title)
                    }
                }
                Section {
                    Button(L10n.get("watch_import_apply")) {
                        companion.applyWatchImportAlso(deviceId: deviceId, text: text, targets: targets, also: also.map { Array($0) })
                        dismiss()
                    }
                    .disabled(targets.allSatisfy { $0.isEmpty } && also.allSatisfy { $0.isEmpty })
                }
            } else {
                Section {
                    Text(L10n.get("watch_import_paste_hint")).font(.footnote).foregroundStyle(.secondary)
                    // PasteButton reads the clipboard without iOS asking for permission.
                    PasteButton(payloadType: String.self) { strings in
                        if let first = strings.first { text = first; invalid = false }
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .onChange(of: text) { invalid = false }
                    if invalid {
                        Text(L10n.get("watch_import_invalid")).font(.footnote).foregroundStyle(.red)
                    }
                }
                Section {
                    Button(L10n.get("watch_import_next")) {
                        if let found = companion.readWatchImport(deviceId: deviceId, text: text), !found.isEmpty {
                            targets = found.map(\.proposed)
                            also = found.map { _ in [] }
                            sets = found
                        } else {
                            invalid = true
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .homeTitle(L10n.get("watch_import_title"))
    }
}

/// One watch's interval plans or strength routines: the three slots with the watch's
/// summary; each opens [WatchPlanEditScreen].
struct WatchPlansScreen: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    let routines: Bool

    var body: some View {
        let watch = companion.watchSettings.first { $0.deviceId == deviceId }
        Form {
            Section { Text(L10n.get(routines ? "watch_routines_intro" : "watch_intervals_intro")).font(.footnote).foregroundStyle(.secondary) }
            if routines, watch?.customStrengthExercisesAvailable == true {
                Section {
                    NavigationLink {
                        WatchCustomExercisesScreen(
                            deviceId: deviceId,
                            initialNames: watch?.customStrengthExercises ?? []
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.get("watch_strength_custom_exercises"))
                            Text((watch?.customStrengthExercises ?? []).joined(separator: ", "))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            ForEach((routines ? watch?.routineSlots : watch?.intervalSlots) ?? [], id: \.key) { slot in
                Section {
                    NavigationLink {
                        WatchPlanEditScreen(deviceId: deviceId, key: slot.key, title: slot.title, routine: routines)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.title)
                            Text(slot.summary).font(.subheadline).foregroundStyle(.secondary)
                            if !slot.detail.isEmpty {
                                Text(slot.detail).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !slot.note.isEmpty {
                        HStack {
                            Text(slot.note).font(.footnote).foregroundStyle(slot.pending ? Color.orange : Color.red)
                            if !slot.pending {
                                Spacer()
                                Button(L10n.get("watch_settings_note_dismiss")) {
                                    companion.dismissWatchNote(deviceId: deviceId, key: slot.key)
                                }
                                .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
        .homeTitle(L10n.get(routines ? "watch_strength_routines" : "watch_interval_menu"))
        .onAppear { companion.refreshWatchSettings() }
    }
}

private struct WatchCustomExercisesScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let deviceId: Int64
    let initialNames: [String]
    @State private var names: [String]
    @State private var newName = ""
    @State private var saveFailed = false

    init(deviceId: Int64, initialNames: [String]) {
        self.deviceId = deviceId
        self.initialNames = initialNames
        _names = State(initialValue: initialNames)
    }

    private var normalizedNames: [String] {
        names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private var validNames: Bool {
        normalizedNames.count <= 16 &&
            normalizedNames.allSatisfy { !$0.isEmpty && $0.count <= 32 } &&
            Set(normalizedNames.map { $0.lowercased() }).count == normalizedNames.count
    }

    private var candidateNames: [String] { normalizedNames + [newName.trimmingCharacters(in: .whitespacesAndNewlines)] }
    private var canAdd: Bool {
        names.count < 16 && !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Set(candidateNames.map { $0.lowercased() }).count == candidateNames.count
    }

    var body: some View {
        Form {
            Section(footer: Text(L10n.get("watch_strength_custom_exercises_hint") + " " + L10n.get("watch_strength_custom_exercises_limit"))) {
                ForEach(names.indices, id: \.self) { index in
                    TextField(
                        L10n.get("watch_strength_exercise") + " \(index + 1)",
                        text: Binding(
                            get: { names[index] },
                            set: { names[index] = String($0.prefix(32)); saveFailed = false }
                        )
                    )
                }
                if !validNames || saveFailed {
                    Text(L10n.get("watch_strength_custom_exercises_invalid"))
                        .font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                HStack {
                    TextField(L10n.get("watch_strength_custom_exercise_add"), text: $newName)
                        .onChange(of: newName) { _, value in
                            newName = String(value.prefix(32))
                            saveFailed = false
                        }
                    Button(L10n.get("watch_strength_custom_exercise_add")) {
                        names.append(newName.trimmingCharacters(in: .whitespacesAndNewlines))
                        newName = ""
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .homeTitle(L10n.get("watch_strength_custom_exercises"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.get("common_cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.get("watch_intervals_save")) {
                    if companion.changeWatchCustomStrengthExercises(deviceId: deviceId, names: normalizedNames) {
                        dismiss()
                    } else {
                        saveFailed = true
                    }
                }
                .disabled(!validNames || normalizedNames == initialNames || !newName.isEmpty)
            }
        }
    }
}

/// Edits one plan or routine with the watch editor's own choices (shared WatchPlanEditor).
/// Back discards the draft; Save sends it to the watch.
struct WatchPlanEditScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let deviceId: Int64
    let key: String
    let title: String
    let routine: Bool
    @State private var view: PlanEditView?
    @State private var confirmClear = false

    var body: some View {
        Form {
            if let view {
                Section { Text(view.summary).font(.headline) }
                ForEach(Array(view.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.rows, id: \.id) { row in
                            PlanRow(row: row, pick: { option in
                                self.view = companion.editWatchPlan(view, deviceId: deviceId, key: key, rowId: row.id, option: option)
                            }, custom: { entry, text in
                                guard let next = companion.editWatchPlanCustom(view, deviceId: deviceId, key: key, rowId: row.id, kind: entry.kind, text: text) else { return false }
                                self.view = next
                                return true
                            })
                        }
                        if !section.removeId.isEmpty {
                            Button(L10n.get("watch_strength_remove_exercise"), role: .destructive) {
                                self.view = companion.editWatchPlan(view, deviceId: deviceId, key: key, rowId: section.removeId, option: 0)
                            }
                        }
                    } header: {
                        if !section.title.isEmpty { Text(section.title) }
                    }
                }
                if view.canClear {
                    Section {
                        Button(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), role: .destructive) {
                            confirmClear = true
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.get("watch_intervals_save")) {
                    if let view { companion.saveWatchPlan(deviceId: deviceId, key: key, draft: view.draft) }
                    dismiss()
                }
                .disabled(view == nil)
            }
        }
        .confirmationDialog(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), isPresented: $confirmClear) {
            Button(L10n.get(routine ? "watch_strength_clear" : "watch_interval_clear"), role: .destructive) {
                companion.saveWatchPlan(deviceId: deviceId, key: key, draft: [])
                dismiss()
            }
        }
        .onAppear {
            if view == nil { view = companion.openWatchPlan(deviceId: deviceId, key: key) }
        }
    }
}

/// A picker for a row with a selection; a menu for an action row ("Start from", "Add exercise"),
/// a value outside the watch's list, or a row that also takes a typed custom value (the
/// menu lists the choices, then "Custom…", which asks for the value in an alert).
private struct PlanRow: View {
    let row: PlanEditRow
    let pick: (Int32) -> Void
    /// Applies typed text for a custom entry; false when the text is no value in range.
    let custom: (PlanCustomEntry, String) -> Bool
    @State private var showingExerciseSearch = false
    @State private var searchText = ""
    @State private var typing: PlanCustomEntry?
    @State private var typed = ""
    @State private var rejected = false

    private var isExerciseSearch: Bool {
        row.id == "add" || row.id.hasSuffix(".exercise")
    }

    var body: some View {
        if isExerciseSearch {
            Button { showingExerciseSearch = true } label: {
                HStack {
                    Text(row.label).foregroundStyle(Color.primary)
                    Spacer()
                    Text(row.value.isEmpty ? "…" : row.value).foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingExerciseSearch, onDismiss: { searchText = "" }) {
                NavigationStack {
                    List {
                        let matches = row.options.filter {
                            searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText)
                        }
                        if matches.isEmpty {
                            Text(L10n.get("settings_search_no_results")).foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(row.options.enumerated()), id: \.offset) { index, option in
                                if searchText.isEmpty || option.localizedCaseInsensitiveContains(searchText) {
                                    Button(option) {
                                        pick(Int32(index))
                                        showingExerciseSearch = false
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle(row.label)
                    .searchable(text: $searchText, prompt: L10n.get("settings_search_hint"))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.get("common_cancel")) { showingExerciseSearch = false }
                        }
                    }
                }
            }
        } else if row.selected >= 0 && row.customs.isEmpty {
            Picker(row.label, selection: Binding(get: { row.selected }, set: { pick($0) })) {
                ForEach(Array(row.options.enumerated()), id: \.offset) { index, option in
                    Text(option).tag(Int32(index))
                }
            }
        } else {
            Menu {
                ForEach(Array(row.options.enumerated()), id: \.offset) { index, option in
                    if Int32(index) == row.selected {
                        Button { pick(Int32(index)) } label: { Label(option, systemImage: "checkmark") }
                    } else {
                        Button(option) { pick(Int32(index)) }
                    }
                }
                if !row.customs.isEmpty {
                    Divider()
                    ForEach(row.customs, id: \.kind) { entry in
                        Button(entry.label) {
                            typed = ""
                            rejected = false
                            typing = entry
                        }
                    }
                }
            } label: {
                HStack {
                    Text(row.label).foregroundStyle(Color.primary)
                    Spacer()
                    Text(row.value.isEmpty ? "…" : row.value).foregroundStyle(.secondary)
                }
            }
            .alert(
                typing?.label.replacingOccurrences(of: "…", with: "") ?? "",
                isPresented: Binding(get: { typing != nil }, set: { if !$0 { typing = nil } }),
                presenting: typing
            ) { entry in
                TextField(entry.hint, text: $typed)
                Button(L10n.get("common_cancel"), role: .cancel) {}
                Button(L10n.get("common_ok")) {
                    if !custom(entry, typed) {
                        // Not a value in range: ask again, with the range marked.
                        rejected = true
                        DispatchQueue.main.async { typing = entry }
                    }
                }
            } message: { entry in
                Text(rejected ? "⚠︎ " + entry.hint : entry.hint)
            }
        }
    }
}

/// One watch setting (toggle or picker); also on "Record on my watch" (`WatchRecordStartView`).
struct WatchSettingRow: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    let item: WatchSettingItem
    /// Instant Mode sets Sensor Records aside on the watch (the setting is kept): the Sensor Record row is dimmed
    /// with a line while it is on, and both carry an info icon (Android `WatchSettingRow`).
    var instantModeOn = false

    private var paused: Bool { item.key == "RecordingBoostEnabled" && item.value != 0 && instantModeOn }
    private var info: String? {
        switch item.key {
        case "InstantMode": return L10n.get("watch_setting_instant_mode_info")
        case "RecordingBoostEnabled": return L10n.get("watch_setting_recording_boost_info")
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isToggle {
                Toggle(isOn: Binding(
                    get: { item.value != 0 },
                    set: { companion.changeWatchSetting(deviceId: deviceId, key: item.key, value: $0 ? 1 : 0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.label)
                            if let info { ChartInfoButton(title: item.label, text: info) }
                        }
                        if paused {
                            Text(L10n.get("watch_setting_recording_boost_paused")).font(.footnote).foregroundStyle(.secondary)
                        } else if item.key == "InstantMode" {
                            // Instant Mode works only with the phone nearby (it receives the live messages).
                            Text(L10n.get("watch_setting_instant_mode_phone")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .opacity(paused ? 0.6 : 1)
            } else {
                Picker(item.label, selection: Binding(
                    get: { item.value },
                    set: { companion.changeWatchSetting(deviceId: deviceId, key: item.key, value: $0) }
                )) {
                    ForEach(item.options, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
            }
            if !item.note.isEmpty {
                HStack {
                    Text(item.note)
                        .font(.footnote)
                        .foregroundStyle(item.pending ? Color.orange : Color.red)
                    if !item.pending {
                        Spacer()
                        Button(L10n.get("watch_settings_note_dismiss")) {
                            companion.dismissWatchNote(deviceId: deviceId, key: item.key)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }
}

// MARK: - Logs

struct LogScreen: View {
    @EnvironmentObject var companion: Companion
    let title: String
    let kind: Companion.LogKind
    @State private var lines: [LogLine] = []
    @State private var loaded = false

    init(title: String, kind: Companion.LogKind) {
        self.title = title
        self.kind = kind
    }

    private var shareKinds: [NordicSportsShared.LogKind] {
        switch kind {
        case .diary: return [.diary]
        case .app: return [.app]
        case .transfer: return [.watchTransfers]
        }
    }

    private var emptyText: String {
        switch kind {
        case .diary: return L10n.get("diary_work_log_empty")
        case .app: return L10n.get("app_log_empty")
        case .transfer: return L10n.get("data_sharing_log_empty")
        }
    }

    var body: some View {
        LogList(lines: lines, loaded: loaded, empty: emptyText)
            .homeTitle(title)
            .toolbar { ShareLogButton(kinds: shareKinds) }
            .task {
                lines = await companion.logLines(kind)
                loaded = true
            }
            .refreshable { lines = await companion.logLines(kind) }
    }
}

/// One activity's history (Android: the activity change log).
struct ActivityLogScreen: View {
    @EnvironmentObject var companion: Companion
    let activityId: String
    @State private var lines: [LogLine] = []
    @State private var loaded = false
    @State private var failure: String?

    init(activityId: String) {
        self.activityId = activityId
    }

    var body: some View {
        LogList(lines: lines, loaded: loaded, empty: L10n.get("activity_change_log_empty"), failure: failure)
            .homeTitle(L10n.get("activity_change_log_title"))
            .toolbar { ShareLogButton(kinds: [.activityHistory], activityId: activityId) }
            .task {
                do { lines = try await companion.activityLog(activityId) } catch {
                    if !error.isCancellation { failure = error.localizedDescription }
                }
                loaded = true
            }
    }
}

/// Every Strava API call the app made (Android: Strava API usage), grouped per day.
struct StravaApiUsageScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var calls: [StravaApiCallView] = []
    @State private var loaded = false
    @State private var failure: String?

    private struct Day: Identifiable {
        let day: Date
        let calls: [StravaApiCallView]
        var id: Date { day }
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: calls) {
            calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.epochMillis) / 1000))
        }
        return grouped.keys.sorted(by: >).map { Day(day: $0, calls: grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if let failure { LoadFailedRow(reason: failure) }
            if loaded && calls.isEmpty && failure == nil {
                Text(L10n.get("strava_api_usage_empty")).foregroundStyle(.secondary)
            }
            ForEach(days) { group in
                Section {
                    ForEach(group.calls, id: \.id) { call in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(call.method) \(call.endpoint)").font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(Date(timeIntervalSince1970: TimeInterval(call.epochMillis) / 1000)
                                    .formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                            Text(call.purpose).font(.footnote)
                            HStack(spacing: 8) {
                                Text(L10n.get(call.success ? "strava_api_call_success" : "strava_api_call_failed"))
                                    .foregroundStyle(call.success ? Color.green : Color.red)
                                if !call.httpStatus.isEmpty {
                                    Text(String(format: L10n.get("strava_api_call_http_status"), call.httpStatus))
                                }
                            }
                            .font(.caption)
                            if !call.detail.isEmpty {
                                Text(call.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                    }
                } header: {
                    let failed = group.calls.filter { !$0.success }.count
                    let count = L10n.plural("strava_api_usage_call_count", group.calls.count)
                    Text("\(group.day.formatted(date: .complete, time: .omitted)) \u{00B7} "
                         + (failed > 0 ? String(format: L10n.get("strava_api_usage_with_failures"), count, failed) : count))
                }
            }
        }
        .homeTitle(L10n.get("strava_api_usage_title"))
        .toolbar { ShareLogButton(kinds: [.stravaApi]) }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            calls = try await companion.core.stravaApiCalls(limit: 500)
            failure = nil
        } catch {
            if !error.isCancellation {
                WatchLinkSpike.shared.add("Strava API usage not loaded: \(error.localizedDescription)")
                failure = error.localizedDescription
            }
            calls = []
        }
        loaded = true
    }
}

/// Android's BuildExpiryScreen for a build below the server's minimum: no sync any more, but the
/// athlete's own data stays reachable (export, delete).
struct OutdatedScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.get("expiry_outdated_title")).font(.title2.bold())
            Text(L10n.get("expiry_body_store"))
            Text(L10n.get("expiry_data_note")).font(.footnote).foregroundStyle(.secondary)
            DownloadMyDataButton()
                .buttonStyle(.borderedProminent)
            Button(L10n.get("status_delete_my_data"), role: .destructive) { confirmingDelete = true }
            Spacer()
        }
        .padding()
        .confirmationDialog(L10n.get("status_delete_confirm_title"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L10n.get("status_delete_confirm_button"), role: .destructive) {
                Task { await companion.deleteAllData() }
            }
        } message: {
            Text(L10n.get("status_delete_confirm_body"))
        }
    }
}

/// Android's first-start guide: seven steps (nickname, demo or own data, watch, wrist, skill level, online repository, diary),
/// each skippable; shown once (also left out when the app is already set up). The step counter stays on top and the
/// buttons at the bottom, so the screen does not change size from step to step; long content scrolls.
struct OnboardingScreen: View {
    @EnvironmentObject var companion: Companion
    let finish: () -> Void
    @State private var step = 0
    @State private var nickname = ""
    /// Step 2 (demo): true = work with demo data (sample activities and a simulated watch).
    @State private var useDemo = false
    @State private var diaryShown = false
    /// "Your watch": 0 asks whether the athlete has the watch app, 1 waits for the watch to talk to this app.
    @State private var watchPhase = 0
    /// Step 6 (review): preset off for a new install (Android `InteractionStep`); the imported-activity review follows
    /// the first switch until it is touched.
    @State private var reviewNew = false
    @State private var reviewImported = false
    @State private var importedTouched = false
    /// Step 10 (tester access, Android `OnboardingGuideStep.SERVER`): the server's move stage for iOS,
    /// asked once for a local install; the step shows while it is pilot, optional or nudge.
    @State private var serverStage: String?
    /// The result text once the install moved in the step.
    @State private var serverMoved: String?

    private var serverStepInPlan: Bool {
        guard !useDemo else { return false }
        return serverMoved != nil
            || (["pilot", "optional", "nudge"].contains(serverStage ?? "") && !companion.onServerConnection)
    }

    /// Pilot: invited testers only, so the others go on with "Not now"; otherwise the step stays until moved.
    private var serverRequired: Bool { serverStage != "pilot" }

    /// Steps: 0 nickname, 1 demo, 10 tester access, 2 watch, 3 wrist, 4 skill level, 5 Strava, 6 diary, 7 review,
    /// 8 "You're set" (Android `OnboardingGuideStep` order). The ones that show for this athlete, for "Step n of N"
    /// without gaps.
    private var plan: [Int] {
        var p = [0, 1]
        if serverStepInPlan { p.append(10) }
        if !useDemo { p.append(2) }
        if wristUnsetWatch != nil { p.append(3) }
        if skillUnsetWatch != nil { p.append(4) }
        p += [5, 6]
        if anythingConnected { p.append(7) }
        p.append(8)
        return p
    }

    /// The review question means something only once Strava or a diary receives the activities.
    private var anythingConnected: Bool { companion.stravaConnected || companion.diaryReceives }

    /// Saves the review step's choice; both of its buttons do (iOS has no new-install marker, so "Not now" applies the
    /// preset, off, as a new Android install reads it).
    private func saveReview() {
        companion.setReviewNewActivities(reviewNew)
        companion.setReviewImportedActivities(reviewImported)
        next()
    }

    /// A watch that reported its settings with the wrist not set (value 0); the wrist is asked for it.
    private var wristUnsetWatch: WatchSettingsView? {
        companion.watchSettings.first { watch in
            watch.groups.contains { $0.items.contains { $0.key == "WatchWrist" && $0.value == 0 } }
        }
    }

    /// A watch that reported its settings with the skill level not set (value 0); it is asked after the wrist.
    private var skillUnsetWatch: WatchSettingsView? {
        companion.watchSettings.first { watch in
            watch.groups.contains { $0.items.contains { $0.key == "SkillLevel" && $0.value == 0 } }
        }
    }

    /// The tester access (10) sits between the demo step and the watch.
    private func next() { step = step == 10 ? 2 : step + 1 }

    private func chooseWrist(_ watch: WatchSettingsView, _ value: Int32) {
        companion.changeWatchSetting(deviceId: watch.deviceId, key: "WatchWrist", value: value)
    }

    private func chooseSkillLevel(_ watch: WatchSettingsView, _ value: Int32) {
        companion.changeWatchSetting(deviceId: watch.deviceId, key: "SkillLevel", value: value)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    let number = (plan.firstIndex(of: step) ?? plan.filter { $0 < step }.count) + 1
                    Text(String(format: L10n.get("onboarding_guide_step"), number, max(plan.count, number)))
                        .font(.footnote).foregroundStyle(.secondary)
                    ProgressView(value: Double(number), total: Double(max(plan.count, number)))
                }
                .padding([.horizontal, .top])
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                Divider()
                footer.padding()
            }
            .navigationDestination(isPresented: $diaryShown) { DiaryLocationsScreen() }
            .task {
                if !companion.onServerConnection { serverStage = await companion.serverMoveStage() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            Text(L10n.get("onboarding_guide_nickname_title")).font(.title2.bold())
            Text(L10n.get("onboarding_guide_nickname_body"))
            TextField("", text: $nickname)
                .textFieldStyle(.roundedBorder)
                .onChange(of: nickname) { _, value in nickname = String(value.prefix(20)) }
            Text(L10n.get("onboarding_guide_nickname_later")).font(.footnote).foregroundStyle(.secondary)
        case 1:
            // Demo data or the athlete's own; either can be changed later in Settings > App.
            Text(L10n.get("onboarding_guide_demo_title")).font(.title2.bold())
            Text(L10n.get("onboarding_guide_demo_body"))
            demoChoice(demo: false, title: "onboarding_guide_demo_option_real", subtitle: "onboarding_guide_demo_option_real_sub")
            demoChoice(demo: true, title: "onboarding_guide_demo_option_demo", subtitle: "onboarding_guide_demo_option_demo_sub")
            Text(L10n.get("onboarding_guide_demo_later")).font(.footnote).foregroundStyle(.secondary)
        case 10:
            // The tester access: About's form inside the guide, before Strava, so its sign-in runs
            // through the server.
            Text(L10n.get("onboarding_guide_server_title")).font(.title2.bold())
            if let serverMoved {
                Text(serverMoved)
            } else {
                Text(L10n.get("onboarding_guide_server_body"))
                ServerMoveForm(onMoved: { text in serverMoved = text })
                Text(L10n.get(serverRequired ? "onboarding_guide_server_required" : "onboarding_guide_server_later"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        case 2:
            // The watch app: ask, then wait until the watch has sent a message (the app sends its
            // settings at every start). "Next" works only after that. The wrist is asked right there.
            if watchPhase == 0 {
                Text(L10n.get("onboarding_guide_watch_ask_title")).font(.title2.bold())
                Text(L10n.get("onboarding_guide_watch_ask_body"))
                WatchStoreCard()
                Text(L10n.get("onboarding_guide_watch_store_hint")).font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(L10n.get("onboarding_guide_watch_check_title")).font(.title2.bold())
                Text(L10n.get("onboarding_guide_watch_check_body"))
                // What the watch shows once the app is open: its start menu (a cut-out watch screenshot).
                Image(["de", "gsw"].contains(Locale.current.language.languageCode?.identifier ?? "") ? "OnboardingWatchAppDe" : "OnboardingWatchApp")
                    .resizable().scaledToFit().frame(height: 170).frame(maxWidth: .infinity)
                if companion.watchEverSeen {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.get("onboarding_guide_watch_ok_title")).font(.headline)
                        if !companion.watchSeenName.isEmpty { Text(companion.watchSeenName).font(.subheadline) }
                        Text(L10n.get("onboarding_guide_watch_ok_body")).font(.footnote)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.15)))
                    if let watch = wristUnsetWatch {
                        wristQuestion(watch)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L10n.get("onboarding_guide_watch_waiting")).foregroundStyle(CardTone.blue.title)
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(CardTone.blue.container))
                }
            }
        case 3:
            // Which wrist the watch is worn on; skipped when no watch reports it as not set.
            if let watch = wristUnsetWatch {
                wristQuestion(watch)
            } else {
                Color.clear.frame(height: 1).onAppear { next() }
            }
        case 4:
            // The self-declared skill level, a step of its own after the wrist (asked inline below the
            // wrist question it vanished with the wrist answer); skipped when no watch reports it as not set.
            if let watch = skillUnsetWatch {
                skillLevelQuestion(watch)
            } else {
                Color.clear.frame(height: 1).onAppear { next() }
            }
        case 5:
            Text(L10n.get("onboarding_guide_strava_title")).font(.title2.bold())
            Text(L10n.get("onboarding_guide_strava_body"))
            Text(L10n.get("onboarding_guide_strava_how")).font(.footnote).foregroundStyle(.secondary)
            StravaConnectButton { companion.connectStrava() }
        case 6:
            Text(L10n.get("onboarding_guide_diary_title")).font(.title2.bold())
            Text(L10n.get("onboarding_guide_diary_body"))
            Text(L10n.get("onboarding_guide_diary_how")).font(.footnote).foregroundStyle(.secondary)
        case 7:
            // Whether new (and imported) activities wait for a review before Strava or the diary; skipped while
            // neither is connected (the question is about them).
            // Skipped, the preset (no review) is still stored: iOS has no new-install marker like Android.
            if !anythingConnected { Color.clear.frame(height: 1).onAppear { saveReview() } }
            Text(L10n.get("onboarding_guide_interaction_title")).font(.title2.bold())
            Text(L10n.get("onboarding_guide_interaction_body"))
            Toggle(L10n.get("settings_review_new_activities"), isOn: Binding(
                get: { reviewNew },
                set: { reviewNew = $0; if !importedTouched { reviewImported = $0 } }
            ))
            Text(L10n.get(reviewNew ? "interaction_option_interactive_description" : "interaction_option_passive_description"))
                .font(.footnote).foregroundStyle(.secondary)
            Toggle(L10n.get("settings_review_imported_activities"), isOn: Binding(
                get: { reviewImported },
                set: { reviewImported = $0; importedTouched = true }
            ))
            Text(L10n.get("settings_review_imported_activities_description")).font(.footnote).foregroundStyle(.secondary)
        default:
            // "You're set": what now happens by itself, and the place-name lookup with its notice and switch.
            Text(L10n.get("onboarding_guide_done_title")).font(.title2.bold())
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.get("onboarding_guide_done_body"))
                if anythingConnected {
                    Text(L10n.get(companion.reviewNewActivities ? "onboarding_guide_done_review_on" : "onboarding_guide_done_review_off"))
                }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.15)))
            Toggle(L10n.get("status_place_names_switch"), isOn: Binding(
                get: { companion.placeNamesEnabled },
                set: { companion.setPlaceNamesEnabled($0) }
            ))
            Text(L10n.get("onboarding_guide_place_names_notice")).font(.footnote).foregroundStyle(.secondary)
        }
        if step == 5 || step == 6 {
            Text(L10n.get("onboarding_guide_later")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// The buttons at the bottom: "not now" on the left, the step's main action on the right.
    @ViewBuilder private var footer: some View {
        HStack {
            switch step {
            case 0:
                Button(L10n.get("onboarding_guide_not_now")) { next() }
                Spacer()
                Button(L10n.get("onboarding_guide_nickname_save")) {
                    companion.setNickname(nickname)
                    next()
                }
                .buttonStyle(.borderedProminent)
                .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            case 1:
                Spacer()
                Button(L10n.get("onboarding_guide_watch_continue")) {
                    if useDemo {
                        // The simulated watch stands in for the real one: the watch step is skipped.
                        Task { await companion.loadDemoData(); step += 2 }
                    } else if serverStepInPlan {
                        step = 10
                    } else {
                        next()
                    }
                }
                .buttonStyle(.borderedProminent)
            case 10:
                if serverMoved == nil && !serverRequired {
                    Button(L10n.get("onboarding_guide_not_now")) { next() }
                }
                Spacer()
                if serverMoved != nil {
                    Button(L10n.get("onboarding_guide_watch_continue")) { next() }
                        .buttonStyle(.borderedProminent)
                }
            case 2:
                if watchPhase == 0 {
                    Button(L10n.get("onboarding_guide_not_now")) { next() }
                    Spacer()
                    Button(L10n.get("onboarding_guide_watch_have_it")) { watchPhase = 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    if !companion.watchEverSeen {
                        Button(L10n.get("onboarding_guide_not_now")) { next() }
                    }
                    Spacer()
                    Button(L10n.get(companion.watchEverSeen ? "onboarding_guide_watch_continue" : "onboarding_guide_watch_next")) { next() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!companion.watchEverSeen)
                }
            case 7:
                Button(L10n.get("onboarding_guide_not_now")) { saveReview() }
                Spacer()
                Button(L10n.get("common_continue")) { saveReview() }
                    .buttonStyle(.borderedProminent)
            case 3, 4, 5:
                Button(L10n.get("onboarding_guide_not_now")) { next() }
                Spacer()
            case 6:
                Button(L10n.get("onboarding_guide_not_now")) { next() }
                Spacer()
                Button(L10n.get("onboarding_guide_choose_diary")) { diaryShown = true }
                    .buttonStyle(.borderedProminent)
            default:
                Spacer()
                Button(L10n.get("onboarding_guide_done_start")) { finish() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func demoChoice(demo: Bool, title: String, subtitle: String) -> some View {
        let selected = useDemo == demo
        return Button { useDemo = demo } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.get(title)).font(.headline).foregroundStyle(.primary)
                    Text(L10n.get(subtitle)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(CardTone.blue.container))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : CardTone.blue.border, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func wristQuestion(_ watch: WatchSettingsView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.get("onboarding_guide_wrist_title")).font(.title3.bold())
            Text(L10n.get("onboarding_guide_wrist_body"))
            HStack(spacing: 12) {
                ForEach([("watch_option_wrist_left", Int32(1)), ("watch_option_wrist_right", Int32(2))], id: \.1) { label, value in
                    Button(L10n.get(label)) { chooseWrist(watch, value) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    /// The self-declared skill level, a step of its own after the wrist (Android's `SkillLevelStep`,
    /// same `SkillLevel` setting as the per-sport screen). No "not set" button: "Not now" leaves it unset.
    private func skillLevelQuestion(_ watch: WatchSettingsView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.get("onboarding_guide_skill_level_title")).font(.title3.bold())
            Text(L10n.get("onboarding_guide_skill_level_body"))
            // One full-width button per level (Android `SkillLevelStep`): side by side the longer
            // labels ("Fortgeschritten") did not fit a phone's width.
            VStack(spacing: 8) {
                ForEach(
                    [("watch_option_skill_level_beginner", Int32(1)), ("watch_option_skill_level_intermediate", Int32(2)),
                     ("watch_option_skill_level_expert", Int32(3))], id: \.1
                ) { label, value in
                    Button { chooseSkillLevel(watch, value) } label: {
                        Text(L10n.get(label)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

/// Android's About: version, what's new, help with the translations, privacy policy, imprint,
/// the description and the trademark note.
struct AboutScreen: View {
    private static let site = AppConfig.websiteUrl

    @EnvironmentObject var companion: Companion

    var body: some View {
        List {
            Section {
                Text("Nordic Sports Companion").font(.title3.bold())
                Text(Format.appVersion + " [" + UserRoleKt.currentUserRoleName() + "]").foregroundStyle(.secondary)
            }
            Section {
                NavigationLink(L10n.get("about_view_changelog")) { ChangelogScreen() }
                NavigationLink(L10n.get("about_help_translate")) { FeedbackScreen(startCategory: "wording") }
                if let privacy = URL(string: Self.site + "/privacy.html") {
                    Link(L10n.get("about_privacy_policy"), destination: privacy)
                }
                if let imprint = URL(string: Self.site + "/impressum.html") {
                    Link(L10n.get("about_imprint"), destination: imprint)
                }
                NavigationLink(L10n.get("about_licenses")) { LicensesScreen() }
            }
            // The anonymous account's ID, only while this install has one (Android: AccountIdSection).
            if let accountId = companion.anonymousAccountId {
                Section(header: Text(L10n.get("about_account_title")), footer: Text(L10n.get("about_account_hint"))) {
                    Text(accountId).textSelection(.enabled).font(.footnote.monospaced())
                    Button(L10n.get("about_account_copy")) { UIPasteboard.general.string = accountId }
                }
            }
            ServerConnectionSection()
            Section {
                Text(L10n.get("about_body"))
                // Free during the beta, paid features possible later; same statement as the website imprint.
                Text(L10n.get("about_pricing_note")).font(.subheadline).foregroundStyle(.secondary)
                Text(L10n.get("about_trademark_disclaimer_ios")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .homeTitle(L10n.get("about_title"))
    }
}

/// About › Server connection (design/server-migration.md; Android: `ServerConnectionSection`):
/// "Local" (the access built into the app, Strava directly) or "Server" (an access of its own,
/// Strava through the server), and "Migrate user" with a mailed one-time code while the server's
/// stage for iOS is pilot or optional. While Local, "I have a tester token" opens the field for a
/// token handed out by hand. On the server: "Back to local" only during the pilot, "Remove token"
/// for a pasted token.
private struct ServerConnectionSection: View {
    @EnvironmentObject var companion: Companion
    @State private var tick = 0
    @State private var stage: String?
    @State private var open = false
    @State private var busy = false
    @State private var message: String?
    @State private var pasteOpen = false
    @State private var tokenText = ""
    @State private var tokenInvalid = false

    var body: some View {
        // Read tick, so a move, an undo or a token change shows at once.
        let _ = tick
        let onServer = companion.onServerConnection
        Section(header: Text(L10n.get("about_server_title"))) {
            Text(String(format: L10n.get("about_server_status"),
                        L10n.get(onServer ? "about_server_status_server" : "about_server_status_local")))
                .font(.body.bold())
            Text(L10n.get(onServer ? "about_server_server_body" : "about_server_local_body"))
                .font(.footnote).foregroundStyle(.secondary)
            if onServer, let end = companion.serverTokenExpiresAt {
                Text(String(format: L10n.get("about_server_valid_until"), end.formatted(date: .abbreviated, time: .omitted)))
                    .font(.footnote)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Color.accentColor)
            }
            if !onServer && !open {
                switch stage {
                case "pilot", "optional", "nudge":
                    if stage == "pilot" {
                        Text(L10n.get("about_server_pilot_hint")).font(.footnote)
                    }
                    Button(L10n.get("about_server_migrate")) { open = true; message = nil }
                case "off":
                    Text(L10n.get("about_server_not_open")).font(.footnote).foregroundStyle(.secondary)
                default:
                    EmptyView() // still asking the server, or it could not be reached
                }
                if !pasteOpen {
                    Button(L10n.get("about_server_have_token")) { pasteOpen = true; message = nil }
                } else {
                    SecureField(L10n.get("about_tester_field"), text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: tokenText) { _, _ in tokenInvalid = false }
                    if tokenInvalid {
                        Text(L10n.get("about_tester_invalid")).font(.footnote).foregroundStyle(.red)
                    }
                    Button(L10n.get("about_tester_save")) {
                        if companion.saveServerToken(tokenText) {
                            pasteOpen = false
                            tokenText = ""
                            tick += 1
                        } else {
                            tokenInvalid = true
                        }
                    }
                    .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(L10n.get("about_server_cancel"), role: .cancel) {
                        pasteOpen = false
                        tokenText = ""
                        tokenInvalid = false
                    }
                }
            }
            if open && !onServer {
                ServerMoveForm(
                    onMoved: { text in message = text; open = false; tick += 1 },
                    onCancel: { open = false; message = nil }
                )
            }
            if onServer && companion.serverTokenRemovable {
                Button(L10n.get("about_tester_remove"), role: .destructive) {
                    companion.clearServerToken()
                    message = nil
                    tick += 1
                }
            }
            // The undo is a safety net for the pilot only; once the move is open to everyone it is gone.
            if onServer && companion.serverMoveCanUndo && stage == "pilot" {
                Button(L10n.get("about_server_undo")) { undo() }.disabled(busy)
            }
        }
        .task { stage = await companion.serverMoveStage() }
    }

    private func undo() {
        busy = true
        Task {
            await companion.undoServerMove()
            message = L10n.get("about_server_undone")
            busy = false
            tick += 1
        }
    }
}

/// The move's e-mail and one-time code form (Android `ServerMoveForm`), shared by About, the setup
/// guide's server step and the start-up reminder: asks for a code, then moves with it. `onMoved`
/// gets the result text once this install is on the server; failures stay in the form. Bordered
/// buttons, so each one reacts on its own inside a List row.
struct ServerMoveForm: View {
    @EnvironmentObject var companion: Companion
    var onMoved: (String) -> Void
    var onCancel: (() -> Void)? = nil
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(L10n.get("about_server_email"), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(busy)
                Text(L10n.get("about_server_email_hint")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.get("about_server_send_code")) { sendCode() }
                    .buttonStyle(.bordered)
                    .disabled(busy || !email.contains("@"))
                if let onCancel {
                    Button(L10n.get("about_server_cancel"), role: .cancel) { onCancel() }
                        .buttonStyle(.borderless)
                        .disabled(busy)
                }
            }
            if codeSent {
                TextField(L10n.get("about_server_code"), text: $code)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .disabled(busy)
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter { $0.isNumber }.prefix(6))
                        if digits != value { code = digits }
                    }
                Button(L10n.get("about_server_move_now")) { move() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || code.count != 6)
            }
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Color.accentColor)
            }
            if busy { ProgressView() }
        }
    }

    private func sendCode() {
        busy = true
        Task {
            let result = await companion.requestServerMoveCode(email: email)
            switch result {
            case "SENT":
                message = L10n.get("about_server_code_sent")
                codeSent = true
            case "NOT_OPEN": message = L10n.get("about_server_not_open")
            case "INVALID": message = L10n.get("about_server_invalid")
            default: message = L10n.get("about_server_failed")
            }
            busy = false
        }
    }

    private func move() {
        busy = true
        message = L10n.get("about_server_moving")
        Task {
            let result = await companion.moveToServer(email: email, code: code)
            busy = false
            let text = L10n.get(Self.moveMessage[result] ?? "about_server_failed")
            if result == "MOVED" || result == "MOVED_LINK_PENDING" {
                codeSent = false
                code = ""
                message = nil
                onMoved(text)
            } else {
                message = text
            }
        }
    }

    private static let moveMessage: [String: String] = [
        "MOVED": "about_server_moved",
        "MOVED_LINK_PENDING": "about_server_moved_link_pending",
        "WRONG_CODE": "about_server_wrong_code",
        "CODE_EXPIRED": "about_server_code_expired",
        "NOT_ELIGIBLE": "about_server_not_eligible",
        "NOT_OPEN": "about_server_not_open",
        "INVALID": "about_server_invalid",
        "FAILED": "about_server_failed",
        "STRAVA_CHECK_FAILED": "about_server_strava_failed",
        "STORE_LATER": "about_server_store_later",
    ]
}

/// The open-source notices, the Companion's generated `open_source_licenses.txt` (CI copies it
/// into App/Texts); the same text as Android's About > Open-source licenses.
struct LicensesScreen: View {
    private let text: String = {
        guard let url = Bundle.main.url(forResource: "open_source_licenses", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return AppConfig.websiteUrl }
        return content
    }()

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .homeTitle(L10n.get("licenses_title"))
    }
}

/// What changed, for the athlete: the shared `AppChangelog` (the same list as Android's), from
/// the first iOS version on (Android's older entries do not apply here). A release adds its entry
/// there once, and a unit test in the Companion fails a version bump without one.
struct ChangelogScreen: View {
    private let entries = AppChangelog.shared.iosEntries

    var body: some View {
        List {
            ForEach(entries, id: \.version) { entry in
                Section("\(entry.version) · \(entry.date)") {
                    ForEach(entry.highlights + entry.highlightKeys.map { L10n.get($0) }, id: \.self) { line in
                        Text(line)
                    }
                }
            }
        }
        .homeTitle(L10n.get("changelog_title"))
    }
}

/// Every Recording Boost burst received from the watch, newest capture first (Android: Recording
/// Boost activities): when, how much, which activity, and where its CSV file is.
struct RecordingBoostScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var bursts: [RecordingBoostView] = []
    @State private var loaded = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Text(String(format: L10n.get("recording_boost_list_default_folder"),
                            "On My iPhone \u{203A} Nordic Sports \u{203A} \(Companion.boostFolder)"))
                    .font(.system(.footnote, design: .monospaced))
            }
            if let failure { LoadFailedRow(reason: failure) }
            // Demo mode: a real record to try the charts on (Android `DemoBurst` row); never stored or exported.
            let demo = companion.core.demoSensorRecordShown()
            if demo {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.get("burst_demo_title")).font(.headline)
                        Text(L10n.get("burst_demo_body")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink(L10n.get("burst_charts_button")) { SensorRecordView(burstId: "demo-burst") }
                        .fixedSize()
                }
            }
            if loaded && bursts.isEmpty && failure == nil && !demo {
                Text(L10n.get("recording_boost_list_empty")).foregroundStyle(.secondary)
            }
            ForEach(bursts, id: \.id) { burst in
                VStack(alignment: .leading, spacing: 3) {
                    // The capture start a complete record carries; else burstId, the capture end.
                    Text(Date(timeIntervalSince1970: TimeInterval(burst.startEpochSec > 0 ? burst.startEpochSec : burst.burstId))
                            .formatted(date: .abbreviated, time: .standard))
                        .font(.headline)
                    if burst.complete {
                        Text(L10n.get("recording_boost_list_complete")).font(.caption.bold()).foregroundStyle(.tint)
                        if burst.roundTripMs >= 0 {
                            Text(String(format: L10n.get("recording_boost_list_phone_synced"), Int(burst.roundTripMs))).font(.caption)
                        }
                    }
                    let seconds = burst.sampleRateHz > 0 ? Int(burst.sampleCount) / Int(burst.sampleRateHz) : 0
                    Text(String(format: L10n.get("recording_boost_list_samples"), Int(burst.sampleCount), seconds, Int(burst.sampleRateHz)))
                    Text(String(format: L10n.get("recording_boost_list_received"),
                                Date(timeIntervalSince1970: TimeInterval(burst.receivedAtEpochMillis) / 1000)
                                    .formatted(date: .abbreviated, time: .standard)))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(burst.activityTitle.isEmpty
                         ? L10n.get("recording_boost_list_not_linked")
                         : String(format: L10n.get("recording_boost_list_linked"), burst.activityTitle))
                        .font(.caption)
                    if !burst.channels.isEmpty {
                        Text(String(format: L10n.get("recording_boost_list_channels"), burst.channels)).font(.caption)
                    }
                    HStack {
                        Text(burst.labelSummary.isEmpty
                             ? L10n.get("recording_boost_list_unlabelled")
                             : String(format: L10n.get("recording_boost_list_label"), burst.labelSummary))
                            .fontWeight(burst.labelSummary.isEmpty ? .regular : .bold)
                        Spacer()
                        Button(L10n.get("recording_boost_label_button")) { labelling = burst }
                            .buttonStyle(.borderless)
                    }
                    if !burst.fileName.isEmpty {
                        Text(L10n.get("recording_boost_list_file_saved")).font(.subheadline.bold())
                        Text(String(format: L10n.get("recording_boost_list_file_name"), burst.fileName))
                            .font(.system(.caption, design: .monospaced))
                        Text(String(format: L10n.get("recording_boost_list_file_size"), Int(burst.sizeBytes)))
                            .font(.caption)
                    } else {
                        Text(L10n.get("recording_boost_list_file_missing")).font(.subheadline.bold()).foregroundStyle(.red)
                        if burst.error.isEmpty {
                            Text(L10n.get("recording_boost_list_file_pending")).font(.caption)
                        } else {
                            Text(String(format: L10n.get("recording_boost_list_file_error"), burst.error))
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .homeTitle(L10n.get("recording_boost_list_title"))
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $labelling) { burst in
            BurstLabelSheet(burst: burst) { technique, terrain, poles, note, surface in
                labelling = nil
                Task {
                    do {
                        try await companion.labelBoost(id: burst.id, technique: technique, terrain: terrain, poles: poles, note: note, surface: surface)
                    } catch {
                        if !error.isCancellation { WatchLinkSpike.shared.add("Recording Boost label not saved: \(error.localizedDescription)") }
                    }
                    await load()
                }
            }
        }
    }

    @State private var labelling: RecordingBoostView?

    private func load() async {
        do {
            bursts = try await companion.core.recordingBoosts()
            failure = nil
        } catch {
            if !error.isCancellation {
                WatchLinkSpike.shared.add("Recording Boost list not loaded: \(error.localizedDescription)")
                failure = error.localizedDescription
            }
            bursts = []
        }
        loaded = true
    }
}

extension RecordingBoostView: Identifiable {}

/// Android's BurstLabelDialog: technique and terrain (coach codes, untranslated except "mixed"),
/// poles for running and unknown sports, and a note. Tapping a selected choice again clears it.
struct BurstLabelSheet: View {
    let burst: RecordingBoostView
    let onSave: (String, String, Int32, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var technique = ""
    @State private var terrain = ""
    @State private var surface = ""
    @State private var poles: Int32 = -1
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(L10n.get("recording_boost_label_hint")).font(.footnote) }
                Section {
                    choices(burst.techniqueOptions, selected: $technique)
                } header: {
                    Text(L10n.get("recording_boost_label_technique"))
                } footer: {
                    // The watch's own verdict as a reminder, never preselected (the label is what it is checked against).
                    if burst.techniqueOptions.contains(burst.watchTechnique) {
                        Text(String(format: L10n.get("feedback_boost_watch_said"), BoostText.code(burst.watchTechnique), Int(burst.watchSeconds), Int(burst.recordSeconds)))
                    }
                }
                Section(L10n.get("recording_boost_label_terrain")) {
                    choices(burst.terrainOptions, selected: $terrain)
                }
                if !burst.surfaceOptions.isEmpty {
                    Section(L10n.get("recording_boost_label_surface")) {
                        ForEach(burst.surfaceOptions, id: \.self) { code in
                            row(BoostText.surface(code), on: surface == code) { surface = surface == code ? "" : code }
                        }
                    }
                }
                if burst.askPoles {
                    Section(L10n.get("recording_boost_label_poles")) {
                        row(L10n.get("recording_boost_label_poles_yes"), on: poles == 1) { poles = poles == 1 ? -1 : 1 }
                        row(L10n.get("recording_boost_label_poles_no"), on: poles == 0) { poles = poles == 0 ? -1 : 0 }
                    }
                }
                Section {
                    TextField(L10n.get("recording_boost_label_note"), text: $note)
                }
                if !burst.labelSummary.isEmpty {
                    Section {
                        Button(L10n.get("recording_boost_label_clear"), role: .destructive) { onSave("", "", -1, "", "") }
                    }
                }
            }
            .navigationTitle(L10n.get("recording_boost_label_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.get("common_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("recording_boost_label_save")) {
                        onSave(technique, terrain, burst.askPoles ? poles : -1, String(note.prefix(200)), burst.surfaceOptions.isEmpty ? "" : surface)
                    }
                }
            }
            .onAppear {
                technique = burst.labelTechnique
                terrain = burst.labelTerrain
                surface = burst.labelSurface
                poles = burst.labelPoles
                note = burst.labelNote
                // A first label starts from what the record makes known (run terrain, poles); never the technique.
                if burst.labelSummary.isEmpty {
                    if burst.terrainOptions.contains(burst.suggestedTerrain) { terrain = burst.suggestedTerrain }
                    if burst.askPoles { poles = burst.suggestedPoles }
                }
            }
        }
    }

    private func choices(_ codes: [String], selected: Binding<String>) -> some View {
        ForEach(codes, id: \.self) { code in
            row(BoostText.code(code), on: selected.wrappedValue == code) {
                selected.wrappedValue = selected.wrappedValue == code ? "" : code
            }
        }
    }

    private func row(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark") }
            }
        }
    }
}

/// A list that could not be loaded says so, instead of looking empty.
struct LoadFailedRow: View {
    let reason: String

    var body: some View {
        Text(String(format: L10n.get("ios_list_load_failed"), reason))
            .font(.footnote)
            .foregroundStyle(.red)
    }
}

private struct LogList: View {
    let lines: [LogLine]
    let loaded: Bool
    let empty: String
    var failure: String?

    var body: some View {
        List {
            if let failure { LoadFailedRow(reason: failure) }
            if loaded && lines.isEmpty && failure == nil {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Date(timeIntervalSince1970: TimeInterval(line.atEpochMillis) / 1000)
                        .formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(line.title).font(.subheadline)
                    if !line.detail.isEmpty {
                        Text(line.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Feedback

struct FeedbackScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    private let category: String

    /// The activity whose Recording Boost files start out chosen (its reminder was accepted): the form opens on the file picker.
    private let preselectActivityId: String

    /// One form per kind ([FeedbackHubScreen] picks it): [startCategory] "error_report", "feature_request",
    /// "other", "wording" (About > Help improve the translations) or "boost" (Recording Boost data, which opens on
    /// the file picker).
    init(startCategory: String = "error_report", preselectActivityId: String = "") {
        category = startCategory
        self.preselectActivityId = preselectActivityId
        _showBoostPicker = State(initialValue: !preselectActivityId.isEmpty || startCategory == "boost")
    }

    /// The server's limits (api/feedback.php): 3 to 4000 characters, as Android's form.
    private static let minMessage = 3
    private static let maxMessage = 4000
    /// Android's Patterns.EMAIL_ADDRESS, close to what the server's FILTER_VALIDATE_EMAIL accepts.
    private static let emailPattern = #"^[A-Za-z0-9+._%\-]{1,256}@[A-Za-z0-9][A-Za-z0-9\-]{0,64}(\.[A-Za-z0-9][A-Za-z0-9\-]{0,25})+$"#

    @State private var app = "companion"
    @State private var text = ""
    @State private var email = ""
    @State private var includeDetails = true
    @State private var includeNickname = false
    @State private var watches: [FeedbackWatchView] = []
    @State private var latestWatch = ""
    /// Index into [watches]; -1 = "Other watch" (typed in), also while no watch is known.
    @State private var watchIndex = 0
    @State private var otherWatch = ""
    @State private var wordingEntries: [WordingEntry] = []
    @State private var wordingPicked: WordingEntry?
    @State private var wordingLang = "en"
    @State private var wordingProposed = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    /// Recording Boost files, kept in memory only (a CSV is large).
    @State private var attached: [BoostAttached] = []
    @State private var showBoostPicker = false
    @State private var editingBoost: BoostAttached?
    @State private var tooLargeFile: String?
    @State private var extrasOpen = false
    /// Whether the form's own Send row is on screen; when it is not, a pinned copy shows at the bottom.
    @State private var sendVisible = true

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailValid: Bool {
        trimmedEmail.isEmpty || trimmedEmail.range(of: Self.emailPattern, options: .regularExpression) != nil
    }
    private var wording: Bool { category == "wording" }
    private var aboutWatch: Bool { !wording && !boost && app != "companion" }
    private var pickedWatch: FeedbackWatchView? {
        aboutWatch && watchIndex >= 0 && watches.indices.contains(watchIndex) ? watches[watchIndex] : nil
    }
    private var detailLines: [FeedbackDetailLine] {
        companion.feedbackDetailLines(
            aboutWatch: aboutWatch, watch: pickedWatch,
            otherWatch: otherWatch.trimmingCharacters(in: .whitespacesAndNewlines), latestWatch: latestWatch)
    }
    private var canSend: Bool {
        if boost { return !attached.isEmpty }
        if wording { return wordingPicked != nil && !wordingProposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let length = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return length >= Self.minMessage && length <= Self.maxMessage
    }
    private var hintKey: String {
        switch category {
        case "feature_request": return "feedback_message_hint_feature"
        case "other": return "feedback_message_hint_other"
        default: return "feedback_message_hint_error"
        }
    }

    /// The Recording Boost form: its files, an optional note, then the same extras and Send.
    private var boost: Bool { category == "boost" }
    /// Error, idea and "something else" ask which app; wording and Boost do not.
    private var problemForm: Bool { !wording && !boost }
    private var formTitleKey: String {
        switch category {
        case "feature_request": return "feedback_hub_feature"
        case "other": return "feedback_hub_other"
        case "wording": return "feedback_category_wording"
        case "boost": return "feedback_hub_boost"
        default: return "feedback_hub_error"
        }
    }
    private var extrasSummary: String {
        String(format: L10n.get("feedback_extras_summary"),
               L10n.get(includeDetails ? "feedback_extras_on" : "feedback_extras_off"),
               L10n.get(trimmedEmail.isEmpty ? "feedback_extras_off" : "feedback_extras_on"))
    }

    /// Send, the last row of the form; the pinned copy below shows only while this one is scrolled out of view.
    private var sendButton: some View {
        Button {
            Task { await send() }
        } label: {
            if sending {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text(boost ? String(format: L10n.get("feedback_boost_send"), attached.count + attached.filter { $0.withPhone }.count) : L10n.get("feedback_send"))
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(sending || !canSend || !emailValid)
    }

    var body: some View {
        Form {
            if sent {
                Section {
                    Text(L10n.get("feedback_thanks_title")).font(.headline)
                    Text(L10n.get("feedback_thanks_body"))
                    Button(L10n.get("feedback_thanks_done")) { dismiss() }
                }
            } else {
                if wording {
                    WordingPicker(entries: wordingEntries, appLanguage: companion.language,
                                  picked: $wordingPicked, lang: $wordingLang, proposed: $wordingProposed)
                }
                if problemForm {
                    Section {
                        Picker(L10n.get("feedback_app_label"), selection: $app) {
                            Text(L10n.get("feedback_app_watch")).tag("watch")
                            Text(L10n.get("feedback_app_companion")).tag("companion")
                            Text(L10n.get("feedback_app_both")).tag("both")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if aboutWatch {
                    // "Which watch?": the watches seen so far plus "Other watch" with a model field,
                    // only the field while none is known (Android's WatchChoice).
                    Section(L10n.get("feedback_watch_label")) {
                        if !watches.isEmpty {
                            Picker(L10n.get("feedback_watch_label"), selection: $watchIndex) {
                                ForEach(Array(watches.enumerated()), id: \.offset) { index, watch in
                                    Text(watch.name).tag(index)
                                }
                                Text(L10n.get("feedback_watch_other")).tag(-1)
                            }
                            .labelsHidden()
                        }
                        if watches.isEmpty || watchIndex < 0 {
                            TextField(L10n.get("feedback_watch_other_field"), text: $otherWatch)
                                .onChange(of: otherWatch) { _, value in
                                    if value.count > 100 { otherWatch = String(value.prefix(100)) }
                                }
                        }
                    }
                }
                if boost {
                    FeedbackBoostSection(attached: $attached, tooLargeFile: tooLargeFile,
                                         showPicker: $showBoostPicker, editing: $editingBoost)
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty && problemForm {
                            Text(L10n.get(hintKey))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text).frame(minHeight: boost ? 80 : 140)
                    }
                    .onChange(of: text) { _, value in
                        if value.count > Self.maxMessage { text = String(value.prefix(Self.maxMessage)) }
                    }
                } header: {
                    Text(L10n.get(wording ? "feedback_wording_reason" : "feedback_message_label"))
                } footer: {
                    if problemForm { Text("\(text.count) / \(Self.maxMessage)") }
                }
                // Technical details, reply e-mail and nickname: folded away, one line says what is on.
                Section {
                    DisclosureGroup(isExpanded: $extrasOpen) {
                        if !companion.nickname.isEmpty {
                            Toggle(L10n.get("feedback_nickname_switch"), isOn: $includeNickname)
                            Text(String(format: L10n.get(includeNickname ? "feedback_nickname_on" : "feedback_nickname_off"), companion.nickname))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.get("feedback_email_label")).font(.subheadline.weight(.semibold))
                            TextField("", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: email) { _, value in
                                    if value.count > 254 { email = String(value.prefix(254)) }
                                }
                            Text(L10n.get(emailValid ? "feedback_email_hint" : "feedback_email_invalid"))
                                .font(.footnote)
                                .foregroundStyle(emailValid ? Color.secondary : Color.red)
                        }
                        Toggle(L10n.get("feedback_details_switch"), isOn: $includeDetails)
                        // Listed in full, so the athlete sees exactly what would be sent.
                        if includeDetails {
                            ForEach(detailLines, id: \.self) { line in
                                Text("\(line.label): \(line.value)").font(.footnote).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(L10n.get("feedback_details_off")).font(.footnote).foregroundStyle(.secondary)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.get("feedback_extras_title"))
                            Text(extrasSummary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    sendButton
                        .onAppear { sendVisible = true }
                        .onDisappear { sendVisible = false }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !sent && !sendVisible {
                sendButton.padding().background(.bar)
            }
        }
        .navigationTitle(L10n.get(formTitleKey))
        .sheet(isPresented: $showBoostPicker) {
            FeedbackBoostPickerSheet(
                attachedKeys: Set(attached.map { $0.id }),
                // A record's phone motion record is a file of its own.
                capacity: Int(companion.core.feedbackBoostMaxFiles) - attached.count - attached.filter { $0.withPhone }.count,
                preselectActivityId: preselectActivityId
            ) { done in
                for item in done {
                    if let index = attached.firstIndex(where: { $0.id == item.id }) { attached[index] = item } else { attached.append(item) }
                }
                tooLargeFile = nil
            }
            .environmentObject(companion)
        }
        .sheet(item: Binding(get: { editingBoost }, set: { editingBoost = $0 })) { item in
            BoostEditSheet(attached: item) { changed in
                if let index = attached.firstIndex(where: { $0.id == changed.id }) { attached[index] = changed }
            }
            .environmentObject(companion)
        }
        .task {
            watches = await companion.feedbackWatches()
            if watches.isEmpty { watchIndex = -1 }
            latestWatch = await companion.latestWatchName()
            wordingEntries = WordingFeedback.load()
        }
    }

    private func send() async {
        sending = true
        error = nil
        var sendApp = app
        var sendCategory = category
        var sendText = text
        var extra: [String: String] = [:]
        if boost {
            // Only the athlete's note: the shared sendFeedback puts the "Sensor Record data" line on each part itself
            // (FeedbackUploadParts.message), as on Android.
            sendApp = "watch"
            sendCategory = "other"
            sendText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if wording, let entry = wordingPicked {
            let composed = WordingFeedback.compose(
                entry: entry, lang: wordingLang, current: entry.texts[wordingLang] ?? "",
                proposed: wordingProposed.trimmingCharacters(in: .whitespacesAndNewlines),
                reason: text.trimmingCharacters(in: .whitespacesAndNewlines))
            sendApp = entry.app.wireValue
            sendCategory = "other"
            sendText = composed.message
            extra = composed.details
        }
        let result = await companion.sendFeedback(
            category: sendCategory, app: sendApp, text: sendText, email: trimmedEmail,
            details: includeDetails ? detailLines : [], includeNickname: includeNickname, extraDetails: extra,
            attachments: boost ? attached : []
        )
        sending = false
        if result.hasPrefix("tooLarge:") {
            tooLargeFile = String(result.dropFirst("tooLarge:".count))
            return
        }
        // "partial:<records sent>:<tooMany|failed>": the first records arrived (in the order sent). They leave the
        // selection, so Send again uploads only the rest instead of duplicating them on the server.
        if result.hasPrefix("partial:") {
            let parts = result.split(separator: ":")
            let arrived = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            let total = attached.count
            attached.removeFirst(min(arrived, attached.count))
            error = String(format: L10n.get("feedback_boost_partial"), arrived, total) + "\n"
                + L10n.get(parts.count > 2 && parts[2] == "tooMany" ? "feedback_error_too_many" : "feedback_error_failed")
            return
        }
        switch result {
        case "sent": sent = true
        case "tooMany": error = L10n.get("feedback_error_too_many")
        default: error = L10n.get("feedback_error_failed")
        }
    }
}

/// "What do you want to tell us?": one row per kind of feedback, each opening its own short form
/// (Android's FeedbackHub). Recording Boost data is its own top-level kind, with the number of
/// activities waiting for a decision.
struct FeedbackHubScreen: View {
    @EnvironmentObject var companion: Companion

    private func row(_ symbol: String, _ key: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 28).foregroundStyle(CardTone.blue.title)
            Text(L10n.get(key))
            Spacer()
            if let badge { Text(badge).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    var body: some View {
        List {
            Section { Text(L10n.get("feedback_intro")).font(.footnote) }
            Section {
                NavigationLink { FeedbackScreen(startCategory: "error_report") } label: {
                    row("exclamationmark.triangle", "feedback_hub_error")
                }
                NavigationLink { FeedbackScreen(startCategory: "feature_request") } label: {
                    row("lightbulb", "feedback_hub_feature")
                }
                NavigationLink { FeedbackScreen(startCategory: "boost") } label: {
                    row("waveform.path.ecg", "feedback_hub_boost",
                        badge: companion.boostReminders.isEmpty ? nil
                            : String(format: L10n.get("feedback_hub_waiting"), companion.boostReminders.count))
                }
                NavigationLink { FeedbackScreen(startCategory: "wording") } label: {
                    row("character.bubble", "feedback_category_wording")
                }
                NavigationLink { FeedbackScreen(startCategory: "other") } label: {
                    row("envelope", "feedback_hub_other")
                }
            }
        }
        .homeTitle(L10n.get("feedback_title"))
    }
}

// MARK: - Add activity by hand

/// "Add activity" by hand (Android `AddActivityScreen`): the type step by step as on the recording start screen
/// (activity, style where there is one, purpose where there is one; the shared `PhoneRecordingCatalog.manualFamilies`,
/// with swimming, SUP and plain Training), the last choice remembered; then duration and when.
struct AddActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    @AppStorage("manual_preset") private var preset = "rollskiSkating"
    @AppStorage("manual_purpose") private var endurancePurpose = "endurance"
    @AppStorage("manual_strength_purpose") private var strengthPurpose = "hypertrophy"
    @State private var endedNow = true
    @State private var minutes = 60
    @State private var otherMinutes = ""
    @State private var start = Date()
    @State private var saving = false

    private static let durations = [30, 60, 90, 120]

    private var duration: Int { Int(otherMinutes) ?? minutes }
    private var catalog: PhoneRecordingCatalog { PhoneRecordingCatalog.shared }
    private var family: PhoneRecordingCatalog.Family { catalog.manualFamilyOf(preset: preset) ?? catalog.manualFamilies[0] }
    private var strengthPurposes: Bool { preset == catalog.STRENGTH }
    private var purpose: String { strengthPurposes ? strengthPurpose : endurancePurpose }
    private var purposes: [String] { strengthPurposes ? catalog.strengthPurposes : catalog.purposes }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.get("add_activity_type_heading")) {
                    ChipFlow(spacing: 8) {
                        ForEach(catalog.manualFamilies.indices, id: \.self) { i in
                            let f = catalog.manualFamilies[i]
                            chip(L10n.get(f.labelKey), on: f.key == family.key) {
                                if f.key != family.key { preset = f.styles[0].preset }
                            }
                        }
                    }
                }
                if family.styles.count > 1 {
                    Section(L10n.get("phone_start_style")) {
                        ChipFlow(spacing: 8) {
                            ForEach(family.styles.indices, id: \.self) { i in
                                let style = family.styles[i]
                                chip(L10n.get(style.labelKey), on: style.preset == preset) { preset = style.preset }
                            }
                        }
                    }
                }
                // Walk and the training presets but Strength have no purpose (as on the watch): Endurance.
                if catalog.hasPurpose(preset: preset) {
                    Section(L10n.get("phone_start_purpose")) {
                        ChipFlow(spacing: 8) {
                            ForEach(purposes, id: \.self) { p in
                                chip(L10n.get("watch_training_type_\(p)"), on: p == purpose) {
                                    if strengthPurposes { strengthPurpose = p } else { endurancePurpose = p }
                                }
                            }
                        }
                    }
                }
                Section(L10n.get("add_activity_duration_heading")) {
                    Picker(L10n.get("add_activity_duration_heading"), selection: $minutes) {
                        ForEach(Self.durations, id: \.self) { value in
                            Text(String(format: L10n.get("add_activity_duration_minutes"), value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(L10n.get("add_activity_duration_other"), text: $otherMinutes)
                        .keyboardType(.numberPad)
                }
                Section(L10n.get("add_activity_when_heading")) {
                    Picker(L10n.get("add_activity_when_heading"), selection: $endedNow) {
                        Text(L10n.get("add_activity_ended_now")).tag(true)
                        Text(L10n.get("add_activity_starts_now")).tag(false)
                    }
                    .pickerStyle(.segmented)
                    DatePicker(L10n.get("activity_detail_started_label"), selection: $start)
                }
            }
            .navigationTitle(L10n.get("add_activity_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.get("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("add_activity_save_button")) {
                        Task {
                            saving = true
                            let id = await companion.addActivity(typeKey: preset, purpose: purpose, start: start, minutes: duration)
                            saving = false
                            if id != nil { dismiss() }
                        }
                    }
                    .disabled(saving || duration <= 0)
                }
            }
            .onAppear {
                // A remembered type that is no longer offered starts again at the first one.
                if catalog.manualFamilyOf(preset: preset) == nil { preset = catalog.manualFamilies[0].styles[0].preset }
                updateStart()
            }
            .onChange(of: endedNow) { _, _ in updateStart() }
            .onChange(of: minutes) { _, _ in updateStart() }
            .onChange(of: otherMinutes) { _, _ in updateStart() }
        }
    }

    /// "Ended now" starts the activity its duration ago; "Starts now" starts it now.
    private func updateStart() {
        start = endedNow ? Date().addingTimeInterval(-Double(duration) * 60) : Date()
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

// MARK: - Edit an activity

/// Android's review screen, field for field (the same shared rules, `ReviewFields`): name, sport
/// and style, training type, the numbers and their corrections, both splits, effort, comment,
/// feeling, note and equipment. Saving is the review.
/// A field label with a small info button that explains the field in an alert (Android's `LabelWithInfo`).
private struct InfoLabel: View {
    let text: String
    let info: String
    var font: Font = .body
    @State private var shown = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(font)
            Button { shown = true } label: { Image(systemName: "info.circle").imageScale(.small) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(format: L10n.get("activity_detail_info_content_description"), text))
        }
        .alert(text, isPresented: $shown) {
            Button(L10n.get("activity_detail_info_got_it"), role: .cancel) {}
        } message: {
            Text(info)
        }
    }
}

/// A picker row whose label carries an info button.
private struct InfoPicker<Selection: Hashable, Content: View>: View {
    let label: String
    let info: String
    @Binding var selection: Selection
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack {
            InfoLabel(text: label, info: info)
            Spacer()
            Picker(label, selection: $selection, content: content).labelsHidden()
        }
    }
}

struct EditActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let item: ActivityItem
    @State private var title: String
    @State private var trainingType: String
    @State private var sport: SportArt
    @State private var style: SportStyle
    @State private var rpe: Int
    @State private var feeling: Int
    @State private var comment: String
    @State private var note: String
    @State private var durationText: String
    @State private var distanceText: String
    @State private var hrText: String
    /// The seven intensity fields (HR zones 1 to 5, Wettkampf, Schnelligkeit); the measured split shows until edited.
    @State private var intensityTexts: [String]
    @State private var intensityEdited: Bool
    /// The Trainingsmittel fields [main, sub]; the whole session in one row shows until edited.
    @State private var disciplineTexts: [String]
    @State private var disciplineEdited: Bool
    @State private var wheelType: Int
    @State private var waxType: Int
    @State private var stravaDescriptionMode: Int32
    /// The Strava title and sport type the athlete chose; nil = not chosen (the rule's, or a renamed title).
    @State private var livePreview: StravaWritePreview?
    @State private var splitsSpread = false
    @State private var stravaTitle: String?
    @State private var stravaSportType: String?
    @State private var saving = false
    /// The Trainingsmittel pair the stored split was made for: it applies only while the pair stays the same.
    private let initialPair: [String]

    init(item: ActivityItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _trainingType = State(initialValue: item.trainingType)
        _sport = State(initialValue: item.sportArt)
        _style = State(initialValue: item.sportStyle)
        _rpe = State(initialValue: Int(item.rpe))
        _feeling = State(initialValue: Int(item.feeling))
        // The diary description starts with the activity title, editable like the rest.
        _comment = State(initialValue: Self.commentWithTitle(item.title, item.diaryComment))
        _note = State(initialValue: item.note)
        let measured = item.elapsedSec
        _durationText = State(initialValue: DiaryFields.shared.formatDuration(totalSeconds: item.overrideElapsedSec > 0 ? item.overrideElapsedSec : measured))
        _distanceText = State(initialValue: Self.km(item.overrideDistanceM > 0 ? item.overrideDistanceM : item.distanceM))
        _hrText = State(initialValue: Self.bpm(item.overrideAvgHeartRate > 0 ? item.overrideAvgHeartRate : item.avgHeartRate))
        _intensityEdited = State(initialValue: !item.intensityMinutes.isEmpty)
        _intensityTexts = State(initialValue: item.intensityMinutes.isEmpty
            ? Array(repeating: "", count: 7) : item.intensityMinutes.map { String(Int($0.floatValue.rounded())) })
        let pair = ReviewFields.shared.disciplinePair(preset: Self.livePreset(item, item.sportArt, item.sportStyle), trainingType: item.trainingType)
        initialPair = pair
        _disciplineEdited = State(initialValue: !item.disciplineMinutes.isEmpty)
        _disciplineTexts = State(initialValue: item.disciplineMinutes.count == 2
            ? item.disciplineMinutes.map { String(Int($0.floatValue.rounded())) } : ["", ""])
        _wheelType = State(initialValue: Int(item.wheelType))
        _waxType = State(initialValue: Int(item.waxType))
        _stravaDescriptionMode = State(initialValue: Int32(item.stravaDescriptionMode))
    }

    // MARK: Values

    /// The preset the chosen Sportart and Sportstil make; a row without a preset (Strava origin) keeps none.
    private static func livePreset(_ item: ActivityItem, _ sport: SportArt, _ style: SportStyle) -> String {
        item.preset.isEmpty ? item.preset : sport.presetFor(style: style)
    }

    private static func km(_ meters: Float) -> String { meters <= 0 ? "" : String(format: "%.2f", Double(meters) / 1000) }
    private static func bpm(_ value: Int32) -> String { value > 0 ? String(value) : "" }
    private static func blank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    private static func digits(_ text: String, max: Int) -> String { String(text.filter(\.isNumber).prefix(max)) }

    private var livePreset: String { Self.livePreset(item, sport, style) }

    private var measuredSeconds: Int { Int(item.elapsedSec) }
    private var durationSeconds: Int? { DiaryFields.shared.parseDuration(text: durationText)?.intValue }
    private var durationInvalid: Bool { !Self.blank(durationText) && durationSeconds == nil }
    /// 0 = as measured.
    private var durationOverride: Int {
        if let seconds = durationSeconds, seconds != measuredSeconds { return seconds }
        return 0
    }

    private var distanceChanged: Bool { !Self.blank(distanceText) && distanceText != Self.km(item.distanceM) }
    private var distanceOverrideM: Float {
        distanceChanged ? (DiaryFields.shared.parseDistanceKm(text: distanceText)?.floatValue ?? 0) : 0
    }
    private var distanceInvalid: Bool { distanceChanged && distanceOverrideM == 0 }

    private var hrChanged: Bool { !Self.blank(hrText) && hrText != Self.bpm(item.avgHeartRate) }
    private var hrOverride: Int32 {
        guard hrChanged, let value = Int32(hrText), Int(value) >= 30, Int(value) <= 250 else { return 0 }
        return value
    }
    private var hrInvalid: Bool { hrChanged && hrOverride == 0 }

    /// The duration after the diary's rounding up to 5 minutes (when it rounds): the corrected one, else the measured one.
    private var roundedSeconds: Int32 {
        DiaryFields.shared.diaryDurationSec(durationSec: Int32(durationSeconds ?? measuredSeconds),
                                            roundUp: companion.diarySettings.roundDurationUp)
    }
    /// The minutes both splits add up to.
    private var totalMinutes: Int { Int(DiaryFields.shared.diaryMinutes(elapsedTimeSec: roundedSeconds)) }

    // Intensity split
    private var measuredSplit: [Int] {
        DiaryFields.shared.distribute(shares: item.measuredIntensityShares, total: Int32(totalMinutes)).map { $0.intValue }
    }
    private var shownIntensityTexts: [String] {
        if intensityEdited { return intensityTexts }
        return measuredSplit.reduce(0, +) > 0 ? measuredSplit.map { String($0) } : Array(repeating: "", count: 7)
    }
    private var intensityCheck: SplitCheck {
        ReviewFields.shared.intensityCheck(texts: shownIntensityTexts, edited: intensityEdited, totalMinutes: Int32(totalMinutes),
                                           measured: measuredSplit.map { KotlinInt(int: Int32($0)) })
    }

    // Trainingsmittel split
    private var disciplinePair: [String] {
        ReviewFields.shared.disciplinePair(preset: livePreset, trainingType: trainingType)
    }
    private var defaultDiscipline: [Int] {
        ReviewFields.shared.defaultDisciplineMinutes(preset: livePreset, trainingType: trainingType, totalMinutes: Int32(totalMinutes)).map { $0.intValue }
    }
    private var shownDisciplineTexts: [String] { disciplineEdited ? disciplineTexts : defaultDiscipline.map { String($0) } }
    private var disciplineCheck: SplitCheck {
        ReviewFields.shared.disciplineCheck(texts: shownDisciplineTexts, edited: disciplineEdited, hasPair: !disciplinePair.isEmpty,
                                            totalMinutes: Int32(totalMinutes), default: defaultDiscipline.map { KotlinInt(int: Int32($0)) })
    }
    /// The watch's own guess for the sub-row, offered with one tap.
    private var suggestedSub: Int? {
        guard disciplinePair.count == 2 else { return nil }
        let suggested = DiaryFields.shared.suggestedSubMinutes(
            subKey: disciplinePair[1], techniqueCatalog: item.techniqueCatalog,
            techniqueSharePercent: item.techniqueSharePercent, totalMinutes: Int32(totalMinutes))?.intValue
        return suggested == disciplineCheck.values[1].intValue ? nil : suggested
    }

    private var inputInvalid: Bool {
        durationInvalid || distanceInvalid || hrInvalid || intensityCheck.invalid || disciplineCheck.invalid
    }

    private func setIntensity(_ index: Int, _ text: String) {
        if !intensityEdited {
            intensityTexts = shownIntensityTexts
            intensityEdited = true
        }
        intensityTexts[index] = Self.digits(text, max: 4)
    }

    private func setDiscipline(_ index: Int, _ text: String) {
        if !disciplineEdited {
            disciplineTexts = shownDisciplineTexts
            disciplineEdited = true
        }
        let clean = Self.digits(text, max: 4)
        disciplineTexts[index] = clean
        // The other field takes the rest of the duration.
        if let value = Int(clean) { disciplineTexts[1 - index] = String(max(0, totalMinutes - value)) }
    }

    /// A pair change (another sport, style or training type) starts the split afresh; the stored one applies to its own pair only.
    private func resetDisciplineForPair() {
        let stored = storedDisciplineApplies
        disciplineEdited = stored
        disciplineTexts = stored ? spread(item.disciplineMinutes) : ["", ""]
    }

    /// A stored split fitted to today's rounded duration (the diary rounding may have changed since it was saved).
    private func spread(_ stored: [KotlinFloat]) -> [String] {
        DiaryFields.shared.distribute(shares: stored, total: Int32(totalMinutes)).map { String($0.intValue) }
    }

    /// Once, when the sheet opens: the stored splits show as they fit the current duration.
    private func spreadStoredSplits() {
        guard !splitsSpread else { return }
        splitsSpread = true
        if !item.intensityMinutes.isEmpty { intensityTexts = spread(item.intensityMinutes) }
        if storedDisciplineApplies { disciplineTexts = spread(item.disciplineMinutes) }
    }

    /// A stored Trainingsmittel split only applies to the pair it was made for.
    private var storedDisciplineApplies: Bool {
        item.disciplineMinutes.count == 2 && disciplinePair == initialPair
    }

    // MARK: Pieces

    private var trainingOptions: [(String, String)] {
        sport == .strength
            ? [("hypertrophy", "activity_detail_training_option_hypertrophy"),
               ("speedStrength", "activity_detail_training_option_speed_strength"),
               ("strengthEndurance", "activity_detail_training_option_strength_endurance")]
            : [("endurance", "activity_detail_training_option_endurance"),
               ("intervals", "activity_detail_training_option_intervals"),
               ("technique", "activity_detail_training_option_technique"),
               ("sprints", "activity_detail_training_option_sprints"),
               ("race", "activity_detail_training_option_race")]
    }

    private static let sports: [SportArt] = [
        .langlauf, .rollski, .laufen, .stocklauf, .gehen, .wandern, .nordicWalking, .inlineskaten, .cycling, .mtb, .swimming, .sup,
        .strength, .training, .other,
    ]
    private static let styles: [SportStyle] = [.skating, .klassisch, .doppelstock]

    /// [comment] with [title] as its first line; the title it started with ([replacing], or [title] in other
    /// punctuation or with a typo) is replaced, never stacked. The shared rule (`DiaryFields.commentWithTitle`,
    /// words compared via `SameText`), the same as Android.
    static func commentWithTitle(_ title: String, _ comment: String, replacing: String? = nil) -> String {
        DiaryFields.shared.commentWithTitle(title: title, comment: comment, replacing: replacing ?? title)
    }

    /// The title typed above, when it differs from the stored one: it becomes the Strava title proposal.
    private var renamedTo: String? {
        let new = title.trimmingCharacters(in: .whitespaces)
        return !new.isEmpty && new != item.title.trimmingCharacters(in: .whitespaces) ? new : nil
    }

    /// The small trash button of a Strava field.
    private func clearButton(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .disabled(!enabled)
            .accessibilityLabel(label)
    }

    /// The tint of the rows the diary entry is built from (the same yellow as the review box on the detail screen).
    private static let diaryRow = CardTone.yellow.container

    private static let feelings = [
        "activity_detail_feeling_option_not_entered", "activity_detail_feeling_option_very_weak",
        "activity_detail_feeling_option_weak", "activity_detail_feeling_option_normal",
        "activity_detail_feeling_option_good", "activity_detail_feeling_option_very_good",
    ]

    private static let wheelOptions = [
        "activity_detail_wheel_option_na", "activity_detail_wheel_option_fast", "activity_detail_wheel_option_standard",
        "activity_detail_wheel_option_slow", "activity_detail_wheel_option_super_slow",
    ]
    private static let waxOptions = [
        "activity_detail_wax_option_na", "activity_detail_wax_option_klister",
        "activity_detail_wax_option_trockenwachs", "activity_detail_wax_option_nowax",
    ]

    /// One corrected number: its field, the measured value it falls back to, and what the value is.
    private func overrideRow(
        _ label: String, text: Binding<String>, suffix: String, keyboard: UIKeyboardType,
        measured: String, overridden: Bool, invalid: Bool, info: String? = nil, reset: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            LabeledContent {
                TextField(measured, text: text)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(invalid ? Color.red : Color.primary)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
                if overridden || invalid {
                    Button(action: reset) { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.get("activity_detail_override_reset"))
                }
            } label: {
                if let info { InfoLabel(text: label, info: info) } else { Text(label) }
            }
            Text(invalid ? L10n.get("activity_detail_override_invalid")
                 : overridden ? String(format: L10n.get("activity_detail_override_changed"), measured.isEmpty ? "-" : measured)
                 : !measured.isEmpty ? L10n.get("activity_detail_override_measured")
                 : L10n.get("activity_detail_override_not_measured"))
                .font(.caption)
                .foregroundStyle(invalid ? Color.red : Color.secondary)
        }
    }

    /// A small minutes box of a split.
    /// A zone's box has a frame in that zone's watch colour (`hrZoneColor`); an error keeps its red.
    private func minutesBox(_ label: String, text: Binding<String>, invalid: Bool, frame: Color? = nil, range: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(invalid ? Color.red : (frame ?? Color.clear), lineWidth: invalid || frame == nil ? 1 : 1.5))
            // A zone's range from the athlete's own limits (watch 0.9.123+), as on Android.
            if let range { Text(range).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }

    private var intensitySplit: some View {
        let check = intensityCheck
        let changed = check.overrideMinutes != nil
        let zones = Array(measuredSplit.prefix(5))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.get("activity_detail_intensity_split_label")).font(.subheadline)
                Spacer()
                if changed || check.invalid {
                    Button { intensityEdited = false } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L10n.get("activity_detail_override_reset"))
                }
            }
            // The diary's order: Wettkampf and Schnelligkeit on top, then the zones.
            HStack(spacing: 6) {
                ForEach([5, 6], id: \.self) { index in
                    minutesBox(L10n.get(index == 5 ? "activity_detail_intensity_wettkampf" : "activity_detail_intensity_schnelligkeit"),
                               text: Binding(get: { shownIntensityTexts[index] }, set: { setIntensity(index, $0) }),
                               invalid: check.invalid)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { zone in
                    minutesBox(String(format: L10n.get("activity_detail_hr_zone_short"), zone + 1),
                               text: Binding(get: { shownIntensityTexts[zone] }, set: { setIntensity(zone, $0) }),
                               invalid: check.invalid, frame: hrZoneColor(zone + 1),
                               range: HrZoneBounds.shared.rangeText(bounds: item.hrZoneBounds, zone: Int32(zone + 1)))
                }
            }
            Text(check.invalid && Int(check.sum) != totalMinutes
                 ? String(format: L10n.get("activity_detail_intensity_split_mismatch"), Int(check.sum), totalMinutes)
                 : check.invalid ? L10n.get("activity_detail_override_invalid")
                 : changed ? String(format: L10n.get("activity_detail_intensity_split_changed"),
                                    zones.reduce(0, +) > 0 ? zones.map { String($0) }.joined(separator: " / ") : "-")
                 : measuredSplit.contains(where: { $0 > 0 }) ? L10n.get("activity_detail_override_measured")
                 : L10n.get("activity_detail_intensity_split_none"))
                .font(.caption)
                .foregroundStyle(check.invalid ? Color.red : Color.secondary)
            Text(L10n.get("activity_detail_intensity_split_info")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var disciplineSplit: some View {
        if disciplinePair.count == 2 {
            let check = disciplineCheck
            let labels = ReviewFields.shared.disciplineLabelKeys(subDisciplineKey: disciplinePair[1])
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.get("activity_detail_discipline_split_label")).font(.subheadline)
                    Spacer()
                    if check.overrideMinutes != nil || check.invalid {
                        Button { disciplineEdited = false } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.get("activity_detail_override_reset"))
                    }
                }
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        minutesBox(L10n.get(labels[index]) + " (min)",
                                   text: Binding(get: { shownDisciplineTexts[index] }, set: { setDiscipline(index, $0) }),
                                   invalid: check.invalid)
                    }
                }
                Text(check.invalid && Int(check.sum) != totalMinutes
                     ? String(format: L10n.get("activity_detail_intensity_split_mismatch"), Int(check.sum), totalMinutes)
                     : check.invalid ? L10n.get("activity_detail_override_invalid")
                     : check.overrideMinutes != nil ? L10n.get("activity_detail_discipline_split_changed")
                     : L10n.get("activity_detail_discipline_split_default"))
                    .font(.caption)
                    .foregroundStyle(check.invalid ? Color.red : Color.secondary)
                if let suggested = suggestedSub {
                    HStack {
                        Text(String(format: L10n.get("activity_detail_discipline_split_suggestion"), suggested))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.get("activity_detail_discipline_split_apply")) {
                            disciplineTexts = [String(totalMinutes - suggested), String(suggested)]
                            disciplineEdited = true
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Text(L10n.get("activity_detail_discipline_split_info")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                // Everything the diary entry is built from is framed in yellow, as on Android.
                Section {
                    TextField(L10n.get("activity_detail_name_label"), text: $title)
                        .onChange(of: title) { old, new in
                            // The title leads the diary description: renaming it renames that part too.
                            comment = Self.commentWithTitle(new, comment, replacing: old)
                        }
                    InfoPicker(label: L10n.get("activity_detail_sport_label"), info: L10n.get("activity_detail_sport_info"), selection: $sport) {
                        ForEach(Self.sports, id: \.self) { Text(L10n.get($0.optionKey)).tag($0) }
                    }
                    .onChange(of: sport) { _, _ in resetDisciplineForPair() }
                    // Garmin Connect and Strava hints share one line (Android: the same).
                    Text(String(format: L10n.get("activity_detail_sport_garmin_hint"), L10n.get(sport.garminKey))
                         + "  ·  " + String(format: L10n.get("activity_detail_sport_strava_hint"), L10n.get(sport.stravaKey)))
                        .font(.caption).foregroundStyle(.secondary)
                    if sport.hasStyle {
                        InfoPicker(label: L10n.get("activity_detail_style_label"), info: L10n.get("activity_detail_style_info"), selection: $style) {
                            ForEach(Self.styles, id: \.self) { Text(L10n.get($0.optionKey)).tag($0) }
                        }
                        .onChange(of: style) { _, _ in resetDisciplineForPair() }
                        Text(String(format: L10n.get("activity_detail_style_garmin_hint"), L10n.get(style.garminKey)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    InfoPicker(label: L10n.get("activity_detail_training_type_label"), info: L10n.get("activity_detail_training_type_info"), selection: $trainingType) {
                        ForEach(trainingOptions, id: \.0) { option in Text(L10n.get(option.1)).tag(option.0) }
                        if !trainingOptions.contains(where: { $0.0 == trainingType }) {
                            Text(Format.trainingTypeWord(trainingType)).tag(trainingType)
                        }
                    }
                    .onChange(of: trainingType) { _, _ in resetDisciplineForPair() }
                } header: {
                    Text(L10n.get("detail_group_activity"))
                }
                .listRowBackground(Self.diaryRow)
                Section {
                    overrideRow(L10n.get("activity_detail_duration_label"), text: $durationText, suffix: "", keyboard: .numbersAndPunctuation,
                                measured: DiaryFields.shared.formatDuration(totalSeconds: item.elapsedSec),
                                overridden: durationOverride != 0, invalid: durationInvalid,
                                info: L10n.get("activity_detail_duration_info")) {
                        durationText = DiaryFields.shared.formatDuration(totalSeconds: item.elapsedSec)
                    }
                    // What the diary books after its rounding; the splits below add up to it.
                    LabeledContent(L10n.get("activity_detail_rounded_duration_label"), value: Format.duration(roundedSeconds))
                    overrideRow(L10n.get("activity_detail_distance_label"), text: $distanceText, suffix: "km", keyboard: .decimalPad,
                                measured: Self.km(item.distanceM), overridden: distanceOverrideM > 0, invalid: distanceInvalid) {
                        distanceText = Self.km(item.distanceM)
                    }
                    overrideRow(L10n.get("activity_detail_avg_hr_label"), text: $hrText, suffix: "bpm", keyboard: .numberPad,
                                measured: Self.bpm(item.avgHeartRate), overridden: hrOverride > 0, invalid: hrInvalid) {
                        hrText = Self.bpm(item.avgHeartRate)
                    }
                } header: {
                    Text(L10n.get("detail_group_numbers"))
                }
                .listRowBackground(Self.diaryRow)
                Section {
                    intensitySplit
                    disciplineSplit
                } header: {
                    Text(L10n.get("detail_group_split"))
                }
                .listRowBackground(Self.diaryRow)
                .onChange(of: totalMinutes) { _, total in
                    // A changed duration keeps the athlete's sub-row minutes; the main row takes the rest.
                    if disciplineEdited, let sub = Int(disciplineTexts[1]), sub <= total { disciplineTexts[0] = String(total - sub) }
                }
                Section {
                    InfoPicker(label: L10n.get("activity_detail_rpe_label"), info: L10n.get("activity_detail_rpe_info"), selection: $rpe) {
                        ForEach(0...10, id: \.self) { value in Text(value == 0 ? "–" : "\(value)").tag(value) }
                    }
                    if let load = DiaryFields.shared.fosterLoad(rpe: Int32(rpe), elapsedTimeSec: roundedSeconds)?.intValue {
                        Text(String(format: L10n.get("activity_detail_foster_load"), load))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        InfoLabel(text: L10n.get("activity_detail_diary_comment_label"), info: L10n.get("activity_detail_diary_comment_info"), font: .caption)
                        TextEditor(text: $comment).frame(minHeight: 80)
                    }
                } header: {
                    Text(L10n.get("detail_group_effort"))
                }
                .listRowBackground(Self.diaryRow)
                Section(L10n.get("activity_detail_section_feeling")) {
                    InfoPicker(label: L10n.get("activity_detail_feeling_label"), info: L10n.get("activity_detail_feeling_info"), selection: $feeling) {
                        ForEach(Self.feelings.indices, id: \.self) { index in Text(L10n.get(Self.feelings[index])).tag(index) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        InfoLabel(text: L10n.get("activity_detail_note_label"), info: L10n.get("activity_detail_note_info"), font: .caption)
                        TextEditor(text: $note).frame(minHeight: 70)
                    }
                }
                .listRowBackground(CardTone.red.container)
                // Wheel only applies to rollerski presets, wax to Langlauf Classic; both show for an unknown preset or a stored value.
                let showWheel = EquipmentLabels.shared.showsWheel(preset: livePreset, wheelType: Int32(wheelType))
                let showWax = EquipmentLabels.shared.showsWax(preset: livePreset, waxType: Int32(waxType))
                if showWheel || showWax {
                    Section(L10n.get("activity_detail_section_equipment")) {
                        if showWheel {
                            InfoPicker(label: L10n.get("activity_detail_wheel_label"), info: L10n.get("activity_detail_wheel_info"), selection: $wheelType) {
                                ForEach(Self.wheelOptions.indices, id: \.self) { Text(L10n.get(Self.wheelOptions[$0])).tag($0) }
                            }
                        }
                        if showWax {
                            InfoPicker(label: L10n.get("activity_detail_wax_label"), info: L10n.get("activity_detail_wax_info"), selection: $waxType) {
                                ForEach(Self.waxOptions.indices, id: \.self) { Text(L10n.get(Self.waxOptions[$0])).tag($0) }
                            }
                        }
                    }
                    .listRowBackground(CardTone.purple.container)
                }
                if let preview = activePreview {
                    // PRIVACY-SYNC: the athlete selects how much generated analysis to send, or removes our blocks.
                    let selectedPreview = preview.withMode(mode: stravaDescriptionMode)
                    let shownTitle = stravaTitle ?? renamedTo ?? preview.title
                    let shownSportType = stravaSportType ?? preview.sportType
                    let sportTypes = (preview.sportTypeOptions as [Any]).compactMap { $0 as? String }
                    Section {
                        // An emptied field means: not changed on Strava.
                        HStack {
                            TextField(L10n.get("activity_detail_strava_preview_title"),
                                      text: Binding(get: { shownTitle }, set: { stravaTitle = $0 }))
                            if shownTitle.trimmingCharacters(in: .whitespaces) != preview.generatedTitle {
                                Button(L10n.get("activity_detail_strava_title_reset")) { stravaTitle = preview.generatedTitle }
                                    .buttonStyle(.borderless)
                            }
                            clearButton(L10n.get("activity_detail_strava_field_clear"), enabled: !shownTitle.isEmpty) {
                                stravaTitle = ""
                            }
                        }
                        HStack {
                            Picker(L10n.get("activity_detail_strava_preview_sport_type"),
                                   selection: Binding(get: { shownSportType }, set: { stravaSportType = $0 })) {
                                if !sportTypes.contains(shownSportType) {
                                    Text(shownSportType.isEmpty ? "–" : shownSportType).tag(shownSportType)
                                }
                                ForEach(sportTypes, id: \.self) { Text($0).tag($0) }
                            }
                            clearButton(L10n.get("activity_detail_strava_field_clear"), enabled: !shownSportType.isEmpty) {
                                stravaSportType = ""
                            }
                        }
                        // The description sits in a thin grey frame like a text box, its buttons inside.
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L10n.get("activity_detail_strava_preview_description"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    stravaDescriptionMode = max(0, stravaDescriptionMode - 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(!selectedPreview.canShrink)
                                .accessibilityLabel(L10n.get("activity_detail_strava_description_shrink"))
                                Button {
                                    stravaDescriptionMode = stravaDescriptionMode == 3 ? 0 : min(2, stravaDescriptionMode + 1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(!selectedPreview.canGrow)
                                .accessibilityLabel(L10n.get("activity_detail_strava_description_grow"))
                                clearButton(L10n.get("activity_detail_strava_description_remove"), enabled: stravaDescriptionMode != 3) {
                                    stravaDescriptionMode = 3
                                }
                            }
                            if !selectedPreview.description_.isEmpty {
                                Text(selectedPreview.description_)
                                    .textSelection(.enabled)
                            } else if stravaDescriptionMode == 3 {
                                Text(L10n.get("activity_detail_strava_description_removed"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.5), lineWidth: 1))
                    } header: {
                        HStack {
                            Text(L10n.get("activity_detail_strava_preview_heading"))
                            Spacer()
                            // Empties title and description and puts the sport type back to the rule's.
                            clearButton(L10n.get("activity_detail_strava_clear_all"), enabled: true) {
                                stravaTitle = ""
                                stravaSportType = nil
                                stravaDescriptionMode = 3
                            }
                        }
                    } footer: {
                        Text(L10n.get("activity_detail_strava_preview_note"))
                    }
                    .listRowBackground(CardTone.orange.container)
                }
                sendSection
            }
            .onAppear { spreadStoredSplits() }
            .task(id: currentEdit) {
                guard item.stravaPreview != nil else { return }
                // Typing settles first; a newer change cancels this task.
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                if let fresh = await companion.stravaPreview(item.id, edit: currentEdit) { livePreview = fresh }
            }
            .navigationTitle(L10n.get("activity_detail_review_heading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.get("common_cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Automatic mode sends on its own: the form action replaces this toolbar Save.
                    if !(companion.automaticSync && companion.sendsSomewhere) {
                        Button(L10n.get("activity_detail_save_button")) { Task { await save(send: false) } }
                            .disabled(saving || inputInvalid)
                    }
                }
            }
        }
    }

    /// The screen's values as the row Save writes.
    private var currentEdit: ActivityEdit {
        ActivityEdit(
            title: title, trainingType: trainingType, sport: sport, style: style,
            rpe: Int32(rpe), feeling: Int32(feeling), diaryComment: comment, note: note,
            overrideElapsedSec: Int32(clamping: durationOverride), overrideDistanceM: distanceOverrideM,
            overrideAvgHeartRate: hrOverride,
            intensityMinutes: intensityCheck.overrideMinutes ?? [], disciplineMinutes: disciplineCheck.overrideMinutes ?? [],
            wheelType: Int32(wheelType), waxType: Int32(waxType), stravaDescriptionMode: stravaDescriptionMode
        )
    }

    /// The Strava box follows the unsaved values; the stored item's preview until the first recompute.
    private var activePreview: StravaWritePreview? { livePreview ?? item.stravaPreview }

    /// Every button saves the screen's values first, so nothing sent is older than what is shown.
    private func save(send: Bool, createOnStrava: Bool = false) async {
        guard !inputInvalid else { return }
        saving = true
        // The box as these exact values make it, not a debounced one; nil keeps the stored choice.
        let fresh = item.stravaPreview == nil ? nil : await companion.stravaPreview(item.id, edit: currentEdit)
        let saved = await companion.saveActivity(
            item.id, edit: currentEdit,
            stravaTitle: fresh.map { stravaTitle ?? renamedTo ?? $0.title },
            stravaSportType: fresh.map { stravaSportType ?? $0.sportType }
        )
        if saved {
            if createOnStrava { await companion.createOnStrava(item.id) }
            if send { await companion.sendNow(item.id) }
        }
        saving = false
        if saved { dismiss() }
    }

    /// "Save & send" (automatic mode) or "Send now" (manual mode), and "Create on Strava" while
    /// the activity has no Strava link.
    @ViewBuilder
    private var sendSection: some View {
        let sends = companion.sendsSomewhere
        // A phone recording is uploaded with its track (FIT) instead of created by hand; hidden while it is queued.
        let phoneRecording = item.source == "phone"
        let canCreate = companion.stravaConnected && item.stravaActivityId.isEmpty && !(phoneRecording && item.stravaUploadQueued)
        let showSend = sends && (item.origin != "strava" || companion.automaticSync)
        if showSend || canCreate {
            Section {
                if showSend {
                    let label = item.origin == "strava"
                        ? "activity_detail_save_button"
                        : companion.automaticSync ? "activity_detail_save_and_send" : "activity_detail_send_now"
                    Button(L10n.get(label)) {
                        Task { await save(send: true) }
                    }
                    .disabled(saving || inputInvalid)
                }
                if canCreate {
                    Button(L10n.get(phoneRecording ? "phone_start_strava" : "activity_detail_strava_create")) {
                        Task {
                            if phoneRecording {
                                await save(send: false)
                                await companion.uploadPhoneRecording(item.id)
                            } else {
                                await save(send: false, createOnStrava: true)
                            }
                        }
                    }
                    .disabled(saving || inputInvalid)
                }
            }
        }
    }
}

// MARK: - Diary locations

/// Android's "Athlete's Diary connections": the Files app and the three clouds, each
/// connected on its own; one is active and receives the diary entries. A cloud shows only what
/// works on iOS (feedback 2026-10-23: the OneDrive part was confusing): the folder's share link
/// (Dropbox: link or path) and Connect, which signs in first when needed (system sheet).
struct DiaryLocationsScreen: View {
    @EnvironmentObject var companion: Companion
    @State private var pickingFile = false
    @State private var links: [String: String] = [:]
    @State private var choice: DiaryLocateView?
    @State private var choosing = false

    private static let xlsx = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        Form {
            Section {
                Text(L10n.get("connect_diary_intro")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    AddFolderDestinationScreen(format: "JSON_PER_ACTIVITY")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.get("settings_add_connection_json"))
                        Text(L10n.get("settings_add_connection_json_help")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    AddFolderDestinationScreen(format: "CSV_MONTHLY")
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.get("settings_add_connection_csv"))
                        Text(L10n.get("settings_add_connection_csv_help")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(companion.diarySources, id: \.key) { source in
                Section(source.name) { rows(source) }
            }
            if companion.diaryBusy {
                HStack { ProgressView(); Text(L10n.get("connect_diary_connecting")) }
            }
        }
        .disabled(companion.diaryBusy)
        .homeTitle(L10n.get("connect_diary_title"))
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [Self.xlsx]) { result in
            switch result {
            case .success(let url): Task { await companion.connectDiary(url) }
            case .failure(let error): companion.post(error.localizedDescription)
            }
        }
        .onChange(of: pickingFile) { _, open in companion.filePickerOpen = open }
        .confirmationDialog(
            L10n.get("connect_diary_file_selection_title"), isPresented: $choosing, titleVisibility: .visible, presenting: choice
        ) { found in
            ForEach(Array(found.candidates.enumerated()), id: \.offset) { index, name in
                Button(name) { Task { show(await companion.chooseCloudWorkbook(index)) } }
            }
        } message: { found in
            if found.status == "confirm" {
                Text(L10n.get("ios_diary_confirm_workbook"))
            } else if found.candidates.isEmpty {
                Text(String(format: L10n.get("ios_diary_no_files"), found.folderName))
            } else {
                Text(String(format: L10n.get("ios_diary_pick_workbook"), found.folderName))
            }
        }
    }

    @ViewBuilder
    private func rows(_ source: DiarySourceView) -> some View {
        if !source.available {
            Text(source.key == "LOCAL" ? L10n.get("ios_not_available") : L10n.get("ios_not_available_build")).foregroundStyle(.secondary)
        } else {
            if source.connected {
                Label(String(format: L10n.get("connect_diary_connected_to"), source.workbookName), systemImage: "book.closed")
                if source.active {
                    Text(L10n.get("connect_diary_active")).font(.footnote).foregroundStyle(.green)
                } else {
                    Text(L10n.get("connect_diary_not_active")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("ios_make_active")) {
                        companion.setActiveDiary(source.key)
                    }
                }
            }
            if source.key == "LOCAL" {
                Label(L10n.get("ios_local_workbook_hint"), systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                Button(source.connected ? L10n.get("ios_choose_other_workbook") : L10n.get("ios_choose_workbook")) { pickingFile = true }
            } else {
                TextField(locationLabel(source.key), text: Binding(
                    get: { links[source.key] ?? source.location },
                    set: { links[source.key] = $0 }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                Button(L10n.get("connect_diary_connect_button")) {
                    let link = links[source.key] ?? source.location
                    if source.signedIn {
                        Task { show(await companion.connectCloud(source.key, location: link)) }
                    } else {
                        // Signs in first; the link is connected right after the sign-in sheet closes.
                        companion.signInCloud(source.key) {
                            show(await companion.connectCloud(source.key, location: link))
                        }
                    }
                }
                .disabled((links[source.key] ?? source.location).trimmingCharacters(in: .whitespaces).isEmpty)
                Text(String(format: L10n.get("ios_cloud_link_footer"), source.name))
                    .font(.footnote).foregroundStyle(.secondary)
                if source.signedIn {
                    Button("\(L10n.get("cloud_account_sign_out_button")) · \(source.name)", role: .destructive) { companion.signOutCloud(source.key) }
                }
            }
            if source.connected {
                Button(L10n.get("connect_diary_disconnect_button"), role: .destructive) { companion.disconnectDiary(source.key) }
            }
        }
    }

    private func locationLabel(_ key: String) -> String {
        switch key {
        case "ONE_DRIVE": return L10n.get("connect_diary_location_label_onedrive")
        case "DROPBOX": return L10n.get("connect_diary_location_label_dropbox")
        default: return L10n.get("connect_diary_location_label_google_drive")
        }
    }

    private func show(_ result: DiaryLocateView?) {
        guard let result else { return }
        switch result.status {
        case "connected":
            companion.post(String(format: L10n.get("connect_diary_connected_to"), result.workbookName))
        case "confirm", "choose":
            choice = result
            choosing = !result.candidates.isEmpty
            if result.candidates.isEmpty {
                companion.post(String(format: L10n.get("ios_diary_no_files"), result.folderName))
            }
        default:
            companion.message = result.message
        }
    }
}

/// The start-up reminder for a local install while the server's move stage for iOS is `nudge`
/// (Android `ServerNudgeDialog`): what changes, the move's form, and "Later".
struct ServerNudgeSheet: View {
    @EnvironmentObject var companion: Companion
    let close: () -> Void
    @State private var moved: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let moved {
                        Text(moved)
                    } else {
                        Text(L10n.get("server_nudge_body"))
                        ServerMoveForm(onMoved: { text in moved = text })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(L10n.get("server_nudge_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get(moved != nil ? "onboarding_guide_watch_continue" : "server_nudge_later")) { close() }
                }
            }
        }
    }
}
