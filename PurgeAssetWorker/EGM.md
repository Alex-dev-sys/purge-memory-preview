# PurgeAssetWorker

## Overview

Separate executable used by existing Apple Intelligence model operations. The app passes an operation and JSON argument to the worker, which returns a JSON response on standard output and exits; the app target does not link the worker's Objective-C runtime calls directly.

## Interface

- `PurgeAssetWorkerMain` reads operation input and dispatches `load`, `asset-type`, `reset`, `unsubscribe`, or `subscribe` requests to `UnifiedAssetCalls`.
- `UnifiedAssetCalls` dynamically loads `UnifiedAssetFramework`, checks classes/selectors and the XPC protocol before sending operations, and returns typed failures for unavailable interfaces or timed out requests.
- `Info.plist` identifies the worker as `io.getpurge.assetworker`.

## Invariants

- `reset` rejects an empty list or any empty asset-set name; `unsubscribe` and `subscribe` reject empty request lists.
- Replies are JSON-safe; values outside JSON's supported types are converted to descriptions.
- This existing worker uses Apple's private UnifiedAssetFramework through the Objective-C runtime. That implementation is isolated to Apple Intelligence asset handling and is not a precedent for the proposed Memory module.

## Side Effects

- Loads `/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework` at runtime and sends XPC requests to `com.apple.siri.uaf.subscription.service`.
- Reads the operation and JSON payload from command-line arguments and writes one JSON response to standard output.

## Verification

- Run: `xcodebuild test -project ../purge.xcodeproj -scheme purge -destination 'platform=macOS'`
- App-side asset operation coverage is in `PurgeTests/AppleIntelligenceModelStoreTests.swift` and `PurgeTests/AppleIntelligenceModelReaderTests.swift`.
