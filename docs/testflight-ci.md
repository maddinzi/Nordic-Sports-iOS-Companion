# TestFlight CI: secrets, certificate, budget

Moved out of the workspace `CLAUDE.md` (2026-10-27). Never print or commit any of these values.

## Workflow
`.github/workflows/ios-testflight.yml`, started on `main` with `python -X utf8 tools/testflight.py start` (GitHub API with the login from git's credential manager; no `gh` on the Windows PC) or by hand (Actions › iOS TestFlight › Run workflow). `tools/testflight.py status`, `wait` and `errors [run_id]` show the result and a failed run's `error:` lines. It checks out Companion `main`, builds the `NordicSportsShared` XCFramework, archives and uploads to TestFlight. The build number is the run number. Push the Companion before starting a run.

Signing is manual: each run creates the App Store profile "Nordic Sports Companion App Store CI" through the API, so no registered device is needed.

## Xcode
The step "Xcode version" selects the newest released Xcode on the runner image (`/Applications/Xcode_<n>.app`, betas and release candidates skipped), not the image default, and prints the iOS SDK. The workflow input `xcode` pins one (e.g. `26.6`) if a new Xcode breaks the build. **Deadline (ITMS-90725, mail on build 68):** from April 2027 App Store Connect accepts only uploads built with the iOS 27 SDK (Xcode 27) or later. As long as the image has no released Xcode 27, the run shows a warning annotation. Before April 2027, check that a run says "iOS SDK 27"; if the `macos-26` image still has none, move `runs-on` to the image that has it (GitHub's runner-images README lists the Xcodes per image). A new Xcode may need a newer Kotlin for the shared XCFramework (Kotlin/Native names the Xcode versions it supports).

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
The entitlement `com.apple.developer.devicecheck.appattest-environment` is commented out in `project.yml` while store security is dark; the capability is enabled on the App ID. Enable the entitlement together with `APP_ATTEST_REGISTRATION_ENABLED: YES` when registration goes live. Checklist for that: `docs/app-attest-setup.md`.
