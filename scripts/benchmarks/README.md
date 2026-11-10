# Optimization comparison

Run on macOS with Xcode. The runner compares a Git revision with the tracked
working-tree changes in two disposable copies, builds both with Release
optimization and coverage disabled, and runs the same fixture on each.
It leaves production source files, preferences and personal files untouched.

```sh
python3 scripts/benchmarks/run.py --baseline 449b3f0fa300a667b271ce6202e9e84273b65a49
```

An optional `--package-cache /path/to/SourcePackages` reuses Xcode's package
checkout. `--output /new/empty/directory` chooses where artifacts are kept.
The runner writes source snapshots, build/test logs, metadata, the compared
patch, JSONL measurements and `summary.json` there. Both builds finish before
measurements begin. These are fixture benchmarks, not a full filesystem scan
or a test of rendering the real SwiftUI list.

The fixture measures:

- Actual `PurgeStore.scanLargeFiles` with 1,000 and 10,000 deterministic metadata
  rows from `FakeScans`, one warm-up and five measured runs. Duplicate hashing is
  disabled by giving the fixture rows `canMoveToTrash: false`. It checks the final
  row count and sorted order and counts every `largeFiles` publication, including
  resets. A 2 ms main-actor heartbeat records scheduling gaps, not frame times.
- Actual memory-group construction, ordering and repeated footprint reads: five
  runs of 1,000 samples, 200 groups and eight members per group. A checksum guards
  the result against elimination and verifies equivalence across versions.
- Memory observer initialization plus 30 seconds in each of two scenarios:
  no memory page; a visible memory page with its process list collapsed. These
  are single runs. An instrumented counter records cleanup ticks; a wrapper
  counts real `ProcessMemoryProvider` samples. No cleanup request is issued.
- Actual `ProcessRunner` source compiled separately with `swiftc -O`. A child
  runs `sleep 2`; cancellation is requested 50 ms after its ready marker. Five
  runs measure time from cancellation to completion. This tests cancellation
  behavior, not `du` traversal speed or the full 300-second sizing timeout.

For the observer scenarios only, the disposable copies permit the two memory
observer services to start inside the test host and force the coordinator's
app-active condition true. A hidden window fixture reports itself as visible.
The same instrumentation is applied to both versions; other test-host guards
stay enabled. This avoids activating a user window or triggering real scans,
cleanup, registration or privileged actions. Only the minimal benchmark test
and its two fixture helpers are compiled into the test bundle.

CPU milliseconds come from `getrusage(RUSAGE_SELF)` user plus system time.
CPU percentages use one core as 100%. Memory values use MiB and come from
`task_info(TASK_VM_INFO)` resident size and physical footprint at the endpoints;
they are not peak usage. Allocation history and background application work
can affect them. Single 30-second observer runs include initialization and do
not establish steady-state CPU, battery savings or a stable RAM reduction.
