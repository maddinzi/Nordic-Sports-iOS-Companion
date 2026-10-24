import AuthenticationServices
import CoreLocation
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
    /// What still waits in the last 7 days (shared `syncStatus`); drives the card on top of the list.
    @Published private(set) var syncStatus: SyncStatusView?
    @Published private(set) var syncLines: [String] = []
    @Published private(set) var lastSync: Date?
    @Published private(set) var stravaConnected = false
    /// Set while connecting or disconnecting Strava takes a few seconds (the text to show); nil otherwise.
    @Published private(set) var stravaBusy: String?
    /// Older than the server's minimum build: nothing syncs, only export and delete stay (Android: BuildExpiry).
    @Published private(set) var outdated = false
    @Published private(set) var diaryName = ""
    @Published private(set) var diaryIssue = ""
    @Published private(set) var diarySettings = DiarySettings(autoUpdate: true, roundDurationUp: true, compactDiary: true)
    @Published private(set) var diaryBusy = false
    @Published private(set) var diarySources: [DiarySourceView] = []
    /// The JSON and CSV destinations (the TTB diary is `diaryName` and friends).
    @Published private(set) var folderDestinations: [DestinationView] = []
    @Published private(set) var watchSettings: [WatchSettingsView] = []
    @Published private(set) var liveActivities: [LiveActivityView] = []
    @Published private(set) var crashReports: [CrashReportView] = []
    @Published private(set) var nickname = ""
    @Published private(set) var placeNamesEnabled = true
    @Published private(set) var stravaUpdateMyActivities = true
    @Published private(set) var stravaIncludeOtherDevices = true
    @Published private(set) var reviewNewActivities = true
    @Published private(set) var syncAutomatically = true
    /// The alert shown now; further messages wait in `queuedMessages` (use `post`).
    /// The activity a tapped notification asks to show; the Activities tab opens it and clears this.
    @Published var openActivityId: String?

    @Published var message: String? {
        didSet { if message == nil, !queuedMessages.isEmpty { showNextMessageSoon() } }
    }
    /// A confirmation with a title and a longer text (the Strava deletion confirmation).
    @Published var notice: Notice?

    let core: CompanionCore
    /// The app language ("de"); changes while the app runs ([chooseAppLanguage]), and the root view
    /// is built again for it.
    @Published private(set) var language: String
    private var authSession: ASWebAuthenticationSession?
    /// Identifies the running sign-in, so a cancelled earlier session's completion cannot clear the new one.
    private var authToken = UUID()
    /// A file picker is open (set by the screens): no sync on open while it is.
    var filePickerOpen = false
    private var lastOpenSync: Date?
    private var queuedMessages: [String] = []
    private var storeFailures = 0
    private var exportingBoosts = false

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
            folderFiles: FolderFiles.shared,
            watchMessenger: WatchLinkSpike.shared,
            debug: { line in
                #if DEBUG
                NSLog("[core] %@", line)
                #endif
            }
        )
        super.init()
        stravaConnected = core.stravaConnected()
        refreshDiary()
        refreshWatchSettings()
        refreshWatchCards()
        nickname = core.nickname()
        placeNamesEnabled = core.placeNamesEnabled()
        stravaUpdateMyActivities = core.stravaUpdateMyActivities()
        stravaIncludeOtherDevices = core.stravaIncludeOtherDevices()
        reviewNewActivities = core.reviewNewActivities()
        syncAutomatically = core.syncAutomatically()
    }

    // MARK: - Messages

    /// Shows [text] now, or after the alert on screen is closed; an identical waiting text is dropped.
    func post(_ text: String) {
        if message == nil {
            message = text
        } else if message != text, !queuedMessages.contains(text) {
            queuedMessages.append(text)
        }
    }

    /// A failed call's text, unless the call was only cancelled (pull to refresh, background expiry).
    private func report(_ error: Error) {
        guard !error.isCancellation else { return }
        post(error.localizedDescription)
    }

    private func showNextMessageSoon() {
        // A moment after the alert closed, because SwiftUI drops an alert shown in the same instant.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if message == nil, !queuedMessages.isEmpty { message = queuedMessages.removeFirst() }
        }
    }

    // MARK: - Diary write time

    /// Runs [body] (a diary write) with a few more seconds from iOS if the app goes to the
    /// background meanwhile; when that time ends, the diary access is told to stop before it
    /// starts the next write. A background run sets its own stop flag (`backgroundSync`).
    private func withDiaryTime(_ body: () async -> Void) async {
        let access = FilesDiaryAccess.shared
        if access.inBackgroundRun {
            await body()
            return
        }
        access.resetStop()
        let token = BackgroundTaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: "diary-write") {
            access.requestStop()
            UIApplication.shared.endBackgroundTask(token.id)
            token.id = .invalid
        }
        await body()
        if token.id != .invalid {
            UIApplication.shared.endBackgroundTask(token.id)
            token.id = .invalid
        }
    }

    // MARK: - Activities

    func refresh() async {
        await refreshFolderDestinations()
        do {
            activities = try await core.activities(limit: 300)
            syncStatus = try await core.syncStatus(nowEpochMillis: Int64(Date().timeIntervalSince1970 * 1000))
        } catch {
            report(error)
        }
        showStravaWithdrawalNotice()
        lookupPlaceNames()
        await exportBoostFiles()
    }

    // MARK: - Recording Boost

    static let boostFolder = "recording-boost"

    /// Android's WatchEventRepository.labelBurst: stores the label (the shared core marks the file
    /// for writing again) and rewrites the CSV with it. Poles: 1 with, 0 without, -1 not said.
    func labelBoost(id: String, technique: String, terrain: String, poles: Int32, note: String) async throws {
        _ = try await core.setRecordingBoostLabel(id: id, technique: technique, terrain: terrain, poles: poles, note: note)
        await exportBoostFiles()
    }

    /// Android's RecordingBoostFileExporter: one CSV per burst in the Documents folder (visible in
    /// Files under On My iPhone > Nordic Sports > recording-boost). The shared core stores and
    /// links the bursts and lists those without a file (also after a late link to an activity,
    /// which rewrites the file with the activity id); this writes them and reports the outcome.
    private func exportBoostFiles() async {
        guard !exportingBoosts else { return }
        exportingBoosts = true
        defer { exportingBoosts = false }
        guard let pending = try? await core.recordingBoostsToExport(), !pending.isEmpty else { return }
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd_HHmm"
        for burst in pending {
            do {
                let csv = try await core.recordingBoostCsv(id: burst.id)
                guard !csv.isEmpty, let data = csv.data(using: .utf8) else { throw CocoaError(.fileWriteUnknown) }
                let folder = try FileManager.default
                    .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent(Self.boostFolder, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let name = "\(stamp.string(from: Date(timeIntervalSince1970: TimeInterval(burst.burstId))))_recording-boost-\(burst.burstId).csv"
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                try await core.recordingBoostFileWritten(
                    id: burst.id, burstId: burst.burstId, fileName: name,
                    location: "On My iPhone \u{203A} Nordic Sports \u{203A} \(Self.boostFolder)", sizeBytes: Int64(data.count)
                )
            } catch {
                do {
                    try await core.recordingBoostFileFailed(id: burst.id, burstId: burst.burstId, message: error.localizedDescription)
                } catch {
                    WatchLinkSpike.shared.add("recording boost file failure could not be reported: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Place names

    private var lookingUpPlaces = false
    private let geocoder = CLGeocoder()
    /// Activities already asked about in this app run, so one without an address is not asked again.
    private var askedPlaceIds = Set<String>()

    /// As Android's LocationDetectionWorker: names the newest activities that have start
    /// coordinates but no place yet, with Apple's geocoder (the shared core lists them and stores
    /// the answer; nothing runs while the switch is off). One at a time, because the geocoder
    /// throttles; the first failure ends the pass, the next refresh tries again.
    private func lookupPlaceNames() {
        guard !lookingUpPlaces, core.placeNamesEnabled() else { return }
        lookingUpPlaces = true
        Task {
            defer { lookingUpPlaces = false }
            guard let candidates = try? await core.placeNameCandidates(limit: 10), !candidates.isEmpty else { return }
            var stored = false
            for candidate in candidates where !askedPlaceIds.contains(candidate.id) {
                let location = CLLocation(latitude: candidate.startLat, longitude: candidate.startLon)
                guard let marks = try? await geocoder.reverseGeocodeLocation(location) else { break }
                askedPlaceIds.insert(candidate.id)
                guard let mark = marks.first else { continue }
                guard let name = PlaceNameLookupKt.formatPlaceName(
                    locality: mark.locality, subAdminArea: mark.subAdministrativeArea,
                    adminArea: mark.administrativeArea, country: mark.country
                ) else { continue }
                try? await core.storePlaceName(activityId: candidate.id, name: name)
                stored = true
            }
            if stored { await refreshAfterPlaceNames() }
        }
    }

    private func refreshAfterPlaceNames() async {
        if let list = try? await core.activities(limit: 300) { activities = list }
    }

    func setPlaceNamesEnabled(_ on: Bool) {
        core.setPlaceNamesEnabled(on: on)
        placeNamesEnabled = core.placeNamesEnabled()
        if on { lookupPlaceNames() }
    }

    /// The two Strava switches (as Android's Strava section, both on by default).
    func setStravaUpdateMyActivities(_ on: Bool) {
        core.setStravaUpdateMyActivities(on: on)
        stravaUpdateMyActivities = core.stravaUpdateMyActivities()
    }

    func setStravaIncludeOtherDevices(_ on: Bool) {
        core.setStravaIncludeOtherDevices(on: on)
        stravaIncludeOtherDevices = core.stravaIncludeOtherDevices()
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
        guard !outdated else { return 0 }
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            WatchLinkSpike.shared.add("watch message could not be read as JSON")
            return 0
        }
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let result = try await core.receiveWatchMessage(json: json, variant: variant, nowEpochMillis: now)
            storeFailures = 0
            WatchLinkSpike.shared.add("activity from \(variant): \(result.summary)")
            // A burst arrives in dozens of chunks: only the last one (stored) changes anything.
            if result.summary == "Recording Boost chunk" { return 0 }
            await refresh()
            // The saved recording's "running on the watch" card was removed in the core.
            refreshWatchCards()
            if !result.activityId.isEmpty {
                notifyNewActivity(result)
                // As Android in automated mode: forward on arrival (the diary now; Strava's
                // copy follows by webhook at the next sync).
                if core.syncAutomatically(), stravaConnected || diaryReceives {
                    Task { await sync() }
                }
            }
            return result.receiptStartTime
        } catch {
            if error.isCancellation { return 0 }
            storeFailures += 1
            let started = (dict["startTime"] as? NSNumber)?.int64Value ?? 0
            WatchLinkSpike.shared.add(
                "activity (start time \(started)) could not be stored, \(storeFailures) in a row: \(error.localizedDescription)"
            )
            // The watch keeps what is not confirmed and sends it again; after three failures in a
            // row the athlete is told (and again after every third one).
            if storeFailures % 3 == 0 {
                post(String(format: L10n.get("ios_store_failures"), storeFailures, error.localizedDescription))
            }
            return 0
        }
    }

    // MARK: - Sync

    /// Asks the server for the oldest supported build (kept when it cannot be reached).
    private func checkOutdated() async {
        let build = Int32(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? Int32.max
        if let answer = try? await core.buildOutdated(build: build) { outdated = answer.boolValue }
    }

    // MARK: - Server token (Android: About > Tester access; design/server-credentials.md)

    /// True when this install holds a server token (pasted by a tester; later from App Attest).
    var hasServerToken: Bool { !core.serverTokenKind.isEmpty }

    /// Stores a pasted tester token; false when it is not a well-formed token.
    func saveServerToken(_ raw: String) -> Bool { core.saveServerToken(raw: raw) }

    func clearServerToken() { core.clearServerToken() }

    /// Sends the finished days of usage counts (Strava calls per kind, no athlete data); does
    /// nothing without a server token. Safe to call often.
    private func reportUsage() async {
        try? await core.reportUsage(appVersion: Format.serverVersion, osVersion: UIDevice.current.systemVersion)
    }

    /// Like Android's onResume: a quiet sync whenever the app comes to the foreground
    /// (automated sync mode only).
    func syncOnOpen() async {
        // Not in the middle of a sign-in or the file picker, and at most once a minute.
        guard authSession == nil, !filePickerOpen else { return }
        if let last = lastOpenSync, Date().timeIntervalSince(last) < 60 { return }
        lastOpenSync = Date()
        await checkOutdated()
        await reportUsage()
        guard !outdated else { return }
        await purgeExpiredStravaData()
        await refresh()
        guard core.syncAutomatically(), stravaConnected || diaryReceives, !syncing else { return }
        await sync()
    }

    /// A background run (BGTaskScheduler; Android: the daily ActivitySyncWorker): the same
    /// sync as on opening, in automated mode only. Returns a line for the Diagnostics log.
    func backgroundSync() async -> BackgroundOutcome {
        let access = FilesDiaryAccess.shared
        access.beginBackgroundRun()
        defer { access.endBackgroundRun() }
        guard !outdated else { return BackgroundOutcome(text: "this build is no longer supported, nothing run", success: true) }
        let stopped = BackgroundOutcome(text: "stopped before the diary was written (background time over)", success: false)
        let purged = await purgeExpiredStravaData()
        if purged > 0 { WatchLinkSpike.shared.add("bg: Strava data removed from \(purged) activities") }
        guard core.syncAutomatically() else { return BackgroundOutcome(text: "manual sync mode, nothing run", success: true) }
        await refreshFolderDestinations()
        guard stravaConnected || diaryReceives else {
            return BackgroundOutcome(text: "neither Strava nor a diary connected", success: true)
        }
        guard !syncing else { return BackgroundOutcome(text: "a sync is already running", success: true) }
        // No diary write is started once the stop flag is set (expiry handler, cancellation).
        if Task.isCancelled || access.stopRequested { return stopped }
        let outcome = await withTaskCancellationHandler {
            await sync()
        } onCancel: {
            access.requestStop()
        }
        switch outcome {
        case .ok(let lines): return BackgroundOutcome(text: "synced (\(lines) lines)", success: true)
        case .failed(let text): return BackgroundOutcome(text: "sync failed: \(text)", success: false)
        case .cancelled: return stopped
        case .skipped: return BackgroundOutcome(text: "a sync is already running", success: true)
        }
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
        ) { error in
            if let error { WatchLinkSpike.shared.add("notification not shown: \(error.localizedDescription)") }
        }
    }

    /// Runs the shared sync; the result tells a background run whether it really worked.
    @discardableResult
    func sync() async -> SyncOutcome {
        guard !syncing, !outdated else { return .skipped }
        syncing = true
        defer { syncing = false }
        var outcome = SyncOutcome.ok(lines: 0)
        await withDiaryTime {
            do {
                let report = try await core.syncNow()
                syncLines = report.lines
                lastSync = Date()
                outcome = .ok(lines: report.lines.count)
            } catch {
                if error.isCancellation {
                    outcome = .cancelled
                } else {
                    outcome = .failed(error.localizedDescription)
                    post(error.localizedDescription)
                }
            }
            refreshDiary()
            await refresh()
        }
        return outcome
    }

    func backfill(days: Int32) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        await withDiaryTime {
            do {
                let report = try await core.backfill(days: days)
                syncLines = report.lines
                lastSync = Date()
            } catch {
                report(error)
            }
            refreshDiary()
            await refresh()
        }
    }

    // MARK: - Strava

    var stravaConfigured: Bool { core.stravaConfigured }

    /// Cancels a sign-in sheet that is still open and returns the token of the next one.
    private func beginAuth() -> UUID {
        authSession?.cancel()
        authSession = nil
        authToken = UUID()
        return authToken
    }

    /// Releases the session, unless a newer sign-in has replaced it in the meantime.
    private func endAuth(_ token: UUID) {
        if authToken == token { authSession = nil }
    }

    func connectStrava() {
        guard let url = URL(string: core.stravaAuthorizeUrl()) else { return }
        let token = beginAuth()
        let session = ASWebAuthenticationSession(
            url: url,
            callback: .https(host: Self.stravaCallbackHost, path: Self.stravaCallbackPath)
        ) { callbackURL, error in
            Task { @MainActor in await self.finishStravaSignIn(callbackURL, error, token) }
        }
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            endAuth(token)
            post(L10n.get("ios_sign_in_not_started"))
        }
    }

    private func finishStravaSignIn(_ callbackURL: URL?, _ error: Error?, _ token: UUID) async {
        endAuth(token)
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            post(String(format: L10n.get("main_toast_strava_connect_failed"), error.localizedDescription))
            return
        }
        guard let callbackURL else { return }
        stravaBusy = L10n.get("strava_connecting")
        do {
            let reason = try await core.completeStravaSignIn(callbackUrl: callbackURL.absoluteString)
            stravaBusy = nil  // the backfill below has its own progress display
            if reason.isEmpty {
                // An empty reason also means "cancelled": only a stored sign-in counts as connected.
                stravaConnected = core.stravaConnected()
                guard stravaConnected else { return }
                post(L10n.get("main_toast_strava_connected"))
                await sync()
            } else {
                post(String(format: L10n.get("main_toast_strava_connect_failed"), reason))
            }
        } catch {
            stravaBusy = nil
            if error.isCancellation { return }
            post(String(format: L10n.get("main_toast_strava_connect_failed"), error.localizedDescription))
        }
    }

    /// As Android: revokes the access at Strava, deletes every Strava data the app holds, then
    /// shows the deletion confirmation (the same text is in the app log).
    func disconnectStrava() async {
        guard stravaBusy == nil else { return }
        stravaBusy = L10n.get("strava_disconnecting")
        defer { stravaBusy = nil }
        do {
            let result = try await core.disconnectStrava()
            notice = Notice(title: result.title, text: result.text)
        } catch {
            report(error)
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

    /// Something receives activities: the TTB diary or a JSON/CSV destination that is not paused.
    var diaryReceives: Bool { diaryConnected || folderDestinations.contains { $0.enabled } }

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
            post(problem)
            return
        }
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            let problem = try await core.connectDiary(fileName: url.lastPathComponent)
            if problem.isEmpty {
                FilesDiaryAccess.shared.confirmPick()
                refreshDiary()
                post(String(format: L10n.get("connect_diary_connected_to"), url.lastPathComponent))
            } else {
                FilesDiaryAccess.shared.restorePrevious()
                post(problem)
            }
        } catch {
            // A thrown error must not leave the unchecked file as the diary.
            FilesDiaryAccess.shared.restorePrevious()
            report(error)
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

    /// Runs after the next successful cloud sign-in (Connect before signing in: the link is
    /// connected once the sheet closes).
    private var afterCloudSignIn: (() async -> Void)?

    /// Signs in to OneDrive, Dropbox or Google Drive in the system sign-in sheet (PKCE);
    /// [then] runs once the sign-in succeeded.
    func signInCloud(_ source: String, then: (() async -> Void)? = nil) {
        afterCloudSignIn = then
        let scheme = core.cloudCallbackScheme(provider: source)
        guard let url = URL(string: core.cloudSignInUrl(provider: source)), !scheme.isEmpty else {
            post(L10n.get("ios_cloud_not_configured"))
            return
        }
        let token = beginAuth()
        let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callbackURL, error in
            Task { @MainActor in await self.finishCloudSignIn(callbackURL, error, token) }
        }
        session.presentationContextProvider = self
        authSession = session
        if !session.start() {
            endAuth(token)
            post(L10n.get("ios_sign_in_not_started"))
        }
    }

    private func finishCloudSignIn(_ callbackURL: URL?, _ error: Error?, _ token: UUID) async {
        endAuth(token)
        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            post(error.localizedDescription)
            return
        }
        guard let callbackURL else { return }
        let next = afterCloudSignIn
        afterCloudSignIn = nil
        do {
            let reason = try await core.completeCloudSignIn(callbackUrl: callbackURL.absoluteString)
            refreshDiary()
            if !reason.isEmpty {
                post(reason)
            } else if let next {
                await next()
            }
        } catch {
            report(error)
            refreshDiary()
        }
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
            report(error)
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
            report(error)
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
        await withDiaryTime {
            do {
                let report = try await core.writeDiary(days: days)
                syncLines = report.lines
                lastSync = Date()
            } catch {
                report(error)
            }
            refreshDiary()
            await refresh()
        }
    }

    /// TEMPORARY (remove a few versions after 0.9.93): rewrites the entries written in the last
    /// [days] days by the current rules; the sync log shows what happened.
    func compactDiary(days: Int32) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        await withDiaryTime {
            do {
                let report = try await core.compactDiary(days: days)
                syncLines = report.lines
                lastSync = Date()
            } catch {
                report(error)
            }
            refreshDiary()
            await refresh()
        }
    }

    /// "Push to diary" for one activity; the sync log shows what was written.
    func pushToDiary(_ activityId: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        await withDiaryTime {
            do {
                let problem = try await core.pushToDiary(activityId: activityId)
                if !problem.isEmpty { post(problem) }
            } catch {
                report(error)
            }
            refreshDiary()
            await refresh()
        }
    }

    // MARK: - JSON and CSV destinations

    func refreshFolderDestinations() async {
        do {
            folderDestinations = try await core.folderDestinations()
        } catch {
            report(error)
        }
    }

    /// A folder in a signed-in cloud: [link] is a sharing link (a Dropbox path works too).
    func pickCloudFolder(provider: String, link: String) async -> FolderPickView {
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            return try await core.pickCloudFolder(provider: provider, location: link)
        } catch {
            return FolderPickView(ok: false, message: error.localizedDescription, folderName: "")
        }
    }

    /// A folder picked in the Files app.
    func pickDeviceFolder(_ url: URL) async -> FolderPickView {
        diaryBusy = true
        defer { diaryBusy = false }
        guard let bookmark = FolderFiles.shared.bookmark(for: url) else {
            return FolderPickView(ok: false, message: FolderFiles.shared.failure(), folderName: url.lastPathComponent)
        }
        do {
            return try await core.pickDeviceFolder(bookmark: bookmark, name: url.lastPathComponent)
        } catch {
            return FolderPickView(ok: false, message: error.localizedDescription, folderName: url.lastPathComponent)
        }
    }

    /// Saves the folder picked last as a destination and writes to it at once.
    func addFolderDestination(format: String, scope: String, backfill: String, position: Bool, monthFolders: Bool, dialect: String) async -> Bool {
        diaryBusy = true
        defer { diaryBusy = false }
        do {
            let problem = try await core.addFolderDestination(
                format: format, scope: scope, backfill: backfill, includeStartPosition: position,
                subfolderPerMonth: monthFolders, dialect: dialect
            )
            if !problem.isEmpty {
                post(problem)
                return false
            }
            post(L10n.get(format == "CSV_MONTHLY" ? "main_toast_csv_added" : "main_toast_json_added"))
            refreshDiary()
            await refresh()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func updateFolderDestination(
        _ id: String, autoWrite: Bool, scope: String, position: Bool, monthFolders: Bool, removeOnDelete: Bool, dialect: String
    ) async {
        do {
            try await core.updateFolderDestination(
                id: id, autoWrite: autoWrite, scope: scope, includeStartPosition: position,
                subfolderPerMonth: monthFolders, removeOnDelete: removeOnDelete, dialect: dialect
            )
        } catch {
            report(error)
        }
        await refreshFolderDestinations()
    }

    func setFolderDestinationEnabled(_ id: String, enabled: Bool) async {
        do { try await core.setFolderDestinationEnabled(id: id, enabled: enabled) } catch { report(error) }
        await refreshFolderDestinations()
    }

    func removeFolderDestination(_ id: String) async {
        do {
            try await core.removeFolderDestination(id: id)
            post(L10n.get("main_toast_destination_removed"))
        } catch {
            report(error)
        }
        await refreshFolderDestinations()
    }

    /// "Write now" on one destination.
    func writeFolderDestinationNow(_ id: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.writeFolderDestinationNow(id: id)
            syncLines = report.lines
        } catch {
            self.report(error)
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
        // The language exists on both devices: changing the watch's offers the same for the app.
        if key == "Language" {
            let tag = core.languageTagOfWatchValue(value: value)
            if !tag.isEmpty, tag != AppLanguage.current { companionLanguageOffer = tag }
        }
    }

    /// The app's language tag offered after the watch's language changed ("Companion language too?"), or nil.
    @Published var companionLanguageOffer: String?

    /// The language's own name ("Rumantsch").
    func languageNativeName(_ tag: String) -> String { core.languageNativeName(languageTag: tag) }

    /// The watches that could take the app language [tag] and do not have it yet.
    func watchesForLanguage(_ tag: String) -> [WatchLanguageTarget] { core.watchesForLanguage(languageTag: tag) }

    func setWatchLanguage(_ deviceId: Int64, _ tag: String) {
        core.setWatchLanguage(deviceId: deviceId, languageTag: tag)
        refreshWatchSettings()
    }

    /// Takes [tag] as the app language ("" = the phone's) and applies it at once: the Swift texts,
    /// the shared core's texts and, through [language], the whole screen (feedback 2026-10-23:
    /// "opened again" meant killing the app, so the change looked lost).
    func chooseAppLanguage(_ tag: String) {
        AppLanguage.chosen = tag
        let effective = AppLanguage.current
        guard effective != language else { return }
        L10n.reload()
        if !core.switchLanguage(textsJson: Self.textTable(effective), language: effective) {
            WatchLinkSpike.shared.add("texts-\(effective).json missing: shared texts stay in \(language)")
        }
        language = effective
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

    /// "Pace → Speed" ([toSpeed]) or "Speed → Pace" for every sport's data fields.
    func switchWatchPaceSpeed(deviceId: Int64, toSpeed: Bool) {
        core.switchWatchPaceSpeed(deviceId: deviceId, toSpeed: toSpeed)
        refreshWatchSettings()
    }

    /// The data field sets, plans and routines of [deviceId] that have something to share.
    func shareableWatchSets(deviceId: Int64) -> [ShareSetView] {
        core.shareableWatchSets(deviceId: deviceId)
    }

    /// The message to share for the sets [ids]: a sentence, then the settings as JSON.
    func watchShareText(deviceId: Int64, ids: [Int32]) -> String {
        core.watchShareText(deviceId: deviceId, ids: ids.map { KotlinInt(value: $0) })
    }

    /// The sets in a pasted message, or nil when it holds no Nordic Sports settings.
    func readWatchImport(deviceId: Int64, text: String) -> [ImportSetView]? {
        core.readWatchImport(deviceId: deviceId, text: text)
    }

    /// Imports the sets of [text] into [targets] (one per set, "" to leave it out).
    func applyWatchImport(deviceId: Int64, text: String, targets: [String]) {
        core.applyWatchImport(deviceId: deviceId, text: text, targets: targets)
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
        // A discarded recording's card goes a few seconds after the watch's message (as Android).
        discardedCardTimer?.cancel()
        let wait = core.discardedCardExpiresInMillis()
        guard wait >= 0 else { return }
        discardedCardTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait + 100) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshWatchCards()
        }
    }

    private var discardedCardTimer: Task<Void, Never>?

    func dismissCrashReport(_ id: String) {
        core.dismissCrashReport(id: id)
        refreshWatchCards()
    }

    /// Sends crash report [id] with the athlete's [note] and the phone details; "sent",
    /// "tooMany" or "failed". Only this tap sends it.
    func sendCrashReport(_ id: String, note: String) async -> String {
        var details = Self.deviceDetails()
        details["companion"] = Format.appVersion
        details["language"] = language
        let result = (try? await core.sendCrashReport(id: id, note: note, appVersion: Format.serverVersion, details: details)) ?? "failed"
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
        do { return try await core.feedbackWatches() } catch {
            WatchLinkSpike.shared.add("watch list for the feedback form not loaded: \(error.localizedDescription)")
            return []
        }
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
            report(error)
            return []
        }
    }

    /// Throws when the history cannot be read; the screen says so instead of showing an empty list.
    func activityLog(_ activityId: String) async throws -> [LogLine] {
        try await core.activityLog(activityId: activityId)
    }

    /// "Download my data": the whole store as JSON, saved with "Save to Files" (DownloadMyDataButton).
    func exportJson() async -> String? {
        do {
            return try await core.exportJson()
        } catch {
            post(String(format: L10n.get("main_toast_export_failed"), error.localizedDescription))
            return nil
        }
    }

    /// A log file for the share sheet (shared LogExport, the same text as Android's), written when the
    /// athlete shares. Earlier log files are removed first, so the temporary folder holds one at most.
    func logFile(kinds: [NordicSportsShared.LogKind], activityId: String?) async throws -> URL {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let text = try await core.logExportText(kinds: kinds, activityId: activityId,
                                                header: "Nordic Sports Companion \(version) (iOS)")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(core.logExportFileName(kinds: kinds))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// "Delete my data", as Android's: the shared core revokes Strava, forgets the diary and
    /// the watches' settings and empties the database; here the diary file bookmark, its
    /// backups, exports and the diagnostics log go too. The diary workbook itself stays.
    /// PRIVACY-SYNC: what "Delete my data" removes on iOS. Changing this? Re-check the
    /// Companion's design/privacy-notice-sync.md.
    func deleteAllData() async {
        var failed: [String] = []
        do {
            failed = try await core.deleteAllData().map { "\($0)" }
        } catch {
            failed = [error.localizedDescription]
        }
        FilesDiaryAccess.shared.forget()
        let files = FileManager.default
        if let documents = files.urls(for: .documentDirectory, in: .userDomainMask).first {
            let backups = documents.appendingPathComponent(FilesDiaryAccess.backupFolder, isDirectory: true)
            if files.fileExists(atPath: backups.path) {
                do { try files.removeItem(at: backups) } catch { failed.append("diary backups") }
            }
        }
        do {
            for name in try files.contentsOfDirectory(atPath: files.temporaryDirectory.path) where name.hasSuffix(".json") {
                try files.removeItem(at: files.temporaryDirectory.appendingPathComponent(name))
            }
        } catch {
            failed.append("exports")
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
        post(failed.isEmpty
            ? L10n.get("main_toast_all_data_deleted")
            : String(format: L10n.get("main_toast_data_delete_partly"), failed.joined(separator: ", ")))
    }

    /// Minutes typed by the athlete as seconds for the core, capped so a huge entry cannot overflow.
    private static func seconds(_ minutes: Int) -> Int32 {
        Int32(clamping: min(max(0, minutes), 100_000) * 60)
    }

    /// The newest watch named in an activity, for the details of a report about the Companion; "" when none.
    func latestWatchName() async -> String {
        (try? await core.latestWatchName()) ?? ""
    }

    /// The technical details a feedback report carries, in the order the form lists them (all of
    /// them, so the athlete sees exactly what is sent), as Android's FeedbackScreen. [aboutWatch]:
    /// the report is about the watch app; then [watch] (picked) or [otherWatch] (typed model)
    /// describes the watch, else [latestWatch] (the newest one seen) is added as "Last watch".
    func feedbackDetailLines(aboutWatch: Bool, watch: FeedbackWatchView?, otherWatch: String, latestWatch: String) -> [FeedbackDetailLine] {
        let device = Self.deviceDetails()
        var lines = [
            FeedbackDetailLine(key: "companion", label: L10n.get("feedback_detail_app"), value: Format.appVersion),
            FeedbackDetailLine(key: "phone", label: L10n.get("feedback_detail_phone"), value: device["phone"] ?? ""),
            FeedbackDetailLine(key: "ios", label: "iOS", value: device["ios"] ?? ""),
            FeedbackDetailLine(key: "language", label: L10n.get("feedback_detail_language"), value: language),
        ]
        if !aboutWatch {
            if !latestWatch.isEmpty {
                lines.append(FeedbackDetailLine(key: "watch", label: L10n.get("feedback_detail_watch"), value: latestWatch))
            }
        } else if let watch {
            let labels = [("watch", "feedback_detail_watch_model"), ("watch_app", "feedback_detail_watch_app"),
                          ("watch_channel", "feedback_detail_watch_channel"), ("watch_fw", "feedback_detail_watch_fw"),
                          ("watch_ciq", "feedback_detail_watch_ciq")]
            for (key, label) in labels {
                guard let value = watch.details[key], !value.isEmpty else { continue }
                let shown = key == "watch_channel" ? L10n.get("feedback_channel_\(value)") : value
                lines.append(FeedbackDetailLine(key: key, label: L10n.get(label), value: shown))
            }
        } else if !otherWatch.isEmpty {
            lines.append(FeedbackDetailLine(key: "watch", label: L10n.get("feedback_detail_watch_model"), value: otherWatch))
        }
        return lines
    }

    /// "sent", "tooMany" or "failed". [details]: the lines the form showed, or empty when the
    /// athlete switched them off; [extraDetails] (the wording proposal) is always sent.
    func sendFeedback(
        category: String, app: String, text: String, email: String, details: [FeedbackDetailLine],
        includeNickname: Bool = false, extraDetails: [String: String] = [:]
    ) async -> String {
        var sent: [String: String] = [:]
        for line in details { sent[line.key] = line.value }
        if includeNickname, !nickname.isEmpty { sent["nickname"] = nickname }
        sent.merge(extraDetails) { _, new in new }
        do {
            return try await core.sendFeedback(
                category: category, app: app, message: text, contactEmail: email,
                appVersion: Format.serverVersion, details: sent
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
        comment: String, minutes: Int, kilometers: Double, stravaDescriptionMode: Int32
    ) async -> Bool {
        do {
            let saved = try await core.saveActivity(
                activityId: activityId, title: title, trainingType: trainingType,
                rpe: Int32(rpe), feeling: Int32(feeling), diaryComment: comment,
                overrideElapsedSec: Self.seconds(minutes), overrideDistanceM: Float(max(0, kilometers) * 1000),
                stravaDescriptionMode: stravaDescriptionMode
            )
            guard saved.boolValue else { return false }
            post(L10n.get("main_toast_activity_updated"))
            await afterEdit()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Whether new activities are sent on their own (the sync mode); the detail then offers
    /// "Save & send" instead of "Save" + "Send now".
    var automaticSync: Bool { core.syncAutomatically() }

    /// Whether anything can receive an activity: Strava or a diary.
    var sendsSomewhere: Bool { stravaConnected || diaryReceives }

    /// "Send now": the sync links the activity to Strava and sets its title, then the diary
    /// entry is written unless the sync already did.
    func sendNow(_ activityId: String) async {
        if stravaConnected { await sync() }
        await refresh()
        if diaryReceives {
            if diaryConnected, folderDestinations.allSatisfy({ !$0.enabled }),
               let item = activities.first(where: { $0.id == activityId }), item.diaryWritten, !item.diaryOutdated {
                return
            }
            await pushToDiary(activityId)
        }
    }

    /// "Create on Strava": links to the same session there, or creates it.
    func createOnStrava(_ activityId: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            let report = try await core.createOnStrava(activityId: activityId)
            syncLines = report.lines
        } catch {
            self.report(error)
        }
        await refresh()
    }

    func skipReview(_ activityId: String) async {
        do {
            try await core.skipReview(activityId: activityId)
        } catch {
            report(error)
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
                elapsedSec: Self.seconds(minutes)
            )
            post(L10n.get("main_toast_activity_saved"))
            await refresh()
            Task { await syncNewActivity(id) }
            return id
        } catch {
            report(error)
            return nil
        }
    }

    /// As Android, right after adding by hand (automated mode): link it to the same session
    /// on Strava or create it there, then write it to the diary.
    private func syncNewActivity(_ id: String) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        await withDiaryTime {
            do {
                let result = try await core.syncNewActivity(activityId: id)
                if !result.lines.isEmpty {
                    syncLines = result.lines
                    lastSync = Date()
                }
            } catch {
                report(error)
            }
            refreshDiary()
            await refresh()
        }
    }

    /// Deletes an activity (the Strava activity stays); returns what to tell the athlete.
    func deleteActivity(_ activityId: String) async -> Bool {
        do {
            guard let result = try await core.deleteActivity(activityId: activityId) else {
                post(L10n.get("main_toast_activity_delete_failed"))
                return false
            }
            if let failure = result.diaryRemovalMessage, result.diaryRemovalAttempted, !result.diaryEntryRemoved {
                post(String(format: L10n.get("main_toast_activity_deleted_diary_removal_failed"), failure))
            } else if result.diaryEntryRemoved {
                post(L10n.get(result.stillOnStrava
                    ? "main_toast_activity_deleted_diary_removed_still_on_strava" : "main_toast_activity_deleted_diary_removed"))
            } else {
                post(L10n.get(result.stillOnStrava ? "main_toast_activity_deleted_still_on_strava" : "main_toast_activity_deleted"))
            }
            await refresh()
            return true
        } catch {
            post(L10n.get("main_toast_activity_delete_failed"))
            return false
        }
    }

    // MARK: - Texts

    /// The phone's language among the Companion's nine, English otherwise ("no", older
    /// iOS's Norwegian, counts as Bokmål).
    private static func preferredLanguage() -> String { AppLanguage.current }

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
/// The language of the app: the one chosen in Settings (Romansh and Swiss German are not iOS
/// system languages, so the system cannot offer them), else the first system language the app has.
/// A change applies at once (`Companion.chooseAppLanguage`).
enum AppLanguage {
    static let supported = ["en", "de", "fr", "it", "rm", "gsw", "nb", "fi", "sv"]
    private static let key = "appLanguage"

    /// The language chosen in the app, "" for the system's.
    static var chosen: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// The first of the iPhone's languages the app has, else English.
    static var system: String {
        for tag in Locale.preferredLanguages {
            var code = tag.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if code == "no" { code = "nb" }
            if supported.contains(code) { return code }
        }
        return "en"
    }

    static var current: String { supported.contains(chosen) ? chosen : system }
}

enum L10n {
    private static var language = AppLanguage.current

    /// The app's texts in [language] (its `.lproj`); the main bundle when there is none.
    private static var bundle: Bundle = bundle(for: language)

    private static func bundle(for language: String) -> Bundle {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }

    /// Reads the texts again after the app language changed (`Companion.chooseAppLanguage`).
    static func reload() {
        language = AppLanguage.current
        bundle = bundle(for: language)
    }

    /// English, for names [bundle] lacks: texts marked translatable="false" ("View on Strava")
    /// and ones not yet translated exist only there, as on Android's `values/`.
    private static let english: Bundle =
        Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main

    private static func text(_ name: String) -> String {
        let missing = "\u{1}"
        let word = bundle.localizedString(forKey: name, value: missing, table: nil)
        return word == missing ? english.localizedString(forKey: name, value: nil, table: nil) : word
    }

    static func get(_ name: String) -> String {
        text(name)
    }

    /// A `<plurals>` text for [count] (the catalog's plural variations).
    static func plural(_ name: String, _ count: Int) -> String {
        String(format: text(name), locale: Locale(identifier: language), count)
    }
}

/// A title and a text to confirm something that happened (an alert with OK).
/// One technical detail of a feedback report: the server's [key], the form's [label], the [value].
struct FeedbackDetailLine: Hashable {
    let key: String
    let label: String
    let value: String
}

struct Notice {
    let title: String
    let text: String
    /// Runs when the athlete closes the alert.
    var onDismiss: (() -> Void)? = nil
}

/// What one sync run came to, for the background task and its Diagnostics line.
enum SyncOutcome {
    case ok(lines: Int)
    case failed(String)
    case cancelled
    /// Not started: another run is active or the build is outdated.
    case skipped
}

/// The Diagnostics line of a background run and whether it counts as success for iOS.
struct BackgroundOutcome {
    let text: String
    let success: Bool
}

/// Holds the identifier of a UIKit background task so its expiry handler can end it.
final class BackgroundTaskToken: @unchecked Sendable {
    var id = UIBackgroundTaskIdentifier.invalid
}

extension Error {
    /// A cancelled Swift task, a cancelled request, or the shared Kotlin code's
    /// CancellationException (it arrives as an NSError carrying the Kotlin exception).
    var isCancellation: Bool {
        if self is CancellationError { return true }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        if let kotlin = ns.userInfo["KotlinException"] {
            return String(describing: type(of: kotlin)).contains("Cancellation")
        }
        return false
    }
}
