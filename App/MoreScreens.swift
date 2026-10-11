import NordicSportsShared
import SwiftUI

// Roadmap step 5.3, 5.4 and 5.6 on iOS: the watch app's settings, adding an activity by
// hand, the transparency logs and feedback. Logic and texts come from the shared core
// (CompanionCore); these views only show and forward.

// MARK: - Watch settings

struct WatchSettingsScreen: View {
    @EnvironmentObject var companion: Companion

    var body: some View {
        Form {
            Section { Text(L10n.get("settings_intro_watch")).font(.footnote).foregroundStyle(.secondary) }
            if companion.watchSettings.isEmpty {
                Text(L10n.get("watch_settings_none")).foregroundStyle(.secondary)
            }
            ForEach(companion.watchSettings, id: \.deviceId) { watch in
                Section {
                    Text(String(format: L10n.get("watch_settings_as_of"), Format.date(watch.reportedAtEpochSec)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if watch.pendingCount > 0 {
                        Text(L10n.plural("watch_settings_waiting", Int(watch.pendingCount)))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button(L10n.get("watch_settings_refresh")) { companion.askWatchAgain(deviceId: watch.deviceId) }
                } header: {
                    Text(watch.watchName)
                }
                ForEach(watch.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.items, id: \.key) { item in
                            WatchSettingRow(deviceId: watch.deviceId, item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Watch settings")
        .onAppear { companion.refreshWatchSettings() }
    }
}

private struct WatchSettingRow: View {
    @EnvironmentObject var companion: Companion
    let deviceId: Int64
    let item: WatchSettingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if item.isToggle {
                Toggle(item.label, isOn: Binding(
                    get: { item.value != 0 },
                    set: { companion.changeWatchSetting(deviceId: deviceId, key: item.key, value: $0 ? 1 : 0) }
                ))
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

    var body: some View {
        LogList(lines: lines, loaded: loaded)
            .navigationTitle(title)
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

    init(activityId: String) {
        self.activityId = activityId
    }

    var body: some View {
        LogList(lines: lines, loaded: loaded, empty: L10n.get("activity_change_log_empty"))
            .navigationTitle(L10n.get("activity_change_log_title"))
            .task {
                lines = await companion.activityLog(activityId)
                loaded = true
            }
    }
}

private struct LogList: View {
    let lines: [LogLine]
    let loaded: Bool
    var empty = "Nothing logged yet."

    var body: some View {
        List {
            if loaded && lines.isEmpty {
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
            }
        }
    }
}

// MARK: - Feedback

struct FeedbackScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    @State private var category = "error_report"
    @State private var app = "companion"
    @State private var text = ""
    @State private var email = ""
    @State private var includeDetails = true
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    private var emailValid: Bool { email.isEmpty || (email.contains("@") && email.contains(".")) }

    var body: some View {
        Form {
            if sent {
                Section {
                    Text(L10n.get("feedback_thanks_title")).font(.headline)
                    Text(L10n.get("feedback_thanks_body"))
                    Button(L10n.get("feedback_thanks_done")) { dismiss() }
                }
            } else {
                Section { Text(L10n.get("feedback_intro")).font(.footnote) }
                Section {
                    Picker(L10n.get("feedback_category_label"), selection: $category) {
                        Text(L10n.get("feedback_category_error")).tag("error_report")
                        Text(L10n.get("feedback_category_feature")).tag("feature_request")
                        Text(L10n.get("feedback_category_other")).tag("other")
                    }
                    Picker(L10n.get("feedback_app_label"), selection: $app) {
                        Text(L10n.get("feedback_app_watch")).tag("watch")
                        Text(L10n.get("feedback_app_companion")).tag("companion")
                        Text(L10n.get("feedback_app_both")).tag("both")
                    }
                }
                Section(L10n.get("feedback_message_label")) {
                    TextEditor(text: $text).frame(minHeight: 140)
                }
                Section(L10n.get("feedback_email_label")) {
                    TextField("", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text(L10n.get(emailValid ? "feedback_email_hint" : "feedback_email_invalid"))
                        .font(.footnote)
                        .foregroundStyle(emailValid ? Color.secondary : Color.red)
                }
                Section {
                    Toggle(L10n.get("feedback_details_switch"), isOn: $includeDetails)
                    if includeDetails {
                        let details = Companion.deviceDetails()
                        Text("\(L10n.get("feedback_detail_app")) \(Format.appVersion) · \(details["phone"] ?? "") · iOS \(details["ios"] ?? "") · \(companion.language)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.get("feedback_details_off")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task {
                            sending = true
                            error = nil
                            let result = await companion.sendFeedback(
                                category: category, app: app, text: text, email: email, includeDetails: includeDetails
                            )
                            sending = false
                            switch result {
                            case "sent": sent = true
                            case "tooMany": error = L10n.get("feedback_error_too_many")
                            default: error = L10n.get("feedback_error_failed")
                            }
                        }
                    } label: {
                        if sending { ProgressView() } else { Text(L10n.get("feedback_send")) }
                    }
                    .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !emailValid)
                }
            }
        }
        .navigationTitle(L10n.get("feedback_title"))
    }
}

// MARK: - Add activity by hand

struct AddActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    @State private var typeKey = ""
    @State private var endedNow = true
    @State private var minutes = 60
    @State private var otherMinutes = ""
    @State private var start = Date()
    @State private var saving = false

    private static let durations = [30, 60, 90, 120]

    private var duration: Int { Int(otherMinutes) ?? minutes }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.get("add_activity_type_heading")) {
                    Picker(L10n.get("add_activity_type_heading"), selection: $typeKey) {
                        ForEach(companion.manualTypes, id: \.key) { type in
                            Text(type.label).tag(type.key)
                        }
                    }
                    .pickerStyle(.navigationLink)
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
                    DatePicker("Start", selection: $start)
                }
            }
            .navigationTitle(L10n.get("add_activity_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.get("add_activity_save_button")) {
                        Task {
                            saving = true
                            let id = await companion.addActivity(typeKey: typeKey, start: start, minutes: duration)
                            saving = false
                            if id != nil { dismiss() }
                        }
                    }
                    .disabled(saving || typeKey.isEmpty || duration <= 0)
                }
            }
            .onAppear {
                if typeKey.isEmpty { typeKey = companion.manualTypes.first?.key ?? "" }
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
}

// MARK: - Edit an activity

/// Android's detail-screen edits that matter most on the go: name, training type, RPE,
/// feeling, diary comment and corrected duration/distance. Saving is the review.
struct EditActivitySheet: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let item: ActivityItem
    @State private var title: String
    @State private var trainingType: String
    @State private var rpe: Int
    @State private var feeling: Int
    @State private var comment: String
    @State private var minutes: String
    @State private var kilometers: String
    @State private var saving = false

    init(item: ActivityItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _trainingType = State(initialValue: item.trainingType)
        _rpe = State(initialValue: Int(item.rpe))
        _feeling = State(initialValue: Int(item.feeling))
        _comment = State(initialValue: item.diaryComment)
        _minutes = State(initialValue: item.overrideElapsedSec > 0 ? String(item.overrideElapsedSec / 60) : "")
        _kilometers = State(initialValue: item.overrideDistanceM > 0 ? String(format: "%.1f", Double(item.overrideDistanceM) / 1000) : "")
    }

    private var trainingOptions: [(String, String)] {
        item.preset == "strength"
            ? [("hypertrophy", "activity_detail_training_option_hypertrophy"),
               ("speedStrength", "activity_detail_training_option_speed_strength"),
               ("strengthEndurance", "activity_detail_training_option_strength_endurance")]
            : [("endurance", "activity_detail_training_option_endurance"),
               ("intervals", "activity_detail_training_option_intervals"),
               ("technique", "activity_detail_training_option_technique"),
               ("sprints", "activity_detail_training_option_sprints")]
    }

    private static let feelings = [
        "activity_detail_feeling_option_not_entered", "activity_detail_feeling_option_very_weak",
        "activity_detail_feeling_option_weak", "activity_detail_feeling_option_normal",
        "activity_detail_feeling_option_good", "activity_detail_feeling_option_very_good",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.get("activity_detail_name_label"), text: $title)
                    Picker(L10n.get("activity_detail_training_type_label"), selection: $trainingType) {
                        ForEach(trainingOptions, id: \.0) { option in Text(L10n.get(option.1)).tag(option.0) }
                        if !trainingOptions.contains(where: { $0.0 == trainingType }) {
                            Text(Format.trainingTypeWord(trainingType)).tag(trainingType)
                        }
                    }
                }
                Section {
                    Picker(L10n.get("activity_detail_rpe_label"), selection: $rpe) {
                        ForEach(0...10, id: \.self) { value in Text(value == 0 ? "–" : "\(value)").tag(value) }
                    }
                    Picker(L10n.get("activity_detail_feeling_label"), selection: $feeling) {
                        ForEach(Self.feelings.indices, id: \.self) { index in Text(L10n.get(Self.feelings[index])).tag(index) }
                    }
                }
                Section(L10n.get("activity_detail_diary_comment_label")) {
                    TextEditor(text: $comment).frame(minHeight: 80)
                }
                Section {
                    LabeledContent(L10n.get("activity_detail_duration_label")) {
                        TextField(Format.duration(item.elapsedSec), text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("min").foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.get("activity_detail_distance_label")) {
                        TextField(item.distanceM > 0 ? String(format: "%.1f", Double(item.distanceM) / 1000) : "0", text: $kilometers)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("km").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Leave empty to keep the watch's values.")
                }
            }
            .navigationTitle(L10n.get("activity_detail_review_heading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            saving = true
                            let km = Double(kilometers.replacingOccurrences(of: ",", with: ".")) ?? 0
                            let saved = await companion.saveActivity(
                                item.id, title: title, trainingType: trainingType, rpe: rpe, feeling: feeling,
                                comment: comment, minutes: Int(minutes) ?? 0, kilometers: km
                            )
                            saving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
    }
}
