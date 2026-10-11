# First iOS Companion: test plan (roadmap step 4)

The app now has three tabs: **Activities**, **Settings** and **Diagnostics** (the spike
screen below). Activities from the watch are stored by the shared Kotlin core, linked to
Strava and retitled there, as on Android.

1. Settings > Watch: the watch from the spike is still selected (else "Choose watch in Garmin Connect").
2. Settings > Strava > **Connect Strava**: Strava's page opens inside the app; after
   "Authorize" it returns to the app and shows "Strava connected". (If it stays on a
   blank page instead: the return link didn't reach the app - tell me.)
3. Record a short watch activity with the app open: it appears under Activities, and the
   watch shows "Received". The Diagnostics log has "activity from ...: stored" and the receipt.
4. Wait until the activity is on Strava, then pull to refresh on Activities (or reopen the
   app): it gets the link symbol, and its Strava title becomes the watch title (e.g.
   "Rollski Skating Ausdauer"). Settings > Last sync shows what happened.
5. Settings > "Pull the last 7 days from Strava": older Strava activities appear, linked
   to watch activities where they match.
6. Open an activity: date, duration, distance, heart rate, zones, the Strava link.
7. Share the Diagnostics log afterwards (into `logs/`).

## Build 16 additions: receipts and the diary (roadmap step 5.1)

8. **Receipts:** the watch's backlog of older activities arrives once more and then stops.
   The watch's About › DOWN log shows `receipt` and `removed` for each one, and those
   activities no longer come back after the next watch app start.
9. Settings › Athlete's Diary › **Choose diary workbook**: pick the TTB workbook in
   Files (OneDrive, iCloud Drive or On My iPhone). After "Connecting…" it shows
   "Connected to "<file>"". A file that is not a TTB workbook is refused, with the reason.
10. Settings › **Write the last 7 days to the diary**: Last sync lists the pending
    activities, the backup, "written …" for each, and the upload. Then open the workbook
    in Excel: the entries are there, as Android writes them.
11. Activities: written activities show a green book. Open one that isn't written yet:
    **Push to Diary** writes just that one.
12. In Files › On My iPhone › Nordic Sports › diary-backups there is a copy of the
    workbook from before each write (newest 30).
13. Quit the app and reopen it: the diary stays connected, and the next sync writes new
    watch activities without picking the file again.

## Build 17 additions (roadmap 5.3, 5.4, 5.6 and fixes)

14. **Diary on OneDrive:** pick the workbook once (no third try), "Write the last 7 days".
    If the write is refused again, Diagnostics now says why ("write failed: … writable …").
15. **Watch settings:** open Nordic Sports on the watch once, then Settings › Watch settings
    lists its settings. Change one (e.g. Auto pause): "Waiting for the watch", then
    confirmed after the watch app has been open. Diagnostics shows "settings to …: success".
16. **Add by hand:** Activities › + › type, duration, "Ended now" › Save. It appears in the
    list; the next sync writes it to the diary.
17. **Delete:** open an activity › Delete. Message says whether it is still on Strava and
    whether the diary entry went too. It does not come back after the next sync.
18. **History:** activity › "Activity history" shows inserted/linked/written lines.
19. **Logs:** Settings › Data logs: diary log, app log (Strava/diary connected, settings),
    watch transfer log (arrivals, receipts, settings).
20. **Export my data:** Settings › My Data › Export, then share/save the JSON file.
21. **Feedback:** Settings › My Data › Send feedback; it reaches the admin console.
22. Diagnostics: each "app in foreground" line now shows the Background App Refresh state
    and Low Power Mode.

## Build 18 additions (edit and review)

23. Open an activity › pencil: change name, training type, RPE, feeling, diary comment,
    duration or distance › Save. The detail shows the new values; with the diary connected
    and automatic writes on, the diary entry is rewritten (Settings › Last sync).
25. Add by hand (Strava connected): Settings › Last sync shows "looking up", then "linked"
    to the same Strava session, or a new manual Strava activity; then the diary write.
24. With interaction mode "interactive" (set on Android, or the default), a new watch
    activity shows "Review activity": Save it or "Skip review"; either releases the diary write.

# Spike 1: watch link (throw-away)

Question: does the Connect IQ iOS SDK (`garmin/connectiq-companion-app-sdk-ios` 1.8.0)
give the Companion what it needs from the watch? For now the TestFlight app *is* this
spike: one screen with the selected watches, three buttons and a log that survives app
restarts (newest first, share button top right).

What it does:
- **Choose watch in Garmin Connect** opens Garmin Connect Mobile (GCM); the selection comes
  back through the URL scheme `nordicsports-ciq` and is stored.
- Listens to both watch app ids: `public` (b6fcbabd-…) and `preview` (fc04cefc-…).
- Answers every activity that carries `"rx": 1` with `{"type": "receipt", "startTime": …}`,
  as the Android Companion does (`Nordic Sports Watch/guides/companion-handover.md`).
- **Ask the watch for its settings** sends `{"type": "settings"}`.
- **Check watch app versions** shows which of the two ids is installed.
- Logs whether the app was in the foreground or the background when something arrived, and
  posts a notification for anything that arrives while it is not in the foreground.
- Bluetooth background mode and Core Bluetooth state restoration are on, so iOS may wake
  the app for watch data.

## Test plan (iPhone with Garmin Connect, paired to a test watch)

1. Install the build from TestFlight, open it, allow notifications and Bluetooth.
2. **Choose watch** -> select the watch in Garmin Connect -> back in the app the watch shows
   with its status (`connected`).
3. **Check watch app versions**: the installed id answers with its version.
4. **Ask the watch for its settings** with the watch app open: a `settings` message arrives.
5. Record a short activity, app in the **foreground**: `received activity`, then
   `receipt … success`; the watch summary shows "Received".
6. Same with the app in the **background** (home screen, a few minutes).
7. Same after **swiping the app away** (closed), and once after a phone **restart** without
   opening the app.
8. Share the log (share button) and send it over.

Findings go to `docs/spike-1-watch-link.md`: what arrived in which state, delays, whether
receipts and the settings exchange work, and a go / no-go.

## Also in this app: spikes 2 and 4

**Spike 2, background (`spikes/background/`).** The app asks iOS for an app refresh task
(earliest every 15 min) and a processing task (earliest every hour, with network) and logs
every run as `bg: ... task ran (N min since the previous one, app in background)`, plus
`app in foreground` / `app in background`. Nothing to press:
1. Check that Settings > General > Background App Refresh is on (the log's first `bg:` line
   says it too).
2. Install, open once, then use the iPhone normally for a day or two (the app may stay
   closed). iOS learns from usage, so the first day says little.
3. Share the log. Findings: how often iOS ran the tasks, at what times, and whether any ran
   while the app was swiped away.

**Spike 4, diary workbook from the Files app (`spikes/diary-file/`).** Uses a *copy* of a
TTB workbook (never the real diary for now):
1. Put a copy into the Files app (iCloud Drive, On My iPhone, or the OneDrive app).
2. "Open diary workbook" and pick it: the section shows zip parts, worksheets, the number
   of diary entries with first and last date, the disciplines, the timings, and whether the
   re-written workbook reads back identical. Compare the entry count with the Android app.
3. Close the app (swipe away), open it again, "Read again (remembered workbook)": shows
   whether iOS keeps the access to the file.
4. "Save re-written copy", save it next to the original, open it in Excel (on the PC):
   it must open without a repair prompt.
