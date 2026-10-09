# iOS Companion roadmap

Goal: an iPhone Companion with the same behaviour as the Android Companion, built so that
a fix or feature is written **once** wherever possible and both apps stay easy to maintain.

Status: sketch (2026-10-09). The decisions marked "proposed" need the athlete's confirmation.

---

## 1. Architecture choice (proposed)

| Option | Shared | Written twice | Verdict |
|---|---|---|---|
| A. Native Swift/SwiftUI rewrite | Nothing (only docs and test fixtures) | All ~32k lines, every future change | Highest maintenance; parity drifts |
| B. **Kotlin Multiplatform core + native platform adapters** | Domain logic, rules, DB schema, network clients, i18n tables | Watch link, auth, file pickers, background, keychain | **Recommended** |
| C. B + Compose Multiplatform UI | B plus most screens | Only platform adapters and a few native screens | Optional later step on top of B |

Why B: the Android code is already Kotlin, and its valuable, bug-prone logic is
platform-neutral (`forwarders/ttb/*`, `HrZoneIntensityMapping`, `StravaActivityMatcher`,
`StravaLinkResolver`, Strava title rules, `WatchActivityEvent` parsing, `WatchSettings`
"A to B" change logic, `xlsx/TtbWorkbookEditor`). Sharing it keeps Activity-Tool parity,
the HR-zone precedence and the language-consistency rules in **one** place.

UI decision (SwiftUI vs Compose Multiplatform) is taken after step 4. The current UI is
already Compose, so Compose Multiplatform would share the most code; SwiftUI feels more
native. Either way the screens stay thin over the shared view models.

### Repository layout (proposed)

- `Nordic Sports Companion` (existing repo) gains a `shared/` KMP module. The Android app
  becomes a consumer of it. One version, one tag `vX.Y.Z`, one CHANGELOG section per
  platform.
- `Nordic Sports iOS Companion` (this folder, own repo) holds the Xcode project and iOS
  adapters, and consumes `shared` as an XCFramework built from the Companion repo at a
  matching tag.
- Alternative to decide later: move this project into the Companion repo as `iosApp/`
  (a single repo makes lockstep releases trivial). Keep the folder independent until
  the shared module has proven itself.

---

## 2. Logical steps

### Step 0: Prerequisites and decisions
- Mac access: **no local Mac**, so everything Apple-side runs remotely (see "Remote Mac
  setup" below). Windows builds and tests the shared JVM side.
- Apple Developer Program account. Bundle id: reuse `me.maddin.nordicsports.companion`.
- Confirm option B, the repo layout and the minimum iOS version (proposal: iOS 17).
- Agree on feature scope for the first iOS release (see step 5).

### Step 1: Feasibility spikes on iOS (in `spikes/`, throw-away)
These carry the real risk. Do them before investing in the shared module.
1. **Watch link:** Connect IQ Mobile SDK for iOS. Device selection goes through Garmin
   Connect Mobile (URL scheme round-trip). Receive a real `TransmitPayload` from both
   watch app ids (public and Preview). Measure what arrives while the app is in the
   background or not running. The watch keeps an activity queued until the Companion
   confirms receipt (`guides/companion-handover.md`), which suits iOS. Confirm that the
   receipt reply works, plus the settings snapshot / "A to B" change messages.
2. **Background:** what BGTaskScheduler and background fetch really deliver for diary
   sync and Strava title updates. Expect "when the app is opened" as the reliable baseline.
3. **Strava OAuth:** ASWebAuthenticationSession with a Universal Link (needs
   `apple-app-site-association` on the server). A custom scheme is not an option: Strava
   rejects custom-scheme `redirect_uri`s (that is why Android uses an https App Link).
4. **Diary file round-trip:** open a real TTB workbook from the Files app (security-scoped
   bookmark), from OneDrive (MSAL iOS), Dropbox (SwiftyDropbox) and Google Drive, edit it,
   and write it back.

Outcome: a short findings note per spike in `docs/`, and a go / no-go per feature.

### Step 2: Make the Android Companion multiplatform-ready (Android repo, no behaviour change)
Done in small, separately released steps, with `testSideloadDebugUnitTest` green after each:
1. Upgrade the toolchain: Kotlin 1.9.24 to 2.x, Room 2.6 to a KMP-capable Room (2.7+), KSP.
   *In progress:* branch `kmp-toolchain-upgrade` (Kotlin 2.3.21, Compose compiler plugin,
   KSP 2.3.12, Room 2.8.4); 201 unit tests green, both flavors build; device test pending.
2. Create an empty `shared` module (targets: android, iosArm64, iosSimulatorArm64) and
   wire it into the app.
   *Done* on branch `kmp-shared-module` (`com.android.kotlin.multiplatform.library`,
   framework `NordicSportsShared`, tests: `gradlew.bat :shared:testAndroidHostTest`).
3. Move pure logic first, with its unit tests: TTB layout/mapping, HR-zone intensity,
   Strava matcher/title rules, watch payload model, activity-type and label tables, diary
   backport matcher.
   *First slice done:* watch payload model (`WatchActivityEvent`, `WatchBuildInfo`,
   `WatchIntervalPlan`, `WatchRecordingBoostBurst`, `WatchAppIds`), `ReviewState`,
   `RollerskiTechniqueInference`, `StravaSyncPolicy`, with 23 tests in `commonTest`.
   *Second slice done:* `DiaryFields` (fingerprint parity-tested against the old
   implementation), the TTB model and `TtbMapping` (`TtbModel.kt`), `HrZoneIntensityMapping`
   with its tests, `JsonNumbers` (org.json replacement for number columns, writes
   Android's exact format). Shared tests: 38. Next candidates: `DiaryEntryRecord`,
   `EntityMapping`, `WatchSettings` (org.json objects), `StravaActivityMatcher`
   (needs its `Context` dependency split off), `StravaTtbMapping`.
   Findings:
   - Most remaining logic takes `ActivityEventEntity` (Room) as input, so the Room
     entities have to move (step 5) before TTB/HR-zone/matching logic can follow, or that
     logic is changed to take `WatchActivityEvent` / small input types instead.
   - `TtbWorkbookEditor` (~1,400 lines) is built on `javax.xml` DOM (`org.w3c.dom`). iOS
     has no DOM parser either, so it needs a pure-Kotlin XML library (candidate:
     `io.github.pdvrieze.xmlutil`), and `XlsxZip` needs a multiplatform zip
     (expect/actual or a library). This is the largest single porting item.
   - `org.json` (Android-only) is used for persistence/JSON; move to kotlinx.serialization.
   - Cross-module rule: smart casts on properties of shared classes no longer work in
     `:app` (use `?.let`).
4. Replace JVM-only APIs in moved code: `java.time` with kotlinx-datetime,
   `HttpURLConnection` with Ktor (keep `applyDefaultTimeouts` semantics), `java.util.zip`
   behind expect/actual for `XlsxZip`, `EncryptedPrefs` behind an interface
   (Android: security-crypto, iOS: Keychain).
5. Move the Room entities, DAOs and migrations into `shared` (schema JSON stays committed;
   same migrations for both platforms).
   *Done* (branch `kmp-shared-module`): schema, 12 entities, 10 DAOs in `shared`,
   schemas in `shared/schemas`, identity hash unchanged (v29). The migrations 12..29 stay
   Android-only in `:app` (`AppDatabaseFactory.kt`, SupportSQLite, 22->23 runs
   `StravaDuplicateMerger`); iOS starts at v29. **Rule from now on:** every new schema
   bump gets a `SQLiteConnection`-based Migration in `shared`, registered on both
   platforms. Still in `:app`: `EntityMapping` (needs `org.json`), `StravaDuplicateMerger`
   and `StravaLinking` (SupportSQLite / `openHelper`).
   Not yet verified: Room KSP for the iOS targets (runs on macOS only; first CI run).
6. Define platform interfaces for everything that stays native: `WatchEventSource`,
   `DiaryProvider`, `TrainingsplanProvider`, token stores, schedulers, notifications,
   location.

### Step 3: iOS project shell (this repo, on a Mac)
- Xcode project, build configurations (Preview / Store, like the two Android flavors),
  signing, script to build and embed the `shared` XCFramework.
- Implement the platform interfaces from step 2.6 with the spike code from step 1.
- Debug fixtures: a stub watch source like `StubWatchEventSource` for the simulator.

### Step 4: Vertical MVP slice
Watch receives activity, then local DB, then activity list and detail, then Strava
link/create and title rewrite. Ship to internal TestFlight. Then take the UI decision
(SwiftUI vs Compose Multiplatform).

### Step 5: Feature parity, in priority order
1. TTB diary write-back (Files app first, then OneDrive, Dropbox, Google Drive)
2. Strava full sync, backfill, conflict / self-echo handling
3. Watch settings, interval plans, strength routines
4. Add activity by hand, delete with tombstone
5. Trainingsplan, place names, Recording Boost export, data export / deletion
6. Worklog transparency log, JSON export, app log, feedback / crash reports
7. Localization: en, de, fr, it, rm, gsw from one shared source (generate iOS
   `.xcstrings` from the Android strings, or move both to shared resources)

### Step 6: Server, privacy and store
- Webhook server: `apple-app-site-association` (Universal Links), possibly APNs push for
  Strava events later (iOS cannot poll in the background like Android).
- Privacy notice (`privacy.html`) covers iOS too; App Store privacy labels follow the
  `PRIVACY-SYNC:` spots, which now partly live in `shared`.
- Entra, Dropbox and Google Cloud: register the iOS bundle id and redirect URIs.
- Garmin: check whether the Connect IQ Store listing should mention the iOS Companion.
- App Store listing (EN/DE) and screenshots (creative-agent).
- TestFlight replaces the Android sideload channel for testers.

### Step 7: Ongoing maintenance process
- **Feature matrix** `docs/feature-parity.md`: each feature with Android / iOS status.
- **Shared contract fixtures:** real watch payloads and TTB workbooks (`Test_files/`)
  used by the shared tests, so both platforms are tested against the same data.
- **Lockstep versions:** iOS `CFBundleShortVersionString` = Android `versionName` =
  watch version. One tag, one CHANGELOG.
- **Rules move with the code:** language-consistency, Strava write-back review and the
  privacy sync check apply to `shared` once, and to each platform's UI and adapters.
- An `ios-agent` in `.claude/agents/` and iOS skills (`ios-verify`, `ios-release`) once
  the Xcode project exists.

---

## Remote Mac setup (no local Mac)

Code is written on Windows, compiled on a Mac in the cloud, and tested on a real iPhone
through TestFlight.

1. **No hand-edited Xcode project:** the project is described in `project.yml`
   ([XcodeGen](https://github.com/yonaskolb/XcodeGen)) and generated on the Mac at build
   time. Text files only, so editing and reviewing on Windows works.
2. **GitHub Actions macOS runner** (the repos are already on GitHub,
   `maddinzi/...`): on push, a workflow builds the `shared` XCFramework from the
   Companion repo, generates and builds the iOS app, runs unit tests on the simulator,
   and (on demand) uploads a build to TestFlight. Signing uses an App Store Connect API
   key stored as a GitHub secret (automatic signing, or fastlane `match`). Check the macOS
   minute quota/cost of the GitHub plan; macOS minutes count several times Linux minutes
   on private repos.
3. **Physical testing via TestFlight:** internal TestFlight builds need no App Review and
   install on the athlete's iPhone within minutes. This is the only way to test the watch
   link (spike 1) without a Mac, because Garmin Connect Mobile and the watch need a real
   phone.
4. **Interactive Mac only when needed:** an hourly rented cloud Mac (e.g. MacinCloud,
   Scaleway Mac mini; Apple's licence forces a 24 h minimum at some providers) for
   one-off tasks: first App Store Connect / certificate setup, debugging with Xcode
   attached, simulator screenshots for the store.
5. **Later option:** Xcode Cloud (included hours with the Apple Developer Program) can
   replace GitHub Actions once the project is stable; it also needs no local Mac after
   the first setup.

Prerequisites for this route: Apple Developer Program membership, App Store Connect API
key, an iPhone with Garmin Connect Mobile paired to a test watch, and a GitHub remote for
this repo.

---

## 3. Main risks

| Risk | Mitigation |
|---|---|
| Connect IQ iOS SDK limits (needs Garmin Connect Mobile, background delivery) | Spike 1 first; the watch queue tolerates late receipt |
| iOS background limits (no WorkManager equivalent) | Sync on app open plus BGTaskScheduler; APNs later |
| No Mac on this PC | Cloud Mac or macOS CI; shared logic stays testable on Windows |
| Toolchain upgrade breaks the Android app | Step 2 in small releases with full unit tests |
| Two UIs drift | Thin UI over shared view models; parity matrix; optional Compose Multiplatform |
