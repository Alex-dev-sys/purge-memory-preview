# PurgeWatch

## Overview

Background launch agent that watches installed application roots while the main Purge app is not running. It records removed apps through `RemovedAppHandoff` and opens the bundled Purge copy so the user can review related leftovers.

## Interface

- `PurgeWatchMain` in `PurgeWatchMain.swift` is the launch agent entry point. It starts `ApplicationsFolderWatcher`, handles departures, monitors its own executable, and listens for owner/app-folder changes.
- `io.getpurge.watch.plist` defines the `io.getpurge.watch` launchd label, bundled executable, `RunAtLoad`, `KeepAlive`, and Purge bundle association.
- App-side watcher policies and handoff types are in `purge/Services/RemovedAppWatchPolicy.swift` and related `purge/Services/RemovedApp*.swift` files.

## Invariants

- A departure is queued only after `RemovedAppWatchPolicy.shouldOfferReview` accepts it, including checks for existing copies and Purge-originated removals.
- A stale agent exits when a newer Purge copy takes ownership; an agent whose own bundle is in Trash does not start watching.
- The watch agent records removals for later review; it does not uninstall applications.

## Side Effects

- Reads installed application roots, process executable paths, and code signatures; maintains filesystem watchers and open file descriptors.
- Writes a `RemovedAppHandoff` record and opens Purge after a departure qualifies for review.
- Runs as a launchd-managed background agent while the Settings preference is enabled.

## Verification

- Run: `xcodebuild test -project ../purge.xcodeproj -scheme purge -destination 'platform=macOS'`
- Relevant policy coverage is in `PurgeTests/RemovedAppWatchPolicyTests.swift`.
