import Foundation
import NordicSportsShared

/// The diary workbook picked in the Files app (iCloud Drive, On My iPhone, or a provider app
/// such as OneDrive), for the shared diary writer (`DiaryFileAccess` in the Companion's
/// iosMain). The file is remembered as a security-scoped bookmark, which spike 4 showed
/// survives app restarts; reads and writes are coordinated so a provider can download or
/// upload the file. Called from a background thread, one call at a time.
///
/// PRIVACY-SYNC: backups of the workbook (training data, comments) stay in the app's own
/// Documents folder (visible in Files under On My iPhone › Nordic Sports), newest 30 kept,
/// removed with the app.
final class FilesDiaryAccess: NSObject, DiaryFileAccess, @unchecked Sendable {
    static let shared = FilesDiaryAccess()

    static let backupFolder = "diary-backups"
    static let keepBackups = 30
    private let bookmarkKey = "diary.bookmark"
    private var lastFailure = ""
    private var lastFailurePermanent = false
    private var lastConflict = false
    private var lastBackupFailed = false

    var hasWorkbook: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// The workbook remembered before [remember], until the new one is confirmed.
    private var previousBookmark: Data?

    /// The URL the picker returned in this app session; tried before the bookmark, so the log
    /// shows whether a failure comes from the bookmark round trip or from the provider.
    private var pickedURL: URL?

    private func log(_ line: String) { WatchLinkSpike.shared.add("diary: \(line)") }

    /// Remembers a workbook just picked in the Files app. Returns nil, or why it can't be kept.
    func remember(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        log("picked \(url.lastPathComponent), scoped access \(scoped), \(Self.describe(url))")
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            previousBookmark = UserDefaults.standard.data(forKey: bookmarkKey)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            pickedURL = url
            return nil
        } catch {
            log("bookmark failed: \(Self.describe(error))")
            return error.localizedDescription
        }
    }

    /// The picked file is no diary: back to the workbook remembered before, if any.
    func restorePrevious() {
        UserDefaults.standard.set(previousBookmark, forKey: bookmarkKey)
        previousBookmark = nil
        pickedURL = nil
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        pickedURL = nil
    }

    // MARK: - DiaryFileAccess

    /// A coordinated read; a provider (OneDrive, iCloud) may first have to download the file.
    /// When that read fails, the file is asked to download, then read again every 3 s (five
    /// times), and finally as a coordinated copy (`.forUploading`). Each attempt is logged.
    func readWorkbook() -> Data? {
        withWorkbook { url in
            do {
                return try Self.coordinatedRead(url, options: [])
            } catch {
                log("read failed: \(Self.describe(error)); \(Self.describe(url))")
                if Self.waitForDownload(url) {
                    log("downloaded: \(Self.describe(url))")
                    if let data = try? Self.coordinatedRead(url, options: []) { return data }
                }
                // OneDrive's provider may need a while for a file it has not downloaded yet
                // (build 16: the third pick worked), without reporting a download state.
                for attempt in 1...5 {
                    Thread.sleep(forTimeInterval: 3)
                    if let data = try? Self.coordinatedRead(url, options: []) {
                        log("read worked on retry \(attempt)")
                        return data
                    }
                }
                let data = try Self.coordinatedRead(url, options: .forUploading)
                log("read as a coordinated copy worked")
                return data
            }
        }
    }

    private static func coordinatedRead(_ url: URL, options: NSFileCoordinator.ReadingOptions) throws -> Data {
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinatorError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    /// Asks the provider to download [url] and waits up to a minute; false when it isn't a
    /// cloud file or did not arrive.
    private static func waitForDownload(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true else { return false }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
            WatchLinkSpike.shared.add("diary: download request failed: \(describe(error))")
            return false
        }
        for _ in 0..<60 {
            let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
            if status == .current { return true }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    /// The workbook's version token (modification date and size), or "" when iOS can't tell.
    /// Asked right before the read; the write is refused when it no longer matches.
    func workbookRevision() -> String {
        withWorkbook { url in Self.revision(of: url) } ?? ""
    }

    private static func revision(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modified = values?.contentModificationDate, let size = values?.fileSize else { return "" }
        return "\(modified.timeIntervalSince1970)|\(size)"
    }

    /// Whether the file is known to differ from [expected] (unknown on either side: not changed).
    private static func hasChanged(_ url: URL, since expected: String) -> Bool {
        guard !expected.isEmpty else { return false }
        let current = revision(of: url)
        return !current.isEmpty && current != expected
    }

    /// A coordinated write that never truncates the workbook first: the new bytes go to a
    /// temporary file in the system's replacement directory and are swapped in with
    /// `replaceItemAt`. Only when that is refused (build 16 with OneDrive in Files: "no permission
    /// to save") the file is written in place, and then read back and compared; on any failure
    /// the previous bytes are put back. A workbook that changed since [expectedRevision] is not
    /// written at all (`failureIsConflict`).
    func writeWorkbook(data: Data, expectedRevision: String) -> Bool {
        lastConflict = false
        let written: Bool? = withWorkbook { url in
            var conflict = false
            do {
                try Self.coordinatedWrite(url, options: .forReplacing) { writeURL in
                    if Self.hasChanged(writeURL, since: expectedRevision) {
                        conflict = true
                        return
                    }
                    do {
                        try Self.replaceAtomically(writeURL, with: data)
                    } catch {
                        log("atomic replace failed: \(Self.describe(error)); writing in place")
                        try Self.writeInPlace(writeURL, data) { try data.write(to: writeURL) }
                    }
                }
            } catch {
                log("write failed: \(Self.describe(error)); \(Self.writeState(url))")
                try Self.coordinatedWrite(url, options: []) { writeURL in
                    if Self.hasChanged(writeURL, since: expectedRevision) {
                        conflict = true
                        return
                    }
                    try Self.writeInPlace(writeURL, data) {
                        let handle = try FileHandle(forWritingTo: writeURL)
                        defer { try? handle.close() }
                        try handle.truncate(atOffset: 0)
                        try handle.write(contentsOf: data)
                    }
                    log("write through a file handle worked")
                }
            }
            if conflict {
                lastConflict = true
                return false
            }
            return true
        }
        if lastConflict { lastFailure = "The diary workbook changed while it was being updated." }
        else if written == nil { log("write failed for good: \(lastFailure)") }
        return written ?? false
    }

    /// Writes [data] to a temporary file next to the system's replacement directory for [url],
    /// checks it, and swaps it in. The original is replaced in one step or not at all.
    private static func replaceAtomically(_ url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent(url.lastPathComponent)
        try data.write(to: temporary)
        guard try Data(contentsOf: temporary) == data else { throw CocoaError(.fileWriteUnknown) }
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
    }

    /// An in-place write by [write], verified by reading the file back; when it fails or does
    /// not match, the bytes the file had before are written back and the error is rethrown.
    private static func writeInPlace(_ url: URL, _ data: Data, _ write: () throws -> Void) throws {
        let original = try? Data(contentsOf: url)
        do {
            try write()
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            if let original { restore(original, to: url) }
            throw error
        }
    }

    private static func restore(_ original: Data, to url: URL) {
        if (try? original.write(to: url)) != nil { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.truncate(atOffset: 0)
            try? handle.write(contentsOf: original)
        }
    }

    private static func coordinatedWrite(
        _ url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ write: (URL) throws -> Void
    ) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { writeURL in
            result = Result { try write(writeURL) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    /// Whether iOS calls the file writable, and its POSIX permissions and lock flag.
    private static func writeState(_ url: URL) -> String {
        let writable = (try? url.resourceValues(forKeys: [.isWritableKey]))?.isWritable.map { "\($0)" } ?? "?"
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber).map { String($0.intValue, radix: 8) } ?? "?"
        let locked = (attributes?[.immutable] as? NSNumber)?.boolValue.description ?? "?"
        return "writable \(writable), permissions \(permissions), locked \(locked), \(describe(url))"
    }

    func failure() -> String { lastFailure }

    func failureIsPermanent() -> Bool { lastFailurePermanent }

    func failureIsConflict() -> Bool { lastConflict }

    func backupFailed() -> Bool { lastBackupFailed }

    func saveBackup(data: Data) -> String {
        lastBackupFailed = false
        do {
            let folder = try FileManager.default
                .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(Self.backupFolder, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.dateFormat = "yyyyMMdd_HHmmss"
            try data.write(to: folder.appendingPathComponent("\(stamp.string(from: Date()))_diary-backup.xlsx"), options: .atomic)
            let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0.hasSuffix("_diary-backup.xlsx") }
                .sorted()
            for old in backups.dropLast(Self.keepBackups) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(old))
            }
            return String(format: L10n.get("ttb_forwarder_backup_saved"), "On My iPhone › Nordic Sports › \(Self.backupFolder)", Self.keepBackups)
        } catch {
            lastBackupFailed = true
            return String(format: L10n.get("ttb_forwarder_backup_failed"), error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Runs [body] on the remembered workbook with its security scope open; nil (and the
    /// failure recorded) when the bookmark no longer resolves or [body] throws.
    private func withWorkbook<T>(_ body: (URL) throws -> T) -> T? {
        lastFailure = ""
        lastFailurePermanent = false
        if let picked = pickedURL {
            let scoped = picked.startAccessingSecurityScopedResource()
            defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
            do {
                return try body(picked)
            } catch {
                log("with the picked URL: \(Self.describe(error)); trying the bookmark")
            }
        }
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return fail("No diary workbook chosen.", permanent: true)
        }
        let url: URL
        do {
            var stale = false
            url = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            if stale, let renewed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(renewed, forKey: bookmarkKey)
            }
        } catch {
            log("bookmark no longer resolves: \(Self.describe(error))")
            return fail(error.localizedDescription, permanent: true)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try body(url)
        } catch {
            log("with the bookmark (scoped access \(scoped)): \(Self.describe(error))")
            return fail(error.localizedDescription, permanent: Self.isPermanent(error))
        }
    }

    /// Domain and code, for the log ("NSCocoaErrorDomain 260 ...").
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code) \(ns.localizedDescription)"
    }

    /// What iOS knows about [url]: on disk or not, cloud file and its download state, size.
    private static func describe(_ url: URL) -> String {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileSizeKey]
        let values = try? url.resourceValues(forKeys: keys)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let cloud = values?.isUbiquitousItem.map { $0 ? "cloud" : "local" } ?? "?"
        let status = values?.ubiquitousItemDownloadingStatus?.rawValue ?? "-"
        let size = values?.fileSize.map { "\($0 / 1024) KB" } ?? "?"
        return "exists \(exists), \(cloud), download \(status), \(size), \(url.path)"
    }

    private func fail<T>(_ message: String, permanent: Bool) -> T? {
        lastFailure = message
        lastFailurePermanent = permanent
        return nil
    }

    /// Gone or no access: stays until the athlete picks the workbook again.
    private static func isPermanent(_ error: Error) -> Bool {
        guard let cocoa = error as? CocoaError else { return false }
        let lasting: [CocoaError.Code] = [.fileNoSuchFile, .fileReadNoSuchFile, .fileReadNoPermission, .fileWriteNoPermission]
        return lasting.contains(cocoa.code)
    }
}
