"""Attach Windows packages after the normal macOS release has been published."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


def gh(*arguments):
    return subprocess.run(["gh", *arguments], check=True, text=True, capture_output=True).stdout


def sha256(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def publish(directory):
    tag = os.environ["GITHUB_REF_NAME"]
    repository = os.environ["GITHUB_REPOSITORY"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Only a version tag can publish Windows release assets.")
    manifests = [directory / f"windows-win-{arch}-preview.json" for arch in ("x64", "arm64")]
    expected = set(manifests)
    for path in manifests:
        manifest = json.loads(path.read_text(encoding="utf-8-sig"))
        channel = manifest["channel"]
        if manifest["version"] != tag[1:] or manifest["packageId"] != "CodexIsland":
            raise ValueError("The Windows installer must match the release tag and application ID.")
        if channel not in ("win-x64-preview", "win-arm64-preview") or not manifest["selfContained"]:
            raise ValueError("Unexpected Windows channel or runtime configuration.")
        if path.name != f"windows-{channel}.json" or manifest["runtime"] != channel.removesuffix("-preview"):
            raise ValueError("The installer manifest does not match its architecture.")
        installer = directory / f"CodexIsland-{channel}-Setup.exe"
        if manifest["installer"] != installer.name or sha256(installer).upper() != manifest["sha256"]:
            raise ValueError("Installer checksum does not match its manifest.")
        feed_path = directory / f"releases.{channel}.json"
        feed = json.loads(feed_path.read_text(encoding="utf-8-sig"))
        if not any(asset["Type"] == "Full" and asset["Version"] == tag[1:] for asset in feed["Assets"]):
            raise ValueError("The update feed must include a full package for this version.")
        expected.update((installer, feed_path))
        for asset in feed["Assets"]:
            name = asset["FileName"]
            kind = asset["Type"]
            if kind not in ("Full", "Delta") or name != f"CodexIsland-{asset['Version']}-{channel}-{kind.lower()}.nupkg":
                raise ValueError("Unexpected update package filename.")
            package = directory / name
            if asset["PackageId"] != "CodexIsland" or asset["Version"] != tag[1:]:
                raise ValueError("The update feed must contain this release's application version.")
            if package.stat().st_size != asset["Size"] or sha256(package).upper() != asset["SHA256"].upper():
                raise ValueError("Update package checksum does not match its feed.")
            expected.add(package)

    release = None
    for _ in range(40):
        try:
            candidate = json.loads(gh("api", f"repos/{repository}/releases/tags/{tag}"))
            names = {asset["name"] for asset in candidate["assets"]}
            if not candidate["draft"] and not candidate.get("prerelease", False) and {"appcast.xml", f"CodexIsland-{tag[1:]}.dmg"} <= names:
                release = candidate
                break
        except subprocess.CalledProcessError:
            pass
        time.sleep(15)
    if release is None:
        raise RuntimeError("The matching macOS release is not ready. No release was created or changed.")

    existing = {asset["name"]: asset for asset in release["assets"]}
    pending = []
    # Availability manifests go last so download pages only advertise complete uploads.
    for path in sorted(expected, key=lambda item: (item in manifests, item.name)):
        if path.name in existing:
            digest = existing[path.name].get("digest")
            if not digest:
                with tempfile.TemporaryDirectory() as temporary:
                    gh("release", "download", tag, "--repo", repository, "--pattern", path.name, "--dir", temporary)
                    digest = "sha256:" + sha256(Path(temporary) / path.name)
            if digest.lower() != "sha256:" + sha256(path):
                raise RuntimeError(f"Published asset {path.name} differs. Publish a new version instead of overwriting it.")
            print(f"Already published: {path.name}")
            continue
        pending.append(path)
    for path in pending:
        gh("release", "upload", tag, str(path), "--repo", repository)
        print(f"Published: {path.name}")


if __name__ == "__main__":
    publish(Path(sys.argv[1]).resolve())
