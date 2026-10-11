# Feature parity: Android Companion vs. iOS Companion

One row per feature the athlete can see or rely on. Keep it current with every Companion
or iOS change (roadmap step 7). Created 2026-10-10, Companion 0.9.89.

**Shared** says how much of the logic already lives in the Kotlin `shared` module
(roadmap step 2): **yes** = logic and data in `shared`, iOS needs UI and platform glue only;
**part** = some pieces shared, the flow itself still Android-only; **no** = Android-only
(platform API or not yet moved). **iOS** is the state in this repo. **MVP** = part of the
first iOS release (roadmap step 4: watch -> local DB -> list/detail -> Strava link and title).

| Area | Feature | Shared | iOS | MVP | Notes |
|---|---|---|---|---|---|
| Watch | Receive activities from the watch (both app ids) | part | spike 1 | yes | Payload model, receipts protocol shared; link is Connect IQ iOS SDK (`WatchEventSource`) |
| Watch | Receipts back to the watch (`"rx"`) | part | spike 1 | yes | Message format in `guides/companion-handover.md` |
| Watch | Recording Boost bursts (chunks, reassembly, files) | part | - | no | Burst model shared; reassembly and file export Android-only |
| Watch | Watch settings: view and change | yes | spike 1 (request only) | no | `WatchSettingsSync`, `WatchSettingsTransport` |
| Watch | Interval plans, strength routines editors | yes | - | no | Models shared; editors are UI |
| Watch | Language offer watch <-> app | part | - | no | |
| Activities | Local database (Room) | yes | - | yes | Entities, DAOs, schema v29 in `shared`; iOS starts at v29 |
| Activities | Activity list with sync badges | part | - | yes | Status rules partly shared (`SyncStatusChecker` Android-only) |
| Activities | Activity detail and diary entry editing | part | - | yes | `DiaryEntryBuilder`, `DiaryFields` shared |
| Activities | Add activity by hand (presets) | part | - | no | |
| Activities | Delete with tombstone | part | - | no | |
| Activities | Review window (interactive mode, 24 h) | part | - | no | `InteractionMode` store Android-only |
| Activities | Place names (reverse geocoding) | part | - | no | `PlaceNameLookup` interface + `formatPlaceName` shared; iOS: CLGeocoder |
| Activities | New-activity notification | part | - | no | `ActivityNotifier` interface |
| Strava | Connect / disconnect (OAuth) | part | - | yes | `StravaOAuthApi` shared; consent screen per platform (iOS: ASWebAuthenticationSession + Universal Link, spike 3) |
| Strava | Link watch activity to Strava activity | part | - | yes | `StravaActivityMatcher` shared; `StravaLinkResolver` Android-only (2.6d) |
| Strava | Title and sport type rewrite | part | - | yes | `StravaPresetRules`, `StravaApi` shared; polling via `CompanionScheduler` |
| Strava | Strength description | no | - | no | `StrengthDescription` (locale formatting) |
| Strava | Create manual activity | yes | - | no | `StravaApi.createManual` |
| Strava | Webhook events, backfill, self-echo | part | - | no | `WebhookServerApi` shared; `StravaActivitySync` Android-only (2.6d) |
| Diary | Write-back to the TTB workbook | part | - | no (step 5.1) | Editor, layout, entry rules shared; write flow in `TtbForwarder` Android-only (2.6c) |
| Diary | OneDrive | yes | - | no | `OneDriveGraphApi`; sign-in per platform (MSAL iOS, spike 4) |
| Diary | Dropbox, Google Drive | no | - | no | Vendor Android SDKs; iOS needs its own clients |
| Diary | Local file (device folder / Files app) | no | - | no | iOS: security-scoped bookmark (spike 4) |
| Diary | Backups and activity metrics export | part | - | no | |
| Diary | Connection problems on the start screen | yes | - | no | `DiaryConnectionStore`, `IssueReportingDiaryFileStore` |
| Sync | Automatic / manual sync mode | yes | - | yes | `SyncModeStore`; background work per platform (BGTaskScheduler, spike 2) |
| Sync | Catch-up after connecting | yes | - | no | `AutomationSettingsStore` |
| Data | Activity JSON files, folder choice | no | - | no | iOS: Files app export |
| Data | Export all my data / delete all my data | no | - | no | Needed for the App Store privacy rules before release |
| Logs | Data sharing log, diary worklog, app log, Strava API usage, transfer log | part | - | no | Tables shared (Room); screens UI |
| App | Settings screen (overview + pages) | part | - | yes (minimal) | Stores shared (`KeyValueStore`); layout maps to SwiftUI `NavigationStack` + `Form` |
| App | Languages en, de, fr, it, rm, gsw | no | - | yes (en/de) | Decision on shared texts pending (roadmap 5.7) |
| App | Theme (light/dark/system) | no | - | no | iOS follows the system by default |
| App | Feedback form | yes | - | no | `FeedbackApi` |
| App | Onboarding guide, about, changelog | no | - | no | |
| Trainingsplan | Plan annotation | part | - | no | Switched off on Android; not in iOS scope until re-enabled |
| Diary backport | | - | - | - | Removed on Android; not ported |
