#!/usr/bin/env python3
"""Check that a packaged macOS app loads its libraries and stays running."""

import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid


def smoke_test(app: Path) -> None:
    with (app / "Contents/Info.plist").open("rb") as stream:
        executable = plistlib.load(stream)["CFBundleExecutable"]
    environment = os.environ.copy()
    # Use the existing test-host isolation: no launch scans, updater or helpers.
    # No DYLD overrides: library loading must behave like a regular app launch.
    environment["XCTestSessionIdentifier"] = str(uuid.uuid4())
    with tempfile.TemporaryFile(mode="w+") as output:
        process = subprocess.Popen(
            [str(app / "Contents/MacOS" / executable)],
            env=environment, stdout=output, stderr=subprocess.STDOUT,
        )
        try:
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    output.seek(0)
                    raise RuntimeError(f"App exited at launch ({process.returncode}):\n{output.read()[-8000:]}")
                time.sleep(0.2)
            print("App launch passed: executable and embedded libraries loaded successfully.")
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    smoke_test(Path(sys.argv[1]).resolve())
