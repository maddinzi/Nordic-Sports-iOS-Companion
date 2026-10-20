import SwiftUI
import UniformTypeIdentifiers
import NordicSportsShared

/// "Add connection" › JSON per activity / CSV per month: the folder (Files app, or a folder in a
/// signed-in cloud), then which activities and options, then Add (design/diary-destinations.md).
struct AddFolderDestinationScreen: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    /// "JSON_PER_ACTIVITY" or "CSV_MONTHLY".
    let format: String
    @State private var links: [String: String] = [:]
    @State private var pickingFolder = false
    @State private var folderName: String?
    @State private var scope = "ALL"
    @State private var backfill = "none"
    @State private var monthFolders = false
    @State private var position = false
    @State private var dialect = "AUTO"

    private var isCsv: Bool { format == "CSV_MONTHLY" }

    private var clouds: [DiarySourceView] { companion.diarySources.filter { $0.key != "LOCAL" } }

    var body: some View {
        Form {
            Section {
                Text(L10n.get(isCsv ? "connect_csv_intro" : "connect_json_intro")).font(.footnote).foregroundStyle(.secondary)
            }
            if let folderName {
                Section {
                    Label(String(format: L10n.get("json_options_folder"), folderName), systemImage: "folder")
                    Button(L10n.get("ios_choose_folder")) { self.folderName = nil }
                }
                options
                Section {
                    Button(L10n.get("json_add_button")) {
                        Task {
                            let added = await companion.addFolderDestination(
                                format: format, scope: scope, backfill: backfill,
                                position: position, monthFolders: monthFolders, dialect: dialect
                            )
                            if added { dismiss() }
                        }
                    }
                }
            } else {
                Section(L10n.get("destination_info_storage")) {
                    Text(L10n.get(isCsv ? "connect_csv_local_pick_folder" : "connect_json_local_pick_folder"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("ios_choose_folder")) { pickingFolder = true }
                }
                ForEach(clouds, id: \.key) { source in
                    Section(source.name) { cloudRows(source) }
                }
            }
            if companion.diaryBusy {
                HStack { ProgressView(); Text(L10n.get("connect_diary_connecting")) }
            }
        }
        .disabled(companion.diaryBusy)
        .navigationTitle(L10n.get(isCsv ? "connect_csv_title" : "connect_json_title"))
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { handle(await companion.pickDeviceFolder(url)) }
            case .failure(let error): companion.post(error.localizedDescription)
            }
        }
        .onChange(of: pickingFolder) { _, open in companion.filePickerOpen = open }
    }

    @ViewBuilder
    private func cloudRows(_ source: DiarySourceView) -> some View {
        if !source.available {
            Text(L10n.get("ios_not_available_build")).foregroundStyle(.secondary)
        } else if !source.signedIn {
            Button("\(L10n.get("destination_sign_in")) · \(source.name)") { companion.signInCloud(source.key) }
        } else {
            TextField(locationLabel(source.key), text: Binding(
                get: { links[source.key] ?? "" },
                set: { links[source.key] = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            Button(L10n.get("ios_choose_folder")) {
                let link = links[source.key] ?? ""
                Task { handle(await companion.pickCloudFolder(provider: source.key, link: link)) }
            }
            .disabled((links[source.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private var options: some View {
        Section(L10n.get("json_scope_heading")) {
            Picker(L10n.get("json_scope_heading"), selection: $scope) {
                Text(L10n.get("json_scope_all")).tag("ALL")
                Text(L10n.get("json_scope_watch")).tag("WATCH_ONLY")
                Text(L10n.get("json_scope_ttb")).tag("TTB_DISCIPLINES")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Section(L10n.get("json_backfill_heading")) {
            Picker(L10n.get("json_backfill_heading"), selection: $backfill) {
                Text(L10n.get("json_backfill_none")).tag("none")
                Text(L10n.get("json_backfill_90")).tag("90")
                Text(L10n.get("json_backfill_all")).tag("all")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Section {
            if !isCsv {
                Toggle(L10n.get("json_month_switch"), isOn: $monthFolders)
                Text(L10n.get("json_month_body")).font(.footnote).foregroundStyle(.secondary)
            }
            Toggle(L10n.get("json_position_switch"), isOn: $position)
            Text(L10n.get("json_position_body")).font(.footnote).foregroundStyle(.secondary)
        }
        if isCsv {
            Section(L10n.get("csv_style_heading")) {
                DialectPicker(dialect: $dialect)
                Text(L10n.get("csv_help")).font(.footnote).foregroundStyle(.secondary)
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

    private func handle(_ result: FolderPickView) {
        if result.ok {
            folderName = result.folderName
        } else if !result.message.isEmpty {
            companion.post(result.message)
        }
    }
}

/// The CSV style choice; "automatic" names what it comes to for the current language.
private struct DialectPicker: View {
    @EnvironmentObject var companion: Companion
    @Binding var dialect: String

    var body: some View {
        Picker(L10n.get("csv_style_heading"), selection: $dialect) {
            Text(L10n.get(companion.language == "de" ? "csv_style_auto_de" : "csv_style_auto_intl")).tag("AUTO")
            Text(L10n.get("csv_style_de")).tag("EXCEL_DE")
            Text(L10n.get("csv_style_intl")).tag("INTERNATIONAL")
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

/// One JSON or CSV destination: its status and options, "Write now", pause and remove.
struct FolderDestinationPage: View {
    @EnvironmentObject var companion: Companion
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var confirmingRemove = false

    private var destination: DestinationView? { companion.folderDestinations.first { $0.id == id } }

    var body: some View {
        Form {
            if let d = destination {
                let csv = d.format == "CSV_MONTHLY"
                Section {
                    LabeledContent(L10n.get("destination_info_folder"), value: d.name)
                    LabeledContent(L10n.get("destination_info_storage"), value: d.storageName)
                    LabeledContent(L10n.get("json_info_scope"), value: scopeText(d.scope))
                    if d.startFromEpochMillis > 0 {
                        LabeledContent(L10n.get("json_info_from"), value: Format.date(d.startFromEpochMillis / 1000))
                    } else {
                        LabeledContent(L10n.get("json_info_from"), value: L10n.get("json_info_from_all"))
                    }
                    status(d)
                }
                Section {
                    Toggle(L10n.get("destination_pause_switch"), isOn: Binding(
                        get: { !d.enabled },
                        set: { paused in Task { await companion.setFolderDestinationEnabled(id, enabled: !paused) } }
                    ))
                    Text(L10n.get("destination_pause_body")).font(.footnote).foregroundStyle(.secondary)
                    Button(L10n.get("destination_write_now")) { Task { await companion.writeFolderDestinationNow(id) } }
                        .disabled(!d.enabled || companion.syncing)
                    if companion.syncing { ProgressView() }
                }
                Section(L10n.get("destination_settings_heading")) {
                    Toggle(L10n.get("json_auto_switch"), isOn: Binding(get: { d.autoWrite }, set: { save(d, auto: $0) }))
                    Text(L10n.get("json_auto_body")).font(.footnote).foregroundStyle(.secondary)
                    Picker(L10n.get("json_scope_heading"), selection: Binding(get: { d.scope }, set: { save(d, scope: $0) })) {
                        Text(L10n.get("json_scope_all")).tag("ALL")
                        Text(L10n.get("json_scope_watch")).tag("WATCH_ONLY")
                        Text(L10n.get("json_scope_ttb")).tag("TTB_DISCIPLINES")
                    }
                    if !csv {
                        Toggle(L10n.get("json_month_switch"), isOn: Binding(get: { d.subfolderPerMonth }, set: { save(d, month: $0) }))
                    }
                    Toggle(L10n.get("json_position_switch"), isOn: Binding(get: { d.includeStartPosition }, set: { save(d, position: $0) }))
                    Toggle(L10n.get(csv ? "csv_remove_switch" : "json_remove_switch"), isOn: Binding(get: { d.removeOnDelete }, set: { save(d, remove: $0) }))
                    Text(L10n.get(csv ? "csv_remove_body" : "json_remove_body")).font(.footnote).foregroundStyle(.secondary)
                    if csv {
                        Picker(L10n.get("csv_style_heading"), selection: Binding(get: { d.dialect }, set: { save(d, dialect: $0) })) {
                            Text(L10n.get(companion.language == "de" ? "csv_style_auto_de" : "csv_style_auto_intl")).tag("AUTO")
                            Text(L10n.get("csv_style_de")).tag("EXCEL_DE")
                            Text(L10n.get("csv_style_intl")).tag("INTERNATIONAL")
                        }
                    }
                }
                Section {
                    Button(L10n.get("destination_remove_button"), role: .destructive) { confirmingRemove = true }
                } footer: {
                    Text(L10n.get("destination_remove_footer"))
                }
            }
        }
        .navigationTitle(destination?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { await companion.refreshFolderDestinations() }
        .confirmationDialog(
            String(format: L10n.get("destination_remove_confirm_title"), destination?.name ?? ""),
            isPresented: $confirmingRemove, titleVisibility: .visible
        ) {
            Button(L10n.get("destination_remove_confirm_button"), role: .destructive) {
                Task {
                    await companion.removeFolderDestination(id)
                    dismiss()
                }
            }
        } message: {
            Text(L10n.get("destination_remove_footer"))
        }
    }

    @ViewBuilder
    private func status(_ d: DestinationView) -> some View {
        if !d.issue.isEmpty {
            Text(d.issue).foregroundStyle(.red)
        } else if !d.enabled {
            Text(L10n.get("destination_status_paused")).foregroundStyle(.secondary)
        } else if d.waiting > 0 {
            Text(L10n.plural("destination_waiting_count", Int(d.waiting)))
        } else if d.lastWrittenEpochMillis > 0 {
            Text(String(format: L10n.get("destination_status_up_to_date_last"), Format.date(d.lastWrittenEpochMillis / 1000)))
                .foregroundStyle(.secondary)
        } else {
            Text(L10n.get("destination_status_up_to_date")).foregroundStyle(.secondary)
        }
    }

    private func scopeText(_ scope: String) -> String {
        switch scope {
        case "WATCH_ONLY": return L10n.get("json_scope_watch")
        case "TTB_DISCIPLINES": return L10n.get("json_scope_ttb")
        default: return L10n.get("json_scope_all")
        }
    }

    /// Saves the options of [d] with the one that changed.
    private func save(
        _ d: DestinationView, auto: Bool? = nil, scope: String? = nil, month: Bool? = nil,
        position: Bool? = nil, remove: Bool? = nil, dialect: String? = nil
    ) {
        Task {
            await companion.updateFolderDestination(
                d.id, autoWrite: auto ?? d.autoWrite, scope: scope ?? d.scope, position: position ?? d.includeStartPosition,
                monthFolders: month ?? d.subfolderPerMonth, removeOnDelete: remove ?? d.removeOnDelete, dialect: dialect ?? d.dialect
            )
        }
    }
}
