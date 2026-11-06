import Foundation

/// File access shared by the diary workbook (`FilesDiaryAccess`) and the JSON/CSV folders (`FolderFiles`): coordinated
/// reads and writes (a provider such as OneDrive or iCloud may first download or later upload the file), the atomic
/// replace, and the verified in-place write for providers that refuse the replace (build 16, OneDrive in Files: "no
/// permission to save").
enum CoordinatedFiles {
    /// Runs [read] on [url] under a coordinated read.
    static func read(_ url: URL, options: NSFileCoordinator.ReadingOptions = [], _ read: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinatorError) { source in
            result = Result { try read(source) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    /// The bytes of [url], read under coordination.
    static func readData(_ url: URL, options: NSFileCoordinator.ReadingOptions = []) throws -> Data {
        var data = Data()
        try read(url, options: options) { source in data = try Data(contentsOf: source) }
        return data
    }

    /// Runs [write] on [url] under a coordinated write.
    static func write(_ url: URL, options: NSFileCoordinator.WritingOptions, _ write: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var result: Result<Void, Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { target in
            result = Result { try write(target) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    /// Writes [data] to a temporary file in the system's replacement directory for [url], checks it, and swaps it in:
    /// the original is replaced in one step or not at all.
    static func replaceAtomically(_ url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        let directory = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fileManager.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent(url.lastPathComponent)
        try data.write(to: temporary)
        guard try Data(contentsOf: temporary) == data else { throw CocoaError(.fileWriteUnknown) }
        _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
    }

    /// An in-place write by [write], verified by reading the file back; when it fails or does not match, the bytes the
    /// file had before are written back and the error is rethrown.
    static func writeInPlace(_ url: URL, _ data: Data, _ write: () throws -> Void) throws {
        let original = try? Data(contentsOf: url)
        do {
            try write()
            guard try Data(contentsOf: url) == data else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            if let original { restore(original, to: url) }
            throw error
        }
    }

    /// Overwrites [url] through a file handle (truncate, then write): the last way in when a provider refuses both the
    /// replace and a plain write. Use inside `writeInPlace`, which checks and undoes it.
    static func writeThroughHandle(_ url: URL, _ data: Data) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
    }

    private static func restore(_ original: Data, to url: URL) {
        if (try? original.write(to: url)) != nil { return }
        try? writeThroughHandle(url, original)
    }

    /// Gone or no access: stays until the athlete picks the file or folder again.
    static func isPermanent(_ error: Error) -> Bool {
        guard let cocoa = error as? CocoaError else { return false }
        let lasting: [CocoaError.Code] = [.fileNoSuchFile, .fileReadNoSuchFile, .fileReadNoPermission, .fileWriteNoPermission]
        return lasting.contains(cocoa.code)
    }

    /// Domain and code, for the log ("NSCocoaErrorDomain 260 ...").
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code) \(ns.localizedDescription)"
    }
}
