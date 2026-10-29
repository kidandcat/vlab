# Milestone 0 — skeleton

Report of what is in this tree: a `vlab-server` binary, a cairn directory, and
a uvl front. The function laboratory is milestone 1. The verified Wasm sandbox
is milestone 3 and the focus of the project. There is no RISC-V mini OS.

## How it is built

The listener is `Std.Http.Server` from Lean 4.35.0 (`Std.Async` and
`Std.Internal.UV` underneath). A minimal server, separate from vlab, was tried
before the design was rested on it: `GET`, `POST` with a body, two requests on
the same connection (keep-alive), and a `Transfer-Encoding: chunked` body. All
four answered `HTTP/1.1 200` with the expected body. A C shim was not needed.

cairn comes in as a Lake dependency at
`543684716dde412bb803702efdf6e6406f435c9d`. `ShardSet.openFiles` opens
`dir/shard-0.cairn` with `Epoch.single`. Notes are the `notes` collection. The
boot counter is the key `meta:boots`. A commit is answered only after that
shard's `sync`.

uvl comes in at `ff2f323df25f2e260c19a28d220c3bf507b033df`. `web/build.sh`
follows uvl's: the Lean runtime and `Init` to Wasm with Emscripten 6.0.12, and
the `.c` files of the `VlabWeb.App` module and of the uvl modules it imports.
The browser shell (`web_shell.c`, `lean_stubs.c`, `uvl-web.js`) is taken from
that uvl revision; it is not copied into the repository. The server only
delivers the four whitelist files (`index.html`, `uvl.js`, `uvl.wasm`,
`uvl-web.js`). There is no path join, so a request cannot leave that list.

The default host is `127.0.0.1`. The maximum HTTP body is 64 KiB. A note's
text is 4000 characters. There is no rate limit: that is left for milestone 1.
A conservative decision, and it is written down here.

## How it was checked

On this machine (4 vCPU, Intel Xeon at 2400 MHz, ext4 on `/dev/vdc`):

1. `lake test` prints `vlab tests ok`. That includes the parser for the body
   `{"text":...}`, the routes (including `..`), the hexadecimal id at both
   ends (`0` and `2^48-1` / `2^80-1`), and a real cairn directory: a note is
   written, the store is closed, it is opened again, the note is still there,
   and the boot counter goes from 1 to 2. An empty note is not stored.
2. `bash scripts/e2e.sh` starts the binary, does `POST` and `GET`, keep-alive
   of two `GET /health`, a `POST` with a chunked body, kills the process, and
   opens it again on the same directory. The note is still there. `boots` is
   2. It printed `e2e ok boots=2 notes=2`. Without `web/dist`, `GET /` answers
   200 in plain text saying the front is missing. A half-written JSON answers
   400. `POST /` answers 405.
3. The front, when `web/build.sh` finishes: `node web/smoke-node.cjs` (one
   frame, the accessibility tree, a click on the button) and
   `REQUIRE_FRONT=1 bash scripts/e2e.sh` (the served Wasm starts with `\0asm`).

The `Dockerfile` has not been built: this machine has no Docker. The file and
[deployment.md](deployment.md) are here for when there is a daemon.

## Proved, and only tested

Nothing in this repository is a theorem about the server. There is no `sorry`
in the vlab code. There is also no proof that the parser, the id, or the
routes are correct for every input: that is executed in `lake test` on the
cases above.

What is used from cairn is what was already proved there (the fold of a batch,
the collection with compare-and-set, the prefix of a well-formed file cut,
`sync` as a barrier). Those theorems do not speak about this HTTP process, nor
about `IO.Ref` publishing the `View` atomically. The failure model is still
cairn's: a prefix of a well-formed file, not arbitrary garbage, and a disk
that lies about the flush is out of scope.

`Std.Http.Server` is not proved. It is tested with the requests above, here
and again inside `scripts/e2e.sh`.

The hexadecimal id is tested at the endpoints, not proved for every `Ulid`.
The JSON parser is a total function (the fuel goes down at each step) and is
tested with quotes, a backslash, a newline, UTF-8, and `\u00e1`. It rejects a
lone `\u` surrogate. It is not a complete JSON parser: an object with another
field, or with two fields, is an error.

The uvl front is not proved here. uvl already proves, in its repository, that
a pixel is not written outside the framebuffer and that a child does not leave
its parent. This milestone only checks that the module starts in Wasm and that
a click changes the counter.

## Numbers

Same machine. One pass of `scripts/e2e.sh`, not averaged. `tookNs` is the
monotonic clock around `addNote` (the commit with sync). `wallUs` is the time
the client sees, including the connection.

```
post tookNs 965248 757605 254850 410444 950380
post wallUs 18281 2245 1122 1343 1857
health wallUs 729
```

A short note's commit landed between about 0.25 ms and about 0.97 ms. The
first request seen from the client was slower (about 18 ms); the later ones
were between 1.1 ms and 2.2 ms. `GET /health` walks the collection: with few
notes, about 0.7 ms seen from the client. This is not a bound. A disk that
waits for stable media will be slower than this ext4.

The front module weighs 2.1 MiB (`web/dist/uvl.wasm`). After the package was
renamed to `vlab`, `node web/smoke-node.cjs` printed
`wasm smoke ok 480x360 ink=37757`: a 480×360 frame and a click on the button
that takes the counter from `pings 0` to `pings 1`. With the front served,
`REQUIRE_FRONT=1 bash scripts/e2e.sh` checked that `GET /uvl.wasm` starts with
the `\0asm` magic and that `GET /` is `index.html`.

`web/build.sh` warm (the Lean runtime and `Init` already compiled under
`.lake/build/wasm`) took 16 s. The first pass, without that cache, was not
timed separately: it compiled the runtime, the 653 `Init` modules, and the
app, and it finished on this same machine. In CI that cache is stored; the
first time it is not there.

Four elaborator symbols (`initialize_Lean`, `initialize_Std_Tactic_BVDecide`,
and two from `Lean.Parser`) remain as stubs that abort if they are called.
The initializer of `VlabWeb.App` is not one of them. When the package was
still called leanlab, a first link replaced `initialize_leanlab_…` with a
stub: the pattern `initialize_Lean` also matched `Leanlab`, and the module
threw a Wasm exception. The script does not treat `initialize_vlab_` as
compile-time code. That showed up when the smoke was run, not only at link
time.
