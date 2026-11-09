# PrivilegedHelper

## Overview

`purge/PrivilegedHelper` is the app-side contract and shared support code for Purge's root privileged helper. It defines the XPC protocol and every identifier, version, authorization right, and code-signing requirement both ends use; manages registration through `SMAppService`; reconciles an installed helper against the version this app ships; and provides the escalation entry point used by the deletion engine when an uninstall cannot move admin-owned files as the user.

The helper exists to do exactly one thing: move already-chosen paths into the connecting user's Trash as root and hand ownership back. There is deliberately no shell, script, or arbitrary-command surface. The path allowlist is enforced on both sides: the scanner and the helper compile `PurgeHelperConstants` and `MacOSInstallLeftovers`, and the helper re-checks every path after any authorization dialog before moving anything. The actual daemon target compiles the shared files here (`PurgeHelperProtocol.swift`, `MacOSInstallLeftovers.swift`, and `HelperSupport.swift`) so the app's tests exercise the exact rules the root process runs.

## Interface

**Protocol, constants, and code-signing identity**

- `PurgeHelperConstants` (`PurgeHelperProtocol.swift:PurgeHelperConstants`): the single source of truth shared by app and helper.
  - `machServiceName = "io.getpurge.helper"` — launchd label, Mach service name, and helper bundle identifier.
  - `version = "8"` — helper build version; the app compares it with the running helper's answer.
  - `removalRightName = "io.getpurge.helper.remove-admin-locked-app"` — authorization right used for a standard account.
  - `removalRightDefinition` — dictionary defining the right: `class` `user`, `group` `admin`, `authenticate-user` true, `shared` false, `timeout` 0, `allow-root` false, `session-owner` false, `tries` 10_000, plus localized `default-prompt` strings.
  - `outsideAllowedLocationsCode = -1` — failure code for a path outside the helper's allowed locations; every other failure code is an errno and never negative.
  - `daemonPlistName = "io.getpurge.helper.plist"` — the bundled daemon plist passed to `SMAppService.daemon(plistName:)`.
  - `teamIdentifier = "BX83ZBV95B"`, `clientRequirement`, and `helperRequirement` — the same-team, Apple-notarized signing requirements.
  - `leftoverRoots(homeDirectory:)`, `isAllowedUninstallLocation(_:homeDirectory:)`, `isAllowedInstallLeftoverLocation(_:root:)`, and `isAllowedMoveSource(_:homeDirectory:installLeftoverRuleHolds:)` — the path allowlist.
  - Private root lists `userLeftoverRelativeRoots` (nine `Library/...` folders under home) and `systemLeftoverRoots` (`/Library/LaunchDaemons`, `/Library/Application Support`, `/Library/LaunchAgents`).
- `HelperMoveRefusal` (`PurgeHelperProtocol.swift:HelperMoveRefusal`): `Int` raw-value refusal for a whole request — `.accepted = 0`, `.notAdministrator = 1`, `.invalidTrash = 2`, `.invalidPeer = 3`, `.approvalUnavailable = 4`.
- `PurgeHelperProtocol` (`PurgeHelperProtocol.swift:PurgeHelperProtocol`): `@objc(PurgeHelperProtocol)` XPC protocol with:
  - `moveToTrash(paths:withReply:)` — legacy move, returns moved paths; retained for wire compatibility with a v2 app talking to a v3 helper.
  - `moveToTrashReportingOwnership(paths:withReply:)` — also returns moved paths whose ownership could not be fully handed back.
  - `moveToTrashReportingFailures(paths:withReply:)` — also returns `failureCodes` and a `HelperMoveRefusal` raw value; used with v7 helpers.
  - `moveToTrashWithAuthorization(paths:authorization:withReply:)` — v8 form; carries an `AuthorizationExternalForm` as `Data` so the helper can show the administrator dialog in the app's session; used with v8 helpers.
  - `helperVersion(withReply:)` — round-trips the helper build version.

**Escalation entry point**

- `PrivilegedMoveResult` (`PrivilegedUninstall.swift:PrivilegedMoveResult`): `moved`, `failed`, `indeterminate`, `ownershipIncomplete`, `helperAvailable`, `refusal`, and `failureCodes` (keyed by `URL`). `indeterminate` means no reply, so the caller must not claim success or failure until it checks the disk.
- `PrivilegedUninstall.moveToTrash(_:)` (`PrivilegedUninstall.swift:PrivilegedUninstall.moveToTrash(_:)`): the deletion engine's single escalation entry. It ensures `~/.Trash` exists, calls `PrivilegedHelperManager.shared.moveToTrash(urls)`, and returns either the helper result or a result with `helperAvailable: false`, `failed: urls`, and nothing moved.

**Manager and version reconciliation**

- `PrivilegedHelperManager` (`PrivilegedHelperManager.swift:PrivilegedHelperManager`): `@MainActor final class ObservableObject`, `shared`, `isUnresponsive`, and a computed `service` that re-creates `SMAppService.daemon(plistName:)` on every read.
- `PrivilegedHelperManager.Registration` (`.enabled`, `.needsApproval`, `.failed(String)`), `status`, `statusOffMain()`, `register()`, `unregister()`, and `openLoginItemsSettings()`.
- `PrivilegedHelperManager.vettedConnection()`: builds an `NSXPCConnection(machServiceName:options: .privileged)`, sets `remoteObjectInterface` to `PurgeHelperProtocol`, applies `helperRequirement` with `setCodeSigningRequirement`, and resumes.
- `PrivilegedHelperManager.moveToTrash(_:)` and `moveToTrashNow(_:)`: serialize moves through `lastMove`, reconcile the helper version first, and call `moveToTrashWithAuthorization(paths:authorization:withReply:)` with an `AdministratorApproval.externalForm` and the v8 reply handler. Timeout and XPC-error paths return `indeterminate: urls`.
- `PrivilegedHelperManager.installedHelperVersion()`: calls `helperVersion` with the version timeout; `nil` means no answer, distinct from a version string.
- `PrivilegedHelperManager.reconcileVersion()`: delegates to `HelperReconciler.reconcile(isEnabled:expectedVersion:probe:reload:)`, stores `isUnresponsive`, and returns whether the helper is ready.
- `PrivilegedHelperManager.reloadRegistration()` and `mayRepairRegistration(bundleURL:homeDirectory:environment:)`: unregister/register repair, allowed only from an installed `/Applications` or `~/Applications` copy and never in the test host.
- Timeouts: `moveTimeout = 300`, `approvalTimeout = 1_800`, `versionTimeout = 10`.
- `HelperReconcileOutcome` (`PrivilegedHelperManager.swift:HelperReconcileOutcome`): `.notEnabled`, `.ready`, `.unresponsive`, `.staleVersion`.
- `HelperReconciler.reconcile(isEnabled:expectedVersion:probe:reload:)` (`PrivilegedHelperManager.swift:HelperReconciler.reconcile(isEnabled:expectedVersion:probe:reload:)`): probes the version, reloads once if stale or silent, re-checks enablement, and probes again; a `nil` reload skips repair.
- `AdministratorApproval` (`PrivilegedHelperManager.swift:AdministratorApproval`): creates an empty `AuthorizationRef` with `AuthorizationCreate`, exposes `externalForm: Data` via `AuthorizationMakeExternalForm`, and `free()` uses `AuthorizationFree(..., [.destroyRights])`.

**Preference store**

- `PrivilegedHelperPreferenceStore` (`PrivilegedHelperPreferenceStore.swift:PrivilegedHelperPreferenceStore`): `@MainActor final class ObservableObject`, `shared`, `@Published status: SMAppService.Status`, `lastRegistrationFailed`, `isUnresponsive`, `isEnabled`, `needsApproval`, `refresh()`, `setEnabled(_:)`, `turnOffForUninstall()`, `openLoginItemsSettings()`, and private `apply(_:)`, `monitorPendingApproval()`.
- `setEnabled(_:)` records `desiredEnabled`, chains `applyTask` so register/unregister calls never overtake each other, opens Login Items when approval is required, and starts approval polling.
- `monitorPendingApproval()` polls up to 600 times at 500 ms (about five minutes), reads status through `statusOffMain()`, and stops when enabled, no longer pending, superseded, or cancelled.

**Shared helper support primitives**

- `HelperDirectory.openWithoutFollowingSymlinks(_:)` (`HelperSupport.swift:HelperDirectory.openWithoutFollowingSymlinks(_:)`): opens an absolute path from `/` one component at a time with `O_SEARCH | O_NOFOLLOW | O_CLOEXEC` (root opened with `O_SEARCH | O_CLOEXEC`), refuses `.`, `..`, and empty components, and returns an owned file descriptor.
- `HelperLinkPolicy.refusal(forSourceMode:linkCount:isAppBundlePath:)` (`HelperSupport.swift:HelperLinkPolicy.refusal(forSourceMode:linkCount:isAppBundlePath:)`): returns `EFTYPE` unless the source is a directory or regular file; an `.app` path must be a directory; a regular file with `linkCount > 1` returns `EMLINK`.
- `HelperLinkPolicy.mayChangeOwner(mode:linkCount:)`: folders may always have ownership handed back; a non-folder needs `linkCount <= 1`.
- `HelperIdleTracker` (`HelperSupport.swift:HelperIdleTracker`): `@unchecked Sendable` class with `start()`, `acquire()`, `release()`, `idleInterval`, `Scheduler`, and `onIdle`. It counts holds, bumps a generation per change, and refuses `acquire()` once `exiting`.
- `AdministratorMembership.includes(userName:primaryGID:)` and `AdministratorMembership.currentUserIsAdministrator()` (`HelperSupport.swift:AdministratorMembership`): local `admin` group membership via `getgrouplist`; `UserRecord.lookUp(uid:)` (`HelperSupport.swift:UserRecord.lookUp(uid:)`) reads the account record with `getpwuid_r` and returns `name`, `primaryGID`, and `home`.

**macOS install leftovers**

- `MacOSInstallLeftovers` (`MacOSInstallLeftovers.swift:MacOSInstallLeftovers`): `root` (`/System/Volumes/Data/macOS Install Data`), `systemVersionFile`, `installHistoryFile`, `lockedFilesName = "Locked Files"`, `isEntryPath(_:root:)`, `entries(root:)`, `systemInstalledDate(systemVersionFile:installHistoryFile:now:)`, `isLeftover(root:systemVersionFile:installHistoryFile:now:)`, and private `itemDates(atPath:)`, `readPropertyList(_:)`.

## Invariants

- **One shared source of truth.** `PurgeHelperProtocol.swift:PurgeHelperConstants` is compiled into both targets, so the Mach service name, daemon plist name, version, refusal codes, authorization right, code-signing requirements, and leftover root lists cannot drift between app and helper. A drift would otherwise appear only as a silent XPC failure.
- **Version compatibility is exact.** `PrivilegedHelperManager.swift:moveToTrashNow(_:)` calls `reconcileVersion()` before sending work and aborts with `nil` unless the enabled helper reports `PurgeHelperConstants.version` exactly. The app never sends a move to a stale, old, or unresponsive helper. The protocol keeps older methods (`moveToTrash`, `moveToTrashReportingOwnership`, `moveToTrashReportingFailures`) for wire compatibility, but current code calls only the v8 `moveToTrashWithAuthorization` after reconciliation.
- **Code-signing requirements are mutual and team-pinned.** `PurgeHelperProtocol.swift:clientRequirement` requires `identifier "io.getpurge.app"`, `anchor apple generic`, and `certificate leaf[subject.OU] = "BX83ZBV95B"`; `PurgeHelperProtocol.swift:helperRequirement` requires the same team and `identifier "io.getpurge.helper"`. The app applies `helperRequirement` in `vettedConnection()` with `NSXPCConnection.setCodeSigningRequirement`; the helper applies `clientRequirement` to callers. A differently signed binary can neither impersonate the app to the helper nor the helper to the app.
- **The authorization right is per-request administrator approval.** `PurgeHelperProtocol.swift:removalRightDefinition` uses `shared: false`, `timeout: 0`, `group: admin`, `authenticate-user: true`, `allow-root: false`, and `session-owner: false`, so a password typed earlier in the session cannot satisfy a new move and every request asks again. Because any process can define an unknown right first, the helper writes this definition as root before every check; changing an existing right requires administrator or root.
- **The helper has no arbitrary-command or arbitrary-write primitive.** `PurgeHelperProtocol.swift:PurgeHelperProtocol` accepts only `[String]` paths, an authorization `Data` blob, and replies; there is no command, script, destination, or environment parameter. The documented operation is a move into the connecting user's Trash plus ownership hand-back. Out-of-allowlist paths fail with `outsideAllowedLocationsCode = -1`; every other per-path failure code is an errno (non-negative).
- **The path allowlist is enforced by the shared rules, never trusted from XPC.** `PurgeHelperProtocol.swift:isAllowedUninstallLocation(_:homeDirectory:)` accepts only:
  - a direct child of a root returned by `leftoverRoots(homeDirectory:)` (the user's nine `~/Library/...` roots plus `/Library/LaunchDaemons`, `/Library/Application Support`, and `/Library/LaunchAgents`), or
  - a path whose extension is `.app` that `AppBundleReach.folderDepth(ofAppAtPath:roots:)` finds at any depth under `/Applications` or `~/Applications`, never through another bundle or package.
- **Symlinks are rejected before the allowlist is trusted.** `PurgeHelperProtocol.swift:isAllowedUninstallLocation` compares `standardizedFileURL.path` with `resolvingSymlinksInPath().standardizedFileURL.path` and rejects any difference. `HelperSupport.swift:HelperDirectory.openWithoutFollowingSymlinks(_:)` then walks every component with `O_NOFOLLOW`, so an allowed-looking path cannot redirect the root process between components. `MacOSInstallLeftovers.swift:itemDates(atPath:)` uses `lstat`, so a symlink is judged as itself and never followed.
- **macOS install leftovers have a separate, stricter rule.** `PurgeHelperProtocol.swift:isAllowedInstallLeftoverLocation(_:root:)` accepts only a direct child of `MacOSInstallLeftovers.root` that passes `MacOSInstallLeftovers.isEntryPath(_:root:)`: non-empty, no deeper slash, not `.` or `..`, not hidden, and not `Locked Files`. `MacOSInstallLeftovers.swift:isLeftover(...)` additionally requires the folder and every item at every depth to be older than the running system's installed date, using the later of modification and change time, with a non-empty entry list; a missing or unreadable item answers `false`, and a root that is a symlink fails the `isDirectory` check.
- **The install-leftover date rule is computed once per request, by the helper.** `MacOSInstallLeftovers.swift:isLeftover(...)` notes that moving an entry bumps the folder's date, so the helper evaluates the rule before it moves anything and never takes the app's word for it. `isAllowedMoveSource(_:homeDirectory:installLeftoverRuleHolds:)` combines the ordinary allowlist with the leftover rule.
- **Hard links are refused where they would leak root-owned files.** `HelperSupport.swift:HelperLinkPolicy.refusal(forSourceMode:linkCount:isAppBundlePath:)` refuses any regular file with a second name (`EMLINK`), because a hard link to a root-owned file could otherwise be moved and handed back to an unprivileged account. `mayChangeOwner(mode:linkCount:)` never changes ownership of a non-folder with a second name.
- **The helper never creates the user's Trash.** `PrivilegedUninstall.swift:PrivilegedUninstall.moveToTrash(_:)` creates `~/.Trash` with `0o700` before asking the helper, so the directory belongs to the signed-in user. The helper validates it and refuses with `HelperMoveRefusal.invalidTrash` when it is missing, a symlink, or not the user's.
- **There is no unprivileged fallback.** `PrivilegedUninstall.swift:PrivilegedUninstall.moveToTrash(_:)` documents that escalation goes through the signed helper and nothing else; the old `osascript` route was removed because macOS showed a malware-verification dialog. If the helper is unavailable, nothing moves and `helperAvailable` is `false`, so the UI can invite setup instead of claiming failure.
- **A timeout is uncertainty, not failure.** `PrivilegedHelperManager.swift:moveToTrashNow(_:)` returns `indeterminate: urls` on timeout or XPC error, because the helper may already have moved some paths. The move timeout is 300 seconds; a standard account gets an additional 1,800 seconds for the administrator dialog. The version probe has a 10-second timeout and distinguishes `nil` (no answer) from a version string.
- **Moves are serialized.** `PrivilegedHelperManager.swift:moveToTrash(_:)` chains each move on `lastMove`, so Retry on several rows cannot put up multiple administrator dialogs at once (#314).
- **Self-repair is restricted to installed copies.** `PrivilegedHelperManager.swift:mayRepairRegistration(bundleURL:homeDirectory:environment:)` returns false in `TestHost.isActive(environment:)` and otherwise requires the standardized bundle path to start with `/Applications/` or `~/Applications/`. Registering from a dev build, disk image, or test host would tie the daemon to a copy that can disappear. Turning the switch on in Settings still works from anywhere because the user chose it.
- **Idle quit is hold-based and race-free.** `HelperSupport.swift:HelperIdleTracker` quits only after no holds for `idleInterval`; a move keeps its own hold, so a slow ownership hand-back is not cut short. Once `exiting` is set under the lock, `acquire()` refuses new work, and a generation check makes timers armed before the latest change inert.
- **Administrator status is read from the local directory service.** `HelperSupport.swift:AdministratorMembership.includes(userName:primaryGID:)` uses `getgrouplist` against the local `admin` group and treats any failed lookup as "not an administrator". `UserRecord.lookUp(uid:)` uses `getpwuid_r`, not the helper's root environment.
- **Status reads are always current.** `PrivilegedHelperManager.swift:service` re-creates `SMAppService.daemon(plistName:)` on every read rather than caching a status snapshot; `statusOffMain()` does the same on a detached utility task. `PrivilegedHelperPreferenceStore.swift:apply(_:)` assigns `status` only on change to avoid re-rendering observers during 500 ms approval polling.
- **Registration requests settle on the last user intent.** `PrivilegedHelperPreferenceStore.swift:setEnabled(_:)` records `desiredEnabled` and chains `applyTask`; a superseded request returns without acting, and `turnOffForUninstall()` awaits the queued unregister so Uninstall Purge reads a completed result.
- **Test-host guard.** `PrivilegedHelperManager.swift:mayRepairRegistration(bundleURL:homeDirectory:environment:)` checks `TestHost.isActive(environment:)` before any registration repair, so the unit-test host cannot re-register the daemon or mutate its launchd state.

## Side Effects

- **XPC connections and calls:** `PrivilegedHelperManager.vettedConnection()` opens a privileged `NSXPCConnection` to `io.getpurge.helper` and applies `helperRequirement`; `moveToTrashNow(_:)` calls `moveToTrashWithAuthorization(paths:authorization:withReply:)`; `installedHelperVersion()` calls `helperVersion(withReply:)`; both invalidate their connection with `connection.invalidate()`. The helper side, outside this directory, receives the move and performs the file moves.
- **Authorization Services prompts:** `AdministratorApproval.init` calls `AuthorizationCreate(nil, nil, [], &created)` and `AuthorizationMakeExternalForm`; `free()` calls `AuthorizationFree(authorization, [.destroyRights])`. The external form is sent so the helper's macOS administrator dialog appears in the app's session, for a standard account only; the right is destroyed after the request.
- **File-system mutation:** `PrivilegedUninstall.moveToTrash(_:)` creates `~/.Trash` with `0o700` when missing. The helper moves the requested paths into that Trash and hands ownership back to the connecting user; those moves are the directory's external, irreversible-without-Trash effect.
- **Service Management state:** `PrivilegedHelperManager.register()` calls `SMAppService.daemon(plistName:).register()`; `unregister()` awaits `unregister()`; `status` and `statusOffMain()` read `SMAppService.Status`; `openLoginItemsSettings()` calls `SMAppService.openSystemSettingsLoginItems()`. `PrivilegedHelperPreferenceStore.refresh()` and approval polling repeatedly read status.
- **System reads:** `MacOSInstallLeftovers.systemInstalledDate(...)` reads `/System/Library/CoreServices/SystemVersion.plist` and `/Library/Receipts/InstallHistory.plist`; `entries(root:)` and `isLeftover(...)` enumerate `/System/Volumes/Data/macOS Install Data`. These calls do not write system files.
- **File descriptors:** `HelperDirectory.openWithoutFollowingSymlinks(_:)` opens and closes a descriptor per path component and returns the final descriptor, which the caller owns and must close.
- **Logging:** `PrivilegedHelperManager.swift` emits `NSLog` lines for XPC errors, stale helpers, failed registration, and failed unregistration; `PrivilegedHelperPreferenceStore.swift:apply(_:)` logs every status change with `NSLog`.
- **No user-defaults access and no generic process launch:** these files do not read or write `UserDefaults`, and they do not spawn arbitrary subprocesses; the daemon itself is started by launchd through `SMAppService`.

## Verification

- Run: `xcodebuild -project purge.xcodeproj -scheme purge -destination 'platform=macOS' test`
