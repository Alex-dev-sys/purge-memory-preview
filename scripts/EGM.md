# Repository Scripts

## Overview

Small repository tools for build packaging, localization and design-token checks, brand icon generation, and helper integration checks.

## Interface

- `check-localization.py` checks localized string coverage.
- `lint-design-tokens.mjs` checks use of design-system tokens.
- `generate-brand-icons.mjs` regenerates brand icon assets from the source catalog in `brand-icon-sources/`.
- `make-dmg.sh` assembles and signs the macOS distribution image; `test-privileged-helper.sh` checks the packaged privileged-helper setup.

## Invariants

- The localization and design-token checks are repository quality gates and should pass after related UI or string changes.
- `make-dmg.sh` is a release packaging path; it is not part of ordinary unit-test execution.

## Side Effects

- The check scripts read source, localization catalogs, and design tokens.
- Icon generation writes generated assets; packaging and helper scripts invoke build, signing, or system tooling.

## Verification

- Run: `python3 scripts/check-localization.py`
- Run: `node scripts/lint-design-tokens.mjs`
- The project instructions require both checks after changes; run helper/package scripts only for their corresponding workflow.
