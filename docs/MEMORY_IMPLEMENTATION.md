# Memory implementation status

Date: 2026-11-10. Status: source implementation added; macOS build and runtime validation pending.

The user explicitly requested implementation after the second design-critique round, superseding the earlier wait-before-code sequence. This is not a claim that EGM review converged or the final specification passed all gates. The implementation baseline is [memory-v1.md](designs/memory-v1.md); the remaining differences are in [the drift report](../2026-11-10_DRIFT_REPORT.md).

## Implemented source

- Memory is in Review after App Uninstaller; ⌘6 selects it, preserving ⌘1–⌘5. Existing header actions and Find routing handle the new tab.
- `MemoryStatsProvider` reads public VM counters, physical memory, runtime page size and swap. `MemoryAccounting` uses checked arithmetic, optional readings, typed diagnostics and explicit approximate categories. An invalid segmented total is unavailable rather than normalized.
- `MemoryCoordinator` is app-owned; foreground aggregate sampling is 1/2 seconds, process sampling 5 seconds, and optional background menu sampling 10 seconds. It shares in-flight process work, discards cancelled foreground results and retains a bounded in-memory chart. Pressure begins Unknown and is event-derived.
- `ProcessMemoryProvider` uses public libproc calls and `(PID, start time)` identity. It rechecks identity/ownership/parent metadata, groups only verified same-bundle ancestry, keeps ambiguous processes standalone and marks inaccessible samples partial. App icons use a bounded cache.
- `MemorySafetyPolicy` is enforced independently by `MemoryActionService`. Unknown, root/other-user, system-component, Purge/component/descendant, helper-only and excluded records cannot be actionable. Every Quit is confirmed; Force Quit has a distinct loss warning. Only `NSRunningApplication.terminate()`/`forceTerminate()` perform actions; no arbitrary signals or privileged helper operation was added.
- Single-use confirmation tokens and one app-wide transaction prevent overlapping or replayed requests. Changed target sets require confirmation again. Leaving Memory or deactivation stops unissued targets; an issued request keeps its bounded observer and outcome/history recording. Normal exit has an eight-second best-effort drain. Normal Quit never escalates automatically.
- Separate versioned/atomic Memory history holds at most 100 action entries. Outcome and non-sensitive reason are independent of signed system-wide measurement. Corrupt/future archives remain preserved until confirmed reset; delayed initial loads cannot overwrite newer UI state. File operations and measurement waits have two-second controller bounds; cancellation cannot forcibly interrupt an already-running filesystem/kernel call, whose late result is ignored.
- Memory settings/exclusions use namespaced defaults. Menu and notifications are off initially. Memory notifications share the existing category registration/delegate, including Review/default activation routing; opt-in is the only authorization-prompt path. An episode has one 60-second timer, cancels on observation gaps/recovery, and delivers at most once before recovery.
- `Memory.strings` has 102 nonempty keys in EN, zh-Hans and RU, with matching format placeholders. Existing unrelated localization tables remain unchanged. Byte counts, percentages and dates use Foundation formatting.

## Source map

| Area | Files |
| --- | --- |
| Models | `purge/Models/Memory/MemorySnapshot.swift`, `MemoryProcessGroup.swift`, `MemoryActionOutcome.swift` |
| Services | `purge/Services/Memory/MemoryCoordinator.swift`, `MemoryStatsProvider.swift`, `ProcessMemoryProvider.swift`, `MemorySafetyPolicy.swift`, `MemoryActionService.swift`, `MemorySettingsStore.swift`, `MemoryHistoryStore.swift`, `MemoryNotificationController.swift` |
| UI | `purge/Views/Memory/MemoryView.swift`, `MemoryProcessListView.swift`, `MemoryHistoryView.swift`, `MemorySettingsSection.swift` |
| Tests | `PurgeTests/Memory/MemoryTests.swift`, `MemoryActionTests.swift`, updated `PurgeTests/TabShortcutTests.swift` |
| Integration | `AppEnvironment.swift`, `AppBootstrapper.swift`, `PurgeStore.swift`, `ContentView.swift`, `SettingsView.swift`, `PageHeaderActionBar.swift`, `purgeApp.swift`, `ScheduledCleanupNotifier.swift`, `purge/Menu/MenuScanNotifier.swift`, `purge.xcodeproj/project.pbxproj` |
| Resources/checks | Three `Memory.strings` tables; `scripts/check-memory-localization.mjs`; extended `scripts/check-localization.py`; package scripts; README |

No `PurgeHelper`, `PurgeWatch`, `PurgeAssetWorker`, file-deletion policy or cleanup-history schema was changed. No dependency was added. The design linter needed a one-line path normalization so its existing token-file exemptions work on Windows as on macOS; no design rule or theme value was relaxed.

## Checks actually performed

- `node scripts/check-memory-localization.mjs`: passed, 102 keys in all three locales and 114 localized source references.
- `node scripts/lint-design-tokens.mjs`: passed. The previously reported 52 problems came from Windows separators failing to match the three intentionally exempt token-definition files; normalizing paths fixed the check.
- Basic lexical delimiter inspection of the 17 new Swift source/test files: passed. This does not establish Swift grammar, type checking, API compatibility or compilation.
- Fifteen Swift Testing cases were added for accounting/overflow, deny rules, grouping, episode timing, ring retention, isolated defaults, corrupt/bounded history, resource coverage, PID reuse, replay/concurrency, no escalation, lifecycle interruption and exclusions. These were **not run** on this host.
- Full Python localization checking, Swift tests and Debug/Release builds were **not run**: Python, Swift and Xcode are not installed on this Windows host. No CPU number or screenshots were fabricated.

## Required macOS verification

Run with the repository's Xcode/Swift toolchain:

```sh
python3 scripts/check-localization.py
node scripts/lint-design-tokens.mjs
xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test
xcodebuild -project purge.xcodeproj -scheme purge -configuration Debug -destination 'platform=macOS' build
xcodebuild -project purge.xcodeproj -scheme purge -configuration Release -destination 'platform=macOS' build
```

Resolve any compiler/API/isolation diagnostics before treating the feature as buildable. On supported Intel/Apple Silicon Macs, validate the counter mapping and Unknown/pressure-event behavior; exercise Quit save dialogs, refusal/timeout, stale identity, partial reconfirmation, sleep/wake and app exit using disposable test apps. Confirm existing notification actions remain intact, permission denial does not prompt repeatedly, and no process polling remains when inactive except the one notification-expiry sample.

Measure idle CPU with 500+ process rows before claiming the under-2% target. Review VoiceOver, keyboard focus, Light/Dark, all three Memory languages and mixed-language fallback. Capture actual dark-mode screenshots of Memory, confirmations, history and Settings on Mac as required by CONTRIBUTING. These human and runtime checks remain pending; source review does not replace them.

Action and policy changes need the repository's additional security/data-loss scrutiny. No Git metadata exists in this workspace, so no branch, commits or PR were created.
