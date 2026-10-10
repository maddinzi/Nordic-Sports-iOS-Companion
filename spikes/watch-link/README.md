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
