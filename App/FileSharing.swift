import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

// Share and save, the same way on every screen (feedback 2026-10-23): the share icon
// (`square.and.arrow.up`) hands a file to the share sheet, the download icon
// (`square.and.arrow.down`) saves one with the system's "Save to Files" dialog.

/// A log as a file for `ShareLink`, written only when the athlete shares (`Companion.logFile`,
/// shared `LogExport`: the same text as Android's).
struct LogFile: Transferable {
    let companion: Companion
    let kinds: [NordicSportsShared.LogKind]
    var activityId: String? = nil

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            SentTransferredFile(try await file.companion.logFile(kinds: file.kinds, activityId: file.activityId))
        }
    }
}

/// The share icon of a log screen's toolbar.
struct ShareLogButton: View {
    @EnvironmentObject var companion: Companion
    let kinds: [NordicSportsShared.LogKind]
    var activityId: String? = nil

    var body: some View {
        ShareLink(item: LogFile(companion: companion, kinds: kinds, activityId: activityId),
                  preview: SharePreview(L10n.get("log_share_this"))) {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(L10n.get("log_share_this"))
    }
}

/// A text file for `.fileExporter` (the "my data" JSON).
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// "Download my data": builds the JSON export and opens "Save to Files", so the athlete picks the
/// folder and finds the file there afterwards (the earlier share link only showed a file name).
struct DownloadMyDataButton: View {
    @EnvironmentObject var companion: Companion
    @State private var document: TextFileDocument?
    @State private var fileName = ""
    @State private var exporting = false
    @State private var preparing = false

    var body: some View {
        Button {
            preparing = true
            Task {
                if let json = await companion.exportJson() {
                    document = TextFileDocument(text: json)
                    fileName = companion.core.exportFileName()
                    exporting = true
                }
                preparing = false
            }
        } label: {
            Label(L10n.get("status_download_my_data"), systemImage: "square.and.arrow.down")
        }
        .disabled(preparing)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: fileName) { result in
            switch result {
            case .success: companion.post(L10n.get("main_toast_export_saved"))
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError {
                    companion.post(String(format: L10n.get("main_toast_export_failed"), error.localizedDescription))
                }
            }
            document = nil
        }
    }
}
