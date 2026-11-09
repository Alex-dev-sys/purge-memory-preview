# Services

## Overview

Application services implement scanning, cleanup, persistence, permissions, and integration with macOS facilities. They are composed by `PurgeStore` and view or intent coordinators.

## Interface

- `AppEnvironment` (`AppEnvironment.swift`) provides the application store and environment wiring.
- `PurgeStore` extensions (`PurgeStore*.swift`) expose scan, overview, app-folder, suite, and queue operations.
- Scanner and policy types include `CacheScanner`, `DevScanner`, `LargeFileScanner`, `AppUninstallScanner`, and their `*ScanPolicy` peers.
- Persistence and cleanup types include `PurgeStore`, `FileDeleter`, `TrashStore`, `CleanupHistoryStore`, `CleanupLedgerStore`, and `LastScanStore`.
- Platform-facing types include `ApplicationsFolderWatcher`, `LoginItemRegistrar`, `ScheduledCleaningRegistrar`, `PurgeUpdater`, and `AppleIntelligenceModelStore`.

## Invariants

- Scanner policies and safety evaluation are implemented in explicit policy types such as `DeletionSafetyPolicy` and the scanner-specific `*ScanPolicy` types; callers use these policies when deriving candidates.
- Store mutations and scan coordination are centralized in `PurgeStore` and its extensions.
- `FileDeleter` and cleanup services operate on selected candidates, and cleanup outcomes are represented by model types such as `CleanOutcome` and `CleanFailure`.

## Side Effects

- Reads filesystem metadata and directories for scan and measurement work; persists scan, preference, and cleanup data through store implementations.
- Invokes system processes, filesystem cleanup, notifications, login-item/watch registration, and privileged-helper integration where the corresponding service is used.
- Some services access Apple framework stores and system application directories.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
