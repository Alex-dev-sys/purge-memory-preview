# PurgeTests Blueprint

## System Overview

This subtree contains the `PurgeTests` Swift Testing unit-test target configured by `purge.xcodeproj/project.pbxproj` as a unit-test bundle and included by the shared `purge` scheme. Test files exercise app policies, stores, service boundaries, and UI coordination; reusable fixtures and fakes live in [`Support/EGM.md`](./Support/EGM.md).

## Interface

- `PurgeTests` is the Xcode unit-test bundle target (`PurgeTests.xctest`) declared in `../purge.xcodeproj/project.pbxproj` and selected by the shared `../purge.xcodeproj/xcshareddata/xcschemes/purge.xcscheme`.
- Tests use Swift Testing (`@Test`, `#expect`); `CLAUDE.md` requires `ThrowawayDefaults` and fake scan/filesystem helpers rather than real user data.

## Subdirectories & System Boundaries

- [Support](./Support/EGM.md) - shared fixtures, isolated defaults, scan and trash fakes, and window helpers.

## Global Invariants

- Tests should use `PurgeTests/Support` fixtures and fakes for user defaults, filesystem operations, scanning, and trash handling rather than act on real user folders.
- The shared scheme runs the app's test bundle; the macOS destination is required.

## Global Side Effects

- Test helpers create temporary filesystem state and isolated defaults; callers are responsible for releasing held streams and cleaning up fixtures.

## System Verification

- Run: `xcodebuild test -project ../purge.xcodeproj -scheme purge -destination 'platform=macOS'`
