# Feature parity: Android Companion vs. iOS Companion

One row per feature the athlete can see or rely on. Keep it current with every Companion
or iOS change (roadmap step 7). Created 2026-10-10 (Companion 0.9.89), rewritten
2026-10-12 after TestFlight build 18, brought up to Companion and watch 0.9.92 on
2026-10-17 (nickname, watch crash reports, live recording card, settings sync strip; build
19 is still not built).

**Shared** says how much of the logic lives in the Kotlin `shared` module: **yes** = logic,
data and texts in `shared`, iOS adds UI and platform glue only; **part** = some pieces
shared; **no** = Android-only. **iOS**: *MVP* = the first app build (roadmap step 4); *build N* = in TestFlight build N and tested on the
iPhone; *build 19* = built, waiting for the next TestFlight build; *-* = missing.
**Next** is the build it is planned for (see the end of this file).

| Area | Feature | Shared | iOS | Next | Notes |
|---|---|---|---|---|---|
| Watch | Receive activities (both app ids), receipts `"rx"` | yes | build 16 | | Connect IQ iOS SDK; arrival in the background still depends on iOS |
| Watch | Watch settings: view and change | yes | build 17 | | `WatchSettingsSync` |
| Watch | Data fields per activity type | yes | build 19 | | Needs watch 0.9.90 (full version); on Android since 0.9.90 |
| Watch | Interval plans, strength routines | yes | build 19 | | Shared `WatchPlanEditor` builds the editor rows; Android keeps its own Compose editor |
| Watch | Settings sync strip (sent / received, failure reason) and "1 update waiting" line | yes | - | 20 | Shared `WatchSettingsSync.activity`; iOS UI only. iOS should also call `nameSeen()` on connect, as Android does, so a watch keeps its name |
| Watch | Nickname to every watch (`Nickname` key, Companion wins) | yes | - | 20 | Shared `AthleteProfileStore`, `WatchSettingsSync(nickname = ...)`, `pushNickname()`; `CompanionCore` passes no nickname yet, so iOS leaves the watches' nickname alone |
| Watch | Recording on the watch card (`activityStart` / `activityStop`, settings `at`) | yes | - | 20 | Shared `WatchLiveActivityTracker`; the iOS watch link routes only `activity` and `settings` so far. Place name with the build 21 geocoder |
| Watch | Watch crash reports (`crashReport`), sent as feedback on Send | yes | - | 20 | Shared `WatchCrashReports`, `FeedbackSource.CRASH_REPORT`; needs routing, a card and "Delete my data" coverage |
| Watch | Language offer watch <-> app | part | - | 21 | |
| Watch | Recording Boost bursts (reassembly, CSV files, list) | part | - | 21 | File export: Files app |
| Activities | Local database, list with sync badges, detail | yes | MVP | | Android 0.9.91: the detail header repeats the list tile with the name, the top bar says "Activity" |
| Activities | Home screen by nickname ("All caught up, Anna!") | no | - | 22 | Android UI (0.9.91); the `_named` strings are in the generated text table |
| Activities | Edit, review window | yes | build 18 | | |
| Activities | Interaction mode (interactive / automatic) setting | yes | - | 20 | Store shared; iOS has no switch yet, uses the default |
| Activities | Add by hand, delete with tombstone | yes | build 17 | | Strava link/create for manual: build 18 |
| Activities | Place names (reverse geocoding) | part | - | 21 | iOS: CLGeocoder behind `PlaceNameLookup` |
| Activities | New-activity notification | part | - | 20 | With the background work |
| Strava | Connect / disconnect, link, title and sport type | yes | MVP | | Universal Link callback |
| Strava | Backfill, webhook events, self-echo | yes | MVP | | Pulled on app open and Sync now only |
| Strava | Duplicate merger (a Strava activity on its own row) | part | - | 20 | |
| Strava | Strength description | part | - | 20 | Wording in `WatchActivityEvent`; check the iOS write path |
| Diary | Write-back, Push to Diary, three diary switches | yes | build 16 | | |
| Diary | Files app workbook | part | build 16 | | Read-only for OneDrive's provider, hence the clouds |
| Diary | OneDrive, Dropbox, Google Drive | yes | build 18 | | PKCE sign-in, Keychain tokens |
| Diary | Backups | part | build 16 | | On the iPhone (Documents/diary-backups) for every cloud |
| Diary | Connection problems on the start screen | yes | build 16 | | |
| Sync | Background sync and its mode (automatic / manual) | part | - | 20 | Background App Refresh was "restricted" on the test phone |
| Data | Export my data (JSON), delete my data | yes | build 17 / 18 | | |
| Data | Activity JSON files, folder choice | no | - | later | Optional on iOS |
| Logs | Diary, app, transfer log, activity history | yes | build 17 | | Texts tidied (`tidyLogText`) in `CompanionCore` since 0.9.92, as on Android |
| Logs | Strava API usage screen | part | - | 21 | |
| App | Feedback | yes | build 17 | | |
| App | Feedback: pick the watch (from activities and settings reports), "Include my nickname" | part | - | 20 | Shared `mergeKnownWatches()`; iOS sends only `latestWatchName()` |
| App | Nickname setting (Settings › App), used in notifications | part | - | 20 | Shared `AthleteProfileStore.clean()`; "Delete my data" must clear it (`CompanionCore.deleteAllData`) |
| App | Languages en, de, fr, it, rm, gsw | part | part | 22 | Generated from Android strings; some iOS labels still English |
| App | Onboarding guide, about, changelog, settings search | no | - | 22 | Android 0.9.90: the guide starts with "How shall I call you?", then Strava, then the diary |
| App | Theme (light / dark / system) | no | system | | iOS follows the system |
| Trainingsplan | Plan annotation | part | - | - | Off on Android; not in iOS scope until re-enabled |

## Builds until parity

- **19:** data fields, interval plans, strength routines. The code is on `main`, but no
  TestFlight run since build 18 (2026-10-11), so its Swift has not been compiled against the
  0.9.92 shared module yet; the next run checks that (`CompanionCore` only gained API since).
- **20:** interaction mode switch, Strava duplicate merger, strength description,
  background sync with notifications; from the 0.9.90 release: nickname (setting, watch
  sync, notifications), the watch messages `activityStart` / `activityStop` / `crashReport`
  with their cards, the settings sync strip, and the feedback watch choice.
- **21:** place names, Recording Boost, language offer, Strava API usage.
- **22:** all iOS labels from the text table, onboarding, about, changelog; then the
  release steps (roadmap step 6).
