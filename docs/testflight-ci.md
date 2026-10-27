# TestFlight CI: secrets, certificate, budget

Moved out of the workspace `CLAUDE.md` (2026-10-27). Never print or commit any of these values.

## Workflow
`.github/workflows/ios-testflight.yml`, started by hand (Actions › iOS TestFlight › Run workflow, on `main`). It checks out Companion `main`, builds the `NordicSportsShared` XCFramework, archives and uploads to TestFlight. The build number is the run number. Push the Companion before starting a run.

Signing is manual: each run creates the App Store profile "Nordic Sports Companion App Store CI" through the API, so no registered device is needed.

## Secrets (GitHub repository secrets)
- `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`: App Store Connect team API key, Admin role.
- `DIST_CERT_P12` (base64), `DIST_CERT_PASSWORD`: the team's Apple Distribution certificate.
- `COMPANION_READ_TOKEN`: fine-grained token, read-only Contents on the Companion repo only. **Expires 2027-10-11**: renew it and update the secret before then.
- `ONEDRIVE_CLIENT_ID`, `DROPBOX_APP_KEY`, `GOOGLE_IOS_CLIENT_ID`: the diary clouds' app ids for the PKCE sign-in, written into `Secrets.xcconfig`. A missing one hides that cloud in the app.
- The workflow exits 1 when the Strava id/secret or the webhook key is missing; the three cloud ids stay optional.

## Distribution certificate
Expires **2027-10-09**: make a new one before then and update both certificate secrets. Create key and CSR with openssl on Windows. Build the `.p12` with `-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`, because macOS cannot import OpenSSL 3's default `.p12`. Keep the local signing folder until a run is green, and compare the fingerprints the workflow prints before deleting it.

## Actions budget
Private repos on GitHub Free count macOS minutes ten times against 2,000 per month (90% used on 2026-10-11). `shared-ios.yml` is manual only: run it once per batch of iOS-relevant shared changes (iosMain, expect/actual, Room, new libraries). Start TestFlight only when a device test follows. Put `[skip ci]` in commits that touch workflow files.

## App Attest
The entitlement `com.apple.developer.devicecheck.appattest-environment` is commented out in `project.yml` while store security is dark; the capability is enabled on the App ID. Enable the entitlement together with `APP_ATTEST_REGISTRATION_ENABLED: YES` when registration goes live.
