# Milestone 3 — Wasm sandbox

The purpose is to run third-party code that is not trusted. The case that
steers the design is, later, an isolated AI agent. This milestone does not
host an agent. The model is in [threat-model.md](threat-model.md). What is not
done is in [next-steps.md](next-steps.md): WASI, Python or JavaScript compiled
to Wasm, floats, SIMD, indirect calls, and running the server inside
Firecracker or gVisor.

## What it does

A Wasm subset: 32-bit and 64-bit integers, structured control (`block`,
`loop`, `if`, `br`, `br_if`), one linear memory, direct calls, and five host
functions from the `vlab` module: `fs_read`, `fs_write`, `net_send`,
`clock_ms`, `random`. There are no floats, no SIMD, and no `call_indirect`.
The parser rejects the rest.

Each sandbox has its own grant and its own quota. The grant comes from the
creation text (`fs-read`, `fs-write`, `clock`, `random`,
`net host port body`). There is no default permission. `net_send` does not
open a socket: if the destination is granted, it copies the `body` fixed in
the grant. The clock, if granted, is the server's clock at the start of that
execution. Randomness is requested from the system only if `random` is
granted.

Each `exec` starts with linear memory at zero, a full fuel tank, and the call
counter at zero. The virtual directory (`data/sandboxes/<id>/`) lives as long
as the sandbox lives and is deleted when the sandbox is destroyed. The cairn
audit (collection `aud-<id>`) is not deleted.

Process ceilings, on top of the request: fuel ≤ 100000, memory ≤ 1 MiB, host
calls ≤ 1000, module ≤ 16 KiB of binary, 32 live sandboxes, 256 KiB in the
virtual directory.

The uvl canvas runs the same pure interpreter on three buttons (`oob`,
`loop`, and `deny`) and paints the theorem name. The HTML panel beside it
creates, runs, and destroys sandboxes on the server.

## How it was checked

On this machine (4 vCPU, Xeon at 2400 MHz, ext4 on `/dev/vdc`), with wasmtime
27.0.0:

- `lake test` prints `vlab tests ok`. That includes the grant parser, `../`
  rejected, `a/../b` left as `b`, the `add` module returning 42, an access
  outside memory as `bounds`, the loop with fuel 30 as `outOfFuel`, `fs_read`
  without a grant leaving the virtual directory empty and recording
  `deny fs_read`, and `..` with a read grant as `escape`.
- The same `add.wasm` under wasmtime `--invoke main` prints `42`. `oob.wasm`
  exits with a code other than 0. `loop.wasm` under `timeout 2 wasmtime` exits
  with code 124 (the `timeout` limit, not a wasmtime trap). Ours stops on
  fuel.
- `scripts/e2e.sh` creates two sandboxes, runs `add` (value 42), `oob`
  (`bounds`), `loop` (`outOfFuel`), and `host` (`deny fs_read` in the audit,
  citing `fsReadOk_grant`). The `bounds` trap is stored in cairn with
  `load?_inRange`, and `outOfFuel` with `evalList_zero`. Destroying the first
  makes another `exec` answer 404. The second sandbox's audit remains.
- `node web/smoke-node.cjs` printed `wasm smoke ok 480x360 ink=30302`. The
  click on `oob` leaves `bounds` in the accessibility tree. The module weighs
  2.2 MiB.

## Proved

There is no `sorry` in this code. The theorems that compile are:

- `normalize_safe`: if `normalize` returns segments, none of them is `..`,
  `.`, or empty.
- `load?_inRange`: a read that returns bytes satisfies
  `addr + len ≤ mem.size`.
- `store?_size`: a write that succeeds does not change the size of the array.
- `grow_le`: growing below the quota leaves the memory at or under the quota.
- `fsReadOk_grant`, `fsWriteOk_grant`, `netOk_grant`, `clockOk_grant`,
  `randomOk_grant`: the admission boolean is true only if that capability is
  in the list.
- `deny_keeps`: building a denial does not change the virtual filesystem, the
  entropy cursor, or the grants.
- `evalList_zero`: with fuel 0 the evaluator answers `outOfFuel` and does not
  run an instruction.

Audit lines cite those names (`fsReadOk_grant`, not a `perform_allow_*` that
does not exist). `tag_known` says every citation comes from that list, and
the test file `#check`s each declaration. A trap (`bounds`, `outOfFuel`,
`escape`, and the rest) is written to cairn in addition to the host calls.
`scripts/check-axioms.sh` prints `#print axioms` for these theorems and fails
if `sorryAx` appears, or an axiom other than `propext`, `Classical.choice`,
and `Quot.sound`.

The evaluator is defined by recursion on fuel, so an execution terminates.
Each instruction spends one unit. That is the definition, not a separate
theorem that counts the steps of an arbitrary program.

It is not proved that the whole evaluator touches memory only through
`load?`, `store?`, and `grow`. Those are the only writes in the `evalList`
code. Equivalence with the Wasm specification is not proved. The parser,
`IO.FS`, cairn, the Lean runtime, and the kernel are out of scope. The
simulated network is not a proof that a future socket would obey the same
list.

## Trusted computing base

We trust the Lean kernel, the compiler, the C runtime, the process that
performs `IO`, the operating-system kernel, and the hardware. wasmtime is not
part of that base: it is the other side of the differential. It is not
impossible to escape. Firecracker or gVisor would be the layer this milestone
does not have.
