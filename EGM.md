# Purge Repository Blueprint

## System Overview

Purge is a native SwiftUI macOS application that scans selected cache and junk locations, presents safety classifications, and moves eligible items to the Trash by default. The main app coordinates UI and state in `purge/`; separate targets handle the optional privileged Trash move helper, app-removal watcher, and Apple Intelligence asset worker. The Xcode project defines the app and test targets. `PurgeTests/` contains the Swift Testing unit suite.

## Subdirectories & System Boundaries

- [purge](./purge/EGM.md) - app entry point, navigation, models, scanners, deletion policy, UI, and integrations.
- [PurgeHelper](./PurgeHelper/EGM.md) - privileged XPC helper that validates requested paths and moves accepted items into the connecting user's Trash.
- [PurgeWatch](./PurgeWatch/EGM.md) - launchd watcher that records app removals for user review.
- [PurgeAssetWorker](./PurgeAssetWorker/EGM.md) - isolated worker for existing Apple Intelligence model asset operations.
- [PurgeTests](./PurgeTests/EGM.md) - Swift Testing unit-test target and shared test fixtures.
- [scripts](./scripts/EGM.md) - localization, design-token, packaging, and asset-generation tools.
- [spikes](./spikes/EGM.md) - standalone experiments; not app targets unless explicitly wired into the Xcode project.
- `purge.xcodeproj/` - project, shared scheme, target membership, build settings, and package references.
- `docs/` - maintained safety notes and design-system guidance.

## Global Invariants

- `DeletionSafetyPolicy.evaluate(_:)` and the specialized scan/action policies gate filesystem removals; unknown paths are refused. Files normally go to the Trash, and the app never empties it.
- User-visible cleanup goes through explicit review and confirmation flows; the privileged helper independently validates sources and the caller.
- Tests use Swift Testing (`@Test`, `#expect`) and must use isolated defaults and test fixtures rather than real user files, as specified in `CLAUDE.md`.
- The app supports macOS 13.0 and later and uses system frameworks; `CLAUDE.md` records the Xcode 26 / Swift 6.2 toolchain requirement.
- New Memory functionality must not adopt the existing Apple Intelligence worker's private API path; that worker is a separate established feature boundary.

## Global Side Effects

- The app scans the local filesystem, stores preferences, cleanup history, and scan snapshots in local Application Support, and checks GitHub only for its update feed/downloads.
- The optional `PurgeHelper` uses macOS authorization and XPC to move approved items to a user's Trash; it does not delete them.
- `PurgeWatch` observes installed application folders and may launch Purge for a review. `PurgeAssetWorker` makes local system-framework/XPC calls for existing Apple Intelligence model operations.

## System Verification

- Unit tests: `xcodebuild test -project purge.xcodeproj -scheme purge -destination 'platform=macOS'`
- Design tokens: `node scripts/lint-design-tokens.mjs`
- Translations: `python3 scripts/check-localization.py`
