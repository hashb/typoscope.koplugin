# Releases

The version lives in `_meta.lua`. `0.0.0` means no release has been made yet.
The release script suggests `0.1.0` for the first release, then increments the
patch number. You can type a different `MAJOR.MINOR.PATCH` version at the prompt.

Install Python 3.9+, Git, and the [GitHub CLI](https://cli.github.com/), and log in
with `gh auth login`. Commit your project changes before publishing. From the
repository root, run:

```sh
python3 scripts/release.py
```

The script prepares an install ZIP, shows the destination, version, and files,
then asks before publishing. It commits only the version change in `_meta.lua`,
creates an annotated `vX.Y.Z` tag, pushes the current branch and that tag to
`origin`, and uses your local `gh` to create the release and upload the ZIP and
SHA-256 checksum. It refuses existing tags/releases and never force-pushes.

Release notes include a **What's Changed** list built from commit titles, links
to each commit, and a full-changelog link, followed by installation instructions.
The range starts after the newest lower-version `vX.Y.Z` tag reachable from the
release commit. For the first release, it includes the full history. Merge
commits are omitted; their individual commits are included. The new version-bump
commit is not part of the list. Notes are shown before the final confirmation
and saved to `dist/vX.Y.Z/release-notes.md`.

The ZIP has one `typoscope.koplugin/` folder containing only `main.lua`,
`geometry.lua`, `_meta.lua`, and `LICENSE`. Website assets, videos, tests,
and editing/release scripts stay out of the install package.

```sh
# Build a preview in dist/ without changing Git, _meta.lua, or GitHub.
python3 scripts/release.py --dry-run

# Choose a version directly, or create a draft release.
python3 scripts/release.py --version 1.0.0
python3 scripts/release.py --draft
```

Dry runs package the committed `HEAD`, with the selected version inserted into
the packaged `_meta.lua`; they do not include other uncommitted edits. Use
`--remote NAME` for a different Git remote, or `--version X.Y.Z --yes` to skip
both prompts. A protected branch that prohibits direct pushes must be handled
through your usual branch workflow; the script does not bypass branch rules.

Publishing fetches release tags before generating notes. Dry runs stay offline
and use local tags; run `git fetch --tags origin` first if those need updating.
Use a full clone (or fetch the missing history) so the notes cover the entire range.

If a push or upload fails, the script preserves the local version commit, tag,
and package, and prints recovery instructions. Inspect any existing draft or
partial release before retrying an upload; don't bump the version again just to
retry. GitHub's automatic source archives are separate from the minimal install ZIP.

Run the release integration checks with `python3 scripts/test_release.py`.
They use temporary Git repositories and a fake `gh`; they don't contact GitHub.
