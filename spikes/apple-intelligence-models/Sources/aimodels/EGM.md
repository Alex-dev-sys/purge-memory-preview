# aimodels Command-Line Experiment

## Overview

Swift command-line sources for the Apple Intelligence asset spike. The executable is an investigative tool under `spikes/`, separate from the shipping app targets.

## Interface

- `main.swift` is the executable entry point; operation and formatting code is split across `Commands.swift`, `Format.swift`, and the related model/reader files in this directory.
- `Package.swift` at the spike root defines how this target is built.

## Invariants

- Treat discovered private framework types, archive formats, and asset names as experimental observations that may vary by macOS release.
- Keep these experiments separate from production Memory functionality and from the normal app target.

## Side Effects

- Commands may read local asset metadata and system files; inspect the specific command before running it.

## Verification

- Run: `swift test` from `spikes/apple-intelligence-models/` when changing the experiment.
