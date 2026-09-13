import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).parents[1] / "publish-release.py")
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)


class PublishReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, GITHUB_REF_NAME="v0.0.2", GITHUB_REPOSITORY="owner/app")
        self.environment.start()
        self.calls = []
        self.release = {"draft": False, "assets": [{"name": "appcast.xml"}, {"name": "CodexIsland-0.0.2.dmg"}]}
        for architecture in ("x64", "arm64"):
            channel = f"win-{architecture}-preview"
            installer = self.root / f"CodexIsland-{channel}-Setup.exe"
            installer.write_bytes(b"installer " + architecture.encode())
            package = self.root / f"CodexIsland-0.0.2-{channel}-full.nupkg"
            package.write_bytes(b"package " + architecture.encode())
            manifest = {"version": "0.0.2", "runtime": f"win-{architecture}", "packageId": "CodexIsland", "channel": channel, "selfContained": True, "unsigned": True, "installer": installer.name, "sha256": publisher.sha256(installer).upper()}
            (self.root / f"windows-{channel}.json").write_text(json.dumps(manifest))
            feed = {"Assets": [{"PackageId": "CodexIsland", "Version": "0.0.2", "Type": "Full", "FileName": package.name, "Size": package.stat().st_size, "SHA256": publisher.sha256(package)}]}
            (self.root / f"releases.{channel}.json").write_text(json.dumps(feed))

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def gh(self, *arguments):
        self.calls.append(arguments)
        return json.dumps(self.release) if arguments[0] == "api" else ""

    def run_publish(self):
        with patch.object(publisher, "gh", self.gh), patch.object(publisher.time, "sleep"):
            publisher.publish(self.root)

    def test_uploads_only_windows_files_and_publishes_manifests_last(self):
        self.run_publish()
        uploads = [call for call in self.calls if call[:2] == ("release", "upload")]
        self.assertEqual(len(uploads), 8)
        self.assertTrue(all(call[2] == "v0.0.2" and "--clobber" not in call for call in uploads))
        self.assertTrue(all(Path(call[3]).name.startswith("windows-") for call in uploads[-2:]))
        self.assertTrue(all(call[0] == "api" or call[:2] == ("release", "upload") for call in self.calls))

    def test_missing_macos_release_prevents_all_uploads(self):
        self.release["assets"] = []
        with self.assertRaisesRegex(RuntimeError, "macOS release is not ready"):
            self.run_publish()
        self.assertTrue(all(call[0] == "api" for call in self.calls))

    def test_draft_macos_release_prevents_all_uploads(self):
        self.release["draft"] = True
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertTrue(all(call[0] == "api" for call in self.calls))

    def test_modified_download_fails_before_contacting_github(self):
        next(self.root.glob("*.nupkg")).write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.run_publish()
        self.assertEqual(self.calls, [])

    def test_prerelease_prevents_production_uploads(self):
        self.release["prerelease"] = True
        with self.assertRaises(RuntimeError):
            self.run_publish()
        self.assertTrue(all(call[0] == "api" for call in self.calls))

    def test_a_feed_cannot_offer_the_other_architectures_package(self):
        target = self.root / "releases.win-x64-preview.json"
        target.write_bytes((self.root / "releases.win-arm64-preview.json").read_bytes())
        with self.assertRaisesRegex(ValueError, "package filename"):
            self.run_publish()
        self.assertEqual(self.calls, [])

    def test_different_published_asset_prevents_every_new_upload(self):
        name = "windows-win-x64-preview.json"
        self.release["assets"].append({"name": name, "digest": "sha256:" + "0" * 64})
        with self.assertRaisesRegex(RuntimeError, "instead of overwriting"):
            self.run_publish()
        self.assertTrue(all(call[0] == "api" for call in self.calls))

    def test_repeated_publish_skips_identical_assets(self):
        self.release["assets"] += [{"name": path.name, "digest": "sha256:" + publisher.sha256(path)} for path in self.root.iterdir()]
        self.run_publish()
        self.assertEqual(len(self.calls), 1)

    def test_untagged_run_cannot_publish(self):
        os.environ["GITHUB_REF_NAME"] = "main"
        with self.assertRaisesRegex(ValueError, "version tag"):
            self.run_publish()
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
