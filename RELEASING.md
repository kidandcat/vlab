# Releasing

vlab uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
`0.x.y` is a development version: a breaking change can land in a minor or a
patch, and the changelog should say so. From `1.0.0` on, use a patch for
fixes, a minor for compatible additions, and a major for an intended break.

Three places name the current version. CI fails when they differ
(`scripts/check-version.sh`):

- `version := v!"X.Y.Z"` in `lakefile.lean`
- `def version : String := "X.Y.Z"` in `Vlab/Version.lean` (the server banner
  and the `version` field of `GET /health`)
- the newest `## [X.Y.Z]` heading in `CHANGELOG.md`

`## [Unreleased]` is not a version. The check uses the first `## [X.Y.Z]`
heading, which Keep a Changelog keeps directly under `Unreleased`.

## Steps

1. Move the notes under `## [Unreleased]` into a new
   `## [X.Y.Z] - YYYY-MM-DD` section. Leave an empty `## [Unreleased]` above it.
2. Set the same `X.Y.Z` in `lakefile.lean` and in `Vlab/Version.lean`.
3. Run `bash scripts/check-version.sh`, `lake build`, and `lake test`.
4. Commit those files together.
5. Tag that commit `vX.Y.Z` (annotated): `git tag -a vX.Y.Z -m "vX.Y.Z"`.
6. Push the commit and the tag.
7. Publish a GitHub release for tag `vX.Y.Z`. Use the changelog section for
   that version as the release notes.

Do not tag or publish a release from a change that only prepares the tree.
Tags and GitHub releases are cut by a maintainer, on purpose, after the
version check is green.
