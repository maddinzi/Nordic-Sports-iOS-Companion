import Foundation
import NordicSportsShared

/// A folder picked in the Files app (security-scoped bookmark, base64) for a JSON or CSV
/// diary destination: lists, reads, writes and deletes files below it. Reads and writes go
/// through `NSFileCoordinator`, a write swaps a temporary file in. The shared code calls it from
/// a background thread; what went wrong is kept for the call that follows (`failure()`).
final class FolderFiles: NSObject, FolderFileAccess, @unchecked Sendable {
    static let shared = FolderFiles()

    private struct Failure {
        var text = ""
        var permanent = false
        var conflict = false
    }

    private let failureBox = Locked(Failure())

    // MARK: - Picking

    /// The bookmark (base64) of a folder just picked, or nil with the reason in `failure()`.
    func bookmark(for url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
        } catch {
            return fail(error.localizedDescription, permanent: false)
        }
    }

    // MARK: - FolderFileAccess

    func ensureFolder(bookmark: String, path: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            try Self.coordinatedWrite(url, options: []) { target in
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            }
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                throw CocoaError(.fileNoSuchFile)
            }
            return true
        } ?? false
    }

    func listFolder(bookmark: String, path: String) -> String? {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            var lines: [String] = []
            try Self.coordinatedRead(url) { source in
                let entries = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: keys)
                for entry in entries {
                    let values = try? entry.resourceValues(forKeys: Set(keys))
                    let modified = Int64((values?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
                    lines.append([
                        entry.lastPathComponent,
                        (values?.isDirectory ?? false) ? "1" : "0",
                        String(modified),
                        String(values?.fileSize ?? 0),
                    ].joined(separator: "\t"))
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    func readFile(bookmark: String, path: String) -> Data? {
        withFolder(bookmark) { root in
            var data = Data()
            try Self.coordinatedRead(Self.url(root, path)) { source in data = try Data(contentsOf: source) }
            return data
        }
    }

    func writeFile(bookmark: String, path: String, data: Data, ifMatch: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            let exists = FileManager.default.fileExists(atPath: url.path)
            if exists, !ifMatch.isEmpty, Self.modified(url) != ifMatch {
                failureBox.set(Failure(text: "\(url.lastPathComponent) changed since it was read.", permanent: false, conflict: true))
                return false
            }
            try Self.coordinatedWrite(url, options: exists ? .forReplacing : []) { target in
                if exists {
                    try Self.replaceAtomically(target, with: data)
                } else {
                    try data.write(to: target, options: .atomic)
                }
            }
            return true
        } ?? false
    }

    func deleteFile(bookmark: String, path: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            try Self.coordinatedWrite(url, options: .forDeleting) { target in
                try FileManager.default.removeItem(at: target)
            }
            return true
        } ?? false
    }

    func failure() -> String { failureBox.get().text }

    func failureIsPermanent() -> Bool { failureBox.get().permanent }

    func failureIsConflict() -> Bool { failureBox.get().conflict }

    // MARK: - Helpers

    /// Runs [body] on the bookmarked folder inside its security scope. Nil (with the reason kept)
    /// when the bookmark no longer resolves or [body] throws.
    private func withFolder<T>(_ bookmark: String, _ body: (URL) throws -> T) -> T? {
        failureBox.set(Failure())
        guard let data = Data(base64Encoded: bookmark) else {
            return fail("The folder is no longer valid. Please choose it again.", permanent: true)
        }
        var stale = false
        let root: URL
        do {
            root = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        } catch {
            return fail(error.localizedDescription, permanent: true)
        }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        do {
            return try body(root)
        } catch {
            return fail(error.localizedDescription, permanent: Self.isPermanent(error))
        }
    }

    private func fail<T>(_ message: String, permanent: Bool) -> T? {
        failureBox.set(Failure(text: message, permanent: permanent, conflict: false))
        return nil
    }

    private static func isPermanent(_ error: Error) -> Bool {
        guard let cocoa = error as? CocoaError else { return false }
        let lasting: [CocoaError.Code] = [.fileNoSuchFile, .fileReadNoSuchFile, .fileReadNoPermission, .fileWriteNoPermission]
        return lasting.contains(cocoa.code)
    }

    private static func url(_ root: URL, _ path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    /// The modified time in epoch milliseconds as text: the revision the shared code hands back.
    private static func modified(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return String(Int64((date?.timeIntervalSince1970 ?? 0) * 1000))
    }

    private static func coordinatedRead(_ url: URL, _ read: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { source in
            result = Result { try read(source) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    private static func coordinatedWrite(
        _ url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ write: (URL) throws -> Void
    ) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { target in
            result = Result { try write(target) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    /// Writes [data] to a temporary file, checks it and swaps it in: the file is replaced in one step or not at all.
    private static func replaceAtomically(_ url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent(url.lastPathComponent)
        try data.write(to: temporary)
        guard try Data(contentsOf: temporary) == data else { throw CocoaError(.fileWriteUnknown) }
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
    }
}
