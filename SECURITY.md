# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | yes |

0.1.0 is the first published version. There is no older release to patch.

## Reporting a vulnerability

Report a security issue privately through a
[GitHub security advisory](https://github.com/kidandcat/vlab/security/advisories/new).

Do not open a public issue, pull request, or discussion for a vulnerability,
and do not put exploit details in a public commit.

A report on the advisory will be acknowledged, confirmed or rejected, and a
fix coordinated before anything is disclosed in public. There is no bug-bounty
program.

## Scope of the sandbox

The Wasm sandbox is not a security boundary.
[docs/threat-model.md](docs/threat-model.md) names the trusted computing base
and the layers this tree does not have: no gVisor and no Firecracker. A defect
in the interpreter, the parser, or the host `IO` path is still in scope for a
private report. The fact that untrusted code can escape this process is
already the documented design. That fact, on its own, is not a new
vulnerability.
