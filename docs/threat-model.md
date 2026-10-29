# Threat model

The vlab sandbox exists to run third-party code that is not trusted. The case
that steers the design, even though this milestone does not yet host a
complete agent, is an isolated AI agent: the model proposes a Wasm module and
the server runs it with the tools an operator granted, and with no others.

The attacker is that module, or the agent that chose it. It wants to leave
the sandbox, read or write outside its directory, talk to a network
destination that is not on the list, or exhaust CPU, memory, or the disk.

## What is assumed about the attacker

- It controls every byte of the module and every byte it writes into its
  linear memory.
- It can call the host functions exported by the interpreter (`fs_read`,
  `fs_write`, `net_send`, `clock_ms`, `random`).
- It can try `..` paths, addresses outside memory, loops, and many calls.
- The module is not assumed to be well formed beyond what the parser accepts.
  If the parser rejects it, it is not run.
- It is not an attacker against the kernel, nor against the operator who
  chooses the quotas, nor against someone who can write the server's data
  directory by another path.

## Layers

| Layer | What it guarantees in this milestone | What it does not guarantee |
| --- | --- | --- |
| Lean theorems (`Vlab.Wasm`, `Vlab.Sandbox`) | A `load` or `store` that returns bytes is inside the memory size. `store` does not change that size. `grow` does not pass the quota when it starts from a memory that already fit. `normalize` does not return a path with `..`, `.`, or an empty segment: a `..` that would leave the root is `none`. An admitted host call had the capability in the list; a denied one does not modify the virtual filesystem or the network table. With fuel 0 the evaluator stops at `outOfFuel`. The evaluator is defined by recursion on fuel, so an execution stops. | It is not a bisimulation with the Wasm specification. It does not cover floats, SIMD, indirect calls, or WASI. It does not speak about the parser, nor about `IO`, nor about the disk, nor about the kernel. |
| Interpreter | The only host effect goes through `perform`. Guest memory changes only by `store?` or `grow`. Each instruction spends one unit of the fuel it was given. The network does not open a socket: `net_send` looks at an in-memory table. | A parser failure can reject a valid module or, if it accepts something outside the subset, interpret it wrongly. The differential against wasmtime covers a few small modules, not the whole subset. |
| Host (this process) | Each sandbox has its own directory. Writes use the already normalized segment list, not the raw string. Symbolic links are not followed: only regular files are read. Fuel, memory, host-call, and virtual-directory byte quotas are bounded by the process as well as by the request. Create, run, and destroy are distinct APIs. Each execution is born with linear memory at zero, fuel full, and the call counter at zero. The virtual directory lives as long as the sandbox lives. | The theorem does not mention `IO.FS`. We trust the Lean runtime and the kernel to apply that path. One sandbox does not protect against another process that can reach the same data directory. |
| Container | It is not in this milestone. The server `Dockerfile` is not isolation for the guest code. | There is no gVisor and no Firecracker. A failure in the Lean runtime, the compiler, or the kernel is not contained by a lower layer. |

## Capabilities

All of them are granted when the sandbox is created. There is no default
permission.

- `fsRead` / `fsWrite` with a prefix inside that sandbox's virtual directory.
  The empty prefix is the virtual root, not the server's disk.
- `net` with a host and a port. In this milestone the response is a body fixed
  in the grant (`body`). No packet leaves for the network.
- `clock`. The reading is the server clock at the instant that execution
  starts, frozen for the rest of it.
- `random`. Bytes are requested from the system only if it is granted, and at
  most 256 per call.

Quotas are explicit too, with a server ceiling: fuel ≤ 100000, memory ≤ 1
MiB, host calls ≤ 1000, total bytes in the virtual directory ≤ 256 KiB,
module ≤ 16 KiB, at most 32 live sandboxes.

## Isolation between sandboxes

Each id has its own grant, its own quota, and its own directory. One
execution does not inherit another's linear memory or fuel. Destroying a
sandbox deletes its directory. The cairn record is not deleted: the audit can
be reconstructed afterwards.

## Trusted computing base

We trust the Lean kernel, the Lean compiler, the Lean runtime written in C,
the process that performs `IO`, the operating-system kernel, and the hardware.
The differential against wasmtime is evidence of agreement on a few programs,
not a proof that the interpreter implements Wasm. wasmtime is not in the
sandbox's trusted computing base: if the two disagree, there is a defect to
investigate, not a permission for the guest.

It is not impossible to escape. A defect in the parser, in the part of `IO`
the theorem does not look at, or in the runtime, can be that escape. The
defense that is missing is to run this process inside gVisor or Firecracker,
without privileges. That is written in [next-steps.md](next-steps.md) as
future work, not as a property of this milestone.
