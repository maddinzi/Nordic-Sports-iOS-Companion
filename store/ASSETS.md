# Assets used for the App Store listing

Paths are relative to the workspace root `C:\Users\marti\code\Nordic Sports`.

## App icon (comes from the build, not uploaded in ASC)

| Use | File | Size |
|---|---|---|
| iOS app icon / App Store icon | `Nordic Sports iOS Companion/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` | 1024x1024, text-free roller skier |
| Same art, Play / design system | `Nordic Sports Companion/design/play-store/icon-512.png`, `Nordic Sports Design/design-system/assets/Logos/app-icon-512.png` | 512x512 |
| Overview of all store and icon images | `Nordic Sports Shared/art/store-images-overview-0.9.109.png` | |

## Screenshots uploaded (iPhone with Dynamic Island, medium display, 1179x2556)

Sources: real TestFlight screenshots from 2026-10-22 (app 0.9.104), German UI, dark mode:
`Nordic Sports Webhook Server/work/screenshots-originals/iPhone/` (1170x2532). Website versions of the same shots: `Nordic Sports Webhook Server/public/assets/img/companion_iphone_*.jpg`.

| # | Uploaded file (`store/screenshots/iphone-6.3/de-DE/`) | Source | Shows |
|---|---|---|---|
| 1 | `01_aktivitaeten_1179x2556.png` | `20261022_184628000_iOS.png` | Activity list, "Alles erledigt" status card, sync badges |
| 2 | `02_detail_1179x2556.png` | `20261022_184643000_iOS.png` | Activity detail "Laufen Ausdauer", synced with Uhr / Strava / Swiss-Ski diary; place name blurred |
| 3 | `03_einstellungen_1179x2556.png` | `20261022_192459000_iOS.png` | Settings: watch, Strava, diary connections |
| 4 | `04_uhr_1179x2556.png` | `20261022_192520000_iOS.png` | Watch page (fēnix 6X Pro): data fields, intervals, strength routines |

Processing: scaled to width 1179 (LANCZOS), 5 px padded at the bottom, blur on the "Ort" value of #2 (`tools/make_screenshots.py`).

## Not used (and why)

- `Nordic Sports Companion/design/play-store/phone1.png` and the Android screenshots: Android UI, not allowed on the App Store.
- `feature-graphic-1024x500.png`, Connect IQ hero: title art only; Apple wants screenshots that show the app in use. Possible base for the optional header asset.
