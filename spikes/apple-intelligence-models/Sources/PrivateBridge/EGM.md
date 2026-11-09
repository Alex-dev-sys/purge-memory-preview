# PrivateBridge Experiment

## Overview

Objective-C source and header for the Apple Intelligence model spike's private-framework bridge.

## Interface

- `PrivateBridge.m` implements the bridge declarations in `include/PrivateBridge.h`.
- The target is wired by `Package.swift` in the parent spike directory.

## Invariants

- This bridge is an experimental private-API boundary. Do not treat it as an approved integration pattern for unrelated Purge features.

## Side Effects

- Calls into private Apple interfaces when invoked by the spike executable.

## Verification

- Run: `swift test` from `spikes/apple-intelligence-models/` when changing the experiment.
