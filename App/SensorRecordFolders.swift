import Foundation
import NordicSportsShared

/// Where the Sensor Record files live in Documents (Files › On My iPhone › Nordic Sports), the shared layout
/// `SensorRecordFiles`: one folder per record holding the watch's file and, when the phone recorded its own motion at
/// the same time, the phone's file. Files saved before this layout stay in the flat `recording-boost` folder and are
/// still found here.
enum SensorRecordFolders {
    private static var layout: SensorRecordFiles { SensorRecordFiles.shared }

    /// The folder of all record folders, and the flat folder of the files saved before.
    static var folder: String { layout.FOLDER }
    static var legacyFolder: String { layout.LEGACY_FOLDER }

    /// The location as the Files app shows it, for the logs and the list screen.
    static var locationLabel: String { "On My iPhone \u{203A} Nordic Sports \u{203A} \(folder)" }

    private static var documents: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The record's end (its watch id, epoch s) in local time as `yyyyMMdd_HHmm`.
    static func stamp(_ burstId: Int64) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(burstId)))
    }

    /// The record's folder (`sensor-records/<record name>`), created when it is not there yet.
    static func recordFolder(_ burstId: Int64) throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let url = docs.appendingPathComponent(layout.folder(stamp: stamp(burstId), burstId: burstId), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func watchFileName(_ burstId: Int64) -> String { layout.watchFileName(stamp: stamp(burstId), burstId: burstId) }
    static func phoneFileName(_ burstId: Int64) -> String { layout.phoneFileName(stamp: stamp(burstId), burstId: burstId) }

    /// The watch's record id in a Sensor Record file or folder name (either layout), 0 when the name has none.
    static func burstId(_ name: String) -> Int64 { layout.burstIdOf(name: name)?.int64Value ?? 0 }

    /// Every stored Sensor Record file of either layout by name, from one listing per folder.
    static func allFiles() -> [URL] {
        guard let docs = documents else { return [] }
        let files = FileManager.default
        var out: [URL] = []
        let legacy = docs.appendingPathComponent(legacyFolder, isDirectory: true)
        for name in (try? files.contentsOfDirectory(atPath: legacy.path)) ?? [] where name.hasSuffix(".csv") {
            out.append(legacy.appendingPathComponent(name))
        }
        let root = docs.appendingPathComponent(folder, isDirectory: true)
        for record in (try? files.contentsOfDirectory(atPath: root.path)) ?? [] {
            let dir = root.appendingPathComponent(record, isDirectory: true)
            for name in (try? files.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".csv") {
                out.append(dir.appendingPathComponent(name))
            }
        }
        return out
    }

    /// The stored file [fileName] (a watch or phone file of either layout), nil while it is not there.
    static func existing(fileName: String) -> URL? {
        guard !fileName.isEmpty, let docs = documents else { return nil }
        let id = burstId(fileName)
        let candidates = [
            docs.appendingPathComponent(layout.folder(stamp: stamp(id), burstId: id), isDirectory: true).appendingPathComponent(fileName),
            docs.appendingPathComponent(legacyFolder, isDirectory: true).appendingPathComponent(fileName),
        ]
        if let hit = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { return hit }
        // A record folder named with another time zone's stamp: look by name.
        return allFiles().first { $0.lastPathComponent == fileName }
    }

    /// Every phone motion record by its Sensor Record's id; the new layout wins over an old file of the same record.
    static func phoneFiles() -> [Int64: URL] {
        var out: [Int64: URL] = [:]
        for url in allFiles() where layout.isPhoneFile(name: url.lastPathComponent) {
            let id = burstId(url.lastPathComponent)
            guard id > 0 else { continue }
            if out[id] == nil || url.path.contains("/\(folder)/") { out[id] = url }
        }
        return out
    }
}
