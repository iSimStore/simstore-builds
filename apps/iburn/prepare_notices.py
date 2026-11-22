#!/usr/bin/env python3
"""Copy notices from the locked sources embedded in iBurn's geocoder bundle."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import subprocess
import sys
import tarfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path, PurePosixPath
from typing import Any


def runtime_packages(packages: dict[str, Any]) -> list[dict[str, Any]]:
    pending = ["node_modules/@turf/turf", "node_modules/levenshtein"]
    seen: set[str] = set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        for dependency in packages[name].get("dependencies", {}):
            for parent in [PurePosixPath(name), *PurePosixPath(name).parents]:
                candidate = str(parent / "node_modules" / dependency)
                if candidate in packages:
                    pending.append(candidate)
                    break
            else:
                raise ValueError(f"Missing geocoder dependency: {dependency}")
    return [packages[name] for name in sorted(seen)]


def copy_notice(package: dict[str, Any], destination: Path) -> None:
    url: str = package["resolved"].replace("http://", "https://", 1)
    if not url.startswith("https://registry.npmjs.org/"):
        raise ValueError(f"Unexpected geocoder source URL: {url}")
    archive = subprocess.check_output(
        ["curl", "--fail", "--location", "--silent", "--show-error", url]
    )
    algorithm, digest = package["integrity"].split("-", 1)
    actual = base64.b64encode(hashlib.new(algorithm, archive).digest()).decode()
    if actual != digest:
        raise ValueError(f"Geocoder source checksum mismatch: {url}")
    name = url.removeprefix("https://registry.npmjs.org/").split("/-/")[0]
    package_dir = destination / (name.replace("/", "__") + "-" + package["version"])
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
        for member in source.getmembers():
            path = PurePosixPath(member.name)
            if len(path.parts) != 2 or not member.isfile():
                continue
            if not path.name.lower().startswith(
                ("license", "licence", "copying", "notice")
            ):
                continue
            stream = source.extractfile(member)
            if stream is None:
                raise ValueError(f"Unreadable notice: {member.name}")
            package_dir.mkdir(parents=True, exist_ok=True)
            (package_dir / path.name).write_bytes(stream.read())


def main() -> None:
    lock = json.loads(Path(sys.argv[1]).read_text())
    destination = Path(sys.argv[2])
    packages = {item["resolved"]: item for item in runtime_packages(lock["packages"])}
    # Browserify embeds this shim outside the geocoder's dependency lock. Its
    # browser.js matches the pinned bundle byte-for-byte; retain its MIT notice.
    process_version, process_digest = sys.argv[3:5]
    packages["process"] = {
        "version": process_version,
        "resolved": f"https://registry.npmjs.org/process/-/process-{process_version}.tgz",
        "integrity": "sha512-" + process_digest,
    }
    with ThreadPoolExecutor(max_workers=6) as executor:
        list(
            executor.map(
                lambda package: copy_notice(package, destination),
                packages.values(),
            )
        )
    print("Copied existing geocoder notices from integrity-verified source archives")


if __name__ == "__main__":
    main()
