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

    var hasWorkbook: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// The workbook remembered before [remember], until the new one is confirmed.
    private var previousBookmark: Data?

    /// Remembers a workbook just picked in the Files app. Returns nil, or why it can't be kept.
    func remember(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            previousBookmark = UserDefaults.standard.data(forKey: bookmarkKey)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The picked file is no diary: back to the workbook remembered before, if any.
    func restorePrevious() {
        UserDefaults.standard.set(previousBookmark, forKey: bookmarkKey)
        previousBookmark = nil
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - DiaryFileAccess

    func readWorkbook() -> Data? {
        withWorkbook { url in
            var coordinatorError: NSError?
            var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
                result = Result { try Data(contentsOf: readURL) }
            }
            if let coordinatorError { throw coordinatorError }
            return try result.get()
        }
    }

    func writeWorkbook(data: Data) -> Bool {
        let written: Bool? = withWorkbook { url in
            var coordinatorError: NSError?
            var result: Result<Void, Error> = .failure(CocoaError(.fileWriteUnknown))
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
                // In place, not atomic: access is granted to this one file, not to its folder,
                // so a temporary file next to it may not be allowed.
                result = Result { try data.write(to: writeURL) }
            }
            if let coordinatorError { throw coordinatorError }
            try result.get()
            return true
        }
        return written ?? false
    }

    func failure() -> String { lastFailure }

    func failureIsPermanent() -> Bool { lastFailurePermanent }

    func saveBackup(data: Data) -> String {
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
            return String(format: L10n.get("ttb_forwarder_backup_failed"), error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Runs [body] on the remembered workbook with its security scope open; nil (and the
    /// failure recorded) when the bookmark no longer resolves or [body] throws.
    private func withWorkbook<T>(_ body: (URL) throws -> T) -> T? {
        lastFailure = ""
        lastFailurePermanent = false
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
            return fail(error.localizedDescription, permanent: true)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try body(url)
        } catch {
            return fail(error.localizedDescription, permanent: Self.isPermanent(error))
        }
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
