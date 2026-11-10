#!/usr/bin/env python3
"""Preserve unchanged source timestamps so restored Xcode builds stay incremental."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def restore_and_record(root: Path, manifest: Path) -> int:
    previous = json.loads(manifest.read_text()) if manifest.is_file() else {}
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=root)
    current = {}
    restored = 0
    for name in tracked.decode().split("\0"):
        if not name:
            continue
        path = root / name
        if not path.is_file() or path.is_symlink():
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        cached = previous.get(name)
        if cached and cached["sha256"] == digest:
            os.utime(path, ns=(path.stat().st_atime_ns, cached["mtime_ns"]))
            restored += 1
        current[name] = {"sha256": digest, "mtime_ns": path.stat().st_mtime_ns}
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(current))
    return restored


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(f"Restored timestamps for {restore_and_record(root, Path(sys.argv[1]))} unchanged files.")
