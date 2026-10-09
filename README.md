# Babytrack

Native iPhone and iPad family baby tracker. The display name is provisional.
Change `APP_DISPLAY_NAME` in `app/Config/Brand.xcconfig` to rename the app;
keep bundle and app-group identifiers stable to preserve accounts and data.

The app includes formula bottles, diapers with color and consistency, sleep and
nap timers, reading, growth measurements, medication, temperature, illness,
vaccines, milestones, appointments, notes and photos. The library holds books
with ISBN lookup and gift givers, toys with age ranges, clothing, and nested
locations. All family members can edit. Apple is the only real-account login.

`Try sample family` opens isolated synthetic data. It connects to the test
backend when available, or saves sample records on the device when offline.
Local sample totals are labelled as sample totals. Real and server-backed
sample families use server-computed totals. Sample identities cannot join real
families. Do not store real child records in sample mode.

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
