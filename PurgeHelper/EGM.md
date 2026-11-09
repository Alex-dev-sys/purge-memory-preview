# PurgeHelper

## Overview

This launchd-managed privileged helper exposes the Purge helper XPC service and moves approved paths into the connecting user's Trash. Its entry point starts an `NSXPCListener` and keeps the process on the main run loop (`main.swift:listener`, `main.swift:RunLoop.main.run()`).

## Interface

- `HelperListenerDelegate` implements `NSXPCListenerDelegate`, installs the configured client code-signing requirement, exports `PurgeHelperProtocol`, and supplies a `HelperService` (`HelperListenerDelegate.swift:HelperListenerDelegate.listener(_:shouldAcceptNewConnection:)`; `../purge/PrivilegedHelper/PurgeHelperProtocol.swift:PurgeHelperConstants.clientRequirement`).
- `HelperService` implements `PurgeHelperProtocol` replies for `helperVersion(withReply:)`, `moveToTrash(paths:withReply:)`, `moveToTrashReportingOwnership(paths:withReply:)`, `moveToTrashReportingFailures(paths:withReply:)`, and `moveToTrashWithAuthorization(paths:authorization:withReply:)` (`HelperService.swift:HelperService`). The protocol declaration is in [`PurgeHelperProtocol.swift`](../purge/PrivilegedHelper/PurgeHelperProtocol.swift), which the `PurgeHelper` target compiles (`purge.xcodeproj/project.pbxproj:521`).
- `io.getpurge.helper.plist` declares the `io.getpurge.helper` launchd label and Mach service, associated with `io.getpurge.app` (`io.getpurge.helper.plist:Label`, `io.getpurge.helper.plist:MachServices`, `io.getpurge.helper.plist:AssociatedBundleIdentifiers`).

## Invariants

- The listener sets `PurgeHelperConstants.clientRequirement` before resuming a new connection, exports `PurgeHelperProtocol`, and refuses the connection if the idle tracker cannot acquire a lease (`HelperListenerDelegate.swift:HelperListenerDelegate.listener(_:shouldAcceptNewConnection:)`, `../purge/PrivilegedHelper/PurgeHelperProtocol.swift:PurgeHelperConstants.clientRequirement`).
- A move requires a current XPC peer with a non-root effective UID that resolves to a user record; the destination must be that user's `.Trash` directory, opened without following symlinks and owned by that UID (`HelperService.swift:HelperService.performMove(paths:authorization:)`, `HelperService.swift:HelperService.validatedTrashDirectory(fileDescriptor:ownerUID:)`).
- Each source must pass `PurgeHelperConstants.isAllowedMoveSource`; standard-account requests require administrator approval, and legacy methods without authorization refuse them (`HelperService.swift:HelperService.allowedSources(_:homeDirectory:outcome:)`, `HelperService.swift:HelperService.administratorApproval(_:)`).
- Source and Trash operations use open directory descriptors and no-follow opens; destination renames use `RENAME_EXCL`, and owner changes do not follow symlinks or change multiply-linked files (`HelperService.swift:HelperService.secureMoveToTrash(_:trashFD:uid:gid:)`, `HelperService.swift:HelperService.renameToUniqueDestination(_:sourceParentFD:sourceName:trashFD:)`, `HelperService.swift:HelperService.chownRecursively(fileDescriptor:uid:gid:)`, `../purge/PrivilegedHelper/HelperSupport.swift:HelperDirectory.openWithoutFollowingSymlinks(_)`, `../purge/PrivilegedHelper/HelperSupport.swift:HelperLinkPolicy.mayChangeOwner(mode:linkCount:)`).

## Side Effects

- Moves accepted paths from their source directories into the peer user's Trash, then recursively attempts to return ownership to that user; incomplete ownership is reported separately from paths that moved (`HelperService.swift:HelperService.performMove(paths:authorization:)`, `HelperService.swift:HelperService.chownRecursively(fileDescriptor:uid:gid:)`).
- Writes the configured macOS authorization right before requesting administrator approval for an authorized standard-account request (`HelperService.swift:HelperService.administratorApproval(_:)`).
- Emits helper and move diagnostics through `NSLog` and `Logger`; the idle tracker can terminate the process after its idle interval (`HelperListenerDelegate.swift:HelperListenerDelegate`, `HelperService.swift:HelperService`).

## Verification

- Run from this directory: `xcodebuild -project ../purge.xcodeproj -scheme purge test` (the shared `purge` scheme includes the `PurgeTests` test target).
