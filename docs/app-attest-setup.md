# App Attest: what to check and set up

For the store move on iOS (Companion `design/server-migration.md`): a TestFlight or App Store build
registers with the server using App Attest and the move's ticket. Nothing of this has run live yet.
This is the Apple counterpart of the Companion's `design/play-integrity-setup.md`, written so you can
work through it in the browser with Claude in Chrome.

Unlike Play Integrity, **the server needs no Apple secret**: it checks the attestation against
Apple's root certificate (`resources/Apple_App_Attestation_Root_CA.pem` in the Webhook Server) and
the fixed app id `6H79YB6QQS.me.maddin.nordicsports.companion` (`AppAttest::APP_ID`). Nothing goes
into `config.php` for Apple.

## 1. Apple Developer: the capability on the App ID

developer.apple.com › Account › **Certificates, Identifiers & Profiles › Identifiers** ›
`me.maddin.nordicsports.companion`.

Check: **App Attest** is ticked under Capabilities (it should already be, see `testflight-ci.md`).
If not: tick it and save. Nothing else on that page changes.

## 2. Signing profile

Nothing to do by hand. The TestFlight workflow creates the App Store profile "Nordic Sports Companion
App Store CI" through the API on every run, so it picks up the capability from step 1.

## 3. The build switches (in this repo, done by Claude on request)

Both together, in the release that opens the store move:
- `project.yml` › entitlements: un-comment
  `com.apple.developer.devicecheck.appattest-environment: production`.
- `project.yml` › settings: `APP_ATTEST_REGISTRATION_ENABLED: YES`.

TestFlight and App Store builds both use the **production** App Attest environment, which is the
only one the server accepts. A build with the switch on but without the entitlement fails on the
device with "device-check" in Diagnostics.

## 4. Server switches (shared with Android)

- `config.php`: `'accounts' => ['anonymous_registration_enabled' => true, 'registration_mode' => 'ticket']`
- `'migration' => ['stage' => ['ios' => 'pilot']]`, and the testers marked pilot in `admin_ui`.

Only once the privacy notice describing the anonymous account is live and the App Store privacy
details (App Store Connect › App Privacy) are updated: the install gets an anonymous account id and
an installation id, linked to the Strava athlete id.

## 5. How we know it works

1. A TestFlight build with steps 3 and 4 done, on the iPhone 12.
2. More › About › Migrate user with your iPhone address. Expected: "Status: Server". The server
   overview shows one more `install` athlete and one iOS installation.
3. If it fails: Diagnostics shows "App Attest registration with ticket failed (<code>)":
   - `device-check`: the entitlement is missing or the device refused (simulator, jailbreak)
   - `server-403`: the ticket was refused (expired or the stage is off)
   - `server-401`: the attestation failed on the server (app id, environment)
   - `server-503`: accounts are not switched on

## What to report back (no secrets)

- App Attest capability ticked: yes or no.
- The last TestFlight run green after the switch: yes or no.
