# Next steps

This is not done, and this milestone does not promise it. It is here so the
design is not read as if it already were.

## Guest language

- WASI, so that a module compiled in the ordinary way finds files and a clock
  under the names the ecosystem already uses. Today the tools are four
  functions of the `vlab` module, not WASI.
- Loading Python or JavaScript that is already compiled to Wasm (for example
  CPython, or a small interpreter). Today only the subset the parser accepts
  is run.
- Floats, SIMD, and indirect calls. The interpreter rejects those opcodes.
  Without indirect calls there is no vtable and no `call_indirect` from a
  language runtime.

## Network

`net_send` does not open a socket. It answers with the `body` stored in the
grant. A later step, if it is taken, would be a connector that dials only
destinations already granted and that lives outside the theorem, behind the
same process isolation.

## Server isolation

Run `vlab-server` inside Firecracker or gVisor, as an unprivileged process,
with the data directory as the only volume. The threat model counts that as a
layer that does not exist today. It does not turn the theorem into a proof
about the kernel.

## Agents

The sandbox is aimed at that: an explicit grant, a quota, its own directory,
a record. There is no agent, no model, and no tool scheduler. A future agent
would be a client of `POST /api/sandboxes` and of
`POST /api/sandboxes/<id>/exec`, not a new permission hidden in the
interpreter.
