import AuthenticationServices
import Foundation
import NordicSportsShared
import SwiftUI
import UIKit
import UserNotifications

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
    @Published private(set) var diarySources: [DiarySourceView] = []
    @Published private(set) var watchSettings: [WatchSettingsView] = []
    @Published private(set) var liveActivities: [LiveActivityView] = []
    @Published private(set) var crashReports: [CrashReportView] = []
    @Published private(set) var nickname = ""
    @Published private(set) var reviewNewActivities = true
    @Published private(set) var syncAutomatically = true
    @Published var message: String?
    /// A confirmation with a title and a longer text (the Strava deletion confirmation).
    @Published var notice: Notice?

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
            oneDriveClientId: setting("OneDriveClientId"),
            dropboxAppKey: setting("DropboxAppKey"),
            googleClientId: setting("GoogleClientId"),
            diaryFile: FilesDiaryAccess.shared,
            watchMessenger: WatchLinkSpike.shared,
            debug: { line in NSLog("[core] %@", line) }
        )
        super.init()
        stravaConnected = core.stravaConnected()
        refreshDiary()
        refreshWatchSettings()
        refreshWatchCards()
        nickname = core.nickname()
        reviewNewActivities = core.reviewNewActivities()
        syncAutomatically = core.syncAutomatically()
    }

    // MARK: - Activities

    func refresh() async {
        do {
            activities = try await core.activities(limit: 300)
        } catch {
            message = error.localizedDescription
        }
        showStravaWithdrawalNotice()
    }

    /// Strava access withdrawn on strava.com or by Strava, noticed by the shared code at a token
    /// refresh: it has already deleted the Strava data; show its notice once (as Android on resume)
    /// and acknowledge it when the athlete closes it.
    private func showStravaWithdrawalNotice() {
        guard notice == nil, let pending = core.pendingStravaWithdrawalNotice() else { return }
        stravaConnected = core.stravaConnected()
        notice = Notice(title: pending.title, text: pending.text) { [core] in core.acknowledgeStravaWithdrawalNotice() }
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
            if !result.activityId.isEmpty {
                notifyNewActivity(result)
                // As Android in automated mode: forward on arrival (the diary now; Strava's
                // copy follows by webhook at the next sync).
                if core.syncAutomatically(), stravaConnected || core.diaryConnected() {
                    Task { await sync() }
                }
            }
            return result.receiptStartTime
        } catch {
            WatchLinkSpike.shared.add("activity could not be stored: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Sync

    /// Like Android's onResume: a quiet sync whenever the app comes to the foreground
    /// (automated sync mode only).
    func syncOnOpen() async {
        await purgeExpiredStravaData()
        await refresh()
        guard core.syncAutomatically(), stravaConnected || core.diaryConnected(), !syncing else { return }
        await sync()
    }

    /// A background run (BGTaskScheduler; Android: the daily ActivitySyncWorker): the same
    /// sync as on opening, in automated mode only. Returns a line for the Diagnostics log.
    func backgroundSync() async -> String {
        let purged = await purgeExpiredStravaData()
        if purged > 0 { WatchLinkSpike.shared.add("bg: Strava data removed from \(purged) activities") }
        guard core.syncAutomatically() else { return "manual sync mode, nothing run" }
        guard stravaConnected || core.diaryConnected() else { return "neither Strava nor a diary connected" }
        guard !syncing else { return "a sync is already running" }
        await sync()
        return "synced (\(syncLines.count) lines)"
    }

    /// Android's new-activity notification (title with the nickname, review or not); iOS
    /// shows it while the app is not on screen.
    private func notifyNewActivity(_ result: WatchMessageResult) {
        let content = UNMutableNotificationContent()
        content.title = result.notificationTitle
        content.body = result.notificationBody
        content.threadIdentifier = "activity-reviews"
        content.userInfo = ["activityId": result.activityId]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "activity-\(result.activityId)", content: content, trigger: nil)
        )
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

    /// As Android: revokes the access at Strava, deletes every Strava data the app holds, then
    /// shows the deletion confirmation (the same text is in the app log).
    func disconnectStrava() async {
        do {
            let result = try await core.disconnectStrava()
            notice = Notice(title: result.title, text: result.text)
        } catch {
            message = error.localizedDescription
        }
        stravaConnected = core.stravaConnected()
        await refresh()
    }

    /// Strava's 7-day rule (Companion design/strava-retention.md): at every foreground and
    /// background run, in either sync mode. The shared code writes the activity and app log
    /// lines. Returns how many activities lost their Strava data.
    @discardableResult
    func purgeExpiredStravaData() async -> Int {
        do {
            let count = try await core.purgeExpiredStravaData().intValue
            if count > 0 { await refresh() }
            return count
        } catch {
            WatchLinkSpike.shared.add("Strava data purge failed: \(error.localizedDescription)")
            return 0
        }
    }

    /// When Strava data was last removed from the activity (epoch millis), or 0.
    func stravaDataRemovedAt(_ activityId: String) async -> Int64 {
        (try? await core.stravaDataRemovedAt(activityId: activityId))?.int64Value ?? 0
    }

    // MARK: - Diary

    var diaryConnected: Bool { !diaryName.isEmpty }

    private func refreshDiary() {
        diaryName = core.diaryConnected() ? core.diaryWorkbookName() : ""
        diaryIssue = core.diaryIssue()
        diarySettings = core.diarySettings()
        diarySources = core.diarySources()
    }

    /// The active diary's place ("OneDrive", "Files", ...), or "".
    var activeDiarySource: String { diarySources.first { $0.active }?.name ?? "" }

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

    /// Forgets one place's diary connection ("LOCAL", "ONE_DRIVE", ...); a cloud stays signed in.
    func disconnectDiary(_ source: String) {
        core.disconnectDiary(provider: source)
        if source == "LOCAL" { FilesDiaryAccess.shared.forget() }
        refreshDiary()
    }

    func setActiveDiary(_ source: String) {
        core.setActiveDiary(provider: source)
        refreshDiary()
    }

    // MARK: - Diary clouds

    /// Signs in to OneDrive, Dropbox or Google Drive in the system sign-in sheet (PKCE).
    func signInCloud(_ source: String) {
        let scheme = core.cloudCallbackScheme(provider: source)
        guard let url = URL(string: core.cloudSignInUrl(provider: source)), !scheme.isEmpty else {
            message = "This build has no app id for that service."
            return
        }
        let session: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callbackURL, error in
                Task { @MainActor in await self.finishCloudSignIn(callbackURL, error) }
            }
        } else {
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                Task { @MainActor in await self.finishCloudSignIn(callbackURL, error) }
            }
        }
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            message = "The sign-in could not start."
        }
    }

    private func finishCloudSignIn(_ callbackURL: URL?, _ error: Error?) async {
        authSession = nil
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = error.localizedDescription
            return
        }
        guard let callbackURL else { return }
        do {
            let reason = try await core.completeCloudSignIn(callbackUrl: callbackURL.absoluteString)
            if !reason.isEmpty { message = reason }
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
    }

    func signOutCloud(_ source: String) {
        core.signOutCloud(provider: source)
        refreshDiary()
    }

    /// Finds the workbook behind a pasted link (or Dropbox path); see `DiaryLocateView`.
    func connectCloud(_ source: String, location: String) async -> DiaryLocateView? {
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            let result = try await core.connectCloudDiary(provider: source, location: location)
            refreshDiary()
            return result
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    func chooseCloudWorkbook(_ index: Int) async -> DiaryLocateView? {
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            let result = try await core.chooseCloudWorkbook(index: Int32(index))
            refreshDiary()
            return result
        } catch {
            message = error.localizedDescription
            return nil
        }
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

    /// Sets data field slot [index] of set [key] ("DataFields_rollski") to catalog field [field].
    func changeWatchDataField(deviceId: Int64, key: String, index: Int32, field: Int32) {
        core.changeWatchDataField(deviceId: deviceId, key: key, index: index, field: field)
        refreshWatchSettings()
    }

    /// The editor for plan or routine slot [key] ("IntervalPlan1", "StrengthRoutine2").
    func openWatchPlan(deviceId: Int64, key: String) -> PlanEditView? {
        core.openWatchPlan(deviceId: deviceId, key: key)
    }

    /// [view] after picking [option] in row [rowId] (an action row's option, or 0 to remove).
    func editWatchPlan(_ view: PlanEditView, key: String, rowId: String, option: Int32) -> PlanEditView {
        core.editWatchPlan(key: key, draft: view.draft, canClear: view.canClear, rowId: rowId, option: option) ?? view
    }

    /// Sends [draft] to the watch; an empty draft clears the slot.
    func saveWatchPlan(deviceId: Int64, key: String, draft: [KotlinInt]) {
        core.saveWatchPlan(deviceId: deviceId, key: key, draft: draft)
        refreshWatchSettings()
    }

    /// The activity list's watch cards: recordings running on a watch, crash reports.
    func refreshWatchCards() {
        liveActivities = core.liveActivities()
        crashReports = core.crashReports()
    }

    func dismissCrashReport(_ id: String) {
        core.dismissCrashReport(id: id)
        refreshWatchCards()
    }

    /// Sends crash report [id] with the athlete's [note] and the phone details; "sent",
    /// "tooMany" or "failed". Only this tap sends it.
    func sendCrashReport(_ id: String, note: String) async -> String {
        var details = Self.deviceDetails()
        details["language"] = language
        let result = (try? await core.sendCrashReport(id: id, note: note, appVersion: Format.appVersion, details: details)) ?? "failed"
        refreshWatchCards()
        return result
    }

    // MARK: - Nickname and review

    /// Stores the nickname (cleaned as the watch can show it) and sends it to the watches.
    func setNickname(_ value: String) {
        nickname = core.setNickname(value: value)
        refreshWatchSettings()
    }

    func setReviewNewActivities(_ on: Bool) {
        core.setReviewNewActivities(on: on)
        reviewNewActivities = core.reviewNewActivities()
    }

    func setSyncAutomatically(_ on: Bool) {
        core.setSyncAutomatically(on: on)
        syncAutomatically = core.syncAutomatically()
        if on { BackgroundSpike.shared.schedule(reason: "sync mode automated") }
    }

    func feedbackWatches() async -> [FeedbackWatchView] {
        (try? await core.feedbackWatches()) ?? []
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

    /// "Delete my data", as Android's: the shared core revokes Strava, forgets the diary and
    /// the watches' settings and empties the database; here the diary file bookmark, its
    /// backups, exports and the diagnostics log go too. The diary workbook itself stays.
    /// PRIVACY-SYNC: what "Delete my data" removes on iOS. Changing this? Re-check the
    /// Companion's design/privacy-notice-sync.md.
    func deleteAllData() async {
        do {
            try await core.deleteAllData()
        } catch {
            message = error.localizedDescription
        }
        FilesDiaryAccess.shared.forget()
        let files = FileManager.default
        if let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? files.removeItem(at: documents.appendingPathComponent(FilesDiaryAccess.backupFolder, isDirectory: true))
        }
        for name in (try? files.contentsOfDirectory(atPath: files.temporaryDirectory.path)) ?? [] where name.hasSuffix(".json") {
            try? files.removeItem(at: files.temporaryDirectory.appendingPathComponent(name))
        }
        WatchLinkSpike.shared.clearLog()
        WatchLinkSpike.shared.add("all data deleted")
        stravaConnected = core.stravaConnected()
        refreshDiary()
        refreshWatchSettings()
        refreshWatchCards()
        nickname = core.nickname()
        reviewNewActivities = core.reviewNewActivities()
        syncAutomatically = core.syncAutomatically()
        syncLines = []
        await refresh()
        message = "All data on this iPhone deleted; Strava and the diary disconnected."
    }

    /// "sent", "tooMany" or "failed". [watch]: the watch the athlete picked (its details are added with the phone's), or nil.
    func sendFeedback(
        category: String, app: String, text: String, email: String, includeDetails: Bool,
        watch: FeedbackWatchView? = nil, includeNickname: Bool = false
    ) async -> String {
        var details: [String: String] = [:]
        if includeDetails {
            details = Self.deviceDetails()
            details["language"] = language
            if let watch {
                details.merge(watch.details) { _, new in new }
            } else if let name = try? await core.latestWatchName(), !name.isEmpty {
                details["watch"] = name
            }
        }
        if includeNickname, !nickname.isEmpty { details["nickname"] = nickname }
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
            Task { await syncNewActivity(id) }
            return id
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    /// As Android, right after adding by hand (automated mode): link it to the same session
    /// on Strava or create it there, then write it to the diary.
    private func syncNewActivity(_ id: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.syncNewActivity(activityId: id)
            if !report.lines.isEmpty {
                syncLines = report.lines
                lastSync = Date()
            }
        } catch {
            message = error.localizedDescription
        }
        refreshDiary()
        await refresh()
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

    /// The phone's language among the Companion's nine, English otherwise ("no", older
    /// iOS's Norwegian, counts as Bokmål).
    private static func preferredLanguage() -> String {
        let supported = ["en", "de", "fr", "it", "rm", "gsw", "nb", "fi", "sv"]
        for tag in Locale.preferredLanguages {
            var code = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if code == "no" { code = "nb" }
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

/// A title and a text to confirm something that happened (an alert with OK).
struct Notice {
    let title: String
    let text: String
    /// Runs when the athlete closes the alert.
    var onDismiss: (() -> Void)? = nil
}
