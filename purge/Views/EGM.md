# Views

## Overview

SwiftUI screens and reusable presentation components for the main application, including cleanup, scanning, settings, and uninstall flows.

## Interface

- `AppChrome.swift` defines shared layout, page header, cleanup action, completion, and failure presentation components.
- Screen types include `AboutView`, `OverviewView`, `SettingsView`, `UninstallView`, `LargeFilesView`, `EverythingElseView`, and `CommandLineToolsSection` in their matching source files.
- [Onboarding](./Onboarding/EGM.md) contains the onboarding flow, steps, result summaries, and reusable onboarding controls.

## Invariants

- Screen presentation is driven by `PurgeStore` state and routes user actions to store or service operations.
- Cleanup presentation in `AppChrome.swift` displays outcomes and retry/admin actions supplied by cleanup state; deletion execution belongs to the store/service layer.

## Side Effects

- Views invoke store operations and open system UI such as Finder or settings when their action handlers are selected.
- Cleanup controls can initiate cleanup through the store; the associated side effects are implemented in services.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`

