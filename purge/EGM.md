# purge Blueprint

## System Overview

This directory contains the macOS app entry point and the app's local UI, model, service, and utility layers. `PurgeApp` and `PurgeAppDelegate` in `purgeApp.swift` configure the SwiftUI app lifecycle; `ContentView` composes the main navigation and page content using `PurgeStore`. Supporting source is grouped by responsibility in the linked child contracts.

## Local Interface & Invariants

- `PurgeApp` and `PurgeAppDelegate` (`purgeApp.swift`) establish the SwiftUI scene, app delegate lifecycle, menu commands, and URL handling.
- `ContentView` (`ContentView.swift`) provides the main app window and selects views from `PurgeStore` state.
- `Info.plist` declares app metadata and platform integration settings.
- The root source files import and compose child components; detailed contracts are in the child `EGM.md` files below.

## Subdirectories & System Boundaries

- [Intents](./Intents/EGM.md) - App Intents, shortcut entities, and Finder uninstall routing.
- [Menu](./Menu/EGM.md) - Menu bar UI, scan state, window presentation, and notifications.
- [Models](./Models/EGM.md) - App and scan data types.
- [PrivilegedHelper](./PrivilegedHelper/EGM.md) - Privileged helper protocol and helper-side operations.
- [Services](./Services/EGM.md) - Scanning, persistence, cleanup, and platform integrations.
- [Theme](./Theme/EGM.md) - Shared application colors.
- [Utilities](./Utilities/EGM.md) - Path, process, sizing, formatting, and support utilities.
- [Views](./Views/EGM.md) - Main application screens and reusable UI.

## Global Invariants

- App state and user actions are coordinated through `PurgeStore`; view code presents state and invokes its operations.
- Cleanup and uninstall behavior is implemented in service/store layers and is exposed to users through confirmation and safety flows.

## Global Side Effects

- App lifecycle and UI operations use SwiftUI, AppKit, and system services.
- Filesystem access and cleanup effects are implemented by linked services and helper components.

## System Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
