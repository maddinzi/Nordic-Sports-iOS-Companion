# Decision needed: translated texts on iOS and in `shared`

Status: proposal, 2026-10-10. Needed before roadmap 2.6c/2.6d (diary write flow, Strava
sync), which produce texts for logs and messages, and before the first iOS screens.

## The situation

- The Android Companion has about 1,000 texts in six languages (en, de, fr, it, rm, gsw)
  in `app/src/main/res/values*/strings.xml`, checked by `TranslationCompletenessTest`.
  Watch words come from the watch's `lang/*.txt` (`watch_labels.xml`) and must stay
  identical to the watch.
- Shared code has no texts of its own yet. Where it needs one, the platform passes it in
  through a small interface (`StravaWriteFailureTexts`, `WatchSettingsTexts`,
  `StravaAuthFallbackTexts`) and Android fills it from `R.string`.
- iOS has no texts yet. Its UI technology (SwiftUI or Compose Multiplatform) is decided
  after the MVP (roadmap step 4).

## Options

**A. Keep the text interfaces; generate the iOS strings from Android's `strings.xml`.**
Shared code keeps asking the platform for its texts. A small script turns the Android
files into an iOS String Catalog (`Localizable.xcstrings`) on CI, so there is one source
and one completeness test. iOS code uses `String(localized:)` as usual.
- For: no new library; each platform uses its native tooling; works with SwiftUI and
  with Compose; the Android app stays as it is.
- Against: every shared text needs an interface method (a few dozen for 2.6c/2.6d); the
  generator must map Android's `%1$s` and plurals to iOS's format (well understood).

**B. Compose Multiplatform resources in `shared`.** Texts move to
`shared/src/commonMain/composeResources/values*/strings.xml` and shared code reads them
directly (`getString(Res.string.…)`).
- For: shared code formats its own texts, no interfaces; natural if the iOS UI becomes
  Compose Multiplatform.
- Against: adds the Compose resources library to `shared` even if iOS uses SwiftUI;
  the Android texts would be split between `app` and `shared`; `getString` is a suspend
  call; the completeness test has to move.

**C. moko-resources.** A third-party library that generates Android and iOS resources
from one source.
- For: one source for both platforms, mature on Android/iOS.
- Against: one more Gradle plugin to keep in step with Kotlin and AGP updates (it has
  lagged behind Kotlin 2.x releases); little gain over A.

## Recommendation

**A**, now. It costs least, keeps every current check, and does not pre-empt the UI
decision. If the iOS UI later becomes Compose Multiplatform, moving the shared texts to B
is a contained step (the interfaces show exactly which texts move).

For the MVP, iOS needs English and German only; the other four languages come through
the same generator once the screens exist.
