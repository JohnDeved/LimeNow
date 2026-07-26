# Remote access validation

Issue #1 is intentionally split into validation phases. LimeNow must not present
remote access as ready until every Phase 1 and Phase 2 check passes.

## Phase 1: portable OpenSSH

Run from a normal, non-administrator PowerShell session:

```powershell
& .\tools\Test-PortableOpenSsh.ps1
```

The harness downloads the pinned official Win32-OpenSSH archive, verifies its
SHA-256 digest, creates temporary host and client keys, binds `sshd` to
`127.0.0.1`, and checks public-key-only command execution and SFTP. All keys and
files used by the harness are deleted from the Windows temporary directory.

Current result on the SalsaNOW/GeForce NOW-style Windows session:

```text
Non-interactive command  False  255
SFTP subsystem           False  255
```

Authentication succeeds, but the post-authentication session cannot start its
configured shell:

```text
CreateProcessW failed error:5
exec request failed on channel 0
```

This is consistent with Win32-OpenSSH's documented service-oriented security
model: the listener normally runs as `SYSTEM` and creates authenticated user
tokens. Starting the official binary as an ordinary foreground process is not
yet a working server implementation.

Do not bypass this failure by:

- installing or starting an administrator-only Windows service;
- disabling public-key authentication;
- exposing the local port publicly;
- substituting a shared-terminal product that lacks normal SSH exec semantics;
- storing a private relay key or other long-lived secret under `I:\Apps`.

## Phase 2: sish relay

Phase 2 remains gated on Phase 1. It must also prove how a new GFN machine can
reclaim a stable private alias without persisting a tunnel private key or other
long-lived credential. A relay configuration that lets anonymous clients claim
aliases does not meet the isolation or anti-hijacking requirements.

## Completed independent work

The setup no longer installs or repairs Codex CLI or GitHub CLI. It removes
LimeNow-managed legacy launchers, shims, packages, and PATH entries while
retaining Node.js, npm, npx, Git, Visual Studio Code, and Windows Terminal.
