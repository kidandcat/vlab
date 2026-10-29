# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Why this starts at 0.1.0

Nothing here was tagged or released before this file existed. Lake treats
`0.x.y` as a development version before a first stable release, and that is
what this tree is: milestone 0 and milestone 3 are in the source, milestone 1
has not been started, and the sandbox is not a security boundary. Numbering
the October 2026 commits as if they had been separate releases would invent
tags that were never cut. **0.1.0** is that history in one version, taken from
`git log` (all of it on 2026-10-28) together with the license, English, and
versioning work that made the repository publishable.

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- Repository created (initial commit).
- Milestone 0: an HTTP/1.1 listener on `Std.Http.Server`, one cairn `ShardSet`
  (`Epoch.single`), a `notes` collection, and the `meta:boots` counter. The
  binary was introduced as `leanlab-server`. What was executed, and what is
  not proved, is written in [docs/milestone-0.md](docs/milestone-0.md).
- uvl front end compiled to WebAssembly (`web/build.sh`). The browser shell
  comes from the pinned uvl revision and is not copied into this repository.
- CI. The native job runs the tests, `scripts/e2e.sh`, and the axiom check.
  The web job builds the Wasm front and also builds `vlab-server`, because the
  end-to-end script needs that binary.
- Milestone 3: a Wasm subset interpreter for untrusted code (32-bit and 64-bit
  integers, structured control, one linear memory, direct calls, and the host
  functions `fs_read`, `fs_write`, `net_send`, `clock_ms`, and `random`).
  Each sandbox has a grant, a quota, a virtual directory, and a cairn audit.
  `net_send` is simulated and does not open a socket. There is no RISC-V mini
  OS. See [docs/milestone-3.md](docs/milestone-3.md) and
  [docs/threat-model.md](docs/threat-model.md).
- Audit lines cite theorems that exist (`fsReadOk_grant` and the other real
  names). Each trap is written to cairn. `scripts/check-axioms.sh` prints the
  kernel axioms of those theorems and rejects `sorryAx` and any axiom other
  than `propext`, `Classical.choice`, and `Quot.sound`.
- MIT license ([LICENSE](LICENSE)), [CONTRIBUTING.md](CONTRIBUTING.md),
  [SECURITY.md](SECURITY.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), and
  GitHub issue and pull request templates.
- Package version `0.1.0` (`version := v!"0.1.0"` in `lakefile.lean`), printed
  on the server banner and returned by `GET /health`. CI runs
  `scripts/check-version.sh`, which checks this heading, the lakefile, and
  `Vlab/Version.lean`. Cutting the next release is described in
  [RELEASING.md](RELEASING.md). No tag is created by this change.

### Changed

- The project was renamed from leanlab to vlab: Lake package `vlab`, binary
  `vlab-server`, and module `VlabWeb`. After that rename,
  `node web/smoke-node.cjs` printed `wasm smoke ok 480x360 ink=37757`.
- Documentation, the browser copy, and the plain-text response that says the
  front has not been built are in English.
