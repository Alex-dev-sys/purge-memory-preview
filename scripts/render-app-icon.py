#!/usr/bin/env python3
"""Export the README preview and DMG icon from the native Icon Composer source."""

from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    root = Path(__file__).resolve().parent.parent
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    renderer = developer.parent / "Applications/Icon Composer.app/Contents/Executables/ictool"
    if not renderer.is_file():
        raise SystemExit("Icon Composer's ictool was not found in the selected Xcode installation.")

    with tempfile.TemporaryDirectory(prefix="purge-icon-") as scratch:
        output = Path(scratch)
        preview = output / "preview.png"
        subprocess.run([
            str(renderer), str(root / "purge.icon"), "--export-image", "--output-file", str(preview),
            "--platform", "iOS", "--rendition", "Default", "--width", "1024", "--height", "1024", "--scale", "1",
        ], check=True)
        # actool's legacy fallback contains only small renditions. The volume
        # icon also needs 512px and 1024px images for Finder's larger previews.
        iconset = output / "VolumeIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                pixels = str(size * scale)
                suffix = "@2x" if scale == 2 else ""
                subprocess.run([
                    "sips", "-z", pixels, pixels, str(preview), "--out", str(iconset / f"icon_{size}x{size}{suffix}.png"),
                ], check=True, stdout=subprocess.DEVNULL)
        volume = output / "VolumeIcon.icns"
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(volume)], check=True)
        shutil.copyfile(preview, root / "Assets/purge-iOS-Default-1024x1024@1x.png")
        shutil.copyfile(volume, root / "Assets/dmg/VolumeIcon.icns")
    print("Exported the README preview and DMG icon from purge.icon.")


if __name__ == "__main__":
    main()
