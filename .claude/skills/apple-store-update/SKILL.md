---
name: apple-store-update
description: Update the App Store Connect product page of the Nordic Sports Companion iOS app (texts DE/EN, screenshots, subtitle, categories, version, build) from store/listing.json via the athlete's logged-in Chrome. Use for "App Store Texte/Screenshots aktualisieren", a new App Store version, or a listing check.
---

# apple-store-update

Fill or refresh the App Store Connect (ASC) listing of **Nordic Sports Companion (iOS)** from the files in `Nordic Sports iOS Companion/store/`. Never submit for review, never accept agreements, never fill legal declarations: those stay with the athlete.

## Files (source of truth)

| File | What |
|---|---|
| `store/listing.json` | All texts per locale (`de-DE` primary, `en-US`), app facts (ASC id 6821149470, URLs, copyright), review notes |
| `store/ASSETS.md` | Which icon and screenshots are used, with source paths |
| `store/README.md` | What is in ASC right now and the open points for the athlete. Update it at the end of every run |
| `store/screenshots/iphone-6.3/<locale>/` | Uploaded screenshots, 1179x2556 |
| `store/tools/make_screenshots.py` | Raw iPhone shots → ASC sizes, optional blur boxes |

Wording rules: `Nordic Sports Shared/glossary.md` (German **du**, "Einheit", "Trainingstagebuch", "fēnix" with macron). Facts: `docs/feature-parity.md` (only claim features that are in a TestFlight build), `Nordic Sports Companion/store/PLAY_STORE_LISTING.md` (Play wording), `Nordic Sports Webhook Server/public/privacy.html`.

## Steps

1. **Read** `store/README.md` and `store/listing.json`. Ask the athlete what changed (new build? new UI? new features?) unless it is clear.
2. **Texts**: edit `listing.json`. Check limits by script, never by eye:
   ```
   python -c "import json;d=json.load(open('store/listing.json',encoding='utf-8'));L={'name':30,'subtitle':30,'promotionalText':170,'description':4000,'keywords':100,'whatsNew':4000};[print(l,k,len(v[k]),'OK' if len(v[k])<=n else 'TOO LONG') for l,v in d['locales'].items() for k,n in L.items()]"
   ```
   - Keywords: comma separated, no brand names of others (Strava, Garmin): guideline 2.3.7. Words from the name need not repeat.
   - **No straight double quotes `"` in the description**: ASC answered HTTP 500 on save. Use “…” (EN) or „…“ (DE).
   - Remove "Beta/Testversion" sentences only when the athlete leaves the test phase; keep the pricing sentence.
   - Trademark block: only names that occur in the text (no Android/Google Play on iOS).
3. **Screenshots** (only when the UI changed): the athlete takes them on the iPhone (or TestFlight build), puts them in a folder, then
   `python store/tools/make_screenshots.py <folder> de-DE --blur x0,y0,x1,y1@<file>` (blur place names and other private details; the website did the same). Look at every result before upload. Only real iOS UI: no Android shots, no pure title art (guideline 2.3.3).
4. **Chrome** (Claude in Chrome, athlete already logged in to ASC). New tab, `https://appstoreconnect.apple.com/apps/6821149470/distribution/ios/version/inflight`. ASC is slow: wait 10-20 s after each navigation; "Sorry, something went wrong" on load usually disappears on a second load.
   - **Text fields**: React inputs. Set them with the native setter and fire `input` + `change` (ids: `promotionalText`, `description`, `keywords`, `supportUrl`, `marketingUrl`, `copyright`, `versionString`; review: `contactFirstName`, `contactLastName`, `contactPhone`, `contactEmail`, `notes`):
     ```js
     const set=(id,v)=>{const el=document.getElementById(id);const p=el.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(p,'value').set.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return el.value.length};
     ```
   - **Language**: the "German ⌄" menu top right of "Product Page Information" switches the locale; "Add English (U.S.)" etc. adds one. Save each locale separately.
   - **Save**, then confirm with `read_network_requests` (pattern `Localizations/`): PATCH 200 = saved, 500 = content problem (split the fields to find it). A red Save button means a field error: read `main.innerText` for "This field is required".
   - The review section blocks the whole page save once any contact field is filled: name, e-mail **and phone** are all required. Leave it empty if the phone is unknown.
   - **Screenshots**: tab "App Previews and Screenshots", device "iPhone with Dynamic Island (medium display)". Upload with `file_upload` to the first `input[type=file]`; the file must be in a path the extension may read: commit to the device folder, then `device_stage_files` it and upload from `/mnt/user-data/uploads/...`. Dismiss the info dialog (OK). Wait until all thumbnails render before Save (processing takes up to a minute; saving earlier fails).
   - **App Information** (`/distribution/info`): `subtitle` per locale, `primaryCategory` / `secondaryCategory` (selects, values like `SPORTS`, `HEALTH_AND_FITNESS`).
   - **Build**: only on the athlete's word. Set `versionString` to the build's `MARKETING_VERSION` (release plan: 0.9.x, no 1.0) and save first, then "Add Build". The app icon comes from the build (`App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`); ASC has no icon upload.
   - Reload and verify every value you set (`.value.length` per id, screenshot count "N of 10 App Screenshots").
5. **Leave alone**: Add for Review / Submit, App Privacy data types, age rating, content rights, pricing, EU trader status, agreements. List them as open points.
6. **Record**: update the state table and open points in `store/README.md`, `store/ASSETS.md` for new images, and commit nothing unless the athlete asks.

## Gotchas seen

- 2026-11-03: EN description with `"Delete my data"` → PATCH 500; curly quotes fixed it.
- Uploading 4 screenshots at once: the first Save failed while 3 were still processing; Save again after the thumbnails appear.
- Adding a build while the version string (1.0) differs from the build (0.9.115) broke the page load; set the version string first.
