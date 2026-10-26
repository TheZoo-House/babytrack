# Babytrack

Native SwiftUI app in `app/`, dependency-free Node backend in `server/`, separate
APNs worker in `relay/`, shared machine-readable catalog and fixtures in `contracts/`.
Branding is configured in `app/Config/Brand.xcconfig`; internal identifiers stay stable.

Follow the user's selected scope. Kanvil project Babytrack uses keys `BABY-*`.
Track coherent work with native kind, difficulty, scopes and readiness, mirror
the required labels through the kanvil skill, and verify ticket readback. Use `<type>/BABY-<number>-<slug>` branches,
signed `BABY-<number>:` commits, and a changelog fragment per tracked change.
Keep main buildable. Publishing and delivery are authorized for the initial build;
merges and production releases require explicit authorization.

Find the shared chokepoint before repeating changes across call sites. App and
widgets share BabyCore; forms use the shared catalog. Server owns authorization,
validation, ordering, computed summaries and shared sleep arbitration. Clients
format values, render cached server state, retain offline drafts/commands and
integrate with platform APIs. Protocol edits validate both Node and Swift consumers.
Use synthetic disposable state in tests. Preserve live services and credentials.
Use platform and standard-library APIs before adding dependencies.

Apply codex-web-no-filler to native iOS UI: concise headings, meaningful labels,
flat rows and open sections. No decorative subtitles or enclosed repeated cards.
Settings root is a category directory. Design for Dynamic Type, VoiceOver,
iPhone compact widths, iPad split layouts and light/dark appearance.

Run `scripts/check` for package/backend/contract checks. Run `scripts/test-ios`
for UI changes, then inspect simulator screenshots. Build and launch the app.
Signing secrets, user photos, runtime state, test screenshots, and artifacts stay
outside git. DevApps delivery uses distribution signing and verifies hosted assets;
TestFlight builds require App Store Connect configuration. Report access gaps at
handoff while continuing independent app work.
