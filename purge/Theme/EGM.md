# Theme

## Overview

Shared color tokens used by Purge's SwiftUI views.

## Interface

- `AppColors` and nested `Chart` (`AppColors.swift`) provide static color values for application UI and charts.

## Invariants

- Color definitions are centralized in `AppColors`; consumers reference these values instead of defining this module's tokens independently.

## Side Effects

- None.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
