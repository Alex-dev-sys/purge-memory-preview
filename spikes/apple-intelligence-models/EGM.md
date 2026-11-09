# Apple Intelligence Models Spike

## Overview

Standalone Swift package used to investigate Apple Intelligence asset metadata and worker behavior. Its sources are not the app's normal SwiftUI implementation.

## Interface

- `Sources/aimodels/` contains the command-line experiment sources.
- `Sources/PrivateBridge/` contains an Objective-C runtime bridge and exported header.
- `Package.swift` defines the package build inputs.

## Subdirectories & Boundaries

- [aimodels](./Sources/aimodels/EGM.md) - command-line experiment sources.
- [PrivateBridge](./Sources/PrivateBridge/EGM.md) - Objective-C private-framework bridge sources.

## Invariants

- Treat the spike as an investigation tool, not as a supported application API contract.
- Private framework and archive assumptions here are specific to the experiment and do not authorize their use in unrelated app features.

## Side Effects

- Commands may inspect local Apple asset metadata and system files; review the selected command before running it.

## Verification

- Run: `swift test` from this package directory when the spike is intentionally being changed.
