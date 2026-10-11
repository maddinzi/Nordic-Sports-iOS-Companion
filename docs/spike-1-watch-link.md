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
- **App swiped away, and after an iPhone restart (test plan step 7).** The log has one
  `launch` line only, so iOS never started the app for watch data. That case is the
  important one for an app that is closed most of the time.
- **A longer background stay.** 1.5 minutes is short; iOS suspends apps after a while.
- **The notification** for data that arrives in the background is not in the log; the
  athlete's report says it worked.

## Decision
**Go** for the watch link on iOS with the app open or recently used. That covers the
normal flow: the watch keeps an activity queued until the receipt, so a late hand-over
loses nothing. Whether iOS wakes a closed app stays open (step 7). If it does not, the
iOS Companion receives activities when it is opened, and says so in its texts.

Follow-ups for the real adapter (step 2.6c, `WatchEventSource` / `WatchSettingsTransport`
on iOS): take the app version from the payload, not from the SDK status; keep both app ids.
