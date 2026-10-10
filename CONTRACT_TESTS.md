# Version 1 contracts

Snapshot version 1 remains backward compatible. Catalog version 2 declares
type scope, title requirements, scheduling, measurement units, choice labels
and upload limits. Node and Swift consume the same catalog. Test fixtures live
under the test target. `scripts/check-contracts.py` checks mirrors and regenerated
fixture content, including details, day summaries and ActivityKit payloads.

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
- `GET /v1/import-source/<recordID>` returns original Nara columns for an active
  imported record in the current family. Normal snapshots omit these raw columns;
  full exports retain them. Private owner samples retain them for offline access.
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

## Nara and App Intents

The authenticated `/v1/import/nara/preview` and `/v1/import/nara/commit` routes
accept `csv`, `familyID`, optional `targetChildID`, and `timeZone`. Preview does
not write. Commit parses again inside one transaction and returns a fresh
snapshot. Stable source IDs are family scoped; existing imported records and
source mappings prevent duplicate children and overwriting edits. Historic
imports do not enqueue notification jobs or grant caregiver access.

Synthetic Nara fixtures cover quoted newlines/commas/emoji, epoch milliseconds,
zero-duration sleeps, unknown amounts/dose units, combined diaper values,
multiple measurements and vaccines, repeated imports, edits and family
isolation. The generated import snapshot also decodes through Swift BabyCore.
App/widget/intent actions share the locked `SharedStorage.record` path. Core
tests verify durable queues, invalid-child/value rejection, per-child formulas,
acknowledgement and explicit start/end semantics. Native UI tests exercise
custom formula reuse, CSV preview/commit and all settings screens. App Intents
metadata contains ten Spotlight shortcuts; physical Siri discovery is a device
verification boundary.

## Large care history responsiveness

The native `testLargeHistoryDropdownPerformance` benchmark expands and collapses
bottle history over 1,700 synthetic records and records application CPU usage.
Check its result with `scripts/check-ios-dropdown-performance <result.xcresult>`;
two toggles must use less than 500 ms of application CPU. This excludes XCTest
driver waits and catches repeated whole-history scans in selected-child lookup.
On hosted CI, `--relative` compares the 1,700-record case with a 24-record control
that has identical visible rows and actions on the same runner. Large-history
mean CPU must stay below 1.5 times the fastest control sample, so a noisy control
cannot inflate the budget. This separates history-dependent work
from the speed of a virtualized simulator; the local 500 ms budget still applies.
The app caches formatted records until data changes or the minute changes;
selection and summaries read draft records without formatting the whole history.
The filtered-history test also verifies that logging actions sit above the
disclosure rows. Personal exports are excluded from both tests.

## Direct care choices

Diaper `contents` remains Wet, Dirty, Both or Dry. The editor presents Wet and
Dirty independently and Dry exclusively. Color and consistency accept multiple
catalog tokens separated by spaces; imported unknown tokens remain editable.
Optional `blowout` and `rash` fields use the strings `true` and `false`. Legacy
`detail: Blowout` still renders as a blowout until an explicit flag overrides it.
An explicit editor change replaces that legacy flag while retaining original
export columns in `ImportSource`. Synthetic tests cover combined selections,
flag persistence, invalid values and reopening a server-saved diaper.

## Today totals and bottle reuse

Server summaries remain authoritative when current and no draft affects the
child. BabyCore projects the full visible records for local previews, pending
changes, active sleep and day rollover. Shared synthetic cases compare Swift
with the server across midnight, spring/fall DST, units and child isolation.
Today refreshes time-dependent values every minute. Bottle reuse copies the
latest known amount/unit pair only; unknown or other-child amounts are not
invented. A touched empty amount blocks saving until replaced.

## Caregiver actions and reminders

`updatedBy`, `updatedByID` and `createdAt` are optional server metadata; clients
cannot select the editing caregiver. Handoff cursors are device-local per child.
Snapshots include the previous seven local-day totals in `daySummaries`; older
or offline days use the same unit and interval-union projection.

`reminderDone` and `reminderSnooze` act on the named stored reminder. Snooze accepts
an epoch-second `entity.at` in the next seven days. `trigger: After last log`
uses `afterHours`, `kind` and optional `anchorTitle` to match feeding or medication
records. `recipients: Only me` assigns `recipientUserID` on the server. Edits by
another caregiver preserve that recipient. The relay drops stale jobs, bounds
transient retries, acknowledges permanent failures and keeps repeats anchored
to the original schedule. Notifications carry `BABYTRACK_REMINDER` and `recordID`.

Sync batches can include `familyID` to reject an obsolete household. Clients
discard acknowledgments from older sessions, and retry transport/database failures
without removing queued writes. Anonymous preview creation has its own rate limit
and expires old preview accounts. Real accounts remain separate.
