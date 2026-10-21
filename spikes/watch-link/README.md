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

## Build 18 additions (edit, review, diary clouds, delete my data)

23. Open an activity › pencil: change name, training type, RPE, feeling, diary comment,
    duration or distance › Save. The detail shows the new values; with the diary connected
    and automatic writes on, the diary entry is rewritten (Settings › Last sync).
24. With interaction mode "interactive" (set on Android, or the default), a new watch
    activity shows "Review activity": Save it or "Skip review"; either releases the diary write.
25. Add by hand (Strava connected): Settings › Last sync shows "looking up", then "linked"
    to the same Strava session, or a new manual Strava activity; then the diary write.
27. **OneDrive:** Settings › Diary › "Athlete's Diary connections" › OneDrive › "Sign in to
    OneDrive" (Microsoft's sheet; allow the access). Paste the OneDrive sharing link of the
    diary folder (as on Android) › Connect. It shows "Active"; then "Write the last 7 days".
    The entries must appear in the workbook on the PC. This replaces the Files-app route for
    OneDrive, which iOS opens read-only.
28. **Dropbox and Google Drive:** the same with a test copy of the workbook: sign in, paste
    the folder link (Dropbox also takes a path such as "/TTB") › Connect, then "Make active"
    and write once. Switch back to OneDrive with "Make active" afterwards.
29. **Choosing a file:** paste a folder without a TTB subfolder: one workbook asks
    "Use this workbook?", several show a list to pick from.
## Build 19 additions (data fields, plans and routines, and the 0.9.90-0.9.95 watch features)

31. Needs a watch app with data field sync (0.9.90 or later, full version). Open Nordic Sports on
    the watch once, then Settings › Watch settings › the watch › "Data fields": Rollski, XC
    Skiing, Running (two screens each) and Training (one screen) show the watch's fields.
    Change one field › "waiting" until the watch confirms; on the watch the technique menu ›
    Data fields shows the new field. Change one on the watch: the phone shows it after the
    watch's next report.
32. **Interval plans and strength routines:** Settings › Watch settings › the watch ›
    "Interval plans": the three slots show the watch's plans ("4x 4:00 / 3:00"). Open one,
    change work or reps (or "Start from" a built-in plan) › Save: "waiting", then confirmed
    after the watch app has been open; on the watch the plan shows the change. The same
    for "Strength routines": add an exercise, change sets, weight, remove one, Save. Clear
    a slot once and check it is empty on the watch.
33. **Settings sync line:** Settings › Watch settings › the watch: under "Ask the watch again" a
    line shows the last message ("Sent to the watch · 14:05", "Received from the watch", or
    "Not sent" with the reason). Change a setting with the watch app closed: "Sent", then
    "Received … applied your change" once you open the app on the watch.
34. **Heart rate sensor:** with a chest strap paired to the watch, start an activity on the
    watch (GPS wait screen) and go back: the watch's page shows "Heart rate sensor" with the
    strap's status, check time and details (name, model, battery for an ANT+ strap).
35. **Recording on the watch:** start a recording on the watch, then open Activities on the
    iPhone: a card "Recording on <watch>" with the activity, start time and running time.
    Save it on the watch: the card goes and the activity arrives. Start one and discard it:
    "Discarded on <watch>" for 15 minutes.
36. **Nickname:** Settings › App › "Your nickname": type a name, press Return. A watch with
    0.9.90 or later gets it with the next settings exchange and greets you after saving. The
    feedback form offers "Include my nickname".
37. **Review new activities:** Settings › App: switch it off. The next watch activity needs
    no review and goes to the diary at the next sync; switch it on again afterwards.
38. **Feedback watch:** Settings › My Data › Send feedback with "Watch" or "Both": "Which
    watch?" lists the watches seen in activities and settings reports.
39. **Resend on reconnect:** with an activity still queued on the watch (Bluetooth off on
    the phone while saving), turn Bluetooth on: within seconds the transfer log shows
    "connected again: asked to send what it still has queued", and the activity arrives.
40. **Crash card** (only if the watch app ever closes unexpectedly): Activities shows "Your
    watch app closed unexpectedly"; Review lists exactly what would be sent; Send or Not now.

## Build 20 additions (duplicate merger, strength description, notifications, background sync)

Build 20 also brings everything from build 19 (steps 31-40), so test both on build 20.

41. **Update first:** install build 20 over build 19 without deleting the app. Activities,
    Strava and the diary are all still there (the database moves to version 30, the diary
    destinations of Android 0.9.96). Sync now works as before.
42. **Duplicate merger:** an activity that is on Strava but not from the watch (recorded with
    the Strava app, say) shows as its own row after a sync. "Add activity by hand" for the
    same session (same start, same length): afterwards there is one row, linked to Strava,
    and Settings › Last sync says "Merged an existing entry for Strava activity …".
43. **Strength description:** a Strength or Stabi activity with sets logged on the watch: once
    its Strava copy is linked and retitled (sync), the Strava description shows the block
    "Strength (Nordic Sports)" with the exercises and "n sets · kg". Your own description
    text stays; a second sync adds nothing.
44. **Notification:** app in the background (home screen), save an activity on the watch: a
    notification "New … activity ready for you to update" ("Anna, your new …" with a
    nickname; "… arrived" with Review new activities off). In automated sync mode the
    diary is written right away.
45. **Sync mode:** Settings › App › Sync mode › Manual: opening the app and a new activity
    no longer sync on their own (Sync now still does). Switch back to Automated.
46. **Background sync:** Background App Refresh on, Low Power Mode off, app left in the
    background for some hours. The Diagnostics log shows `bg: refresh task ran …` followed
    by `bg: refresh sync: synced (n lines)`; iOS decides when (often only at night or
    while charging).

## Build 21 additions (Strava branding and Strava data retention)

Build 21 carries everything of builds 19 and 20 too.

47. **Update:** install over the previous build; the database moves to version 34, nothing is lost.
48. **Branding:** Settings › Strava shows the orange "Connect with Strava" button (when not
    connected) and the "Powered by Strava" logo. An activity linked to Strava shows its
    Strava title, an orange bold underlined "View on Strava" (English in every language; it
    opens the Strava app, else Safari) and the logo.
49. **Deleted on Strava:** delete a linked test activity on Strava, pull Sync on Activities a
    few times over the next 1-2 days (the check runs at most every 8 h and waits 24 h): a
    Strava-only row disappears, a watch row loses its link and shows "Strava data removed on
    …"; its activity log and the app log say why. The diary entry stays.
50. **7-day rule:** a Strava-linked activity nobody touched for more than 7 days loses its link
    the next time the app opens (same note and log lines); a rollerski import that came only
    from Strava disappears. Watch data and diary entries stay.
51. **Disconnect Strava (near the end, before 30):** Settings › Strava › Disconnect Strava: the
    question says the Strava data is deleted. Confirm: an alert lists what was deleted and that
    the access was revoked at Strava. All Strava links are gone; reconnect with the orange button
    and pull the last 7 days to get them back.

52. **Access withdrawn on Strava (optional, after 51 and reconnecting):** on strava.com ›
    Settings › My Apps, revoke Nordic Sports. Open the app and pull Sync (it may take until the
    next token refresh, up to 6 hours): an alert says Strava access was withdrawn and the Strava
    data was deleted; after OK it does not come back. Reconnect with the orange button.

## Build 33 additions (feedback button, activity type names)

53. **Feedback button:** Activities has a speech-bubble button next to Sync; it opens the
    feedback form (Settings › Privacy › Feedback still works too). Send a short test message:
    it now arrives ("Thank you!"); builds before 33 always said "Couldn't send". Check the
    form: hint text in the empty message, a "n / 4000" counter, Send stays off below 3
    characters and for an e-mail like "a@b."; "Watch app" shows "Which watch?" with "Other
    watch" and a model field; the details list every line that is sent (Companion, phone, iOS,
    language, watch lines). Send a watch crash report too, if the card shows.
54. **Add by hand:** "+" › Activity type lists real names in the app language ("Rollski
    Skating", "Laufen", …), no `@string/…`. Save one: its name in the list and the diary is the
    real name. Activities added by hand before build 33 keep the `@string/…` name: rename or
    delete them.
55. **Activity detail texts (app in German):** an activity on Strava shows "View on Strava"
    in bold orange, underlined, next to the Strava logo (no `strava_view_on_strava`); it opens
    the activity. "Tagebucheintrag" starts with "Diese Werte kommen in dein
    Trainingstagebuch." and names the workbook in plain text, not tinted like a link. A row
    imported from Strava shows "Sportart: Laufen" (not `strava:run`). Feedback › App shows
    "Companion" for the third choice.

30. **Delete my data (last, it empties the app):** export first if you want the data,
    then Settings › My Data › Delete my data › confirm. Activities and logs are empty
    (the app log starts with "data deleted"), Strava and the diary show "not connected",
    Strava's "My Apps" no longer lists Nordic Sports, watch settings are empty until the
    watch reports again, and On My iPhone › Nordic Sports has no `diary-backups`. The diary
    workbook itself is unchanged. Reconnect Strava and the diary afterwards.

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
