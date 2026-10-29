# Deployment

It is not deployed. The `Dockerfile` builds the native binary and leaves the
process listening on port 8080, inside the container, with the data in
`/data`. It is not a production configuration.

## What the image does

- Ubuntu 24.04, elan, toolchain `v4.35.0`.
- `lake update` and `lake build vlab-server` at the pinned revisions of cairn
  and uvl.
- User `vlab` (uid 10001), with no login shell.
- The process listens on `0.0.0.0:8080` only inside the container network. On
  the machine, the binary stays on `127.0.0.1` unless `--host` is passed.

The Wasm front is not compiled in the image. If the build context brings
`web/dist/`, it is copied and the server serves it. If not, `GET /` says the
front is missing and the API keeps answering.

## Build

A Docker daemon is required. The environment where milestone 0 was written had
no Docker, so this image has not been built or run here.

```bash
docker build -t vlab:dev .
docker run --rm -p 127.0.0.1:8080:8080 -v vlab-data:/data vlab:dev
```

The published port stays on the host loopback. Do not publish `0.0.0.0` on a
machine that can be reached from outside.

## What is missing before production

- A proxy that terminates TLS. The server speaks cleartext HTTP/1.1.
- Rate limits. Milestone 0 only limits the body size and the note size.
- A user and a network tighter still than this container: no extra
  capabilities, a filesystem that is read-only except for `/data`, and an
  isolation runtime (gVisor or Firecracker) if the process comes to execute
  something other than this binary. Milestone 2 writes that down together with
  the sandbox's trusted computing base; here the process is the Lean server,
  not an interpreter of someone else's code.
- Copies and supervision of the data directory. cairn does `fdatasync` per
  commit on the local shard. That does not replace a copy off the machine.
- There is no secret in the image. Do not put tokens in the build context.
