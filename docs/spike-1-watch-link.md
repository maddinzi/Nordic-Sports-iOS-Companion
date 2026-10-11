# Spike 1: watch link on iOS, findings

Tested 2026-10-11 on the iPhone 12 (TestFlight build 14, Connect IQ iOS SDK 1.8.0) with a
fenix 6X Pro (firmware 28.02, Nordic Sports 0.9.86 sideload, Preview id). Evidence: the
spike's log from that session (16:12 to 16:41), kept locally, not committed (it has GPS
positions).

## What worked
| Check | Result |
|---|---|
| Device selection through Garmin Connect (URL scheme round-trip) | OK, the watch came back and showed `connected` within a second |
| App status for both ids | Preview `installed`, public `not installed`: correct. The SDK reports version `0`, while the payload says 0.9.86, so take the version from the payload |
| Settings request | `success`; the snapshot arrived (full `v` block, same keys as on Android). A second snapshot arrived later with the app in the background |
| Activity, app in the foreground | Received, receipt `success` about 1 s later |
| Queued activity from the day before | Delivered on connect, receipt `success`: the watch queue flushes to iOS |
| Activity, app in the background (about 1.5 min) | Received in the background, receipt `success` 2 s later |
| Payload | Same JSON as on Android (schema 1, `rx`, HR zones, position, device info), so the shared parsing applies as is |

## Not yet shown
- **App swiped away (test plan step 7), second session 16:54 to 17:00: no delivery.** An
  activity recorded while the app was swiped away never arrived, and nothing came when
  the app was opened again. Expected on iOS: an app the user swipes away is not started
  again for background events until the user opens it. The activity is not lost: the watch
  keeps it queued until the receipt and resends it at the next watch app start once the
  retry gap (15 min, doubling) has passed (`Nordic Sports Watch/guides/companion-handover.md`).
  Still to confirm: that this resend arrives, and what happens after an iPhone restart.
- **A longer background stay.** 1.5 minutes is short; iOS suspends apps after a while.
  A second session (16:42 to 16:54) shows watch connection events arriving 6 to 11
  minutes after the app went to the background, so iOS does wake it for the watch
  link; no activity was sent in that window.
- **The notification** for data that arrives in the background is not in the log; the
  athlete's report says it worked.

## Decision
**Go** for the watch link on iOS with the app open or recently used. That covers the
normal flow: the watch keeps an activity queued until the receipt, so a late hand-over
loses nothing. A swiped-away app receives nothing until it is opened, and then only once
the watch resends. The iOS Companion's texts must say so: leave the app in the background
rather than closing it, and open it to collect activities.

Follow-ups for the real adapter (step 2.6c, `WatchEventSource` / `WatchSettingsTransport`
on iOS): take the app version from the payload, not from the SDK status; keep both app ids.
