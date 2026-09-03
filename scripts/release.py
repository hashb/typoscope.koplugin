#!/usr/bin/env python3
"""Build a minimal install ZIP, bump _meta.lua, tag, and release using local gh.

Python 3.9+ standard library only. Run --help for preview and publishing options.
"""
import argparse
import hashlib
import json
import re
import shlex
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_FILES = ("main.lua", "geometry.lua", "_meta.lua", "LICENSE")
VERSION_PATTERN = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")
META_VERSION = re.compile(r'''^[ \t]*version[ \t]*=[ \t]*(["'])([^"'\r\n]+)\1[ \t]*,?[ \t]*(?:--[^\r\n]*)?\r?$''', re.MULTILINE)


class ReleaseError(Exception):
    pass


def command(*args, check=True):
    result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if check and result.returncode:
        raise ReleaseError(f"{shlex.join(args)} failed:\n{result.stderr.strip() or result.stdout.strip()}")
    return result


def git(*args):
    return command("git", *args).stdout.strip()


def version_tuple(version):
    if not VERSION_PATTERN.fullmatch(version):
        raise ReleaseError("Use a version such as 0.1.0 or 1.2.3 (MAJOR.MINOR.PATCH, without leading zeroes).")
    return tuple(map(int, version.split(".")))


def meta_version(text):
    matches = list(META_VERSION.finditer(text))
    if len(matches) != 1:
        raise ReleaseError('_meta.lua must contain exactly one version field, such as version = "0.1.0",')
    version = matches[0].group(2)
    version_tuple(version)
    return version


def set_meta_version(text, version):
    matches = list(META_VERSION.finditer(text))
    if not matches:
        # The initial dry run can use HEAD from before the version field was added.
        text, count = re.subn(r'(\breturn[ \t]+\{[ \t]*\r?\n)',
                             lambda m: m[0] + f'    version = "{version}",' + ('\r\n' if '\r\n' in m[0] else '\n'), text)
        if count != 1:
            raise ReleaseError("Cannot locate the metadata table in _meta.lua.")
        return text
    meta_version(text)
    match = matches[0]
    return text[:match.start(2)] + version + text[match.end(2):]


def choose_version(current, supplied):
    major, minor, patch = version_tuple(current)
    suggested = "0.1.0" if current == "0.0.0" else f"{major}.{minor}.{patch + 1}"
    while True:
        version = supplied if supplied is not None else input(f"Release version [{suggested}]: ").strip() or suggested
        version = version.removeprefix("v")
        try:
            if version_tuple(version) <= version_tuple(current):
                raise ReleaseError(f"The new version must be greater than {current}.")
            return version
        except ReleaseError as error:
            if supplied is not None:
                raise
            print(error, file=sys.stderr)


def clean_checkout():
    status = git("status", "--porcelain", "--untracked-files=normal")
    if status:
        raise ReleaseError("Commit or stash your changes before releasing (including untracked files).\n"
                           "Use --dry-run to preview a package without a clean checkout.\n" + status)


def contents_at(commit, version=None):
    files = {}
    for name in RUNTIME_FILES:
        # Read committed blobs, never a recursive copy of the checkout.
        kind = git("ls-tree", commit, "--", name).split()
        if len(kind) < 3 or kind[0] not in ("100644", "100755") or kind[1] != "blob":
            raise ReleaseError(f"{name} must be a regular tracked file in {commit}.")
        result = subprocess.run(["git", "show", f"{commit}:{name}"], cwd=ROOT, capture_output=True)
        if result.returncode:
            raise ReleaseError(f"Cannot read {name} from {commit}.")
        files[name] = result.stdout
    if version is not None:
        files["_meta.lua"] = set_meta_version(files["_meta.lua"].decode(), version).encode()
    return files


def package(commit, version):
    tag = "v" + version
    directory = ROOT / "dist" / tag
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / f"typoscope.koplugin-{tag}.zip"
    # Stable timestamps make repeated previews of the same source reproducible.
    timestamp = max(int(git("show", "-s", "--format=%ct", commit)), 315532800)
    date = datetime.fromtimestamp(timestamp, timezone.utc).timetuple()[:6]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, content in contents_at(commit, version).items():
            entry = zipfile.ZipInfo("typoscope.koplugin/" + name, date)
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            bundle.writestr(entry, content)
    checksum = directory / (archive.name + ".sha256")
    checksum.write_text(f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n")
    return archive, checksum


def previous_release_tag(commit, version):
    # Ignore unrelated tags and releases on branches not included in this commit.
    for tag in git("tag", "--merged", commit, "--sort=-version:refname").splitlines():
        if tag.startswith("v") and VERSION_PATTERN.fullmatch(tag[1:]):
            if version_tuple(tag[1:]) < version_tuple(version):
                return tag
    return None


def preview_repo_url(remote):
    """Resolve ordinary GitHub HTTPS/SSH remotes without invoking gh or the network."""
    result = command("git", "remote", "get-url", "--push", remote, check=False)
    match = re.fullmatch(r"(?:https://|git@|ssh://git@)([^/:]+)[:/]([^/]+/[^/]+?)(?:\.git)?", result.stdout.strip())
    return f"https://{match[1]}/{match[2]}" if match else None


def release_notes(commit, version, archive, repo=None):
    if git("rev-parse", "--is-shallow-repository") == "true":
        raise ReleaseError("Release notes need the full commit history. Fetch the missing history and tags before retrying.")
    tag = "v" + version
    previous = previous_release_tag(commit, version)
    revision = f"{previous}..{commit}" if previous else commit
    entries = []
    for line in git("log", "--reverse", "--no-merges", "--format=%H%x09%s", revision, "--").splitlines():
        sha, title = line.split("\t", 1)
        # Keep titles as literal text, including any Markdown-like characters.
        title = re.sub(r"([\\`*_{}\[\]<>])", r"\\\1", title)
        reference = f"[{sha[:7]}]({repo}/commit/{sha})" if repo else f"`{sha[:7]}`"
        entries.append(f"- {title} ({reference})")
    changes = "\n".join(entries) if entries else "No new commits since the previous release tag."
    changelog = ""
    if repo:
        url = f"{repo}/compare/{previous}...{tag}" if previous else f"{repo}/commits/{tag}"
        changelog = f"\n\n**Full changelog:** {url}"
    notes = archive.parent / "release-notes.md"
    notes.write_text(
        f"Typoscope {tag} for KOReader.\n\n"
        f"## What's Changed\n\n{changes}{changelog}\n\n"
        "## Installation\n\n"
        f"Download **{archive.name}** and extract its `typoscope.koplugin` folder "
        "into `koreader/plugins/`. Restart KOReader, open a supported book, and "
        "enable **Typoscope reading mask** in Tools (or Tools → More tools).\n\n"
    )
    print(f"Release notes: {notes}\nCommit range: {revision}")
    return notes


def preflight(remote, branch, commit, tag):
    urls = git("remote", "get-url", "--push", "--all", remote).splitlines()
    if len(urls) != 1:
        raise ReleaseError("The release remote must have exactly one push URL.")
    push_url = urls[0]
    repo = json.loads(command("gh", "repo", "view", push_url, "--json", "url").stdout)["url"]
    if command("git", "show-ref", "--verify", "--quiet", "refs/tags/" + tag, check=False).returncode == 0:
        raise ReleaseError(f"Local tag {tag} already exists. Choose a new version; existing tags are never replaced.")
    refs = git("ls-remote", "--", push_url, "refs/tags/" + tag, "refs/heads/" + branch)
    for line in refs.splitlines():
        sha, ref = line.split()
        if ref == "refs/tags/" + tag:
            raise ReleaseError(f"Remote tag {tag} already exists. Choose a new version.")
        if ref == "refs/heads/" + branch:
            # Fetch the push destination, even if its URL differs from the fetch URL.
            git("fetch", "--no-tags", "--", push_url, "refs/heads/" + branch)
            remote_tip = git("rev-parse", "FETCH_HEAD")
            if command("git", "merge-base", "--is-ancestor", remote_tip, commit, check=False).returncode:
                raise ReleaseError(f"Your {branch} branch is behind or diverged from {remote}. Pull/rebase before releasing.")
    existing = command("gh", "release", "view", tag, "--repo", repo, "--json", "url", check=False)
    if existing.returncode == 0:
        raise ReleaseError(f"Release {tag} already exists. Choose a new version.")
    if "release not found" not in existing.stderr.lower():
        raise ReleaseError("Could not check for an existing release:\n" + existing.stderr.strip())
    # Fetch release tags from the publishing destination before selecting the
    # changelog baseline. A moved local tag is not silently overwritten.
    git("fetch", "--no-tags", "--", push_url, "refs/tags/v*:refs/tags/v*")
    return repo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="Choose the version without the version prompt; optional v prefix.")
    parser.add_argument("--dry-run", action="store_true", help="Build from HEAD into dist/ with the chosen version in the packaged _meta.lua; no gh calls, checkout edits, commits, tags, or pushes.")
    parser.add_argument("--draft", action="store_true", help="Create a draft GitHub release instead of publishing it.")
    parser.add_argument("--yes", action="store_true", help="Skip the final publish confirmation (use --version to skip the version prompt).")
    parser.add_argument("--remote", default="origin", help="Git remote to push and release to (default: origin).")
    args = parser.parse_args()
    if not shutil.which("git"):
        raise ReleaseError("Install git first.")
    if not args.dry_run and not shutil.which("gh"):
        raise ReleaseError("Install the GitHub CLI and run gh auth login first.")
    commit = git("rev-parse", "HEAD")
    version_file = ROOT / "_meta.lua"
    if not version_file.is_file() or version_file.is_symlink():
        raise ReleaseError("_meta.lua must be a regular file containing the current version.")
    current = meta_version(version_file.read_text())
    if not args.dry_run:
        clean_checkout()
        if not git("ls-files", "--", "_meta.lua"):
            raise ReleaseError("Commit _meta.lua before releasing.")
    print(f"Current version: {current}")
    version = choose_version(current, args.version)
    tag = "v" + version
    archive, checksum = package(commit, version)
    print(f"\nPackage: {archive}\nSize: {archive.stat().st_size:,} bytes")
    print("Contents: " + ", ".join(RUNTIME_FILES))
    if args.dry_run:
        release_notes(commit, version, archive, preview_repo_url(args.remote))
        print(f"\nDry run complete. Source: {commit[:12]}. Version in the ZIP's _meta.lua: {version}.\n"
              "Only dist/ was written; the checkout and remote were not changed.")
        return
    branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
    repo = preflight(args.remote, branch, commit, tag)
    notes = release_notes(commit, version, archive, repo)
    mode = "draft" if args.draft else "published"
    print("\n" + notes.read_text())
    print(f"\nRepository: {repo}\nBranch: {branch}\nVersion: {current} → {version}\n"
          f"Tag: {tag}\nRelease: {mode}\n"
          "This will commit _meta.lua, push this branch and its tag, and upload the ZIP and checksum.")
    if not args.yes and input("Continue? [y/N]: ").strip().lower() not in ("y", "yes"):
        print("Cancelled. The package is available in dist/; the metadata and branch/tag refs were not changed.")
        return
    clean_checkout()
    if git("rev-parse", "HEAD") != commit:
        raise ReleaseError("HEAD changed during preparation. Run the script again.")
    version_file.write_bytes(set_meta_version(version_file.read_bytes().decode(), version).encode())
    git("add", "--", "_meta.lua")
    git("commit", "--only", "-m", f"Release {tag}", "--", "_meta.lua")
    release_commit = git("rev-parse", "HEAD")
    clean_checkout()
    if meta_version(git("show", release_commit + ":_meta.lua")) != version:
        raise ReleaseError("The committed metadata version differs from the selected version.")
    if contents_at(commit, version) != contents_at(release_commit):
        raise ReleaseError("Runtime files changed during the release commit. Inspect the commit before proceeding.")
    git("tag", "-a", tag, "-m", f"Typoscope {tag}", release_commit)
    upload = ["gh", "release", "create", tag, str(archive), str(checksum), "--repo", repo,
              "--verify-tag", "--title", f"Typoscope {tag}", "--notes-file", str(notes)]
    if args.draft:
        upload.append("--draft")
    try:
        # Atomic, explicit refs: never force-push or upload unrelated local tags.
        git("push", "--atomic", "--", args.remote,
            f"HEAD:refs/heads/{branch}", f"refs/tags/{tag}:refs/tags/{tag}")
        result = command(*upload)
    except ReleaseError:
        print(f"\nRelease {tag} stopped after its local commit/tag were created. They have been preserved.\n"
              f"Package: {archive}\n"
              f"After fixing any push failure, push {branch} and {tag}. If no GitHub release was created, run:\n"
              f"  {shlex.join(upload)}\n"
              f"If a draft or partial release already exists, inspect it with gh release view {tag} --repo {repo} "
              "and upload any missing assets with gh release upload. Do not bump again just to retry.", file=sys.stderr)
        raise
    print(result.stdout.strip() or f"Created {mode} release {tag} in {repo}.")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
    except (EOFError, KeyboardInterrupt):
        print("\nInterrupted; inspect git status before retrying if the release had started.", file=sys.stderr)
        sys.exit(1)
