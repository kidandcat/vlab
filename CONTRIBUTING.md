# Contributing

vlab is public and licensed under the MIT license. A contribution is licensed
under that same license.

[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) applies to issues, pull requests, and
discussion.

## Language

Write English: issues, pull requests, commit messages, documentation,
comments, docstrings, UI strings, errors, and logs. A non-English string stays
only when it is Unicode test data. Mark that test with a `unicode-fixture`
comment so a reader can see the intent.

## Setup

Install `elan` and the toolchain named in `lean-toolchain`
(`leanprover/lean4:v4.35.0`). `lake test` also runs a differential against
wasmtime 27.0.0, which must be on `PATH`. The browser build needs Emscripten
6.0.12 (`emcc` on `PATH`).

```bash
lake update
lake build
lake test
bash scripts/e2e.sh
bash scripts/check-axioms.sh
bash scripts/check-version.sh
```

The browser UI is a separate build:

```bash
web/build.sh
node web/smoke-node.cjs web/dist
REQUIRE_FRONT=1 bash scripts/e2e.sh
```

`lake build VlabWeb` typechecks the canvas without Emscripten.

## Pull requests

- Say what changed and how you checked it.
- Keep claims about the sandbox honest. A test is not a proof. A new cited
  theorem belongs in the milestone notes and in `scripts/check-axioms.sh`.
- Put user-visible changes under `## [Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md).
- Do not bump the version, tag, or publish a GitHub release unless you are
  cutting a release. That procedure is [RELEASING.md](RELEASING.md).
- Do not commit secrets, tokens, or local data. `data/`, `.lake/`, and
  `web/dist/` are gitignored.

## Security

Do not file a public issue for a vulnerability. Use the private advisory path
in [SECURITY.md](SECURITY.md). The sandbox is not a security boundary; a
defect in it can still be reported that way.
