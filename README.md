# Nordic Sports iOS Companion

The iPhone version of the Nordic Sports Companion. It receives activities from the
Nordic Sports Watch app and forwards them to Strava and the training diary, the same way
the Android Companion (`../Nordic Sports Companion`) does.

## Status

**Release plan (2026-10-20):** no version 1 for now. The watch app is a beta listing in the Connect IQ Store, the Android Companion a test version in Google Play and the iOS Companion a TestFlight build. All stay 0.9.x while they are stabilised with testers. See `Nordic Sports Watch/testing/release-gate.md`.

The app is in TestFlight (marketing version 0.9.118; the build number says which
Companion state it holds). Android parity is tracked row by row in
[docs/feature-parity.md](docs/feature-parity.md); plan and history in
[docs/ROADMAP.md](docs/ROADMAP.md).

## Architecture

One product, two platforms, one business-logic codebase:

- Platform-neutral logic (watch payload, diary write-back, HR-zone intensity, Strava
  matching and titles, sync rules, database schema and migrations) lives in the
  Companion repo's Kotlin Multiplatform `shared` module.
- This repo holds the SwiftUI app (`App/`) and the platform adapters: watch link
  (Connect IQ Mobile SDK, `spikes/watch-link/`), sign-in, file access, background work,
  keychain, notifications. It consumes `shared` as an XCFramework built from Companion
  `main`.
- The Xcode project is generated from `project.yml` (XcodeGen); never edit it by hand.

## Building

- No local Mac: builds run on GitHub Actions macOS runners and reach the iPhone through
  TestFlight. Start and follow a build with `python -X utf8 tools/testflight.py
  start | status | wait | errors`; push the Companion first, the workflow builds its
  `main`. Secrets, expiry dates and the macOS-minute budget: [docs/testflight-ci.md](docs/testflight-ci.md).
- Shared logic is tested on Windows through the Companion's JVM tests
  (`:shared:testAndroidHostTest`); iOS-only Kotlin compiles with
  `gradlew.bat :shared:compileKotlinIosArm64`.
- Device test plan: `spikes/watch-link/README.md`.
