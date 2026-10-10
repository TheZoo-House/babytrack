# Babytrack

Native iPhone and iPad family baby tracker. The display name is provisional.
Change `APP_DISPLAY_NAME` in `app/Config/Brand.xcconfig` to rename the app;
keep bundle and app-group identifiers stable to preserve accounts and data.

The app includes formula, breast-milk and mixed bottles, diapers with color and consistency, sleep and
nap timers, reading, growth measurements, medication, temperature, illness,
vaccines, milestones, appointments, notes and photos. The library holds books
with ISBN lookup and gift givers, toys with age ranges, clothing, and nested
locations. All caregivers can edit. Apple is the only real-account login.

Today keeps direct logging actions above expandable care histories and shows
the time since each latest record. Journal shows totals for past days and can
share a date-range care report as CSV or PDF. Family has a caregiver handoff
for changes since the last check. Medication records support Log again with
the previous dose and unit. Reminders support Done, Snooze, Only me, and an
interval after the last matching bottle or medication log. Nursing is excluded.

`Try sample family` opens isolated synthetic data. It connects to the test
backend when available, or saves sample records on the device when offline.
Real and server-backed sample families use server-computed totals. Sample
identities cannot join real families. Standard builds contain only synthetic
sample data. An explicitly requested owner build can bundle a private local
sample through `scripts/archive-owner`; this resource never enters Git, CI or
the anonymous sample endpoint.

## Nara import and voice logging

Open Settings → Account & data → Import Nara Baby after signing in. Choose the
CSV export and either create its child profiles or map a single profile to an
existing child. Review counts, already imported records and warnings before
Import. Original values, units, notes, time zones and caregiver attribution are
retained. Missing amounts and dose units stay unknown. Re-importing skips both
saved and deleted source records and cannot overwrite edits or add caregivers.

Spotlight shows care shortcuts when searching for the app. Siri phrases include
"Log a bottle in Babytrack", "Log a wet diaper in Babytrack", "Start sleep in
Babytrack", "End sleep in Babytrack", "Log medication in Babytrack", "Log a
temperature in Babytrack" and "Log a measurement in Babytrack". Siri prompts for
required parameters; the child picker uses the selected child when available.
Records enter the same durable offline queue used by the app and widgets. Open
the app to sync queued records when connectivity returns.

To prepare a private owner sample from a user-authorized export:

```sh
node scripts/owner-preview.mjs /private/export.csv "$HOME/.local/share/babytrack/imports/OwnerPreview.json"
scripts/archive-owner
```

That archive contains personal data. Keep it in the owner's private delivery
channel. Normal `scripts/archive` and CI exclude it.

## Develop

Open `app/Babytrack.xcodeproj` in Xcode, or regenerate it with:

```sh
xcodegen generate --spec app/project.yml
scripts/check
scripts/test-ios
```

The app and widgets use `BabyCore` for models, shared storage and queued
operations. `contracts/catalog.json` defines fixed forms and validation fields;
edit `scripts/generate-catalog.py`, run it, and check both consumers. Synthetic
contract fixtures are generated with `node scripts/generate-fixture.mjs`.
`scripts/check` verifies generated snapshots, details, summaries and Live Activity
payloads against both consumers. Test-only fixtures are not bundled in releases.
On a fresh Mac or CI runner, run `scripts/setup-ios-test-pool` before native tests.

The test wrapper leases a shared simulator and starts its own disposable HTTP
backend. Tests do not use real Apple logins, deployed data or APNs credentials.
Runtime screenshots and build artifacts stay in ignored `.codex-tmp/`.

## Backend

Requires Node 24 or newer. No third-party runtime packages are needed.

```sh
PREVIEW_ENABLED=1 DATABASE_PATH=./data/babytrack.sqlite node server/main.mjs
```

The current Mac test deployment runs at
`https://devapps.thezoo.house/babytrack-api`. `scripts/start-server` is installed
as the `house.thezoo.babytrack.backend` LaunchAgent. Its database and logs are in
`~/.local/share/babytrack/`. `scripts/register-proxy.py` adds only the app's
path to the existing local Caddy server; rerun it if another service replaces
the active proxy configuration. No public DNS change is needed for testing.

For the NAS, `docker compose up -d --build` runs the backend and separate APNs
worker against a persistent SQLite volume. Point a Cloudflare Tunnel at the
backend, use HTTPS, and set the app's Connection URL. Keep preview disabled on
production. Protect the data volume and backup directory as child health data.
Use `scripts/backup-server` for a consistent SQLite backup, not a live-file copy.

The relay receives semantic sleep/reminder jobs and owns APNs credentials.
Set `APNS_KEY_ID`, `APNS_TEAM_ID`, and `APNS_KEY_PATH`; mount the key read-only.
Without a key the queue is retained and push delivery is paused. Foreground
family sync and on-device sleep activities work independently of APNs.

## Delivery

```sh
scripts/archive release-testing
scripts/archive app-store-connect
```

The first produces an owner-device IPA for DevApps, the second a TestFlight IPA.
Both use the existing Xcode account and automatic signing. CI validates the
Node backend/relay, matching contract files, Swift package, app and extension.
`CI Gate` aggregates the current commit's checks. Main and pull requests run CI.

TestFlight requires an App Store Connect app record with bundle ID
`house.thezoo.babytrack`, created through Apple's website. After that, upload the
App Store IPA with `xcrun altool` and the account's App Store Connect API key.
Configure beta descriptions and an internal group before an external group.
External testing requires Apple's beta review. Do not publish an App Store release
as part of a development delivery.

## Contracts and privacy

See [CONTRACT_TESTS.md](CONTRACT_TESTS.md) for the API and test coverage.
Sessions live in Keychain; queued records and photos use protected app-group
storage. The server verifies Apple signatures, audience, expiration and one-use
nonces, then issues revocable opaque sessions. Invitations are single-use and
expire. Every request and referenced entity is scoped to the signed-in family.
No analytics or advertising SDKs are included. Export contains records and
pending changes, never authentication credentials.
