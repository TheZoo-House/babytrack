# Version 1 contracts

The JSON catalog and snapshot fixture are consumed by Node and bundled in the
Swift package. `scripts/check-contracts.py` rejects resource drift.

All timestamps are Unix seconds. Entity IDs and operation IDs are stable client
UUIDs. A record has `type`, `childID`, `title`, `at`, optional `end`, fixed
string `fields`, a server `version`, `updatedAt`, `actor`, `detail`, and derived
`scheduled`. Types are fixed in the catalog. Unknown JSON fields are tolerated
by Swift; required version-1 fields remain mandatory.

- `GET /health` reports service and contract readiness.
- `GET /v1/catalog` returns the fixed catalog.
- `POST /v1/auth/challenge` issues a nonce. The native Apple request uses its
  SHA-256 hex digest. `POST /v1/auth/apple` verifies the identity token and
  consumes the original nonce once, returning a session and snapshot.
- `POST /v1/auth/preview` exists only when preview is explicitly enabled and
  creates a new isolated synthetic family.
- `GET /v1/snapshot?timeZone=…` returns family-scoped records, members and local-day
  summaries. Server owns unit-normalized totals, location paths, age, event
  descriptions, scheduled state and shared sleep arbitration.
- `POST /v1/sync` accepts at most 50 commands with `id`, `action`, `entity` and
  `baseVersion`. Each command runs in an SQLite transaction. Accepted operations
  are idempotent per family/user/operation. Stale edits return `conflict` and
  load the latest record; invalid changes return `rejected` and remain in the
  client's queue for recovery. In-flight acknowledgments cannot erase newer
  local operations. `sleepStart` arbitrates one active sleep per child;
  `sleepStop` is idempotent so any caregiver can end the shared session.
- `POST /v1/invites` creates a single-use code; `/v1/invites/join` consumes it.
  The app shares a `babytrack://join?code=…` link; codes can also be pasted.
- `POST /v1/devices` registers opt-in alert, push-to-start and per-session
  ActivityKit tokens. Tokens and environments are device-scoped. Relay retries
  preserve per-recipient acknowledgments and ignore superseded jobs.
- `GET /v1/books/lookup?isbn=…` queries Open Library, with manual entry on failure.
- `GET /v1/export` returns the current family snapshot.
- `POST /v1/auth/logout` revokes the session. Sign-out disables the device's
  remote notifications before removing its local credentials.
- `POST /v1/account/delete` removes the account and device registrations.
  Family records remain for other members; the last member deletes family data.

Node tests cover isolation, identity token validation, nonce reuse, invitations,
idempotency, stale writes, concurrent sleep, field validation, references,
location cycles, midnight/DST summaries, relay payloads and retry deduplication.
Swift tests cover decoding, durable queue recovery, conflicts, rejected changes,
atomic shared writes and preservation of corrupt files. UI tests create
synthetic state and exercise bottle/diaper entry, sleep, inventory creation and
app-to-backend sync; screenshots cover iPhone and iPad.

Physical-device Apple sign-in, camera scanning, remote APNs delivery and external
TestFlight availability require real device/Apple-service checks. Simulator tests
are not proof of those capabilities.
