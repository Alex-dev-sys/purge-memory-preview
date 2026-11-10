<div align="center">
  <img src="Assets/purge-iOS-Default-1024x1024@1x.png" width="112" alt="Purge app icon" />
  <h1>Purge Memory Preview</h1>
  <p>A native macOS app for reviewing disk usage and managing memory.</p>
  <p>English · <a href="README.zh-CN.md">简体中文</a></p>
  <p>
    <a href="https://github.com/Alex-dev-sys/purge-memory-preview/releases"><b>Download a preview</b></a>
    · <a href="#memory">Memory</a>
    · <a href="#build-from-source">Build from source</a>
  </p>
  <a href="https://github.com/Alex-dev-sys/purge-memory-preview/actions/workflows/memory-preview.yml"><img src="https://img.shields.io/github/actions/workflow/status/Alex-dev-sys/purge-memory-preview/memory-preview.yml?branch=main&label=preview" alt="Preview build status" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license" /></a>
</div>

This is the Memory Preview fork of [Purge](https://github.com/jithin-sabu/purge-app). It combines the original disk cleanup tools with a Memory page, Russian and English language selection, and preview releases built on GitHub Actions.

Preview downloads use a separate app identifier and separate settings, data and helper names from the upstream app. They are ad-hoc signed, are not notarized, and do not use the upstream Sparkle update feed. Install updates from this repository's [Releases](https://github.com/Alex-dev-sys/purge-memory-preview/releases) page.

## Install

1. Open [Releases](https://github.com/Alex-dev-sys/purge-memory-preview/releases) and download a `Purge-Memory-Preview-…dmg` from a completed prerelease. Each DMG supports Apple silicon and Intel Macs.
2. Open the DMG and drag **Purge Memory Preview** into **Applications**.
3. Open the app. macOS may require you to approve an app distributed outside the App Store.
4. Grant **Full Disk Access** if you want the scans that need it. Without access, Purge still offers limited scans and explains which locations it cannot read.

To check the downloaded file, save the release's `SHA256SUMS.txt` beside the DMG and run:

```bash
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

An `OK` result confirms that the file matches the checksum published with that release. The upstream Homebrew cask installs upstream Purge, not this preview.

## Language

Open **Settings → General → Language** and choose **English**, **Русский**, or **System language**. Click **Restart Purge** to apply the choice throughout the app. Restart is unavailable during a cleanup or process action.

Russian text covers the interface, safety explanations, Finder/Siri actions and plural forms. Simplified Chinese is also available through the system-language option. Language selection affects this app, not the macOS language.

## Memory

Open **Memory** with **⌘6** to see memory status, estimated RAM usage and a collapsible list of applications grouped with their helper processes. Applications eligible for a confirmed quit request appear first; protected or unavailable groups follow. Name and memory-use sorting apply within those sections.

### Clean memory

The controls are on the **Memory** page and in **Settings → Memory**. Click **Clean Memory** to ask macOS to release reclaimable file-cache pages through its system `purge` command. Running applications stay open. Their live allocations and wired memory remain under application and macOS control, so this action cannot promise a particular amount of free RAM or reduce usage to a chosen target. Files on disk stay in place. Applications can fill the cache again as they continue working; re-reading uncached files may temporarily be slower.

Memory cleanup uses an optional, dedicated system service. Enabling that service requires approval in the native macOS administrator dialog. Purge does not store your password. The service runs only the fixed memory-cleanup command; it does not accept a shell command or arbitrary command-line arguments from the app.

After a cleanup, the app compares free-RAM samples taken before and after the request. The result is an **observed increase in free memory**, not an exact count of bytes reclaimed by `purge`: other applications can allocate or release memory during the same interval. A completed request may show **no measured increase**. When no valid before/after sample pair is available, the app reports that the change could not be measured instead of showing a reclaimed amount. Results are recorded in **Memory history**.

### Automatic cleanup

Automatic memory cleanup starts **off**. The initial timer interval is 30 minutes; the initial usage threshold is 85%. Choose a trigger in the Memory settings:

| Trigger | Options | When it runs |
| --- | --- | --- |
| **Timer** | Every 5, 15, 30 or 60 minutes | After the selected interval, while Purge is running and available for cleanup. |
| **RAM usage** | 70%, 80%, 85%, 90% or 95% | When estimated used RAM stays at or above the selected percentage for 30 seconds. |

The percentage is a trigger for a cache-release attempt, not a target to which RAM will be reduced. The used-RAM estimate counts app, wired and compressed memory; releasing file caches can increase free RAM while that percentage remains high.

Automatic requests are separated by at least five minutes. For a usage trigger to re-arm, usage must first fall five percentage points below the selected threshold. The system service also rejects requests made less than 60 seconds apart. These limits prevent a busy Mac from repeatedly clearing a cache it is immediately rebuilding.

The manual button is disabled during a disk cleanup or process action; automatic requests are deferred. Automatic cleanup runs only while Purge is running and pauses during sleep. To keep it available after closing the window, enable **Keep Purge in the menu bar**. Quitting Purge stops automatic requests; a schedule does not launch the app or run a cleanup on its own.

### Readings and process actions

Physical RAM categories and process footprints are different estimates. Neither is an exact per-app share of the system's used-memory figure. macOS manages RAM automatically; a low free-memory figure alone does not mean the Mac is unhealthy. When macOS has not supplied a memory-status event, the page keeps the status badge hidden rather than labelling it Normal.

**Quit** and **Force Quit** are separate, confirmed process actions. They apply only to recognized user applications and protect system processes, Purge and its helpers, excluded apps and targets that fail identity checks. A normal quit is never silently escalated to Force Quit. Memory cleanup does not use either process action. History and exclusions stay on the Mac.

In **Settings → Memory**, choose a one- or two-second aggregate refresh interval, enable the optional menu-bar indicator, or request notifications for sustained Warning or Critical memory status. Notifications wait for 60 seconds at the selected level and require macOS notification permission. The menu indicator and notifications start off. Process details refresh every five seconds while the Memory page is visible; background process polling is off.

## Disk tools

| Area | What it provides |
| --- | --- |
| **Overview** | Used, free and total disk space; category totals; a read-only map of uncategorized space. |
| **App Caches** | Known application caches, logs, crash reports and supported system leftovers, with explanations and safety labels. |
| **Dev Tools** | Global developer caches, project build/dependency folders, unused simulators and simulator runtimes. Active projects and registered Git worktrees are protected. |
| **Large Files** | Search and filters for personal files, local AI models and virtual machines; byte-for-byte duplicate detection; Quick Look and Finder actions. |
| **App Uninstaller** | Installed apps, associated support files, leftovers from removed apps and command-line tools, with a review before removal. |

**Clean Safe Items** combines eligible App Caches and Dev Tools results. **Check First** and **Not Sure** items require review. Disk cleanup can also run on an optional schedule, separately from Memory settings.

Large Files are personal files, not caches. They are not part of an automatic safe cleanup. **Keep Only in iCloud** removes a fully synced file's downloaded copy from this Mac while keeping the iCloud file; it is a separate, reviewed action.

On supported Macs, the Overview also offers Time Machine local snapshot management and Apple Intelligence model management. Model removal requires macOS 27 and Apple silicon; downloading again asks Apple's service for the model sets Purge removed.

### What can be restored

Files and folders move to the **Trash** by default. Purge does not empty it. You can restore those files until you empty the Trash yourself.

Some actions use another system or app's removal mechanism and do not use the Trash:

- iOS simulators and simulator runtimes are removed through Xcode's `simctl`.
- Time Machine local snapshots are removed through `tmutil`; the newest snapshot and the one from the last backup are kept.
- Apple Intelligence models are released through Apple's asset service and can be downloaded again.
- Command-line tools and Homebrew cask apps are deleted by their package manager when you choose that option in the review.

The confirmation sheet describes the action before it runs. Docker Desktop's data folder goes to the Trash; Purge does not run `docker system prune`.

## Build from source

You need macOS 13 or later and Xcode 26 or later. Xcode 26 supplies the Swift 6.2 features used by the project. Node.js and Python 3 are needed for the repository checks; npm dependencies are only needed to regenerate the checked-in brand icons.

Use a separate checkout for a preview build: the configuration script changes the checkout's identifiers, helper filenames and URL scheme, and disables Sparkle updates.

```bash
git clone https://github.com/Alex-dev-sys/purge-memory-preview.git
cd purge-memory-preview
python3 scripts/configure-memory-preview.py

xcodebuild build \
  -project purge.xcodeproj \
  -scheme purge \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/local \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  COMPILER_INDEX_STORE_ENABLE=NO

open build/local/Build/Products/Debug/Purge.app
```

Swift Package Manager downloads [Sparkle](https://github.com/sparkle-project/Sparkle) on the first build. It remains linked in the preview, but its updater is disabled. Preview builds disable Hardened Runtime because an ad-hoc app identity cannot match Sparkle's Developer ID signature; the release workflow checks that the finished app actually launches.

### Checks and tests

Run the source checks:

```bash
node scripts/lint-design-tokens.mjs
python3 scripts/check-localization.py
```

Run the main test suite with ad-hoc signing:

```bash
xcodebuild test \
  -project purge.xcodeproj \
  -scheme purge \
  -destination 'platform=macOS' \
  -derivedDataPath build/tests \
  -parallel-testing-enabled NO \
  -skip-testing:PurgeTests/ProcessRunnerTests \
  -skip-testing:PurgeTests/FolderSizingConcurrencyTests \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES
```

Run the two stress suites separately with the same project, scheme, destination and derived-data path, using `test-without-building` and either `-only-testing:PurgeTests/ProcessRunnerTests` or `-only-testing:PurgeTests/FolderSizingConcurrencyTests`. CI uses this split so their worker-pool stress does not interfere with unrelated asynchronous tests.

The optional Apple Intelligence language-alias integration test requires `PURGE_SYSTEM_INTEGRATION_TESTS=1` on a Mac with the corresponding assets installed. Regular alias-resolution tests use fixtures.

To regenerate brand icons:

```bash
npm ci
npm run generate:icons
```

### GitHub releases

A push to `main`, or a manual **Memory preview** workflow run on `main`, starts tests and universal Release packaging in parallel. Publication waits for both jobs to pass. The workflow verifies signatures, checks both architectures, launches the app, creates a DMG and publishes it with `SHA256SUMS.txt`. The same files are kept as an Actions artifact.

Xcode products, compiler modules and Swift packages are cached per Xcode version. Source timestamps are restored only when their content hash matches the cached file, allowing unchanged files to reuse compiler outputs. Stress suites reuse their test build. A newer push cancels an older preview workflow for the same branch.

## Privacy and safety

Scans, memory samples, exclusions, settings and histories are handled locally. No file contents or memory samples are sent to an AI service. Duplicate detection compares files on the Mac. Preview builds do not contact the upstream Sparkle update feed. Explicit download actions, such as fetching Apple Intelligence models again, use their owning service.

Disk removal is constrained by allowlists and protected paths. The read-only Everything Else map does not remove files. Memory actions have their own process-identity checks and exclusions. See [SECURITY.md](SECURITY.md) for the underlying project's security model and reporting guidance; signing and update claims for upstream releases do not describe these ad-hoc preview builds.

## Uninstall

Use **Uninstall Purge…** in the app menu or Settings to review and remove the app's background components before it moves itself to the Trash. This turns off automatic memory cleanup and includes removal of its dedicated system service; approve the macOS administrator dialog when asked. Settings and history are kept unless you also select their removal. Full Disk Access must be removed separately in macOS System Settings.

If you plan to remove the app directly in Finder, first open the information button (ⓘ) beside **Memory cleaning**, then choose **Remove memory cleaning permission** and approve removal of the service. Dragging the app to the Trash does not remove a separately installed system service.

## Project and license

This fork is based on [jithin-sabu/purge-app](https://github.com/jithin-sabu/purge-app), created by Jithin Sabu. The app and this fork are released under the [MIT License](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) for repository guidance.
