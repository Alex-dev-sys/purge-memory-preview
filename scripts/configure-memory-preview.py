#!/usr/bin/env python3
"""Give release previews their own app, helper and persistent-data identities."""

from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parent.parent

for directory in ("purge", "PurgeHelper", "PurgeWatch", "PurgeAssetWorker", "purge.xcodeproj"):
    for path in list((ROOT / directory).rglob("*")):
        if path.is_file() and path.suffix in {".swift", ".plist", ".pbxproj"}:
            source = path.read_text()
            # Keep this transformation idempotent for local rebuilds.
            source = source.replace("io.getpurge.memorypreview", "io.getpurge")
            source = source.replace("purge://", "purge-memory-preview://")
            source = source.replace('url.scheme == "purge"', 'url.scheme == "purge-memory-preview"')
            path.write_text(source.replace("io.getpurge", "io.getpurge.memorypreview"))
            if path.name.startswith("io.getpurge."):
                name = path.name.replace("io.getpurge.memorypreview", "io.getpurge")
                path.rename(path.with_name(name.replace("io.getpurge", "io.getpurge.memorypreview")))

info_path = ROOT / "purge/Info.plist"
with info_path.open("rb") as stream:
    info = plistlib.load(stream)
info.pop("SUFeedURL", None)
info.pop("SUPublicEDKey", None)
info["SUEnableAutomaticChecks"] = False
info["PurgeDisableUpdates"] = True
for entry in info.get("CFBundleURLTypes", []):
    entry["CFBundleURLSchemes"] = ["purge-memory-preview"]
with info_path.open("wb") as stream:
    plistlib.dump(info, stream, sort_keys=False)

print("Configured isolated Memory preview; Sparkle updates disabled.")
