# Releases

The version is in `_meta.lua`. The version `0.0.0` means that no release exists.
The release script suggests `0.1.0` for the first release. For the next
releases, the script increases the patch number. You can type a different
`MAJOR.MINOR.PATCH` version at the prompt.

Before you publish a release:

1. Install Python 3.9 or a later version, Git and the [GitHub CLI](https://cli.github.com/).
2. Log in with `gh auth login`.
3. Commit your project changes.

Then, from the repository root, run:

```sh
python3 scripts/release.py
```

The script prepares an install ZIP file. It shows the destination, the version
and the files. Then it asks for confirmation before it publishes. After
confirmation, the script does these steps:

- It commits only the version change in `_meta.lua`.
- It creates an annotated `vX.Y.Z` tag.
- It pushes the current branch and the tag to `origin`.
- It uses your local `gh` to create the release. It uploads the ZIP file and
  the SHA-256 checksum.

The script does not accept an existing tag or an existing release. The script
does not do a force push.

## Release notes

The release notes include a **What's Changed** list. The script makes this list
from the commit titles. Each item has a link to its commit. The notes also have
a full-changelog link and the installation instructions.

The commit range starts after the newest reachable `vX.Y.Z` tag that has a
lower version than the release. For the first release, the range includes the
full history. The script omits merge commits. The script includes the
individual commits of each merge. The new version-bump commit is not in the
list.

The script shows the notes before the final confirmation. The script saves the
notes to `dist/vX.Y.Z/release-notes.md`.

## Package contents

The ZIP file has one `typoscope.koplugin/` folder. This folder contains only
`main.lua`, `geometry.lua`, `_meta.lua` and `LICENSE`. Website assets, videos,
tests and the editing and release scripts are not in the install package.

## Options

```sh
# Build a preview in dist/. This does not change Git, _meta.lua or GitHub.
python3 scripts/release.py --dry-run

# Select a version directly, or create a draft release.
python3 scripts/release.py --version 1.0.0
python3 scripts/release.py --draft
```

A dry run packages the committed `HEAD`. The script puts the selected version
into the packaged `_meta.lua`. A dry run does not include other uncommitted
changes. Use `--remote NAME` to select a different Git remote. Use
`--version X.Y.Z --yes` to skip the two prompts.

If a protected branch does not permit direct pushes, use your usual branch
workflow. The script does not bypass branch rules.

A publish run fetches the release tags before it makes the notes. A dry run
stays offline and uses the local tags. If the local tags are old, run
`git fetch --tags origin` first. Use a full clone, or fetch the missing history.
Then the notes include the full range.

## Recovery

If a push or an upload fails, the script keeps the local version commit, the
tag and the package. The script then shows the recovery instructions. Examine
an existing draft or partial release before you retry an upload. Do not
increase the version only to retry. The automatic source archives of GitHub are
different from the minimal install ZIP file.

## Tests

To run the release integration checks, run `python3 scripts/test_release.py`.
The checks use temporary Git repositories and a fake `gh`. The checks do not
connect to GitHub.
