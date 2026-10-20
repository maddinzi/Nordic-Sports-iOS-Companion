# iOS Companion code review, 2026-10-20 (exception handling and failure paths)

Scope: `App/*.swift`, `spikes/*/*.swift` (compiled into the app via `project.yml`), `project.yml`,
`.github/workflows/ios-testflight.yml`, plus the Kotlin signatures in the Companion's `shared` module
that Swift calls (`CompanionCore.kt`, `IosCompanion.kt`, `KeychainSecretStore.kt`, `FilesDiaryWorkbook.kt`).
Read-only review; nothing was built or run. No `.env` or `Secrets.xcconfig` value was read. Every item
below is something I read in the code; where a consequence depends on iOS or Kotlin runtime behaviour
I did not run, the item says so.

Grep result: no `try!`, no `as!`, no `fatalError`, no force unwrap of external data in `App/` or `spikes/`.

## Kotlin boundary: checked

All public `suspend fun` in `CompanionCore` carry `@Throws(Exception::class)` (checked with a script over
`CompanionCore.kt`; none missing). The Swift side calls every one of them with `try await`. The
non-suspend Kotlin functions Swift calls (`watchMessage`, `changeWatchSetting`, `setNickname`,
`disconnectDiary`, `signOutCloud`, `cloudSignInUrl`, `diaryConnected`, `stravaConnected`, ...) are NOT
`@Throws`: an exception in them terminates the app, and Swift cannot catch it. Only findings 3 and 6 below
are known concrete routes into that.

---

## HIGH

### 1. "Delete my data" reports success whatever happened, and leaves files behind
`App/Companion.swift:669-695`, `CompanionCore.kt:1581-1600`, `spikes/diary-file/DiaryFileSpike.swift:18`.

- Line 672-674 stores `core.deleteAllData()`'s error in `message`, but line 694 then unconditionally sets
  `message = "All data on this iPhone deleted; Strava and the diary disconnected."`, which overwrites it.
  The athlete is told everything is gone when the core threw.
- Even when the core does not throw, each of its steps is wrapped in `step { ... } catch (e: Exception) { debugLog }`
  (CompanionCore.kt:1582-1590). A failed Strava revoke, token clear or database wipe is only `NSLog`ged;
  `deleteAllData()` returns Unit, so Swift cannot know.
- Swift's own cleanup uses `try?` (lines 678, 680-681); a failed removal is invisible.
- Not removed at all: `Documents/recording-boost/*.csv` (written by `exportBoostFiles`, lines 96-125, raw
  watch sensor bursts), the Diagnostics spike bookmark `spike.diary.bookmark` and `DiaryFileSpike.copy`
  (in-memory copy of the diary workbook), `spike.devices` (saved watches), the `onboardingDone` flag, pending
  notifications. The `PRIVACY-SYNC` comment (line 667) and the privacy notice should list exactly what is removed.
- The message is hard-coded English.

Fix: make the core return a result (list of failed steps) instead of swallowing; in Swift, build the final
message from the core result plus the file removals (`do/catch`, not `try?`), show a failure text (with the
failed step names) instead of the success text, and only then clear UI state. Also delete `recording-boost`,
`spike.diary.bookmark`, `spike.devices` and reset `DiaryFileSpike.shared`. Use `L10n.get` for the text.

### 2. Integer overflow traps (crash from ordinary input)
`App/Companion.swift:746` and `:785`; inputs `MoreScreens.swift:859-861`, `:975-977`, `:839`, `:1003`.

`Int32(minutes * 60)` (add) and `Int32(max(0, minutes) * 60)` (edit) trap when `minutes >= 35,791,395`
(8 digits). The fields are a free-text `numberPad` (`otherMinutes`, `minutes`), parsed with `Int(...)`, which
accepts up to 19 digits. Typing 99999999 and tapping Save crashes the app. `duration <= 0` is the only
check (`MoreScreens.swift:886`). Same trap pattern, from watch-supplied data: `Format.duration(Int32(running))`
in `Screens.swift:181` (`running = now - live.startEpochSec`; traps if `startEpochSec` is below about -0.4e9,
i.e. a corrupt `activityStart` message).

Fix: clamp before converting, e.g. `Int32(clamping: min(minutes, 24 * 60) * 60)` (a manual activity longer
than a day is never right), or validate in the sheet (`duration` in 1...1440) and disable Save otherwise;
use `Int32(clamping:)` in `Screens.swift:181`.

### 3. The Keychain write is delete-then-add, and a Keychain read failure crashes the launch
`KeychainSecretStore.kt` (`write`, `readItem`, `delete`), reached from `Companion.swift:55`.

- `write()` calls `delete()` first and `SecItemAdd` after. If `SecItemAdd` fails, `check(...)` throws and the
  tokens are already gone. Strava rotates refresh tokens, so a failed write after a refresh loses both the
  old and the new token: the athlete is silently logged out and has to reconnect. (`edit` sets `cache` only
  after `write`, so memory is not updated either.) Same for the cloud stores.
- `StravaTokenStore` computes `MutableStateFlow(hasTokens())` in its initialiser (StravaTokenStore.kt:43,148),
  i.e. a Keychain read during `IosCompanion.create`, which runs inside `Companion.init` (Companion.swift:55)
  and `core.stravaConnected()` (line 70). `readItem` does `check(status == errSecSuccess)` for any status other
  than not-found. That is a non-`@Throws` path from the singleton's initialiser: any Keychain error status
  (for example a launch while the data is not yet available) is an `IllegalStateException` that Swift cannot
  catch, and the app dies at launch, on every launch, until the Keychain answers. I did not run it; whether
  iOS returns such a status in practice depends on the device state. Also, `IosCompanion.create` has no
  fallback if Room or the Application Support path fails (`requireNotNull`).

Fix: in Kotlin, update with `SecItemUpdate` (add only when not found) so the old item stays on failure;
make `read()` return an empty store plus a flag/log on a non-fatal status instead of `check`, or wrap
`hasTokens()` in `runCatching`; in Swift, a failed core creation needs a visible "cannot open the app data"
screen rather than a crash (make `create` return a result, or catch in Kotlin and expose a failure string).

### 4. Diary workbook is overwritten in place, non-atomically, and a background task can be cut off mid-write
`DiaryFile.swift:124-146`, `FilesDiaryWorkbook.kt` (`uploadReplace`), `BackgroundSpike.swift:47-67`,
`Companion.swift:233-242`.

- The first write is `data.write(to: writeURL)` without `.atomic` (comment: access is only to this one file).
  If the process is suspended or killed during it, the athlete's real TTB workbook is truncated or partial.
- The fallback (lines 135-140) does `handle.truncate(atOffset: 0)` then `handle.write`; a failure after the
  truncate leaves an empty workbook and the function reports failure.
- `DiaryWriter.saveBackup` is documented never to block the write (DiaryWriter.kt:65), so a failed backup
  (disk full) still proceeds to the destructive write with no copy.
- `BackgroundSpike.run` (line 62-66) sets `expirationHandler = { work.cancel(); finish.complete(success: false) }`.
  `Task.cancel()` does not stop the Kotlin coroutine or the blocking Swift write in `Dispatchers.IO`; after
  `setTaskCompleted` iOS may suspend the process in the middle of that write.

Fix: before writing, verify the backup exists and abort the write if `saveBackup` failed; write via
`NSFileCoordinator` with `.forReplacing` and `FileManager.replaceItemAt` from a temp file in the same
volume where the provider allows it (keep in-place only as the logged fallback); after the in-place write
re-read the file and compare size/bytes, restoring from the backup on mismatch; in the background handler
do not start diary writes at all when `BGTask.expirationHandler` is the only stop signal (skip the diary
phase in `backgroundSync`, or pass a "stop" flag that Kotlin checks between steps). Wrap the write in
`UIApplication.shared.beginBackgroundTask` for the foreground case.

---

## MEDIUM

### 5. A cancelled or failed device selection erases the saved watches
`spikes/watch-link/WatchLinkSpike.swift:66-75`.
`parseDeviceSelectionResponse(from:) as? [IQDevice] ?? []` turns a nil or cancelled response into `[]`; the
code then unregisters all listeners, sets `devices = []` and `saveDevices([])`. Any callback with the URL
scheme but no device (the athlete backs out of Garmin Connect, or an unrelated call) drops the watch link
and the saved selection; `registerAll` then listens to nothing and activities stop arriving until the
athlete selects again. Nothing is shown.
Fix: if the parse result is nil or empty, log it and return without touching `devices`/registrations.

### 6. Failure of diary connect leaves the unvalidated file bookmarked
`Companion.swift:381-401`, `DiaryFile.swift:34-55`.
`remember(url)` replaces the stored bookmark before the workbook is validated. `restorePrevious()` runs only on
the `!problem.isEmpty` branch (line 394); the `catch` branch (397-399, any thrown Exception from
`connectDiary`) does not call it, so a thrown error keeps the new, unchecked file as the diary while the core
still shows the old workbook name; later writes go to the wrong file. Also, picking twice before
confirming overwrites `previousBookmark` with the first unconfirmed pick (line 40).
Fix: call `restorePrevious()` in the `catch`; in `remember`, only set `previousBookmark` when it is nil
(or keep the confirmed one separately); clear `pickedURL` in `restorePrevious` (already done) and in the catch.

### 7. Stale-bookmark renewal runs outside the security scope and its failure is swallowed
`DiaryFile.swift:219-223`.
`url.bookmarkData(...)` for a stale bookmark is called before `startAccessingSecurityScopedResource()` (line 228)
and inside `try?`. If it fails (access is not open), the bookmark stays stale and will stop resolving later, with
no log line. (The spike code does it in the other order, `DiaryFileSpike.swift:33-35,43-49`.)
Fix: start access first, renew inside the scoped region, log the failure.

### 8. Background and open-app runs hide failures; cancellation shows as an error
`Companion.swift:233-242`, `:257-270`, all `catch` blocks; `BackgroundSpike.swift:57-61`; `Screens.swift:133-136`.
- `backgroundSync()` returns `"synced (n lines)"` even when `sync()` caught an error (it only wrote `message`),
  and `BackgroundSpike` always calls `finish.complete(success: true)`. The alert (`message`) is then shown at some
  later foreground moment out of context; the Diagnostics log says "synced".
- No `catch` distinguishes cancellation (grep: no `Task.isCancelled`/`CancellationError` check anywhere).
  `.refreshable { await companion.sync() }` and the background expiry `work.cancel()` can cancel the Swift task
  while Kotlin is mid-call; how that surfaces (a thrown `CancellationException` as `NSError`, or nothing) depends on
  the Kotlin/Native interop version; I did not run it. If it surfaces, the athlete gets an alert with a
  cancellation message ("pull to refresh" while the list rebuilds is the usual trigger).
- `message` is a single slot, so a second error replaces the first before it is read.
Fix: make `sync()` return a result enum (`ok(lines)`, `failed(text)`, `cancelled`) and use it in
`backgroundSync` and `finish.complete(success:)`; ignore cancellation (`catch is CancellationError`, and Kotlin
`CancellationException` by NSError domain/description); queue messages instead of overwriting.

### 9. Strava sign-in: iOS 17.0 to 17.3 cannot connect; success message not verified
`Companion.swift:291-308,310-330`, `project.yml` (`deploymentTarget iOS 17.0`).
- `.https` callback needs iOS 17.4 (line 293); on 17.0-17.3 the button only shows a hard-coded English text.
  Cloud sign-in has a fallback for older iOS (line 430), Strava does not.
- `completeStravaSignIn` returns `""` for `StravaAuthResult.Cancelled` as well as success
  (CompanionCore.kt:~815-820). Swift treats `""` as success: it shows the localised "connected" toast and starts a
  sync (lines 320-323) without checking `core.stravaConnected()`.
- `callbackURL == nil` with no error returns silently (line 317).
- The authorize URL has no `state` parameter (CompanionCore.kt:783-789) and the code does not check one on return;
  the Universal Link host restriction limits the exposure, but a `state` is the standard protection against a
  swapped code. (The cloud PKCE flow does check `state`, CloudOAuth.kt:164.)
Fix: raise the deployment target to 17.4 or add a fallback; after `reason.isEmpty` check
`core.stravaConnected()` and show nothing or "cancelled" otherwise; add `state` generation and check in
`StravaOAuth`.

### 10. Strava client secret and webhook key ship inside the app bundle
`project.yml` (Info.plist properties `StravaClientSecret`, `WebhookApiKey`), `Companion.swift:58-61`.
Both values are written to the app's Info.plist at build time and can be read from any IPA/device backup
copy of the app. The Strava secret allows anyone to exchange codes as this app; the webhook key
authorises writes at the server. (Android has the same design, so this is a known trade-off, but it should be a
conscious decision.) Fix: move the code exchange and token refresh behind the webhook server so the secret
stays server-side, or at least make the webhook key per-install (registered on first use) and rotatable.

### 11. A watch activity that fails to store is only logged
`Companion.swift:182-210`.
On an exception the only trace is a line in the Diagnostics spike log (line 207) and the watch is not
sent a receipt, so it resends. A persistent fault (full disk, Room error) never reaches the athlete, while the
watch keeps retrying with each connection. Also returns 0 silently when `outdated` (line 183) and when the JSON
is invalid (line 187, logged only).
Fix: count consecutive failures and surface a `message`/status card after N failures; include the error
in the log with the activity start time.

### 12. `FilesDiaryAccess` is `@unchecked Sendable` with unsynchronised state and very long blocking
`DiaryFile.swift:13-31,67-119,202-236`.
- `lastFailure`, `lastFailurePermanent`, `pickedURL`, `previousBookmark` are read and written from the main
  thread (`remember`, `forget`, `restorePrevious`) and from Kotlin's IO threads (`withWorkbook`) with no lock; the
  class comment relies on "one call at a time", but `forget()` runs from `deleteAllData` while a sync can be
  running.
- One failed read can block a thread for about 75 s (60 s `waitForDownload` + 5 x 3 s + the final attempt), and
  `withWorkbook` repeats the whole thing for the bookmark after the picked-URL attempt fails (line 205-213), so
  up to about 2.5 minutes on an IO thread, longer than a `BGAppRefreshTask` allows and not cancellable.
Fix: guard the state with an `NSLock`/serial queue; pass a deadline (shorter for background runs) and skip the
second attempt when the first failure was a timeout.

### 13. Watch payloads and file paths are persisted in the Diagnostics log
`WatchLinkSpike.swift:159,268-278,290-298`, `DiaryFile.swift:37,245-253`, `Companion.swift:67`.
`describe(message)` logs up to 600 characters of every watch message (activity JSON including start
coordinates, HR) via `NSLog` and into `UserDefaults` (`spike.log`, 500 lines), and the diary logger writes
provider paths. The Diagnostics tab can share it (`WatchLinkSpikeView.swift:54`). No token, secret or API
key is logged (checked: `debug` lines in the shared module only log messages and `e.message`; the OAuth
callback URL and codes are never passed to a logger in Swift). The privacy notice should still mention the
on-device log, and `NSLog` should not carry payloads in the TestFlight/production build.
Fix: log type and size only (or gate payload logging behind a debug switch); keep paths to the file name.

---

## LOW

14. `exportBoostFiles()` has no re-entrancy guard (`Companion.swift:102-125`; `lookingUpPlaces` guards only places).
    Overlapping `refresh()` calls (burst chunks each call `refresh()` via `receive`) can write the same CSV twice and
    call `recordingBoostFileWritten` twice. The failure report itself is `try?` (line 122), so a failed report is lost.
    Fix: add a `exportingBoosts` flag; log the report failure.
15. `try?` hides failures the athlete may want to see: `core.recordingBoostsToExport` (103), `placeNameCandidates`
    (143), `storePlaceName` (154), `stravaApiCalls` and `recordingBoosts` (`MoreScreens.swift:430,641`: an error shows
    the "empty" text), `activityLog` (648), `feedbackWatches` (622: the watch picker vanishes), `checkOutdated` (217,
    kept by design), `FilesDiaryAccess.remember`/`saveBackup` log lines. Fix: show `message` for the user-visible
    lists (api usage, boosts, activity log) instead of an empty list.
16. `scenePhase == .active` runs `syncOnOpen()` (`NordicSportsCompanionApp.swift:32`) every time the app regains
    focus, including after the Strava/cloud sign-in sheet, the Files picker and Garmin Connect, so a sync and an
    outdated-check network call run in the middle of those flows. Fix: debounce (skip when the last run was under
    a minute ago, or when `authSession`/a picker is active).
17. `signInCloud`/`connectStrava` overwrite `authSession` without cancelling a running session
    (`Companion.swift:304,435`); a second tap leaves the first sheet's completion running. Fix: `authSession?.cancel()` first.
18. Notifications: `UNUserNotificationCenter.add` has no completion handler (`Companion.swift:252`), so an
    authorisation denial or failure is silent (acceptable, but unlogged), and there is no delegate or response
    handler for the `userInfo` `activityId`, so a tap does not open that activity.
19. `String(format:)` with externally generated texts and `Int` arguments (`%d` with a 64-bit `Int`, e.g.
    `Screens.swift:484` and many in `MoreScreens.swift`): a translation with a wrong specifier is undefined
    behaviour or a crash. `tools/test_generate_strings.py` runs in CI; add a check that every placeholder count
    and type matches the English text. Prefer `%ld` for `Int`.
20. `ActivityDetailScreen` reads many fields from the captured `item` and others from `current`
    (`Screens.swift:316,333-349` vs `362-383`), so after an edit the detail shows old duration/RPE/feeling until the
    screen is reopened. Use `current` throughout.
21. `exportFile()` writes the full data export into the temporary directory (`Companion.swift:652-661`); it is
    deleted only by "Delete my data" or by the OS. The `exportURL` in `SettingsPrivacyPage` also goes stale after new
    data arrives. Fix: delete the file after the share sheet closes, or regenerate on every tap.
22. `WatchLinkSpike.sendToWatch` (called from Kotlin on an arbitrary thread) reads `apps`, which `registerAll()`
    reassigns on the main thread (`WatchLinkSpike.swift:78,223`): a data race. Fix: copy `apps` under a lock or hop to
    main.
23. `deviceStatusChanged`/`receivedMessage` use `DispatchQueue.main.sync` from SDK threads
    (`WatchLinkSpike.swift:132,155`): fine today, but a deadlock if the SDK ever calls back from a queue the main
    thread is waiting on. `async` plus the value read in the Task would remove the risk.
24. `Log` writes: `add()` serialises the whole 500-line array into `UserDefaults` on every line
    (`WatchLinkSpike.swift:275`), on the main thread, once per Recording Boost chunk (dozens per burst).
    Fix: batch/throttle.
25. Spike code (`spikes/`) is compiled into the production TestFlight app and reachable from the Diagnostics tab
    (a second diary bookmark, workbook copy export); this is intentional for now but the delete-my-data flow does not
    know about it (finding 1).

### Workflow (`.github/workflows/ios-testflight.yml`)
26. A missing secret does not fail the build: the "App secrets" step only prints `MISSING` (lines 94-96), so a
    TestFlight build with empty Strava/webhook values can ship. Fix: `exit 1` for the required ones.
27. `echo "KEY = $VALUE"` into `Secrets.xcconfig` (lines 86-93): in an xcconfig, `//` starts a comment and a
    newline ends the value, so a value containing `//` is silently truncated. Quote or escape, or write the values
    straight to the plist.
28. Line 158 prints 8 hex digits of the SHA-256 of the distribution-certificate password to the log, and line
    159 a p12 hash prefix. Short hash prefixes of a password in build logs are a small offline-guessing aid if the
    password is weak; remove once the cert flow works, or keep only the length.
29. Unpinned installs: `brew install xcodegen` (line 100) and `pip install pyjwt cryptography` (line 115) take
    whatever is current, and actions are pinned to tags (`@v7`, `@v6`), not commit SHAs. Pin versions/SHAs for a
    pipeline that holds signing keys. The step `Remove the API key...` (`if: always()`) correctly removes the key,
    p12 and `Secrets.xcconfig`; a `security import -A` into a throw-away keychain is acceptable on a one-run runner.
30. `inputs.companion_ref` is only used in `with:` (line 41), not interpolated into a shell, so no injection
    there.

---

## What looked solid

- Every `suspend fun` Swift calls is `@Throws(Exception::class)` and called inside `do/catch` or `try?`; no
  call to a `suspend` function without `try`. No `try!`, `as!`, `fatalError`, implicit force unwrap of external
  data in `App/` or `spikes/`.
- UI types are `@MainActor` (`Companion`), published state is mutated on the main actor; delegate callbacks in
  `WatchLinkSpike` hop to the main thread before touching `@Published` values.
- `ASWebAuthenticationSession` handling: both flows treat `.canceledLogin` as a silent cancel, show the localised
  failure text for other errors, check `session.start()`, release `authSession` in the completion, and supply a
  presentation anchor with a safe fallback. Cloud sign-in uses PKCE and checks `state`; a failed exchange returns a
  user-visible reason.
- Security-scoped resource calls are balanced: every `startAccessingSecurityScopedResource` is paired with a
  `defer` stop (`DiaryFile.swift:35-36,206-207,228-229`, `DiaryFileSpike.swift:43-46`); reads and writes go through
  `NSFileCoordinator`; coordinator errors are thrown rather than ignored; the `Result` bridge in
  `coordinatedRead/Write` handles errors from inside the block.
- Keychain items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (usable by background sync, never synced to
  iCloud) and are cleared by `signOutCloud`/`deleteAllData`.
- Receipt protocol: the receipt goes out only when the core confirms the store (`startTime > 0`) and uses a 32-bit
  `NSNumber`; send results flow back to the core's transfer log.
- Background task completion is guarded exactly once by `Finish` (`NSLock`), `BGTaskScheduler` handlers are
  registered in `App.init` before launch ends, and the next requests are scheduled inside the handler.
- No token, refresh token, client secret, API key, or OAuth code/callback URL is logged by the Swift code; the
  workflow prints only set/missing and lengths for app secrets, and removes the API key, p12 and `Secrets.xcconfig`
  in an `if: always()` step. `Secrets.xcconfig`, `*.p12` and `logs/` are gitignored.
- Defensive array access on SDK data uses a safe subscript (`WatchLinkSpike.swift:321-323`); division by sample
  rate is guarded (`MoreScreens.swift:607`); `URL(string:)` results are unwrapped with `guard`/`if let` everywhere.
- Closures: no retain cycle of consequence (all long-lived objects are singletons; the auth-session completion
  releases the session).
