# Nordic Sports iOS Companion

The iPhone version of the Nordic Sports Companion. It receives activities from the
"Nordic Sports" Garmin Connect IQ watch app and forwards them to Strava and the TTB
training diary, the same way the Android Companion (`../Nordic Sports Companion`) does.

## Status

Planning only. This folder holds the iOS app container, the design notes and the
feasibility spikes. No Xcode project exists yet.

- Roadmap and logical steps: [docs/ROADMAP.md](docs/ROADMAP.md)
- Feasibility spikes (throw-away code, one folder per spike): `spikes/`

## Guiding decision (proposed, not yet confirmed)

One product, two platforms, **one business-logic codebase**:

- The platform-neutral logic of the Android Companion (watch payload, TTB write-back,
  HR-zone intensity, Strava matching and titles, sync rules, database schema) moves into
  a **Kotlin Multiplatform `shared` module** in the Companion repo.
- Android and iOS consume the same `shared` module. Only platform integration is written
  twice: watch link (Connect IQ Mobile SDK), sign-in flows, file access, background work,
  secure storage, notifications.
- This project holds the iOS app and its platform adapters. It builds against the
  `shared` framework produced by the Companion repo.

## Prerequisites (once work starts)

- A Mac with Xcode (or a cloud Mac / macOS CI runner). iOS apps and the Kotlin/Native iOS
  targets cannot be built on Windows. Shared logic can still be written and unit-tested on
  Windows via the JVM tests.
- An Apple Developer Program membership (TestFlight, App Store, Universal Links, Keychain
  sharing).
- Garmin Connect IQ Mobile SDK for iOS, and Garmin Connect Mobile installed on the test
  iPhone.
