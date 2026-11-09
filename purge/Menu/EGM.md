# Menu

## Overview

Menu bar presentation and its interaction with the shared `PurgeStore`, including scan status, safe cleanup, window presentation, and notifications.

## Interface

- `MenuBarStatusIcon` and `MenuBarContentView` (`MenuBarView.swift`) render the status item and its content.
- `MenuViewModel` and `MenuState` (`MenuViewModel.swift`) attach to the store, start scans, derive display state, and request safe cleanup.
- `AppWindowPresenter`, `AppWindowID`, and `MainWindowLocator` (`AppWindowPresenter.swift`, `MainWindowLocator.swift`) identify and reveal the main app window.
- `MenuScanNotifier` (`MenuScanNotifier.swift`) configures and sends scan and cleanup notifications.

## Invariants

- `MenuViewModel.clean()` collects `store.manualSafeCleanupCandidates()` and passes them to `performManualSafeCleanNow`; menu cleanup follows the store's safe-candidate policy.
- `MenuViewModel` attaches once to store scan state and tracks in-flight work through its tasks and published `MenuState`.

## Side Effects

- Starts or joins store scans and invokes store cleanup.
- Registers wake notifications and timers, presents the app window, and requests user notifications through `UNUserNotificationCenter`.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
