# vlab

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/kidandcat/vlab/actions/workflows/ci.yml/badge.svg)](https://github.com/kidandcat/vlab/actions/workflows/ci.yml)

vlab is a Lean 4 service (toolchain `v4.35.0`, the same as
[cairn](https://github.com/kidandcat/cairn) and
[uvl](https://github.com/kidandcat/uvl)). Current version: **0.1.0**. The
process speaks HTTP/1.1 with `Std.Http.Server`, stores data in a cairn
`ShardSet`, and serves a front end compiled with uvl to WebAssembly.

The public repository is [kidandcat/vlab](https://github.com/kidandcat/vlab).
It contains no secrets. There is no production deployment. There is a
`Dockerfile` and [docs/deployment.md](docs/deployment.md).

The sandbox is not a security boundary. Milestone 3 proves a short list of
properties of a small Wasm subset. It does not prove equivalence with the Wasm
specification, the parser and `IO` are outside those proofs, and nothing under
the Lean process contains an escape. There is no gVisor and no Firecracker in
this tree. See [docs/threat-model.md](docs/threat-model.md).

## Milestone status

| Milestone | What it is | Where it stands |
| --- | --- | --- |
| 0 | Skeleton: HTTP server, cairn, uvl front | In this tree. Tested. Not proved. |
| 1 | Function laboratory | Not started. |
| 3 | Wasm sandbox for untrusted code | In this tree. The theorems listed below are proved. The interpreter is tested on small modules. Not a security boundary. |

The RISC-V mini OS is not part of this repository. The reports are
[docs/milestone-0.md](docs/milestone-0.md) and
[docs/milestone-3.md](docs/milestone-3.md). What is not promised is
[docs/next-steps.md](docs/next-steps.md). Deployment, which has not been run,
is [docs/deployment.md](docs/deployment.md).

### Milestone 0 — tested, not proved

Nothing in this repository is a theorem about the server. There is no `sorry`.
Cairn's own theorems are used (batch fold, compare-and-set collection, the
prefix of a well-formed file cut, `sync` as a barrier). They do not speak
about this HTTP process or about `IO.Ref` publishing a `View`.

What was executed: `lake test` (the `{"text":...}` parser, routes including
`..`, hex ids at `0` and at `2^48-1` / `2^80-1`, a real cairn directory across
a restart) and `scripts/e2e.sh` (POST and GET, keep-alive, a chunked body, a
restart, `boots=2`). `Std.Http.Server` was tried on those requests. It is not
proved. The JSON parser is total and is tested with quotes, a backslash, a
newline, UTF-8, and `\u00e1`. It is not a full JSON parser and it is not
proved for every input. The hex id is not proved for every `Ulid`. The uvl
front is not proved here; uvl proves framebuffer and parent bounds in its own
repository. The `Dockerfile` was not built on the machine that wrote the
report (no Docker there).

### Milestone 1 — not started

The function laboratory is not in this tree. Milestone 0 left rate limits for
it. They are still absent.

### Milestone 3 — some theorems, not a boundary

Proved, with no `sorry`, and checked by `scripts/check-axioms.sh` (only
`propext`, `Classical.choice`, and `Quot.sound`): `normalize_safe`,
`load?_inRange`, `store?_size`, `grow_le`, `fsReadOk_grant`,
`fsWriteOk_grant`, `netOk_grant`, `clockOk_grant`, `randomOk_grant`,
`deny_keeps`, and `evalList_zero`. The evaluator is defined by recursion on
fuel, so a run stops. That is the definition, not a separate step-counting
theorem.

Tested, on this subset only: `lake test` (grant parser, `../` rejected,
`a/../b` becomes `b`, `add` returns 42, out-of-bounds, fuel 30, deny, escape)
and a wasmtime 27.0.0 differential on those small modules (`add` prints 42,
`oob` exits non-zero). `scripts/e2e.sh` creates two sandboxes, checks the
audit citations, and checks that destroy makes the next `exec` answer 404.
`node web/smoke-node.cjs` left `bounds` in the accessibility tree after the
`oob` click.

Not verified, and not claimed: equivalence with the Wasm specification;
floats, SIMD, `call_indirect`, and WASI; a theorem that `evalList` touches
memory only through `load?`, `store?`, and `grow` (those are the only writes
in that code, which is not the same as a proof); the parser, `IO.FS`, cairn,
the Lean runtime, and the kernel; that a future socket would obey the grant
list (`net_send` copies a scripted body); that wasmtime's agreement on a few
modules makes wasmtime part of the trusted computing base. It is not
impossible to escape.

## Pinned dependencies

| Package | Revision |
| --- | --- |
| cairn | `543684716dde412bb803702efdf6e6406f435c9d` |
| uvl | `ff2f323df25f2e260c19a28d220c3bf507b033df` |

`lake-manifest.json` repeats those revisions. One shard (`Epoch.single`): a
document is one key, and cairn rejects a batch that crosses shards.

## Build, test, and run

`elan` with `leanprover/lean4:v4.35.0` is required. `lake test` also needs
wasmtime 27.0.0 on `PATH`.

```bash
lake update
lake build
lake test
bash scripts/e2e.sh
bash scripts/check-axioms.sh
bash scripts/check-version.sh
```

The binary is `.lake/build/bin/vlab-server`.

```bash
.lake/build/bin/vlab-server --data data --host 127.0.0.1 --port 8080 --static web/dist
```

The default host is the loopback. `--host` accepts only an IPv4 address. Each
note is a cairn commit, with `sync` before the response. Startup prints the
package version. `GET /health` returns it in the `version` field.

Without a built front, `GET /` answers in text that `web/build.sh` has not
been run. The API still works:

```bash
curl -s http://127.0.0.1:8080/health
curl -s -X POST http://127.0.0.1:8080/api/notes \
  -H 'Content-Type: application/json' \
  --data '{"text":"hello"}'
curl -s http://127.0.0.1:8080/api/notes
```

A note body is an object with a single `text` field (at most 4000 characters).
The HTTP body does not exceed 64 KiB. The list returns at most 50 notes, from
oldest to newest.

A sandbox is created with grant text, not with JSON:

```bash
curl -s -X POST http://127.0.0.1:8080/api/sandboxes --data $'fuel 1000\nmemory 131072\ncalls 4\nfs-read\n'
curl -s -X POST http://127.0.0.1:8080/api/sandboxes/ID/exec --data 'example add'
curl -s http://127.0.0.1:8080/api/sandboxes/ID/audit
curl -s -X DELETE http://127.0.0.1:8080/api/sandboxes/ID
```

`example` is `add`, `oob`, `loop`, or `host`. `wasm HEX` sends a module of
your own, in hexadecimal, of at most 16 KiB.

## Front

Emscripten 6.0.12 (`emcc` on `PATH`) is required, the same one uvl uses.

```bash
web/build.sh
node web/smoke-node.cjs web/dist
REQUIRE_FRONT=1 bash scripts/e2e.sh
```

`web/build.sh` is adapted from uvl's `web/build.sh` at the pinned revision.
The Lean runtime and `Init` are compiled to Wasm once and kept under
`.lake/build/wasm`. The output is `web/dist/` (`index.html`, `uvl.js`,
`uvl.wasm`, `uvl-web.js`).

Open `http://127.0.0.1:8080/` with the server running. The uvl canvas runs the
interpreter on the `oob`, `loop`, and `deny` buttons. The panel beside it
creates sandboxes on the server.

## What cairn stores

One directory, one file `shard-0.cairn`.

- The `notes` collection: `Ulid` id, version, text.
- The `sandboxes` collection and the keys `spec:<id>` / `alive:<id>`.
- The `aud-<id>` collection: one line per host attempt. It is not deleted when
  the sandbox is destroyed.
- The key `meta:boots`: how many times the directory has been opened.
- The directory `sandboxes/<id>/`: that sandbox's files. Deleted on destroy.

On open, the id generator is seeded with the greatest id already stored, so
it does not mint one that sorts earlier. If the collection passes 100000 pages
of 64, the process refuses to start instead of guessing.

## Versioning

[Semantic Versioning](https://semver.org/spec/v2.0.0.html). History so far is
[CHANGELOG.md](CHANGELOG.md). Cutting a release is [RELEASING.md](RELEASING.md).
This tree does not create tags.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md), [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md),
and [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Copyright (c) 2026 kidandcat.
