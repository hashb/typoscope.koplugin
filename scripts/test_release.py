#!/usr/bin/env python3
"""Release integration checks: real temporary Git repos, a fake gh, no network."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

SOURCE = Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="typoscope-release-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.repo = base / "checkout"
        self.repo.mkdir()
        self.remote = base / "remote.git"
        self.log = base / "gh-calls.jsonl"
        self.env = os.environ.copy()
        # Isolate tests from user signing settings, hooks, and credentials.
        self.env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GH_LOG=str(self.log))
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        self.run_cmd("git", "init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Release test")
        self.run_cmd("git", "init", "--bare", "-q", str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        (self.repo / "scripts").mkdir()
        shutil.copyfile(SOURCE / "scripts/release.py", self.repo / "scripts/release.py")
        (self.repo / "_meta.lua").write_text('return {\n    version = "0.2.4",\n    fullname = "Typoscope",\n}\n')
        for name in ("main.lua", "geometry.lua", "LICENSE"):
            (self.repo / name).write_text("fixture " + name + "\n")
        (self.repo / ".gitignore").write_text("dist/\n")
        (self.repo / "docs").mkdir()
        (self.repo / "docs/video.mp4").write_bytes(b"Not an installation file")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture")
        self.git("push", "-q", "origin", "main")
        self.original = self.git("rev-parse", "HEAD")
        binary = base / "bin"
        binary.mkdir()
        fake = binary / "gh"
        fake.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
a = sys.argv[1:]
with open(os.environ["GH_LOG"], "a") as log:
    log.write(json.dumps(a) + "\\n")
if a[:2] == ["repo", "view"]:
    print(json.dumps({"url": "https://github.com/example/typoscope.koplugin"}))
elif a[:2] == ["release", "view"]:
    if os.environ.get("FAKE_GH_EXISTS"):
        print(json.dumps({"url": "https://github.com/example/typoscope.koplugin/releases/tag/" + a[2]}))
    else:
        print("release not found", file=sys.stderr)
        sys.exit(1)
elif a[:2] == ["release", "create"]:
    if os.environ.get("FAKE_GH_FAIL_UPLOAD"):
        print("simulated upload interruption", file=sys.stderr)
        sys.exit(1)
    assert Path(a[3]).is_file() and Path(a[4]).is_file()
    print("https://github.com/example/typoscope.koplugin/releases/tag/" + a[2])
else:
    sys.exit("unexpected gh call: " + repr(a))
''')
        fake.chmod(0o755)
        self.env["PATH"] = str(binary) + os.pathsep + self.env["PATH"]

    def run_cmd(self, *args):
        return subprocess.run(args, cwd=self.repo, env=self.env, capture_output=True, text=True, check=True).stdout.strip()

    def git(self, *args):
        return self.run_cmd("git", *args)

    def release(self, *args, input=None):
        return subprocess.run([sys.executable, str(self.repo / "scripts/release.py"), *args],
                              cwd=self.temp.name, env=self.env, input=input, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def assert_package(self, version):
        archive = self.repo / f"dist/v{version}/typoscope.koplugin-v{version}.zip"
        with zipfile.ZipFile(archive) as bundle:
            self.assertEqual(set(bundle.namelist()), {"typoscope.koplugin/" + n for n in ("main.lua", "geometry.lua", "_meta.lua", "LICENSE")})
            self.assertIn(f'version = "{version}"', bundle.read("typoscope.koplugin/_meta.lua").decode())
            self.assertIsNone(bundle.testzip())
        self.assertEqual(Path(str(archive) + ".sha256").read_text().split()[0], hashlib.sha256(archive.read_bytes()).hexdigest())
        return archive

    def test_dry_run_uses_committed_files_without_side_effects(self):
        (self.repo / "main.lua").write_text("uncommitted edit\n")
        before = self.git("status", "--porcelain")
        result = self.release("--dry-run", "--version", "v0.3.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.assert_package("0.3.0")
        with zipfile.ZipFile(archive) as bundle:
            self.assertEqual(bundle.read("typoscope.koplugin/main.lua"), b"fixture main.lua\n")
        self.assertEqual(self.git("status", "--porcelain"), before)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assertEqual(self.git("tag"), "")
        self.assertEqual(self.calls(), [])

    def test_prompt_can_override_version_and_upload_matches_tag(self):
        result = self.release(input="1.0.0\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Release version [0.2.5]", result.stdout)
        archive = self.assert_package("1.0.0")
        self.assertEqual(self.git("diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"), "_meta.lua")
        self.assertEqual(self.git("cat-file", "-t", "v1.0.0"), "tag")
        self.assertEqual(self.git("rev-parse", "v1.0.0^{}"), self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("--git-dir=" + str(self.remote), "rev-parse", "refs/heads/main"), self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("--git-dir=" + str(self.remote), "rev-parse", "v1.0.0^{}"), self.git("rev-parse", "HEAD"))
        with zipfile.ZipFile(archive) as bundle:
            for name in ("main.lua", "geometry.lua", "_meta.lua", "LICENSE"):
                self.assertEqual(bundle.read("typoscope.koplugin/" + name), (self.repo / name).read_bytes())
        upload = self.calls()[-1]
        self.assertEqual(upload[:3], ["release", "create", "v1.0.0"])
        self.assertIn("--verify-tag", upload)
        self.assertNotIn("--draft", upload)
        notes = Path(upload[upload.index("--notes-file") + 1]).read_text()
        self.assertIn("## What's Changed", notes)
        self.assertIn(f"- Fixture ([{self.original[:7]}]", notes)
        self.assertIn("/commits/v1.0.0", notes)
        self.assertNotIn("- Release v1.0.0", notes)
        self.assertIn("## Installation", notes)

    def test_default_patch_bump_and_draft(self):
        result = self.release("--draft", input="\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version = "0.2.5"', (self.repo / "_meta.lua").read_text())
        self.assertIn("--draft", self.calls()[-1])

    def test_cancel_does_not_bump_or_tag(self):
        result = self.release("--version", "0.2.5", input="n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assertEqual(self.git("tag"), "")
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_dirty_tree_and_existing_release_stop_before_bump(self):
        (self.repo / "untracked.txt").write_text("work in progress")
        result = self.release("--version", "0.2.5", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        (self.repo / "untracked.txt").unlink()
        self.env["FAKE_GH_EXISTS"] = "1"
        result = self.release("--version", "0.2.5", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.original)
        self.assertEqual(self.git("tag"), "")

    def test_failed_upload_preserves_recovery_artifacts(self):
        self.env["FAKE_GH_FAIL_UPLOAD"] = "1"
        result = self.release("--version", "0.2.5", "--yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Do not bump again just to retry", result.stderr)
        self.assert_package("0.2.5")
        self.assertEqual(self.git("--git-dir=" + str(self.remote), "rev-parse", "v0.2.5^{}"), self.git("rev-parse", "HEAD"))

    def test_notes_use_newest_reachable_version_tag_and_include_merged_work(self):
        self.git("tag", "v0.2.9")
        self.git("commit", "--allow-empty", "-qm", "Previously released improvement")
        self.git("tag", "v0.2.10")
        # A newer tag on an unmerged branch must not become the baseline.
        self.git("checkout", "-qb", "future")
        self.git("commit", "--allow-empty", "-qm", "Unreleased future work")
        self.git("tag", "v0.2.11")
        self.git("checkout", "-q", "main")
        self.git("checkout", "-qb", "feature")
        self.git("commit", "--allow-empty", "-qm", "Add a mask color")
        self.git("checkout", "-q", "main")
        self.git("commit", "--allow-empty", "-qm", "Fix [mask] <bounds>")
        self.git("merge", "--no-ff", "-qm", "Merge branch feature", "feature")
        self.git("tag", "unrelated-snapshot")
        result = self.release("--dry-run", "--version", "0.3.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Commit range: v0.2.10..", result.stdout)
        notes = (self.repo / "dist/v0.3.0/release-notes.md").read_text()
        self.assertIn("Add a mask color", notes)
        self.assertIn(r"Fix \[mask\] \<bounds\>", notes)
        for omitted in ("Fixture", "Previously released improvement", "Unreleased future work", "Merge branch feature"):
            self.assertNotIn(omitted, notes)
        self.assertEqual(self.calls(), [])

    def test_publish_fetches_missing_release_tag_for_notes(self):
        self.git("tag", "-a", "v0.2.4", "-m", "Prior release")
        self.git("push", "-q", "origin", "v0.2.4")
        self.git("tag", "-d", "v0.2.4")
        self.git("commit", "--allow-empty", "-qm", "Improve line stepping")
        result = self.release("--version", "0.2.5", "--yes")
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = (self.repo / "dist/v0.2.5/release-notes.md").read_text()
        self.assertIn("Improve line stepping", notes)
        self.assertNotIn("Fixture", notes)
        self.assertIn("https://github.com/example/typoscope.koplugin/compare/v0.2.4...v0.2.5", notes)


if __name__ == "__main__":
    unittest.main()
