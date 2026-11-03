# App Store listing: Nordic Sports Companion (iOS)

Working folder for the App Store Connect (ASC) product page. Texts live in `listing.json`
(source of truth, DE + EN), the chosen images are referenced in `ASSETS.md`, the uploaded
screenshots sit in `screenshots/`. Skill: `../.claude/skills/apple-store-update/SKILL.md`.

- ASC app: https://appstoreconnect.apple.com/apps/6821149470/distribution (Apple ID 6821149470)
- Bundle ID `me.maddin.nordicsports.companion`, SKU `nordicsports-companion-ios`, team `6H79YB6QQS`
- Primary language in ASC: **German**. Second localization: English (U.S.).
- iPhone only (`TARGETED_DEVICE_FAMILY: "1"`), so no iPad screenshots are needed.

## State in App Store Connect (2026-11-03, entered by Claude)

| Item | DE | EN (U.S.) | Notes |
|---|---|---|---|
| Name | done (already there) | done | "Nordic Sports Companion" |
| Subtitle | done | done | App Information page |
| Category | Sports (was set) + secondary Health & Fitness | | |
| Promotional text | done | done | |
| Description | done | done | EN: straight `"` caused HTTP 500 on save, uses curly quotes now |
| Keywords | done | done | no third-party brand names (guideline 2.3.7) |
| Support / Marketing URL | done | done | https://nordicsports.maddin.me |
| Copyright | done | (shared) | "2026 Martin Zisler" |
| Screenshots iPhone 6.1"/6.3" | 4 uploaded | inherits | real TestFlight screenshots (build 0.9.104), see ASSETS.md |
| Privacy Policy URL | was already set (DE) | check | https://nordicsports.maddin.me/privacy.html |
| Version string | 0.9.115 (was 1.0) | | release plan: everything stays 0.9.x; set to the build you attach |
| Build | **not attached** | | the athlete builds a new version first; the app icon comes from that build |
| App icon | from the build | | `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` |

## Open points for the athlete (not done on purpose)

1. **Build**: attach the new build (Version › Build › Add Build) and set the version string to its `MARKETING_VERSION`. The icon then appears in ASC.
2. **App Review contact**: first/last name, e-mail and **phone** are required before ASC saves the review section. The prepared notes are in `listing.json` › `review.notes`.
3. **App Privacy › Data Types**: currently "Data Not Collected". The app sends the Strava athlete id and notification ids to the Nordic Sports server and start coordinates to Apple's geocoder. Check against `privacy.html` and `../../Nordic Sports Companion/design/privacy-notice-sync.md` before submitting (your decision).
4. **Age rating questionnaire**, **Content Rights**, **Pricing and Availability**, **EU trader status (DSA)**: your declarations.
5. **Screenshots**: refresh with the new UI after the next build (4 to 6 screens; same names, rerun `tools/make_screenshots.py`). Optional English set.
6. **Header asset** (new ASC feature, 3840x1646 or 5244x2950): optional, not made yet. Source art: `../../Nordic Sports Shared/art/bro/bro_master_2048.png`.
7. "What's New" is not shown for the first App Store version; text is prepared in `listing.json`.
