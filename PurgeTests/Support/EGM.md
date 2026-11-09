# PurgeTests Support

## Overview

Shared fixtures and test doubles for the `PurgeTests` Swift Testing target. These helpers isolate defaults, filesystem fixtures, and deletion behavior where callers inject the corresponding fake.

## Interface

- `FakeScans` in `FakeScans.swift` supplies configurable `ScanSources` and `makeStore(gitChecker:fileDeleter:lastScanStore:)` for store tests.
- `FakeTrash` in `FakeTrash.swift` implements `FileDeleter.Trasher`, records paths and main-thread calls, and can fail a configured number of calls without moving files.
- `ThrowawayDefaults` in `ThrowawayDefaults.swift` creates an isolated defaults suite and removes its persistent domain and temporary folder when cleaned up.
- `ActivityFixture`, `RealHomeFolders`, and `FakeAssetsV2` provide temporary on-disk fixtures; `withTemporaryHandoffRoot` scopes `RemovedAppHandoff`'s task-local root.
- `WindowFixtures` creates the `NSWindow` and `NSPanel` variants used by window-presentation tests. `eventually(timeout:condition:)` is a main-actor polling helper.

## Invariants

- Use unique temporary roots and call fixture cleanup; `FakeTrash` never moves anything to the real Trash.
- `ActivityFixture.cleanUp()` removes only its owned root and removes the shared container only with `rmdir`, so unrelated contents prevent removal.
- `ThrowawayDefaults` must be cleaned up after its last write because later writes can recreate the defaults domain.
- `FakeScans.cleanUp()` releases held scan streams and continuations; tests that hold work must release or clean it up.
- `RealHomeFolders.remove()` removes tracked items and uses `rmdir` for parent folders, preserving pre-existing or non-empty directories.

## Side Effects

- Fixtures create and remove unique temporary files and directories. `ActivityFixture` and `RealHomeFolders` may operate under a test fixture folder in the current user's home directory.
- `ThrowawayDefaults` writes to a unique `UserDefaults` suite and removes that suite on cleanup.
- `FakeScans`, `FakeTrash`, and `WindowFixtures` keep test-only state in memory; `FakeTrash` records requests but does not delete or move files.

## Verification

- Run: `xcodebuild test -project ../../purge.xcodeproj -scheme purge -destination 'platform=macOS'`
- Representative callers: `PurgeTests/ProjectActivityPolicyTests.swift`, `PurgeTests/FileDeleterRetryRouteTests.swift`, `PurgeTests/CustomCleaningIntervalTests.swift`, and `PurgeTests/AppWindowPresenterTests.swift`.
