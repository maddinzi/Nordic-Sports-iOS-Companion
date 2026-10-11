import NordicSportsShared
import SwiftUI
import UniformTypeIdentifiers

/// Spike 4, local part (roadmap step 1, throw-away): a TTB diary workbook from the Files app
/// (iCloud Drive, On My iPhone, or a provider app such as OneDrive), read with the shared
/// Kotlin TTB code, re-written (every part re-compressed with iOS zlib) and read back. The
/// workbook is remembered as a security-scoped bookmark, so "Read again" after an app restart
/// shows whether iOS keeps the access. The re-written copy can be saved and opened in Excel.
final class DiaryFileSpike: ObservableObject {
    static let shared = DiaryFileSpike()

    @Published private(set) var fileName: String?
    @Published private(set) var summary: [String] = []
    @Published private(set) var copy: Data?
    @Published private(set) var busy = false

    private let bookmarkKey = "spike.diary.bookmark"
    private var log: (String) -> Void { WatchLinkSpike.shared.add }

    var hasBookmark: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// A workbook just picked in the Files app.
    func open(_ url: URL) {
        read(url, remember: true)
    }

    /// The remembered workbook, without the picker.
    func readAgain() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
            log("diary: bookmark resolved\(stale ? " (stale, renewed)" : "")")
            read(url, remember: stale)
        } catch {
            log("diary: bookmark no longer resolves: \(error.localizedDescription)")
            summary = ["The remembered workbook can no longer be opened: \(error.localizedDescription)"]
        }
    }

    private func read(_ url: URL, remember: Bool) {
        let scoped = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if remember {
                let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
            data = try readCoordinated(url)
        } catch {
            log("diary: cannot read \(url.lastPathComponent): \(error.localizedDescription)")
            summary = ["Cannot read the workbook: \(error.localizedDescription)"]
            return
        }
        fileName = url.lastPathComponent
        busy = true
        log("diary: read \(url.lastPathComponent), \(data.count / 1024) KB, scoped access \(scoped)")
        DispatchQueue.global(qos: .userInitiated).async {
            let lines: [String]
            var copy: Data?
            do {
                let probe = try WorkbookProbeKt.probeWorkbook(workbook: data)
                copy = probe.rewritten
                lines = [
                    "\(probe.parts) zip parts, \(probe.worksheets) worksheets",
                    "\(probe.diaryEntries) diary entries, \(probe.firstEntryDay ?? "-") to \(probe.lastEntryDay ?? "-")",
                    "Disciplines: \(probe.disciplines.isEmpty ? "-" : probe.disciplines)",
                    "Read \(probe.readMillis) ms, re-write and read back \(probe.writeMillis) ms",
                    probe.roundTripOk ? "Re-written workbook reads back identical: OK" : "Re-written workbook differs: FAILED",
                ]
            } catch {
                lines = ["The shared code could not read it: \(error.localizedDescription)"]
            }
            DispatchQueue.main.async {
                self.summary = lines
                self.copy = copy
                self.busy = false
                lines.forEach { self.log("diary: \($0)") }
            }
        }
    }

    /// Files from provider apps (OneDrive, iCloud) may need downloading first; a coordinated
    /// read waits for the provider.
    private func readCoordinated(_ url: URL) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}

/// The spike screen's diary section.
struct DiaryFileSpikeSection: View {
    @ObservedObject var spike = DiaryFileSpike.shared
    @State private var picking = false
    @State private var exporting = false

    private static let xlsx = UTType(filenameExtension: "xlsx") ?? .data

    var body: some View {
        Section("Diary workbook (Files app)") {
            if let name = spike.fileName {
                Text(name).font(.headline)
            }
            ForEach(spike.summary, id: \.self) { Text($0).font(.footnote) }
            if spike.busy { ProgressView() }
            Button("Open diary workbook") { picking = true }
            Button("Read again (remembered workbook)") { spike.readAgain() }
                .disabled(!spike.hasBookmark || spike.busy)
            Button("Save re-written copy") { exporting = true }
                .disabled(spike.copy == nil)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [Self.xlsx]) { result in
            switch result {
            case .success(let url): spike.open(url)
            case .failure(let error): WatchLinkSpike.shared.add("diary: picker failed: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: WorkbookDocument(data: spike.copy ?? Data()),
            contentType: Self.xlsx,
            defaultFilename: (spike.fileName.map { ($0 as NSString).deletingPathExtension } ?? "Diary") + " (iOS copy)"
        ) { result in
            if case .failure(let error) = result {
                WatchLinkSpike.shared.add("diary: saving the copy failed: \(error.localizedDescription)")
            } else {
                WatchLinkSpike.shared.add("diary: re-written copy saved")
            }
        }
    }
}

private struct WorkbookDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "xlsx") ?? .data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
