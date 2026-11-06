import CryptoKit
import Foundation
import NordicSportsShared

/// A folder picked in the Files app (security-scoped bookmark, base64) for a JSON or CSV
/// diary destination: lists, reads, writes and deletes files below it. Reads and writes go
/// through `NSFileCoordinator` (`CoordinatedFiles`); a write swaps a temporary file in, and where
/// the provider refuses that (OneDrive in Files) it writes in place, checked and undone on failure,
/// as the diary workbook does. The shared code calls it from a background thread; what went wrong
/// is kept for the call that follows (`failure()`).
final class FolderFiles: NSObject, FolderFileAccess, @unchecked Sendable {
    static let shared = FolderFiles()

    private struct Failure {
        var text = ""
        var permanent = false
        var conflict = false
    }

    private let failureBox = Locked(Failure())

    /// Bookmarks iOS called stale, renewed on the phone: the shared core keeps the bookmark it was
    /// given, so the renewed one is stored here under a hash of the original (UserDefaults, a few
    /// hundred bytes each; "Delete my data" clears them). An entry of a removed destination is never
    /// asked for again.
    private let renewalsKey = "folder.renewedBookmarks"
    private let renewalsLock = NSLock()

    private func log(_ line: String) { WatchLinkSpike.shared.add("folder: \(line)") }

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

    /// Forgets every renewed bookmark ("Delete my data").
    func forgetRenewals() {
        renewalsLock.lock()
        defer { renewalsLock.unlock() }
        UserDefaults.standard.removeObject(forKey: renewalsKey)
    }

    // MARK: - FolderFileAccess

    func ensureFolder(bookmark: String, path: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            try CoordinatedFiles.write(url, options: []) { target in
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
            try CoordinatedFiles.read(url) { source in
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
        withFolder(bookmark) { root in try CoordinatedFiles.readData(Self.url(root, path)) }
    }

    /// The order of attempts follows `FilesDiaryAccess.writeWorkbook`: the atomic swap, then (refused by
    /// the provider) a checked in-place write in the same coordination, then, when that coordination
    /// itself failed, a plain coordinated write through a file handle.
    func writeFile(bookmark: String, path: String, data: Data, ifMatch: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            let name = url.lastPathComponent
            let exists = FileManager.default.fileExists(atPath: url.path)
            if exists, !ifMatch.isEmpty, Self.modified(url) != ifMatch {
                failureBox.set(Failure(text: "\(name) changed since it was read.", permanent: false, conflict: true))
                return false
            }
            guard exists else {
                try CoordinatedFiles.write(url, options: []) { target in
                    do {
                        try data.write(to: target, options: .atomic)
                    } catch {
                        // A new file: nothing to lose, so a plain write is the fallback.
                        log("\(name): atomic create failed (\(CoordinatedFiles.describe(error))), writing directly")
                        try data.write(to: target)
                    }
                }
                return true
            }
            do {
                try CoordinatedFiles.write(url, options: .forReplacing) { target in
                    do {
                        try CoordinatedFiles.replaceAtomically(target, with: data)
                    } catch {
                        log("\(name): atomic replace failed (\(CoordinatedFiles.describe(error))), writing in place")
                        try CoordinatedFiles.writeInPlace(target, data) { try data.write(to: target) }
                    }
                }
            } catch {
                log("\(name): write failed (\(CoordinatedFiles.describe(error))), trying a file handle")
                try CoordinatedFiles.write(url, options: []) { target in
                    try CoordinatedFiles.writeInPlace(target, data) { try CoordinatedFiles.writeThroughHandle(target, data) }
                }
                log("\(name): write through a file handle worked")
            }
            return true
        } ?? false
    }

    func deleteFile(bookmark: String, path: String) -> Bool {
        withFolder(bookmark) { root in
            let url = Self.url(root, path)
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            try CoordinatedFiles.write(url, options: .forDeleting) { target in
                try FileManager.default.removeItem(at: target)
            }
            return true
        } ?? false
    }

    func failure() -> String { failureBox.get().text }

    func failureIsPermanent() -> Bool { failureBox.get().permanent }

    func failureIsConflict() -> Bool { failureBox.get().conflict }

    // MARK: - Helpers

    /// Runs [body] on the bookmarked folder inside its security scope (a renewed bookmark first, if
    /// one is stored). A stale bookmark is renewed inside the scope. Nil (with the reason kept) when
    /// the bookmark no longer resolves or [body] throws.
    private func withFolder<T>(_ bookmark: String, _ body: (URL) throws -> T) -> T? {
        failureBox.set(Failure())
        let key = Self.renewalKey(bookmark)
        let current = renewed(key) ?? bookmark
        guard let data = Data(base64Encoded: current) else {
            return fail(L10n.get("ios_folder_invalid"), permanent: true)
        }
        var stale = false
        let root: URL
        do {
            root = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        } catch {
            log("bookmark no longer resolves: \(CoordinatedFiles.describe(error))")
            return fail(error.localizedDescription, permanent: true)
        }
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        if stale { renew(root, key: key) }
        do {
            return try body(root)
        } catch {
            return fail(error.localizedDescription, permanent: CoordinatedFiles.isPermanent(error))
        }
    }

    private func renewed(_ key: String) -> String? {
        renewalsLock.lock()
        defer { renewalsLock.unlock() }
        return UserDefaults.standard.dictionary(forKey: renewalsKey)?[key] as? String
    }

    /// Stores a fresh bookmark for [root]; called inside its security scope, or iOS refuses it.
    private func renew(_ root: URL, key: String) {
        do {
            let fresh = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil).base64EncodedString()
            renewalsLock.lock()
            defer { renewalsLock.unlock() }
            var all = UserDefaults.standard.dictionary(forKey: renewalsKey) ?? [:]
            all[key] = fresh
            UserDefaults.standard.set(all, forKey: renewalsKey)
            log("stale bookmark of \(root.lastPathComponent) renewed")
        } catch {
            log("stale bookmark of \(root.lastPathComponent) could not be renewed (it may stop resolving): \(CoordinatedFiles.describe(error))")
        }
    }

    /// The key a renewed bookmark is stored under: the SHA-256 of the bookmark the shared core holds.
    private static func renewalKey(_ bookmark: String) -> String {
        SHA256.hash(data: Data(bookmark.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fail<T>(_ message: String, permanent: Bool) -> T? {
        failureBox.set(Failure(text: message, permanent: permanent, conflict: false))
        return nil
    }

    private static func url(_ root: URL, _ path: String) -> URL {
        path.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    /// The modified time in epoch milliseconds as text: the revision the shared code hands back.
    private static func modified(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return String(Int64((date?.timeIntervalSince1970 ?? 0) * 1000))
    }
}
