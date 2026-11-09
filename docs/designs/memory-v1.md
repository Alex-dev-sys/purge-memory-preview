# Memory Feature Design

* **Author:** Codex (workspace Git identity unavailable; user name not supplied)
* **Status:** Implementation baseline: user authorized code before EGM completion
* **Date:** 2026-11-10

--------------------------------------------------------------------------------

## Overview

Memory adds a view of RAM use centered on Memory Pressure, a grouped process list and confirmed recognized-app actions. Process data stays on the Mac; free RAM is not a health score. Menu-bar information and pressure notifications start disabled. Notifications default to Critical sustained for 60 observed seconds, with Warning selectable.

Memory belongs in the existing Review group because it reviews process use and offers user-confirmed process actions rather than cleaning files.

## The Problem

macOS manages physical memory itself. A low free-memory figure can be normal, while Memory Pressure is the primary indication of whether the system is under strain. Purge currently focuses on reclaimable files and has no place to explain memory pressure, show which applications account for process footprints, or help a user request that a recognized application quit.

Those actions can lose unsaved work, and process lists change while a user is looking at them. The feature must clearly separate ordinary Quit from Force Quit, preserve normal save prompts, and recheck process identity and safety when carrying out an action. It must also distinguish an observed system-wide memory change from memory specifically attributable to the app that quit.

## Goals

- Show Total, Used, Free, App Memory, Wired, Compressed, Cached Files, Swap Used and Memory Pressure under the normative accounting contract below. Label derived App Memory, Cached Files and Used as estimates; do not claim Activity Monitor equivalence. Pressure states are Normal (green), Warning (yellow), Critical (red) and Unknown (neutral). Free RAM is not a health score.
- Provide a segmented memory view and an in-memory graph with 60-second, 5-minute, and 1-hour ranges. Collect aggregate data every 1–2 seconds while Memory is visible; slow or stop collection when it is inactive. Gather data away from the main UI thread and publish updates in batches.
- Target less than 2% idle CPU with 500 or more process rows. Measure before claiming compliance. Separate aggregate/process refresh cadences; show sample age and unavailable/partial readings.
- List the largest process footprints, group known application helper processes under their application, and show an app icon, name, footprint, percentage of RAM, expandable PIDs, sorting, search, and a short explanation for recognizable applications.
- Use **Safe to Quit**, **Check First** and **Protected** under the eligibility/classification contract below. Safe to Quit means policy-eligible for a normal quit request, never proof that no unsaved work exists. Unknown, system-component, Purge/component, root-owned, other-user and failed-identity processes remain read-only.
- Allow confirmed normal Quit, including selected-app batches, preserving save prompts. If termination is not observed within five seconds, say the app has not quit; distinguish refusal from timeout without diagnosing responsiveness. Never escalate automatically.
- Offer Force Quit only for recognized user applications, after a separate confirmation and clear data-loss warning. Never use an arbitrary PID kill command. Every action requires explicit confirmation.
- Confirmation shows names and sampled group footprints as context, explicitly not guaranteed release. Record each action outcome separately from its measured, below-threshold or unmeasured system-wide Used estimate change. Never attribute that change to one app.
- Settings cover aggregate refresh interval, menu-bar display, notification threshold and exclusions. Use “Exclude from Memory actions” in row menus and Settings. Exclusions disable actions without hiding monitoring data; v1 has no suggestion engine.
- The optional menu indicator shows pressure and estimated Used RAM with navigation actions. Notifications follow the selected Warning or Critical threshold for 60 observed seconds, default Critical; Review opens Memory without closing anything. Both integrations start disabled.
- Keep data local, bounded, and limited to counters and process metadata; never inspect process memory contents or send process data over the network.
- Preserve the existing English and Simplified Chinese resources. Add Russian localization for Memory strings only; English remains the default language and fallback. Put all new user-facing text in localization resources; translate new strings into Simplified Chinese or explicitly fall back to English, with no empty or broken keys. Use system formatters for sizes, numbers, and dates, and test that every Memory string key exists in English, Simplified Chinese, and Russian. In v1, the rest of Purge is not localized into Russian, so Russian-speaking users may see a mixed-language interface.
- Preserve ⌘1–⌘5 and add ⌘6 for Memory. Place Memory in the existing Review sidebar group, after Large Files and App Uninstaller.

## Non-Goals

- Present free RAM as a health score or claim a specific system-wide result from closing an app.
- Automatically close applications, including through any automatic Force Quit behavior.
- Include Smart Free suggestions in v1.
- Run `/usr/sbin/purge` or reset disk cache (out of scope for v1; future work only).
- Add any new privileged action or capability to `PurgeHelper` for Memory.
- Act on arbitrary PIDs, unknown processes, protected processes, root processes, or processes owned by another user.
- Read process memory contents, use private APIs, bypass sandbox/TCC, or send process data over the network.
- Translate the rest of Purge into Russian in v1.

--------------------------------------------------------------------------------

## Technical Plan

### App integration

- Add a `memory` case to `PurgeStore.Tab`, its display name and icon, and the `ContentView.tabBody` switch. Add Memory to the Review sidebar group and to `keyboardTabs` after the existing five tabs so ⌘1–⌘5 retain their current mapping and ⌘6 selects Memory. Add a localized page title and preserve the current tab's view-lifecycle behavior: the selected page is built on demand, rather than keeping every page mounted.
- Own one app-lifetime `MemoryCoordinator` in `AppEnvironment`, separate from global `PurgeStore` publications. It owns providers, sampling, pressure observation, the chart buffer and the app-lifetime `MemoryActionService`. A page-owned `MemoryViewModel` holds presentation state and expresses visible/active sampling demand. Authorized action transactions belong to the action service, not the page or foreground sampling generation; their lifecycle is defined below.
- Use small views following existing `AppStyle`/`AppColors`. Menu-bar and notification models use the same coordinator, never independent pollers. Publish aggregate/process changes separately so frequent stats updates do not rebuild the process list.

### Data collection and presentation

- `MemoryStatsProviding` uses public `sysctl` physical-memory/swap readings, `host_statistics64` counters and runtime `host_page_size`. Apply the normative accounting contract below with explicit validity. Observe pressure with `DispatchSource.makeMemoryPressureSource` under the pressure contract; do not claim its event levels reproduce Activity Monitor's combined pressure calculation.
- Add `ProcessMemoryProviding` backed by public macOS process interfaces (`proc_listpids`/`proc_pid_rusage` from libproc), never `ps`/`top` text parsing. Enumerate and measure off the main actor. Treat inaccessible, exited, or stale PIDs as partial data and discard a result when the PID's identity changed during sampling. Keep process records to PID, owner UID, parent PID, bundle identifier when known, app name/icon source, activation policy, and physical footprint; do not inspect process memory contents.
- Group helper footprints only with the positive evidence defined below. Unresolved processes remain separate Protected/read-only rows. Membership is accounting context, never permission to terminate a child; actions target one freshly revalidated regular `NSRunningApplication`.
- Keep one app-owned, timestamped aggregate ring buffer capped at 3,601 points and one hour, with no disk persistence. Active aggregate refresh is 1 or 2 seconds (default 2), process refresh independently 5 seconds, with no overlapping scans. Inactive aggregate refresh is 10 seconds only for the enabled menu indicator; inactive periodic process enumeration stops. Notification expiry may request one shared process sample. The lifecycle/pressure/notification contracts below are authoritative.
- Reuse existing `formatBytes` Foundation `ByteCountFormatter` behavior where compatible. Its default-table zero branch needs a Memory-localized adapter; use Memory resources for zero/unavailable text. Do not use manual-unit `formatStorageBytes`/`formatBytesRoundedDown` or rewrite unrelated formatters. Counts/dates use current-locale Foundation styles; test zero/large values in EN/zh-Hans/RU.

### Action and safety boundary

- `MemorySafetyPolicy` classifies records; `MemoryActionService` independently enforces the predicate, deny precedence and freshness contract below. Reacquire and check current owner, regular activation, bundle identity, PID/start time, exclusions and protection immediately before each request. UI-enabled state is never authority to act; helper-only and arbitrary PID actions are forbidden.
- Normal Quit calls `NSRunningApplication.terminate()` and observes `isTerminated` for a bounded five-second window. A refusal or timeout returns a localized not-quit outcome; it never escalates automatically. Force Quit calls `forceTerminate()` only after its own confirmation, then observes termination and records the result. Do not invoke a shell command, signal arbitrary PIDs, or change `PurgeHelper`.
- Every Quit requires confirmation, including Safe to Quit; Force Quit needs its own confirmation/data-loss warning. Show exact names, action, group footprint context, sample age and label meanings. All confirmations acknowledge possible unsaved work; Check First adds a prominent warning. The Action lifecycle is authoritative for partial-target reconfirmation, outcomes and measurement; no shortcut path may bypass it.
- Exclusions use stable bundle identifiers across instances and disable actions without hiding counters. No persistent path/name fallback exists for a missing bundle ID: that row stays read-only. Use “Exclude from Memory actions”; no suggestion machinery is added.

### Settings, menu bar, notifications, and history

- Add namespaced `memory.*` preferences in a dedicated `MemorySettingsStore`, with registered defaults: menu-bar indicator off, notifications off, a 2-second sampling interval while active, and a notification threshold of critical pressure sustained for 60 seconds. Let the user choose Warning or Critical pressure; keep the sustained duration fixed at 60 seconds in v1. Store settings and exclusions in `UserDefaults`; provide an isolated defaults suite to tests.
- Add a Memory subsection to `SettingsView` for refresh interval, menu-bar indicator, notifications, and excluded apps. Keep menu-bar presence and login-item behavior separate: Memory's optional indicator must not silently enable Purge's existing startup/menu-bar mode.
- The indicator offers Open Memory/navigation, never one-click Quit/Force Quit. Follow the pressure contract even with notifications off. Extend existing `ScheduledNotificationPresentationDelegate` to route Memory Review and default notification activation to Memory, preserving existing handlers. Register the Memory category together with existing categories through `purge/Menu/MenuScanNotifier.configure()` rather than replacing the set. Request permission only on user opt-in, never launch or hosted tests. The selected-threshold contract below governs delivery.
- Use separate `MemoryHistoryEntry`/`MemoryHistoryStore`, not cleanup-history schema. Each entry stores timestamp, app bundle identity/name, action, explicit outcome/reason, and independent measurement status/signed delta. Versioned atomic persistence is capped at 100 entries; no paths, arguments or historical process snapshots. Provide history viewing and confirmed clearing.

### Localization and test seams

- Put Memory-only strings in a separate `Memory.strings` table in `purge/en.lproj/`, `purge/zh-Hans.lproj/`, and new `purge/ru.lproj/`. Use `String(localized: "…", table: "Memory")` for every Memory label, accessibility description, alert, notification, and menu-bar label. English is the source and fallback; Chinese and Russian entries must be present and non-empty for every source key. This avoids requiring Russian translations for unrelated Purge screens.
- Extend `scripts/check-localization.py` (or add a focused companion check) to parse all three `Memory.strings` tables, verify identical key sets and non-empty values, and compare format placeholders. Add Swift Testing coverage that runs against the checked-in localization resources, plus unit tests for stat derivation, chart bounds, process grouping, action revalidation/deny rules, action outcomes, history bounds/decoding, locale formatting, and notification timing. Keep hardware and process access behind protocols; tests use fakes and never terminate a real process.
- Add Memory files under the proposed Services/Models/Views/Test folders and verify synchronized membership/RU packaging. Integrate at navigation/settings/app composition seams. Extend `AppEnvironment.swift` for ownership, `ScheduledCleanupNotifier.swift` for routing and `purge/Menu/MenuScanNotifier.swift` for combined category registration. Do not change `PurgeHelper` or cleanup-history schema.

### Proposed files

- Create `purge/Services/Memory/MemoryCoordinator.swift`, `MemoryStatsProvider.swift`, `ProcessMemoryProvider.swift`, `MemoryActionService.swift`, `MemorySafetyPolicy.swift`, `MemorySettingsStore.swift`, `MemoryHistoryStore.swift` and `MemoryNotificationController.swift`; inject testable provider, timing and pressure interfaces.
- Create `purge/Models/Memory/MemorySnapshot.swift`, `MemoryProcessGroup.swift`, `MemoryActionOutcome.swift`, and `MemoryHistoryEntry.swift`.
- Create `purge/Views/Memory/MemoryView.swift`, `MemoryPressureCard.swift`, `MemoryBreakdownView.swift`, `MemoryHistoryView.swift`, `MemoryActionConfirmationView.swift`, and `MemorySettingsSection.swift`.
- Add `Memory.strings` for English, Simplified Chinese, and Russian; add focused test files under `PurgeTests/Memory/`; update the localization checker and tab-shortcut tests. Update the README only after the design review and implementation authorization.

### Alternatives considered

| Decision | Selected | Rejected alternative and reason |
| --- | --- | --- |
| Lifetime | App-owned coordinator; page-local presentation | Page-owned sampler cannot serve optional surfaces after page teardown; global PurgeStore polling would publish frequent unrelated-tab updates. |
| Refresh | Separate aggregate/process cadences; one scan at a time | Common 1–2-second process scans add unmeasured recurring work; per-surface pollers duplicate work. |
| History | Separate Memory archive | Cleanup history conflates file removal and process actions and adds compatibility risk. |
| Grouping | Positive same-bundle ancestry evidence; standalone fallback | Names/prefixes can match unrelated processes; no grouping omits an agreed feature. |
| Pressure | Public event levels with Unknown | Free-RAM heuristics and Activity Monitor equivalence lack evidence. |

Purge, new helper privileges, automatic closure and Smart Free remain deferred. Sidebar placement/shortcuts are defined in App integration without duplicating that rationale.

## Data Contracts and Failure Handling

### Snapshot and process records

- `MemorySnapshot` is immutable/Sendable with timestamp, physical bytes, typed readings, pressure/validity and completeness. Unavailable is never zero. The coordinator retains chart history across page reconstruction; relaunch starts empty. Expire points after one hour and preserve gaps instead of interpolating unobserved intervals.
- Derivation uses checked arithmetic and fields present in the returned VM-info revision. Overflow, negative dependent subtraction or inconsistent totals invalidates dependent estimates and the breakdown, without clamping or normalizing them into plausible values. The accounting contract specifies the proposed equations, approximation labels and release validation.
- A record carries `(pid, processStartTime)`, UID, parent PID, optional bundle ID, name/icon source, activation policy, footprint and classification. Grouping-only bundle/executable URL metadata stays transient and is never persisted/logged. Group ID includes owning app process identity plus bundle ID, not bundle ID alone. Checked sums count validated members once; inaccessible members mark the footprint partial. Search names/bundle IDs, sort bytes and expose PIDs only on expansion.
- A process sample is a point-in-time view. The UI displays its sample age and partial-access status, and selection resolves to the process-group identity captured by that sample. Before any action, the service obtains a fresh `NSRunningApplication`, rechecks current user, activation policy, bundle identity, PID, process start time, protected/deny rules, and exclusions. Any mismatch fails closed with an outcome that the UI can explain.

### Action lifecycle and results

1. The user selects one or more actionable application rows and chooses Quit, or chooses Force Quit from the separate destructive action.
2. Show a confirmation sheet with exact app names, action, sample age and sampled group footprint, not promised release. Every confirmation acknowledges possible unsaved work; for **Check First**, make that warning prominent. Force Quit uses a distinct confirmation with the data-loss warning. Cancel performs no action. The service binds a single-use confirmation token to the deduplicated target identities and action; dismissing/replacing the confirmation invalidates that token.
3. Submit the confirmed set to the action service, which atomically claims its app-wide transaction slot and consumes the single-use token before any asynchronous wait. Reject a busy or replayed submission without queuing it or issuing requests. Validate the entire confirmed set before requesting termination. If any target fails, issue no requests from that confirmation: record skips/reasons and require a new confirmation/token for the remaining valid list. Cancel sends no requests. Immediately before each sequential request revalidate that target and the transaction's lifecycle permission; a mismatch stops the remaining batch and requires a new confirmation. Never redirect a reused PID.
4. Request `terminate()` or separately confirmed `forceTerminate()`, observing completion for at most five seconds with injected monotonic timing. Distinct outcomes are `terminated`, `requestRefused`, `timedOut`, `alreadyExited`, `identityChanged` and `policySkipped`, with non-sensitive reason codes. Timeout means not observed to quit, not unresponsive; normal Quit never escalates.
5. Execute targets sequentially with a fresh per-target baseline immediately before each request. After observed termination wait one second and take one post-action aggregate sample; never extend that settling wait. Compute the signed system-wide Used-estimate change under the measurement contract. Append each attempted/skipped result; targets left unattempted when the user cancels are not failures.

### Sampling and notification states

- Active sampling demand requires selected Memory, active app and visible window. Aggregate refresh is configured 1 or 2 seconds; process refresh independently 5 seconds, with an initial sample on entry. Coalesce demands, allow at most one process scan in flight and skip missed ticks. Cancel foreground sampling on deactivation/tab switch; check cancellation between reads and discard old sampling-generation results. This cancellation never discards an already-issued action's observer, outcome or history write. Identity/footprint unavailable, old sampling generation or process age greater than 10 seconds disables a new action until refresh. Execution always revalidates regardless of age; action lifecycle follows its separate contract.
- After opt-in/granted permission, notify at selected Warning or Critical for 60 uninterrupted observed seconds (default Critical). Normal < Warning < Critical; Unknown never qualifies. One timer belongs to an episode. Warning→Critical does not reset a Warning-threshold episode. Below-threshold, Unknown, source interruption, sleep, setting/threshold change or denial cancels the timer. At expiry recheck policy/state/generation/continuity, request or share at most one process sample, then recheck before one delivery. Omit an unreadable consumer name; re-arm only after recovery. Sleep/wake and source restart invalidate continuity: require a new qualifying event and never count the gap. Show denial without repeated prompts.
- Menu-only demand samples aggregate values every 10 seconds and keeps pressure observation active; no periodic process enumeration. The coordinator uses the fastest currently demanded aggregate cadence. Observe pressure while Memory is active, menu indicator enabled or permitted notifications enabled. No sampling demand cancels periodic work and invalidates pressure/timers; it does not cancel an issued action transaction. A bounded action measurement may take its one-off aggregate readings without starting background polling. Notification expiry's one shared sample is the sole inactive full-process-sampling exception; per-target identity validation is not a full process scan. App shutdown follows the action-drain contract before stopping services.

### Persistence and degraded operation

- Persist preferences under a `memory.` namespace in `UserDefaults`; register explicit defaults, and inject a unique defaults suite for tests. Persist exclusions as stable bundle identifiers. If an app has no stable bundle identifier, show it but do not offer a persistent exclusion or action.
- Persist a version-1 atomic archive capped at 100 entries, with independent action outcome/reason and measurement status/optional signed bytes. Missing file starts empty. Preserve malformed/unsupported archives and surface recoverable history-unavailable without blocking monitoring; do not overwrite preserved data until confirmed clear/reset. Clearing requires confirmation. Never store executable paths, arguments or process snapshots.
- Provider failures leave last good readings visibly stale only within the current app process; do not append invented chart points or enable actions from stale data. Expire aggregate chart points after one hour; retain the chart buffer across tabs and reset it on relaunch. Interrupted pressure observation becomes Unknown. Logs include provider/error codes, never process arguments or paths.

### Normative action transaction contract

MemoryActionService is app-lifetime and owns transaction state independently of foreground samplers and page tasks. It enforces at most one transaction across the app. Claim the transaction slot and consume a matching single-use confirmation token synchronously before the first await; actor isolation alone is not a substitute for that explicit state. Deduplicate target identities (PID/start time plus bundle identity) before presenting confirmation and again at submission. A token binds the action and exact deduplicated list; changed targets/action require a new confirmation. Reject busy, expired or replayed tokens without queuing actions or appending a false attempted-action entry.

The transaction remains busy through preflight, each issued request's bounded observer, optional measurement and history recording. Reconstructed pages can observe progress, but cannot recreate, resume or resubmit the transaction automatically. Disable new Quit/Force Quit initiation with a localized busy explanation. A separately confirmed Force Quit never replaces an outstanding normal request; it can be initiated only after that transaction finishes and with a new confirmation and fresh identity/policy checks.

Before a request, page dismissal, tab switch, app deactivation, sleep or app exit invalidates unconsumed confirmation tokens and prevents new requests from the current transaction. If a request was already issued, keep its observer and result/history recording alive outside foreground cancellation, but permanently stop the remaining batch. Returning to the page/app never automatically resumes remaining targets; show them as unattempted and require a new confirmation. Deactivation caused by the target app's normal save prompt follows this same rule. A sent termination request cannot be undone, and the UI must not imply otherwise.

The issued request retains its original five-second monotonic observation deadline. On tab change or ordinary deactivation it continues observing; if termination is observed, its one-off aggregate measurement may complete without foreground demand. On sleep or an observation gap, forbid remaining requests and mark measurement unmeasured(observationGap). When execution resumes, enforce the original deadline rather than starting a fresh five-second wait: record terminated only from observed evidence, otherwise timedOut with an observationInterrupted reason once the deadline has passed. Do not infer termination success from loss of foreground sampling or a reused PID.

For normal Purge exit while a transaction is active, prevent further requests and use the app's termination-deferral hook to drain only the already-issued observer and history write, skipping measurement as unmeasured(appExiting). The exit deferral is bounded to eight seconds from the exit request; it never initiates another target. If no action was issued, release the transaction immediately. Give the history write at most two seconds; a write failure remains a history-unavailable condition, never a fabricated saved success. Forced termination, crash or OS shutdown can interrupt this best-effort drain; v1 does not promise durable outcome recovery in those cases or introduce a recovery journal. Tests must exercise the normal-exit deadline and the interrupted cases with fakes.

Keep the busy slot through result handling so a page rebuild cannot overlap another transaction with an outstanding request. Release it only when the transaction is finished/cancelled before issue or its bounded observation/result handling is complete. On wake after a suspended transaction, settle it before accepting a new submission. Whole-set validation and per-target validation remain mandatory; serialization is not permission to bypass either check.

### Normative accounting contract

These equations are proposed product definitions, not a claim to reproduce Activity Monitor. Let P be runtime page size, T physical bytes, F the returned free_count, S speculative_count, I internal_page_count, E external_page_count, Q purgeable_count, W wire_count and C compressor_page_count from one successful HOST_VM_INFO64 reading. Use the returned revision/count to establish field availability. All products and sums are checked.

| Displayed reading | Proposed byte definition | Meaning/limit |
| --- | --- | --- |
| Total | T from hw.memsize | Positive physical-memory denominator. |
| Free | (F - S) × P | Excludes speculative file data; S must not exceed F. |
| App Memory (estimate) | (I - Q) × P | Proposed anonymous non-purgeable estimate; Q must not exceed I. |
| Wired | W × P | Wired bytes reported by VM counters. |
| Compressed | C × P | Physical compressor storage, not uncompressed logical size. |
| Cached Files (estimate) | (E + Q + S) × P | Proposed reclaimable/file-backed estimate; not a guarantee that every byte is immediately reclaimable. |
| Used (estimate) | App estimate + Wired + Compressed | Defined working estimate for overview, chart and result deltas. |
| Swap Used | vm.swapusage.xsu_used | Swap bytes, not an additional RAM segment. |

Speculative pages are removed from Free before inclusion in Cached; purgeable pages are removed from App before inclusion in Cached. Do not add active/inactive or logical uncompressed counters to these segments. Raw public-counter descriptions establish counter meanings, not this complete partition's accuracy on every supported OS.

For a breakdown, validate each component and the checked sum B = App + Wired + Compressed + Cached + Free against T. If a required field is missing, a component exceeds T, or B > T, mark the segmented breakdown unavailable; do not normalize, clamp or render incomplete named segments. Keep independently valid scalar readings visible with their validity/estimate labels. When all required components are valid and B < T, show the remaining area as a neutral unaccounted remainder with localized explanation, never relabel it as App/Free. This is an uncertainty indicator, not a sixth claimed memory metric. A mathematically consistent sum alone is insufficient proof of semantic accuracy.

Before release, compare the proposed mappings and diagnostic differences with Activity Monitor on macOS 13 and a current supported release, with Intel/Apple Silicon coverage, and exercise file-cache growth, anonymous allocation and compression. Record sources/OS/hardware and results. If the mapping cannot be substantiated, retain unavailable states for affected categories and return that release-blocking limitation to design resolution; do not silently substitute another equation or drop an agreed category. No equivalence claim is authorized by this proposal.

### Normative eligibility and classification contract

The action allowlist is predicate-based, not a catalog of every installed app. A target is recognized only through a current NSRunningApplication with stable nonempty bundle ID, regular activation policy, current non-root user ownership, readable process start time and main executable/bundle identity. Capture and freshly compare PID/start time, UID, bundle ID and executable/bundle identity. Re-read public libproc identity before/after sampling and immediately adjacent to termination. An inability to establish any required field fails closed; names alone never authorize an action. Use NSRunningApplication termination methods only. A final user-space check reduces PID-reuse risk but cannot be described as an atomic kernel guarantee; later implementation review must inspect this race.

Deny takes precedence over eligibility, display label and exclusions. Deny root/other-user ownership, unknown identity, nonregular/helper-only rows, failed freshness, the current Purge process, its bundle, known PurgeHelper/PurgeWatch/PurgeAssetWorker components and descendants. Deny system executables within canonical /System/Library or /usr and these explicit system identities regardless of activation policy: com.apple.finder, com.apple.dock, com.apple.loginwindow, com.apple.SystemUIServer, com.apple.controlcenter, and process identities matching kernel_task, launchd or WindowServer. Missing canonical metadata never becomes permission. Ordinary user-facing apps in /Applications or /System/Applications are not denied solely for being Apple apps; all other predicates still apply. Exclusions then deny matching stable bundle IDs across instances. Maintain the deny rules in MemorySafetyPolicy with explicit fixtures, without altering file-deletion policy.

Protected means action denied, with a localized reason. Among eligible applications, Check First is the default, including every unrecognized app category. Safe to Quit is a narrow reviewed classification catalog, initially only com.apple.calculator and com.apple.weather, contingent on all eligibility checks; it means a normal-quit request is permitted, not that background work/unsaved data is absent. All other eligible apps remain Check First; an unknown process that lacks recognized-app evidence remains Protected, not Check First. Changes to this catalog require explicit safety review. Force Quit always uses its own warning regardless of label. The initial classification entries require platform validation and are not evidence that an app contains no valuable state.

### Normative grouping contract

An app's root process owns its own group. A nonregular process can join that group only when all of the following are established in the current scan: same non-root UID, readable PID/start identity, readable canonical executable URL located inside the owning application's canonical bundle, and a complete acyclic parent chain of validated PID/start identities reaching that exact root instance. Intermediate members must also belong to that bundle and user. Do not infer ownership from name, bundle-ID prefix or shared vendor. A regular app is always its own root, even if its bundle resembles another root.

Read parent identities from public process metadata in the scan, validate again before publishing, and discard changed relations. Missing/reparented parents, multiple candidate roots, cycles, unreadable paths or stale identities leave the process standalone/read-only. No unbounded historical ancestry cache is used. Keep paths transient solely for relationship/protection checks; do not persist/log them or expose arguments. In particular, shared external helpers may remain ungrouped in v1 rather than guessed.

Assign each member at most once and sum readable footprints with checked arithmetic. Mark incomplete footprints explicitly. Grouped helper memory is displayed context, not a promise that the helper exits when the app quits. Confirmation labels the figure as sampled group footprint, not guaranteed bytes freed. Actions address only the recognized regular root and never separately close helper PIDs.

### Normative pressure validity contract

Pressure is an event-derived observation with level, validity, observation generation and last-event timestamp, distinct from VM counter sampling. A new/restarted source starts Unknown; do not infer Normal from silence or Free RAM. Register normal/warning/critical events. A single recognized event maps to its named level. Coalesced contradictory flags or unsupported data become Unknown and cancel continuity rather than guessing the last transition. A quiet uninterrupted live source retains its last observed level; stopping/replacing the source, sleep/wake or detected observation failure resets Unknown.

Keep this source while active-page, menu-indicator or permitted-notification demand exists, even if notifications themselves are off. Use system sleep/wake lifecycle signals to invalidate state/timers. Delivery requires an uninterrupted current generation and an injected monotonic 60-second deadline. A new source cannot retroactively time existing pressure. Unknown has explanatory text and neutral appearance in both page/menu. Pressure observation failure does not erase valid RAM counters or imply healthy pressure.

Verify on supported Macs whether initial event delivery occurs, how event coalescing behaves and how suspension affects observation. The design assumes none of those guarantees. If Unknown persists after registration, display it honestly; assess that limitation before release, with no private sysctl or heuristic substitute silently introduced.

### Normative action measurement contract

Termination result and measurement status are separate persisted fields. Outcome is one of terminated, requestRefused, timedOut, alreadyExited, identityChanged or policySkipped; reason codes carry no paths/arguments. Revalidation failure does not become successful termination. Preserve the bounded five-second wait and separate Force Quit confirmation.

Measurement uses signed delta = before Used estimate - after Used estimate. Positive means system-wide decrease, negative increase; neither is attributed to the target. Before each sequential target request, take a new baseline, never reuse the batch's first baseline. The baseline must complete no more than one second before the request. After observed termination, wait exactly one second, take one fresh sample, and report that timestamp/window. Bound each measurement request to two seconds; failures/timeouts do not prevent an already authorized Quit.

If outcome is not terminated, status is unmeasured(actionNotObserved) with no delta. If either Used estimate is incomplete/unavailable, its accounting version differs, a measurement times out or the baseline is too old, status is unmeasured with a non-sensitive reason and no delta. For two valid comparable estimates, abs(delta) < 16 MiB is belowReportingThreshold with no claimed freed amount; this is a display/noise threshold, not a statistical confidence proof. Otherwise status is observedSystemChange with signed delta. Store the accounting-definition version and before/after timestamps with measured results. UI says observed system-wide change; never sum per-target deltas into app-attributed freed bytes. When measurement fails, action success remains visible.

## Implementation and Verification Plan

The user explicitly requested implementation after Design Critique round 2, overriding the earlier wait-before-code sequence. This document records the implementation baseline, including conservative resolution of the five remaining lifecycle/concurrency/copy findings. It is not a claim that the five-stage EGM process or final specification approval completed. Release still requires macOS build, tests, accounting validation, CPU measurement and manual UI/action review. Security-sensitive changes require the extra scrutiny described in [CONTRIBUTING.md](../../CONTRIBUTING.md).

1. **Read-only monitoring:** implement coordinator, accounting contracts, Unknown-aware pressure, breakdown, bounded chart, lifecycle demand and ⌘6. Test derivation/lifecycle. Validate proposed counter semantics on supported Macs before accepting the named breakdown for release; unsupported/inconsistent results show unavailable. No process actions yet.
2. **Read-only processes:** implement separate 5-second sampling, positive-evidence grouping, search/sort, explanations, age/partial states and safety labels. Fixtures cover PID reuse, inaccessible members, ancestry cycles, missing/reparented parents, competing app instances, deduplication, ownership and protected identities. Measure scan cost; no actions yet.
3. **Confirmed actions/history:** implement predicate eligibility/deny precedence, whole-set preflight, partial-target reconfirmation, per-request checks, app-wide transaction serialization/single-use tokens, lifecycle-safe observers, independent outcomes/measurements and bounded persistence. Test concurrent submissions, duplicate identities, page reconstruction, save-prompt deactivation, sleep/wake, exit deferral, observer/measurement interruption and history failure using injected time/lifecycle fakes only, never live termination. Mark action/security changes for CONTRIBUTING.md's elevated review.
4. **Settings/optional integrations:** add preferences/exclusions, off-by-default menu indicator and selected-threshold notifications through existing delegate/category ownership. Test defaults, denied permission, lifecycle/sleep/wake, Unknown startup, threshold changes, de-duplication, Review/default routing and preserved existing actions/categories. Complete EN/zh-Hans/RU resources and key/placeholder checks.
5. **Quality and documentation:** add or update the remaining unit tests and tab-shortcut tests; update README Features and keyboard shortcut sections; run the localization/design-token checks, the full macOS test suite, and Debug and Release builds. Measure idle CPU with at least 500 visible process rows on a recorded reference Mac; report the measurement method, duration, hardware, and result against the <2% target. Run EGM Drift Report and correct or explain every mismatch before the final report.

Each implementation increment is a separate commit and must build before the next begins. No increment adds `/usr/sbin/purge`, disk-cache reset, automatic app closure, or a new privileged `PurgeHelper` operation.

### Acceptance criteria

- Memory monitoring, grouped processes, action history, settings, exclusions, optional menu-bar display, and optional notifications are present; the last two are off on a fresh install.
- ⌘1–⌘5 continue to select their current tabs in the same order, and ⌘6 selects Memory in Review.
- Unknown, system-component/protected, root-owned, other-user, Purge/component and helper-only records cannot be acted on. Predicate eligibility and deny precedence are independently enforced; identity/freshness failures fail closed. Every Quit requires confirmation, Force Quit has its own confirmation, and normal timeout neither escalates nor diagnoses responsiveness.
- Memory string keys are present and non-empty in English, Simplified Chinese, and Russian, with matching placeholders. EN remains fallback; only Memory receives RU translations in v1. Formatting uses current system locale.
- No process contents are read or sent over the network. No new helper privilege or purge operation exists.
- Debug and Release builds have no new warnings from Memory files, all tests and localization checks pass, idle CPU is below 2% under the specified measurement, and EGM Drift Report findings are resolved or explicitly documented.
- Human review covers VoiceOver, Light/Dark appearance, each supported locale, confirmation copy, app quit/save behavior, stale-data presentation, and notification opt-in. Review findings do not substitute for these checks.

### Design references

- Apple documents memory-pressure dispatch sources as event sources: [DispatchSourceMemoryPressure](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure).
- Apple's Activity Monitor guide defines the system memory categories and describes Memory Pressure as a combined signal: [View memory usage in Activity Monitor](https://support.apple.com/guide/activity-monitor/actmntr1004/mac).
- Apple documents the runtime page-size API and 64-bit host statistics interface: [host_page_size](https://developer.apple.com/documentation/kernel/1502512-host_page_size), [host_statistics64](https://developer.apple.com/documentation/kernel/1502863-host_statistics64).
- Apple documents that `NSRunningApplication.terminate()` requests a normal quit and `forceTerminate()` attempts to force quit; a caller must observe `isTerminated` for completion: [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication).
- Apple documents language tables, fallback/localization workflows, and plural variations in Xcode: [Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog).

--------------------------------------------------------------------------------

*Drafted with EGM*


