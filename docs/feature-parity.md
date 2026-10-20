# Feature parity: Android Companion vs. iOS Companion

One row per feature the athlete can see or rely on. Keep it current with every Companion
or iOS change (roadmap step 7). Created 2026-10-10 (Companion 0.9.89), rewritten
2026-10-12 after TestFlight build 18, brought up to Companion and watch 0.9.92 on
2026-10-17 (nickname, watch crash reports, live recording card, settings sync strip), and
on 2026-10-19 the build 20 items (duplicate merger, strength description, notifications,
background sync) against Companion `kmp-shared-module` (database version 30).

**Shared** says how much of the logic lives in the Kotlin `shared` module: **yes** = logic,
data and texts in `shared`, iOS adds UI and platform glue only; **part** = some pieces
shared; **no** = Android-only. **iOS**: *MVP* = the first app build (roadmap step 4); *build N* = in TestFlight build N and tested on the
iPhone; *build 19* = built, waiting for the next TestFlight build; *-* = missing.
Build 20 also carries every build 19 row (build 19 was never tested on its own).
**Next** is the build it is planned for (see the end of this file).

| Area | Feature | Shared | iOS | Next | Notes |
|---|---|---|---|---|---|
| Watch | Receive activities (both app ids), receipts `"rx"` | yes | build 16 | | Connect IQ iOS SDK; arrival in the background still depends on iOS |
| Watch | Watch settings: view and change | yes | build 17 | | `WatchSettingsSync` |
| Watch | Data fields per activity type | yes | build 19 | | Needs watch 0.9.90 (full version); on Android since 0.9.90 |
| Watch | Interval plans, strength routines | yes | build 19 | | Shared `WatchPlanEditor` builds the editor rows; Android keeps its own Compose editor |
| Watch | Settings sync strip (sent / received, failure reason) and "1 update waiting" line | yes | build 19 |  | Shared `WatchSyncView` in `WatchSettingsView.sync` (texts in `TableTexts`); iOS calls `watchConnected()` on connect, which keeps the name |
| Watch | Nickname to every watch (`Nickname` key, Companion wins) | yes | build 19 |  | `CompanionCore` passes the nickname to `WatchSettingsSync`; `setNickname()` pushes it |
| Watch | Recording on the watch card (`activityStart` / `activityStop`, settings `at`) | yes | build 19 |  | `CompanionCore.watchMessage()` routes `activityStart` / `activityStop`, `liveActivities()`; coordinates shown until the build 21 geocoder |
| Watch | Watch crash reports (`crashReport`), sent as feedback on Send | yes | build 19 |  | `crashReports()`, `sendCrashReport()`, `dismissCrashReport()`; "Delete my data" clears them |
| Watch | Ask the watch to resend its queue when it connects again (`{"type": "resend"}`) | part | build 19 |  | `watchConnected()` returns the app id (once a minute per watch), `resendRequested()` logs it |
| Watch | Heart rate sensor section from the watch's `HrStrapInfo` / `HrStrapName` / `HrStrapBleName` (shared `WatchHrStrapInfo`: state, check time, strap name, Bluetooth name, model name, ANT+ ID, serial, battery); no "HR Chest Strap" switch | part | build 19 |  | `WatchSettingsView.hrStrap` built in `CompanionCore` as Android's `HrStrapDetails` |
| Watch | Language offer watch <-> app | part | - | 21 | |
| Watch | Recording Boost bursts (reassembly, CSV files, list) | part | - | 21 | File export: Files app |
| Activities | Local database, list with sync badges, detail | yes | MVP | | Android 0.9.91: the detail header repeats the list tile with the name, the top bar says "Activity" |
| Activities | Home screen by nickname ("All caught up, Anna!") | no | - | 22 | Android UI (0.9.91); the `_named` strings are in the generated text table |
| Activities | Open items first, oldest on top; "To review" / "Done" headings; green frame for one just finished | part | - | 22 | `ReviewState.openItemsFirst` shared; the list UI and the just-finished frame per platform (Android 0.9.93) |
| Activities | Detail buttons: "Save & send" (automated) / "Save" + "Send now" (manual), saving first; "Create on Strava" only without a Strava link; diary without Strava; in-sync + review as one home box | part | - | 22 | Android 0.9.94, UI per platform |
| Activities | Edit, review window | yes | build 18 | | |
| Activities | Interaction mode (interactive / automatic) setting | yes | build 19 |  | `reviewNewActivities()` / `setReviewNewActivities()`, Settings › App |
| Activities | Add by hand, delete with tombstone | yes | build 17 | | Strava link/create for manual: build 18 |
| Activities | Place names (reverse geocoding) | part | - | 21 | iOS: CLGeocoder behind `PlaceNameLookup` |
| Activities | New-activity notification (nickname, review or not) | yes | build 20 | | Texts from `WatchMessageResult` (shared); iOS shows it while the app is not on screen; a tap opens the app, not yet the activity |
| Strava | Connect / disconnect, link, title and sport type | yes | MVP | | Universal Link callback |
| Strava | Backfill, webhook events, self-echo | yes | MVP | | Pulled on app open and Sync now only |
| Strava | Duplicate merger (a Strava activity on its own row) | yes | build 20 | | Shared `StravaDuplicateMerger`; iOS runs it in a Room transaction when "Add by hand" links a Strava id another row holds |
| Strava | Strength description | yes | build 20 | | Shared `StrengthDescription`; iOS writes it after the title (`CompanionCore`), numbers as Android's Locale |
| Strava | Connect with Strava button (official orange image, 48 pt) where OAuth starts | yes (branch `strava-brand-compliance`) | build 21 | | Settings › Strava (iOS has no add-connection list, onboarding or reconnect card yet; they use `StravaConnectButton` when built). Strava's PNGs unchanged in `StravaConnectButton.imageset` (1x, 2x) |
| Strava | Powered by Strava logo (orange, horizontal, about 18 pt) | yes (branch) | build 21 | | Settings › Strava and the activity detail with a Strava id; `StravaPoweredBy.imageset` (Strava's 365x37 PNG as 2x) |
| Strava | "View on Strava" link (not translated, bold, underlined, #FC5200) | yes (branch) | build 21 | | Activity detail, hidden without a Strava id; SwiftUI `Link` (Strava app via universal link, else Safari) |
| Strava | Data retention: 7-day purge, 48 h delete sync, purge and revoke on disconnect | yes (branch, stages 1-5) | build 21 | | Shared `StravaRetentionPurger`; iOS runs `purgeExpiredStravaData()` on every foreground and background run (both sync modes); the delete safety net runs inside `syncNow`; Disconnect asks with `status_disconnect_confirm_body_strava` and shows the `StravaDisconnectResult` confirmation; activity note "Strava data removed on …"; log labels and texts come from the table. Room 31-34 registered in `IosCompanion`. Stage 5b: access withdrawn on strava.com (noticed at a token refresh) deletes the Strava data too; iOS shows `pendingStravaWithdrawalNotice()` once at the next refresh and acknowledges it on OK (no system notification, as Android) |
| Diary | Write-back, Push to Diary, three diary switches | yes | build 16 | | |
| Diary | TTB rules 0.9.93: ids in the hidden register sheet (no cell note), compact "Title: comment" joined with "; ", oldest first, back-to-back sessions in one slot, formula results recalculated before upload | yes | - | 22 | All in shared (`DiaryWriter`, `TtbWorkbookEditor`, `TtbRecalculator`); arrives with the next XCFramework. Text `ttb_forwarder_legacy_notes_moved` is in the table |
| Diary | "Compact diary" for the last n days (temporary, remove a few versions after 0.9.93) | part | - | 22 | `DiarySync.rewriteRecent` shared; iOS needs the settings row (Android: under the Strava backfill) |
| Diary | Files app workbook | part | build 16 | | Read-only for OneDrive's provider, hence the clouds |
| Diary | OneDrive, Dropbox, Google Drive | yes | build 18 | | PKCE sign-in, Keychain tokens |
| Diary | Backups | part | build 16 | | On the iPhone (Documents/diary-backups) for every cloud |
| Diary | Connection problems on the start screen | yes | build 16 | | |
| Diary | Settings: one row and page per connection (Strava, each diary destination "TTB diary · OneDrive", Cloud accounts only while a cloud is signed in, "Add connection") | no | - | | Android branch `settings-connection-rows` (diary destinations stage 1, `design/diary-destinations.md` in the Companion repo); UI per platform, page order in Android's `SettingsPageModel.kt` |
| Sync | Background sync and its mode (automatic / manual) | part | build 20 | | Sync mode in Settings › App (shared store); BGTaskScheduler refresh and processing tasks run the sync; iOS decides when. Android's Strava title polling after an arrival is not on iOS: the next sync picks the title up |
| Data | Database version 30 (diary destinations) on iOS | yes | build 20 | | Shared `Migration29To30.CONNECTION_MIGRATION`; every later schema version needs its migration in `IosCompanion` too |
| Data | Export my data (JSON), delete my data | yes | build 17 / 18 | | |
| Data | Activity JSON files, folder choice | no | - | later | Optional on iOS |
| Logs | Diary, app, transfer log, activity history | yes | build 17 | | Texts tidied (`tidyLogText`) in `CompanionCore` since 0.9.92, as on Android |
| Logs | Strava API usage screen | part | - | 21 | |
| App | Feedback | yes | build 17 | | |
| App | Minimum supported version from the server (`api/client-config.php`): below it nothing syncs, only export and delete | part | - | 22 | Android 0.9.96 (`ClientStatus`, `ui/BuildExpiryScreen.kt`); shared `core/BuildExpiry` and `ClientConfigApi` are ready, iOS needs the check at app start and the blocking screen. Sideload expiry is Android-only: TestFlight builds expire after 90 days on their own |
| App | Feedback: pick the watch (from activities and settings reports), "Include my nickname" | part | build 19 |  | `feedbackWatches()` (shared `mergeKnownWatches`), nickname as `details.nickname` |
| App | Feedback "Wording / translation": search any Companion or watch text in nine languages, propose a better wording (flag + short code chips, Swiss German as CH) | yes | build 21 (untested) | | Shared `WordingCatalog` / `WordingSearch`; iOS `App/WordingFeedback.swift` + category in `FeedbackScreen`; CI copies the Companion's `wording_texts.json` into `App/Texts`. Sent as category `other` with `wording_*` details. No About entry yet (Android has "Help improve the translations") |
| App | Nickname setting (Settings › App), used in notifications | part | build 19 |  | Settings › App; "Delete my data" clears it; not yet in notifications (iOS has none yet) |
| App | Languages en, de, fr, it, rm, gsw, nb, fi, sv | part | part | 22 | Generated from Android strings (nb, fi, sv since 0.9.93: generator, `CFBundleLocalizations`, language pick); some iOS labels still English |
| App | Onboarding guide, about, changelog, settings search | no | - | 22 | Android 0.9.90: the guide starts with "How shall I call you?", then Strava, then the diary |
| App | Theme (light / dark / system) | no | system | | iOS follows the system |
| Trainingsplan | Plan annotation | part | - | - | Off on Android; not in iOS scope until re-enabled |

## Builds until parity

- **19:** data fields, interval plans, strength routines; from build 20 moved forward
  (2026-10-19): the settings sync line, nickname, recording card, crash reports, resend on
  reconnect, heart rate sensor section, the review switch and the feedback watch choice.
- **20:** Strava duplicate merger, strength description, background sync with
  notifications (with the nickname in them); built 2026-10-19 with Companion
  `kmp-shared-module`, so it also needs the database upgrade to version 30.
- **21 (first part built 2026-10-20 with Companion `ios-build-21` = `kmp-shared-module` +
  `strava-brand-compliance`):** Strava branding and data retention (stages 1-5b). Still open for 21: place
  names, Recording Boost, language offer, Strava API usage. Strava brand
  compliance (decided 2026-10-20: "Powered by Strava"; Reconnect Strava also uses the official
  Connect with Strava button; no Strava logo on About).
- **22:** all iOS labels from the text table, onboarding, about, changelog; then the
  release steps (roadmap step 6).
