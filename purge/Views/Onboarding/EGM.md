# Onboarding

## Overview

The onboarding flow collects the initial scan results, presents categories and findings, and supports the user's decision to clean or continue into the app.

## Interface

- `OnboardingFlowView` (`OnboardingFlowView.swift`) coordinates onboarding steps and completion paths.
- `OnboardingFirstScanStep`, `OnboardingResultsStep`, `OnboardingWelcomeStep`, and `OnboardingCelebrationView` render the individual flow states.
- `OnboardingResultsSnapshot`, `onboardingResultsSnapshot(for:)`, `resultsCategories(for:)`, and `onboardingFindings(for:)` (`OnboardingResultsStep.swift`) derive the results presentation from deletion candidates.
- `OnboardingScanRevealController` (`OnboardingScanRevealController.swift`) buffers and reveals findings.

## Invariants

- `OnboardingFlowView.startResultsCleanup()` passes the store's `manualSafeCleanupCandidates()` to `performManualSafeCleanNow`.
- Onboarding completion and look-deeper relaunch state are recorded by `OnboardingFlowView` using `UserDefaults` keys declared in that type.

## Side Effects

- Reads and writes onboarding flow keys in `UserDefaults`.
- Starts store scans and cleanup, and opens the macOS Full Disk Access settings pane through `openFullDiskAccessSettings()` in `OnboardingComponents.swift`.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
