#!/usr/bin/env python3
"""
Writes Raspberry Pi Imager's OS list for the kiosk image a build just made, from the
`estoki-kiosk-<tag>.json` that image/build.sh writes beside it.

estokiapp.com/kiosk/os-list.json redirects to the copy build-image.yml commits to the public
releases repository, so Imager always lists the newest image that finished building. The format is
Imager's repository JSON (raspberrypi/rpi-imager, doc/json-schema); `init_format` `cloudinit-rpi`
is what makes Imager offer its settings, as for Raspberry Pi OS Trixie. Standard library only.

Usage: os_list.py --image-json estoki-kiosk-v12-butterfree.json --out os-list.json
"""

import argparse
import json
import sys
from pathlib import Path

REPO = "4FreedomHub/estoki-kiosk-releases"
SITE = "https://estokiapp.com"
NAME = "Estoki Kiosk"
DESCRIPTION = (
    "Raspberry Pi OS with the Estoki kiosk: your household's stock and what to use first, "
    "on a Raspberry Pi 5 with the Touch Display 2 and a barcode scanner."
)
FIELDS = ("extract_size", "extract_sha256", "image_download_size", "image_download_sha256")


def os_list(image: dict) -> dict:
    missing = [field for field in ("tag", "image", "built_at", *FIELDS) if field not in image]
    if missing:
        raise ValueError(f"The image description lacks {', '.join(missing)}.")
    tag = image["tag"]
    return {
        "os_list": [
            {
                "name": NAME,
                "description": DESCRIPTION,
                "icon": f"{SITE}/kiosk/icon.png",
                "website": f"{SITE}/kiosk/",
                "url": f"https://github.com/{REPO}/releases/download/{tag}/{image['image']}",
                **{field: image[field] for field in FIELDS},
                "release_date": image["built_at"][:10],
                "init_format": "cloudinit-rpi",
                "devices": ["pi5-64bit"],
            }
        ]
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--image-json", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        data = os_list(json.loads(args.image_json.read_text(encoding="utf-8")))
    except ValueError as error:
        print(f"::error::{error}")
        return 1
    args.out.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
