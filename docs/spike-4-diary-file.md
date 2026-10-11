# Spike 4: diary workbook from the Files app, findings

Tested 2026-10-11 on the iPhone 12 (TestFlight build 14) with a copy of a real TTB
workbook (`2627_TTB_D_MZ_Test_Large_.xlsx`, 1,332 KB). Only the Files-app part of the
spike; OneDrive (MSAL), Dropbox and Google Drive sign-in are not covered yet.

## Results (two reads, identical)
| Check | Result |
|---|---|
| Open via the Files picker, security-scoped access | OK (`scoped access true`) |
| Workbook structure | 263 zip parts, 61 worksheets |
| Diary entries (shared Kotlin TTB code) | 180, from 2026-04-27 to 2026-10-10, 14 disciplines (one entry without a discipline, `?`) |
| Read time | 6.1 to 6.4 s; once 14.1 s, right after a launch while the watch connection was being set up |
| Re-write (iOS zlib) and read back | 181 ms, every part identical |
| Save the re-written copy | OK; the athlete reports that it opened fine |
| Remembered workbook (bookmark) | Survives closing the app: resolved and read in two new app sessions (17:01, 17:03), no picker needed |

## Not yet shown
- **The entry count against the Android app** (180) and which entry has no discipline.
  The Android app must show the same count, and the same entry without a discipline.

## Decision
**Go** for TTB diary files on iOS through the Files app. The shared Kotlin code reads and
re-writes a full-size workbook on the iPhone without changes.

Follow-up: 6.3 s to read is slow. Measure the same workbook on Android. If iOS is much
slower, profile the XML parsing in the Kotlin/Native release build before step 3. The
cloud providers (OneDrive, Dropbox, Google Drive) are a later part of spike 4.
