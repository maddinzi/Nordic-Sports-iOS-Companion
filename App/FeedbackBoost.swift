import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

// Recording Boost files attached to a feedback message: Android's FeedbackBoostScreens.kt. The
// picker lists the bursts on this phone grouped by activity (the latest activity first, from the
// shared core) and can add CSV files from the Files app; the declaration step asks per file for
// the activity type, technique, terrain, poles and a note.

/// A file that can be attached: a stored burst (`view.id`) or a CSV the athlete picked (`content`).
struct BoostCandidate: Identifiable, Hashable {
    let key: String
    let view: FeedbackBoostFileView
    let content: String
    /// The phone's motion record of this Sensor Record (`PhoneMotionCapture`), nil when there is none or it is too large.
    var phoneURL: URL? = nil
    var id: String { key }

    static func == (a: BoostCandidate, b: BoostCandidate) -> Bool { a.key == b.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }
}

/// What the athlete says a file shows; the activity type is required. `poles`: 1, 0, or -1 for not said.
struct BoostDeclaration: Equatable {
    var activityType = ""
    var technique = ""
    var terrain = ""
    var poles: Int32 = -1
    var note = ""
    /// The athlete's own skill, self-declared: "beginner", "intermediate", "expert" or "" (not said).
    var competence = ""
    /// The ground under the feet (a BurstLabelOptions.SURFACES code), "" not said.
    var surface = ""
    /// The lead side of V1/V2A ("left", "right"), "" not said; sent only with those techniques.
    var lead = ""
}

struct BoostAttached: Identifiable {
    let candidate: BoostCandidate
    var declaration: BoostDeclaration
    /// The phone's motion record goes along with the same declaration (a second file).
    var withPhone = false
    var id: String { candidate.key }
}

enum BoostText {
    /// "XC Skiing › Skating", "Running"; an unknown key as it is.
    static func typeName(_ catalog: String) -> String {
        let ski = L10n.get("activity_detail_sport_option_langlauf")
        switch catalog {
        case "skiSkating": return "\(ski) › \(L10n.get("activity_detail_style_option_skating"))"
        case "skiClassic": return "\(ski) › \(L10n.get("activity_detail_style_option_klassisch"))"
        case "skiDoublePole": return "\(ski) › \(L10n.get("activity_detail_style_option_doppelstock"))"
        case "running": return L10n.get("activity_detail_sport_option_running")
        default: return catalog
        }
    }

    static let competenceLevels = ["beginner", "intermediate", "expert"]

    static func competenceName(_ level: String) -> String {
        switch level {
        case "beginner": return L10n.get("feedback_boost_competence_beginner")
        case "intermediate": return L10n.get("feedback_boost_competence_intermediate")
        case "expert": return L10n.get("feedback_boost_competence_expert")
        default: return level
        }
    }

    /// The sides of V1/V2A (shared FeedbackAttachment.LEAD) and the techniques that ask for one (LEAD_TECHNIQUES).
    static let leadSides = ["left", "right"]
    static let leadTechniques: Set<String> = ["V1", "V2A"]

    static func leadName(_ side: String) -> String {
        switch side {
        case "left": return L10n.get("feedback_boost_lead_left")
        case "right": return L10n.get("feedback_boost_lead_right")
        default: return side
        }
    }

    /// Technique and terrain codes are the coaches' codes; only "mixed" is translated.
    static func code(_ code: String) -> String {
        code == "MIXED" ? L10n.get("recording_boost_label_mixed") : code
    }

    /// The ground surface code in the athlete's language (the keys the Android strings use).
    static func surface(_ code: String) -> String {
        L10n.get("recording_boost_surface_\(code.lowercased())")
    }

    static func summary(_ d: BoostDeclaration) -> String {
        var parts = [typeName(d.activityType)]
        if !d.technique.isEmpty { parts.append(code(d.technique)) }
        if !d.lead.isEmpty && leadTechniques.contains(d.technique) { parts.append(leadName(d.lead)) }
        if !d.surface.isEmpty { parts.append(surface(d.surface)) }
        if !d.terrain.isEmpty { parts.append(d.terrain) }
        if d.poles == 1 { parts.append(L10n.get("recording_boost_label_poles_yes")) }
        if d.poles == 0 { parts.append(L10n.get("recording_boost_label_poles_no")) }
        if !d.competence.isEmpty { parts.append(competenceName(d.competence)) }
        let note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private static let competenceKey = "boostCompetence"

    /// The last skill the athlete chose, the start for a file whose activity has none.
    static func rememberCompetence(_ level: String) {
        UserDefaults.standard.set(level, forKey: competenceKey)
    }

    /// The activity type the file says (when we know it), a label it already carries and the skill: the
    /// activity's own, else the last answer.
    static func defaults(_ c: BoostCandidate, catalogs: [String]) -> BoostDeclaration {
        BoostDeclaration(
            activityType: catalogs.contains(c.view.catalog) ? c.view.catalog : "",
            technique: c.view.labelTechnique,
            // Facts the record makes known fill what the label leaves open (run terrain, poles); never the technique.
            terrain: c.view.labelTerrain.isEmpty && c.view.catalog == "running" ? c.view.suggestedTerrain : c.view.labelTerrain,
            poles: c.view.labelPoles >= 0 ? c.view.labelPoles : c.view.suggestedPoles,
            note: c.view.labelNote,
            competence: c.view.competence.isEmpty ? (UserDefaults.standard.string(forKey: competenceKey) ?? "") : c.view.competence,
            surface: c.view.labelSurface
        )
    }
}

/// "Add Recording Boost files": pick, then declare; `onDone` gets the files with their declarations.
struct FeedbackBoostPickerSheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let attachedKeys: Set<String>
    let capacity: Int
    /// The activity whose files start out chosen (its reminder was accepted), "" for none.
    var preselectActivityId = ""
    let onDone: ([BoostAttached]) -> Void

    @State private var stored: [BoostCandidate] = []
    @State private var manual: [BoostCandidate] = []
    @State private var loaded = false
    @State private var selected: [String] = []
    @State private var importing = false
    @State private var problem: String?
    @State private var declaring = false
    /// Records whose phone motion record the athlete unticked (it goes along by default).
    @State private var phoneOff: Set<String> = []

    private var chosen: [BoostCandidate] {
        selected.compactMap { key in (manual + stored).first { $0.key == key } }
    }

    private func withPhone(_ c: BoostCandidate) -> Bool { c.phoneURL != nil && !phoneOff.contains(c.key) }

    /// Files that go out: each chosen record plus its phone motion record (both count toward the server's limit).
    private var fileCount: Int { chosen.count + chosen.filter { withPhone($0) }.count }

    /// Chooses [item] when there is room; its phone record goes along only while there is room for it too.
    private func choose(_ item: BoostCandidate) {
        guard !selected.contains(item.key), fileCount < capacity else { return }
        selected.append(item.key)
        if item.phoneURL != nil && fileCount > capacity { phoneOff.insert(item.key) }
    }

    /// The stored files in the core's order, one group per activity (its bursts are listed together).
    private var groups: [(title: String, subtitle: String, items: [BoostCandidate])] {
        var result: [(title: String, subtitle: String, items: [BoostCandidate])] = []
        var lastActivity: String?
        for item in stored {
            if item.view.activityId != lastActivity || result.isEmpty {
                lastActivity = item.view.activityId
                let linked = !item.view.activityId.isEmpty
                let subtitle = linked && item.view.activityStartEpochSec > 0
                    ? Date(timeIntervalSince1970: TimeInterval(item.view.activityStartEpochSec)).formatted(date: .abbreviated, time: .shortened)
                    : ""
                result.append((linked ? item.view.activityTitle : L10n.get("feedback_boost_pick_unlinked"), subtitle, []))
            }
            result[result.count - 1].items.append(item)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(L10n.get("feedback_boost_pick_file")) { importing = true }
                    if let problem { Text(problem).foregroundStyle(.red).font(.footnote) }
                }
                if !manual.isEmpty {
                    Section(L10n.get("feedback_boost_pick_file")) { ForEach(manual) { row($0) } }
                }
                if loaded && stored.isEmpty && manual.isEmpty {
                    Section { Text(L10n.get("feedback_boost_pick_empty")).foregroundStyle(.secondary) }
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    Section {
                        ForEach(group.items) { row($0) }
                    } header: {
                        VStack(alignment: .leading) {
                            Text(group.title)
                            if !group.subtitle.isEmpty { Text(group.subtitle).font(.caption) }
                        }
                    }
                }
                Section {} footer: {
                    Text(String(format: L10n.get("feedback_boost_pick_limit"), Int(companion.core.feedbackBoostMaxFiles)))
                }
            }
            .navigationTitle(L10n.get("feedback_boost_add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.get("common_cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(format: L10n.get("feedback_boost_pick_continue"), fileCount)) { declaring = true }
                        .disabled(selected.isEmpty)
                }
            }
            .navigationDestination(isPresented: $declaring) {
                let catalogs = companion.feedbackBoostCatalogs
                BoostDeclareView(
                    candidates: chosen,
                    initial: Dictionary(uniqueKeysWithValues: chosen.map { ($0.key, BoostText.defaults($0, catalogs: catalogs)) })
                ) { done in
                    // One declaration per record: its phone motion record takes the same answers.
                    onDone(done.map { a in
                        var out = a
                        out.withPhone = withPhone(a.candidate)
                        return out
                    })
                    dismiss()
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importFiles(urls) }
            }
            .task {
                let files = await companion.feedbackBoostFiles()
                let maxChars = Int(companion.core.feedbackBoostMaxChars)
                // One folder listing; the files themselves are read only when the message is sent.
                let phones = PhoneMotionCapture.storedAll()
                stored = files.map { f in
                    var c = BoostCandidate(key: "burst:\(f.id)", view: f, content: "")
                    // The phone's motion record of this Sensor Record, found by the watch's record id in its file name.
                    if let url = phones[PhoneMotionCapture.burstId(fileName: f.fileName)],
                       let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maxChars {
                        c.phoneURL = url
                    }
                    return c
                }
                loaded = true
                if preselectActivityId.hasPrefix("burst:"), selected.isEmpty {
                    // A Sensor Record screen's Upload: just that record (and its phone motion record).
                    stored.filter { $0.key == preselectActivityId && !attachedKeys.contains($0.key) }.forEach { choose($0) }
                } else if !preselectActivityId.isEmpty, selected.isEmpty {
                    stored.filter { $0.view.activityId == preselectActivityId && !attachedKeys.contains($0.key) }.forEach { choose($0) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ item: BoostCandidate) -> some View {
        recordRow(item)
        // The phone's motion record of the same moment, right under its record: ticked by default, only with the
        // record, and declared together with it.
        if item.phoneURL != nil {
            let on = selected.contains(item.key) && withPhone(item)
            let can = selected.contains(item.key) && (on || fileCount < capacity)
            Button {
                if on { phoneOff.insert(item.key) } else { phoneOff.remove(item.key) }
            } label: {
                HStack {
                    Image(systemName: "iphone").foregroundStyle(phoneColor)
                    Text(L10n.get("feedback_boost_with_phone")).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    if on { Image(systemName: "checkmark") }
                }
                .padding(.leading, 16)
            }
            .disabled(!can)
        }
    }

    private func recordRow(_ item: BoostCandidate) -> some View {
        let already = attachedKeys.contains(item.key)
        let on = already || selected.contains(item.key)
        return Button {
            if selected.contains(item.key) {
                selected.removeAll { $0 == item.key }
            } else {
                choose(item)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if item.view.receivedAtEpochMillis > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(item.view.receivedAtEpochMillis) / 1000)
                            .formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.primary)
                        Text(item.view.fileName).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(item.view.fileName).foregroundStyle(.primary)
                    }
                }
                Spacer()
                if on { Image(systemName: "checkmark") }
            }
        }
        .disabled(already)
    }

    /// Only a Recording Boost CSV of at most the server's size passes.
    private func importFiles(_ urls: [URL]) {
        problem = nil
        let maxChars = Int(companion.core.feedbackBoostMaxChars)
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                problem = String(format: L10n.get("feedback_boost_not_boost"), name)
                continue
            }
            if data.count > maxChars {
                problem = String(format: L10n.get("feedback_boost_too_large"), name)
                continue
            }
            guard let text = String(data: data, encoding: .utf8),
                  let view = companion.feedbackBoostFromCsv(name: name, csv: text) else {
                problem = String(format: L10n.get("feedback_boost_not_boost"), name)
                continue
            }
            let candidate = BoostCandidate(key: "file:\(UUID().uuidString)", view: view, content: text)
            manual.append(candidate)
            choose(candidate)
        }
    }
}

/// "What do the files show?": per file the activity type, technique, terrain (running), poles and a note.
struct BoostDeclareView: View {
    @EnvironmentObject var companion: Companion
    let candidates: [BoostCandidate]
    let onDone: ([BoostAttached]) -> Void
    @State private var declarations: [String: BoostDeclaration]

    init(candidates: [BoostCandidate], initial: [String: BoostDeclaration], onDone: @escaping ([BoostAttached]) -> Void) {
        self.candidates = candidates
        self.onDone = onDone
        _declarations = State(initialValue: initial)
    }

    private var complete: Bool {
        candidates.allSatisfy { !(declarations[$0.key]?.activityType ?? "").isEmpty }
    }

    var body: some View {
        Form {
            ForEach(candidates) { candidate in
                let d = declarations[candidate.key] ?? BoostDeclaration()
                let options = companion.feedbackBoostOptions(d.activityType)
                Section {
                    Text(L10n.get("feedback_boost_declare_type")).font(.caption).foregroundStyle(.secondary)
                    ForEach(companion.feedbackBoostCatalogs, id: \.self) { type in
                        choice(BoostText.typeName(type), on: d.activityType == type) {
                            var next = d
                            next.activityType = type
                            let allowed = companion.feedbackBoostOptions(type)
                            if !allowed.techniques.contains(next.technique) { next.technique = "" }
                            if !BoostText.leadTechniques.contains(next.technique) { next.lead = "" }
                            if type != "running" { next.terrain = ""; next.surface = "" }
                            if !allowed.askPoles { next.poles = -1 }
                            declarations[candidate.key] = next
                        }
                    }
                    if !d.activityType.isEmpty {
                        Text(L10n.get("recording_boost_label_technique")).font(.caption).foregroundStyle(.secondary)
                        ForEach(options.techniques, id: \.self) { code in
                            choice(BoostText.code(code), on: d.technique == code) {
                                var next = d
                                let same = d.technique == code
                                next.technique = same ? "" : code
                                if !BoostText.leadTechniques.contains(next.technique) { next.lead = "" }
                                declarations[candidate.key] = next
                            }
                        }
                        if options.techniques.contains(candidate.view.watchTechnique) {
                            Text(String(format: L10n.get("feedback_boost_watch_said"), BoostText.code(candidate.view.watchTechnique), Int(candidate.view.watchSeconds), Int(candidate.view.recordSeconds)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        // V1 and V2A pole on one side: which one leads (Android: a drop-down after the technique).
                        if BoostText.leadTechniques.contains(d.technique) {
                            Text(L10n.get("feedback_boost_lead")).font(.caption).foregroundStyle(.secondary)
                            ForEach(BoostText.leadSides, id: \.self) { side in
                                choice(BoostText.leadName(side), on: d.lead == side) {
                                    var next = d
                                    next.lead = d.lead == side ? "" : side
                                    declarations[candidate.key] = next
                                }
                            }
                        }
                        if d.activityType == "running" {
                            Text(L10n.get("recording_boost_label_surface")).font(.caption).foregroundStyle(.secondary)
                            ForEach(options.surfaces, id: \.self) { code in
                                choice(BoostText.surface(code), on: d.surface == code) {
                                    var next = d
                                    next.surface = d.surface == code ? "" : code
                                    declarations[candidate.key] = next
                                }
                            }
                            Text(L10n.get("recording_boost_label_terrain")).font(.caption).foregroundStyle(.secondary)
                            ForEach(options.terrains, id: \.self) { code in
                                choice(code, on: d.terrain == code) {
                                    var next = d
                                    next.terrain = d.terrain == code ? "" : code
                                    declarations[candidate.key] = next
                                }
                            }
                        }
                        if options.askPoles {
                            Text(L10n.get("recording_boost_label_poles")).font(.caption).foregroundStyle(.secondary)
                            choice(L10n.get("recording_boost_label_poles_yes"), on: d.poles == 1) {
                                var next = d
                                next.poles = d.poles == 1 ? -1 : 1
                                declarations[candidate.key] = next
                            }
                            choice(L10n.get("recording_boost_label_poles_no"), on: d.poles == 0) {
                                var next = d
                                next.poles = d.poles == 0 ? -1 : 0
                                declarations[candidate.key] = next
                            }
                        }
                    }
                    // About the athlete, for every sport (Android: a drop-down on each file's declare screen).
                    Text(L10n.get("feedback_boost_competence")).font(.caption).foregroundStyle(.secondary)
                    ForEach(BoostText.competenceLevels, id: \.self) { level in
                        choice(BoostText.competenceName(level), on: d.competence == level) {
                            var next = d
                            next.competence = d.competence == level ? "" : level
                            declarations[candidate.key] = next
                            BoostText.rememberCompetence(next.competence)
                        }
                    }
                    TextField(L10n.get("recording_boost_label_note"), text: Binding(
                        get: { declarations[candidate.key]?.note ?? "" },
                        set: { declarations[candidate.key, default: BoostDeclaration()].note = String($0.prefix(200)) }
                    ))
                } header: {
                    Text(candidate.view.fileName)
                }
            }
            if !complete {
                Section { Text(L10n.get("feedback_boost_declare_need_type")).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L10n.get("feedback_boost_declare_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.get("feedback_boost_declare_add")) {
                    onDone(candidates.map { BoostAttached(candidate: $0, declaration: declarations[$0.key] ?? BoostDeclaration()) })
                }
                .disabled(!complete)
            }
        }
    }

    private func choice(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark") }
            }
        }
    }
}

/// Changing what one attached file shows.
struct BoostEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attached: BoostAttached
    let onDone: (BoostAttached) -> Void

    var body: some View {
        NavigationStack {
            BoostDeclareView(candidates: [attached.candidate], initial: [attached.candidate.key: attached.declaration]) { done in
                // The phone motion record stays with its record (its answers follow the record's).
                if var first = done.first {
                    first.withPhone = attached.withPhone
                    onDone(first)
                }
                dismiss()
            }
        }
    }
}

/// The feedback form's "Recording Boost files" block.
struct FeedbackBoostSection: View {
    @Binding var attached: [BoostAttached]
    let tooLargeFile: String?
    @Binding var showPicker: Bool
    @Binding var editing: BoostAttached?
    @EnvironmentObject var companion: Companion

    var body: some View {
        Section {
            ForEach(attached) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.candidate.view.fileName)
                    Text(BoostText.summary(item.declaration)).font(.footnote).foregroundStyle(.secondary)
                    if item.withPhone {
                        Label(L10n.get("feedback_boost_with_phone"), systemImage: "iphone")
                            .font(.footnote).foregroundStyle(phoneColor)
                    }
                    HStack(spacing: 16) {
                        Button(L10n.get("feedback_boost_edit")) { editing = item }
                        Button(L10n.get("feedback_boost_remove"), role: .destructive) {
                            attached.removeAll { $0.id == item.id }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.footnote)
                }
            }
            if attached.count + attached.filter({ $0.withPhone }).count < Int(companion.core.feedbackBoostMaxFiles) {
                Button(L10n.get("feedback_boost_add")) { showPicker = true }
            }
            if let tooLargeFile {
                Text(String(format: L10n.get("feedback_boost_too_large"), tooLargeFile)).foregroundStyle(.red).font(.footnote)
            }
        } header: {
            Text(L10n.get("feedback_boost_section"))
        } footer: {
            Text(L10n.get("feedback_boost_hint"))
        }
    }
}
