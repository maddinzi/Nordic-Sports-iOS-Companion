import AuthenticationServices
import Foundation
import NordicSportsShared
import SwiftUI
import UIKit

/// The app's state on top of the shared Kotlin core (`CompanionCore`, built by
/// `IosCompanion` in the Companion repo): the activity list, Strava sign-in and sync. Every
/// rule lives in the shared code; this class only calls it and publishes the results.
@MainActor
final class Companion: NSObject, ObservableObject {
    static let shared = Companion()

    /// Strava's https redirect, received as a Universal Link (the server's
    /// apple-app-site-association); must match `CompanionCore.STRAVA_REDIRECT_URI`.
    static let stravaCallbackHost = "api.nordicsports.maddin.me"
    static let stravaCallbackPath = "/strava-callback"

    @Published private(set) var activities: [ActivityItem] = []
    @Published private(set) var syncing = false
    @Published private(set) var syncLines: [String] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var stravaConnected = false
    @Published private(set) var diaryName = ""
    @Published private(set) var diaryIssue = ""
    @Published private(set) var diarySettings = DiarySettings(autoUpdate: true, roundDurationUp: true, compactDiary: true)
    @Published private(set) var diaryBusy = false
    @Published private(set) var watchSettings: [WatchSettingsView] = []
    @Published var message: String?

    let core: CompanionCore
    let language: String
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        let language = Self.preferredLanguage()
        let info = Bundle.main.infoDictionary ?? [:]
        func setting(_ key: String) -> String { (info[key] as? String) ?? "" }
        self.language = language
        core = IosCompanion.shared.create(
            textsJson: Self.textTable(language),
            language: language,
            stravaClientId: setting("StravaClientId"),
            stravaClientSecret: setting("StravaClientSecret"),
            webhookBaseUrl: "https://api.nordicsports.maddin.me",
            webhookApiKey: setting("WebhookApiKey"),
            diaryFile: FilesDiaryAccess.shared,
            watchMessenger: WatchLinkSpike.shared,
            debug: { line in NSLog("[core] %@", line) }
        )
        super.init()
        stravaConnected = core.stravaConnected()
        refreshDiary()
        refreshWatchSettings()
    }

    // MARK: - Activities

    func refresh() async {
        do {
            activities = try await core.activities(limit: 300)
        } catch {
            message = error.localizedDescription
        }
    }

    /// One message from the watch app [variant] (a Connect IQ dictionary). Returns the start
    /// time to confirm to the watch, or 0.
    func receive(message dict: [String: Any], variant: String) async -> Int64 {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            WatchLinkSpike.shared.add("watch message could not be read as JSON")
            return 0
        }
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let result = try await core.receiveWatchMessage(json: json, variant: variant, nowEpochMillis: now)
            WatchLinkSpike.shared.add("activity from \(variant): \(result.summary)")
            await refresh()
            return result.receiptStartTime
        } catch {
            WatchLinkSpike.shared.add("activity could not be stored: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Sync

    /// Like Android's onResume: a quiet sync whenever the app comes to the foreground.
    func syncOnOpen() async {
        await refresh()
        guard stravaConnected || core.diaryConnected(), !syncing else { return }
        await sync()
    }

    func sync() async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.syncNow()
            syncLines = report.lines
            lastSync = Date()
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
        await refresh()
    }

    func backfill(days: Int32) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.backfill(days: days)
            syncLines = report.lines
            lastSync = Date()
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
        await refresh()
    }

    // MARK: - Strava

    var stravaConfigured: Bool { core.stravaConfigured }

    func connectStrava() {
        guard let url = URL(string: core.stravaAuthorizeUrl()) else { return }
        guard #available(iOS 17.4, *) else {
            message = "Strava sign-in needs iOS 17.4 or later."
            return
        }
        let session = ASWebAuthenticationSession(
            url: url,
            callback: .https(host: Self.stravaCallbackHost, path: Self.stravaCallbackPath)
        ) { callbackURL, error in
            Task { @MainActor in await self.finishStravaSignIn(callbackURL, error) }
        }
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            message = "Strava sign-in could not start."
        }
    }

    private func finishStravaSignIn(_ callbackURL: URL?, _ error: Error?) async {
        authSession = nil
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = String(format: L10n.get("main_toast_strava_connect_failed"), error.localizedDescription)
            return
        }
        guard let callbackURL else { return }
        do {
            let reason = try await core.completeStravaSignIn(callbackUrl: callbackURL.absoluteString)
            if reason.isEmpty {
                stravaConnected = core.stravaConnected()
                message = L10n.get("main_toast_strava_connected")
                await sync()
            } else {
                message = String(format: L10n.get("main_toast_strava_connect_failed"), reason)
            }
        } catch {
            message = String(format: L10n.get("main_toast_strava_connect_failed"), error.localizedDescription)
        }
    }

    func disconnectStrava() async {
        do {
            try await core.disconnectStrava()
        } catch {
            message = error.localizedDescription
        }
        stravaConnected = core.stravaConnected()
        message = L10n.get("main_toast_strava_disconnected")
    }

    // MARK: - Diary

    var diaryConnected: Bool { !diaryName.isEmpty }

    private func refreshDiary() {
        diaryName = core.diaryConnected() ? core.diaryWorkbookName() : ""
        diaryIssue = core.diaryIssue()
        diarySettings = core.diarySettings()
    }

    /// A workbook picked in the Files app: remembered, read once and connected when it opens
    /// as a TTB diary.
    func connectDiary(_ url: URL) async {
        if let problem = FilesDiaryAccess.shared.remember(url) {
            message = problem
            return
        }
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            let problem = try await core.connectDiary(fileName: url.lastPathComponent)
            if problem.isEmpty {
                refreshDiary()
                message = String(format: L10n.get("connect_diary_connected_to"), url.lastPathComponent)
            } else {
                FilesDiaryAccess.shared.restorePrevious()
                message = problem
            }
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
    }

    func disconnectDiary() {
        core.disconnectDiary()
        FilesDiaryAccess.shared.forget()
        refreshDiary()
    }

    func setDiaryAutoUpdate(_ on: Bool) { core.setDiaryAutoUpdate(enabled: on); refreshDiary() }
    func setDiaryRoundDurationUp(_ on: Bool) { core.setDiaryRoundDurationUp(enabled: on); refreshDiary() }
    func setDiaryCompact(_ on: Bool) { core.setDiaryCompact(enabled: on); refreshDiary() }

    /// "Write to diary now": everything due from the last [days] days.
    func writeDiary(days: Int32) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.writeDiary(days: days)
            syncLines = report.lines
            lastSync = Date()
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
        await refresh()
    }

    /// "Push to diary" for one activity; the sync log shows what was written.
    func pushToDiary(_ activityId: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let problem = try await core.pushToDiary(activityId: activityId)
            if !problem.isEmpty { message = problem }
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
        await refresh()
    }

    // MARK: - Watch settings

    func refreshWatchSettings() {
        watchSettings = core.watchSettings()
    }

    /// [value] is 0/1 for an on/off setting, else the option's value; sent right away.
    func changeWatchSetting(deviceId: Int64, key: String, value: Int32) {
        core.changeWatchSetting(deviceId: deviceId, key: key, value: value)
        refreshWatchSettings()
    }

    func askWatchAgain(deviceId: Int64) {
        core.refreshWatchSettings(deviceId: deviceId)
        refreshWatchSettings()
    }

    func dismissWatchNote(deviceId: Int64, key: String) {
        core.dismissWatchSettingNote(deviceId: deviceId, key: key)
        refreshWatchSettings()
    }

    // MARK: - Logs, export, feedback

    enum LogKind { case diary, app, transfer }

    func logLines(_ kind: LogKind) async -> [LogLine] {
        do {
            switch kind {
            case .diary: return try await core.diaryWorkLog(limit: 500)
            case .app: return try await core.appLogLines(limit: 500)
            case .transfer: return try await core.transferLogLines(limit: 500)
            }
        } catch {
            message = error.localizedDescription
            return []
        }
    }

    func activityLog(_ activityId: String) async -> [LogLine] {
        (try? await core.activityLog(activityId: activityId)) ?? []
    }

    /// "Export my data": the JSON written to a temporary file, for the share sheet.
    func exportFile() async -> URL? {
        do {
            let json = try await core.exportJson()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(core.exportFileName())
            try json.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            message = String(format: L10n.get("main_toast_export_failed"), error.localizedDescription)
            return nil
        }
    }

    /// "sent", "tooMany" or "failed".
    func sendFeedback(category: String, app: String, text: String, email: String, includeDetails: Bool) async -> String {
        var details: [String: String] = [:]
        if includeDetails {
            details = Self.deviceDetails()
            details["language"] = language
            if let watch = try? await core.latestWatchName(), !watch.isEmpty { details["watch"] = watch }
        }
        do {
            return try await core.sendFeedback(
                category: category, app: app, message: text, contactEmail: email,
                appVersion: Format.appVersion, details: details
            )
        } catch {
            return "failed"
        }
    }

    /// The phone model ("iPhone13,2") and iOS version, as the feedback's technical details.
    static func deviceDetails() -> [String: String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return ["phone": "Apple \(model)", "ios": UIDevice.current.systemVersion]
    }

    // MARK: - Edit and review

    /// Saves the athlete's edits (saving is the review), then lets the next sync write the
    /// diary: iOS has no background job for that yet, so it runs right away.
    func saveActivity(
        _ activityId: String, title: String, trainingType: String, rpe: Int, feeling: Int,
        comment: String, minutes: Int, kilometers: Double
    ) async -> Bool {
        do {
            let saved = try await core.saveActivity(
                activityId: activityId, title: title, trainingType: trainingType,
                rpe: Int32(rpe), feeling: Int32(feeling), diaryComment: comment,
                overrideElapsedSec: Int32(max(0, minutes) * 60), overrideDistanceM: Float(max(0, kilometers) * 1000)
            )
            guard saved.boolValue else { return false }
            message = L10n.get("main_toast_activity_updated")
            await afterEdit()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func skipReview(_ activityId: String) async {
        do {
            try await core.skipReview(activityId: activityId)
        } catch {
            message = error.localizedDescription
        }
        await afterEdit()
    }

    private func afterEdit() async {
        if diaryConnected, diarySettings.autoUpdate {
            await sync()
        } else {
            await refresh()
        }
    }

    // MARK: - Add and delete

    var manualTypes: [ManualTypeView] { core.manualTypes() }

    /// Stores an activity entered by hand; returns its id, or nil when that failed.
    func addActivity(typeKey: String, start: Date, minutes: Int) async -> String? {
        do {
            let id = try await core.addActivity(
                typeKey: typeKey,
                startEpochSec: Int64(start.timeIntervalSince1970),
                elapsedSec: Int32(minutes * 60)
            )
            message = L10n.get("main_toast_activity_saved")
            await refresh()
            return id
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// Deletes an activity (the Strava activity stays); returns what to tell the athlete.
    func deleteActivity(_ activityId: String) async -> Bool {
        do {
            guard let result = try await core.deleteActivity(activityId: activityId) else {
                message = L10n.get("main_toast_activity_delete_failed")
                return false
            }
            if let failure = result.diaryRemovalMessage, result.diaryRemovalAttempted, !result.diaryEntryRemoved {
                message = String(format: L10n.get("main_toast_activity_deleted_diary_removal_failed"), failure)
            } else if result.diaryEntryRemoved {
                message = L10n.get(result.stillOnStrava
                    ? "main_toast_activity_deleted_diary_removed_still_on_strava" : "main_toast_activity_deleted_diary_removed")
            } else {
                message = L10n.get(result.stillOnStrava ? "main_toast_activity_deleted_still_on_strava" : "main_toast_activity_deleted")
            }
            await refresh()
            return true
        } catch {
            message = L10n.get("main_toast_activity_delete_failed")
            return false
        }
    }

    // MARK: - Texts

    /// The phone's language among the Companion's six, English otherwise.
    private static func preferredLanguage() -> String {
        let supported = ["en", "de", "fr", "it", "rm", "gsw"]
        for tag in Locale.preferredLanguages {
            let code = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if supported.contains(code) { return code }
        }
        return "en"
    }

    /// The generated `texts-<language>.json` (tools/generate_strings.py), for the shared code.
    private static func textTable(_ language: String) -> String {
        guard let url = Bundle.main.url(forResource: "texts-\(language)", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "{}" }
        return text
    }
}

extension Companion: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
            return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
        }
    }
}

/// The Android texts by name, from App/Localizable.xcstrings (generated from strings.xml).
enum L10n {
    static func get(_ name: String) -> String {
        NSLocalizedString(name, comment: "")
    }

    /// A `<plurals>` text for [count] (the catalog's plural variations).
    static func plural(_ name: String, _ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(name, comment: ""), count)
    }
}
