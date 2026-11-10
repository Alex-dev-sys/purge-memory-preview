#!/usr/bin/env python3
"""Compare a Git revision and the working tree in isolated, optimized macOS test hosts.

This creates disposable copies; it never changes production source files. TestHost
checks are bypassed ONLY in the two memory-observer files in the disposable copies.
The window is a hidden fixture whose visibility is controlled, and NSApp.isActive
is forced true in the coordinator. This measures the observer lifecycle without
activating a real window. Other launch, disk-scan, deletion and privilege guards
stay enabled. No cleanup requests are issued.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TEMPLATES = Path(__file__).resolve().parent


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def prepare(work, baseline):
    command(['git', 'archive', '--format=tar', '-o', str(work / 'baseline.tar'), baseline], cwd=ROOT)
    revision = subprocess.check_output(['git', 'rev-parse', baseline], cwd=ROOT, text=True).strip()
    (work / 'working-tree.patch').write_bytes(subprocess.check_output(['git', 'diff', baseline], cwd=ROOT))
    metadata = {'baseline_revision': revision, 'repetitions': 5,
                'build': 'Release, ENABLE_TESTABILITY=YES, coverage disabled',
                'machine': subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string', 'hw.memsize'], text=True).strip(),
                'os': subprocess.check_output(['sw_vers'], text=True).strip(),
                'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip()}
    (work / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    changed = subprocess.check_output(['git', 'diff', '--name-only', baseline], cwd=ROOT, text=True).splitlines()
    for label in ['before', 'after']:
        destination = work / label
        destination.mkdir()
        command(['tar', '-xf', str(work / 'baseline.tar'), '-C', str(destination)])
        if label == 'after':
            for relative in changed:
                source = ROOT / relative
                target = destination / relative
                if source.is_file():
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
                elif target.is_file():
                    target.unlink()
        for relative in ['purge/Services/Memory/MemoryCoordinator.swift', 'purge/Services/Memory/MemoryCleanupService.swift']:
            path = destination / relative
            path.write_text(path.read_text().replace('!TestHost.isActive()', 'true').replace('NSApp.isActive', 'true'))
        path = destination / 'purge/Services/Memory/MemoryCleanupService.swift'
        path.write_text(path.read_text().replace('    func tick() async {',
            '    private(set) var benchmarkTicks = 0\n    func tick() async {\n        benchmarkTicks += 1'))
        scheme = destination / 'purge.xcodeproj/xcshareddata/xcschemes/purge.xcscheme'
        scheme.write_text(scheme.read_text().replace('<TestAction\n', '<TestAction\n      codeCoverageEnabled = "NO"\n'))
        # Keep the same minimal test host on both sides; compile no unrelated test suites.
        tests = destination / 'PurgeTests'
        for path in tests.rglob('*.swift'):
            if str(path.relative_to(tests)) not in {'Support/FakeScans.swift', 'Support/ThrowawayDefaults.swift'}:
                path.unlink()
        shutil.copyfile(TEMPLATES / 'OptimizationBenchmarks.swift.txt', tests / 'OptimizationBenchmarks.swift')
    shutil.copyfile(TEMPLATES / 'ProcessCancellation.swift.txt', work / 'CancellationBenchmark.swift')


def run(work, package_cache):
    # Build both first so neither benchmark runs while a compiler is active.
    for label in ['before', 'after']:
        args = ['xcodebuild', 'build-for-testing', '-project', 'purge.xcodeproj', '-scheme', 'purge',
                '-configuration', 'Release', '-destination', 'platform=macOS',
                '-derivedDataPath', str(work / ('build-' + label)),
                '-enableCodeCoverage', 'NO', 'ENABLE_TESTABILITY=YES', 'ENABLE_HARDENED_RUNTIME=NO',
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS=BENCH_' + label.upper(),
                'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=YES', 'CODE_SIGNING_ALLOWED=YES']
        if package_cache:
            args += ['-clonedSourcePackagesDirPath', str(package_cache)]
        print('Building ' + label, flush=True)
        with (work / (label + '-build.log')).open('w') as log:
            command(args, cwd=work / label, stdout=log, stderr=subprocess.STDOUT)
        command(['xcrun', 'swiftc', '-O', '-D', 'BENCH_' + label.upper(),
                 str(work / label / 'purge/Utilities/ProcessRunner.swift'),
                 str(work / 'CancellationBenchmark.swift'), '-o', str(work / ('cancel-' + label))])
    for label in ['before', 'after']:
        print('Measuring ' + label, flush=True)
        with (work / (label + '.log')).open('w') as log:
            command(['xcodebuild', 'test-without-building', '-project', 'purge.xcodeproj', '-scheme', 'purge',
                     '-configuration', 'Release', '-destination', 'platform=macOS',
                     '-derivedDataPath', str(work / ('build-' + label)), '-parallel-testing-enabled', 'NO',
                     '-enableCodeCoverage', 'NO', '-only-testing:PurgeTests/OptimizationBenchmarks',
                     'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_REQUIRED=YES', 'CODE_SIGNING_ALLOWED=YES'],
                    cwd=work / label, stdout=log, stderr=subprocess.STDOUT)
        markers = work / ('cancel-' + label + '-markers')
        markers.mkdir()
        with (work / ('cancel-' + label + '.jsonl')).open('w') as output:
            command([str(work / ('cancel-' + label)), str(markers)], stdout=output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', default='HEAD', help='Git revision before optimization (default: HEAD)')
    parser.add_argument('--output', type=Path, help='New directory for disposable sources, builds and results')
    parser.add_argument('--package-cache', type=Path, help='Existing Xcode SourcePackages directory (optional)')
    options = parser.parse_args()
    work = options.output.resolve() if options.output else Path(tempfile.mkdtemp(prefix='purge-benchmark-', dir='/private/tmp'))
    work.mkdir(parents=True, exist_ok=True)
    if any(work.iterdir()):
        parser.error('Output directory must be empty')
    print('Artifacts: ' + str(work), flush=True)
    prepare(work, options.baseline)
    run(work, options.package_cache)
    command(['python3', str(TEMPLATES / 'summarize.py'), str(work)])


if __name__ == '__main__':
    main()
