# Remote access validation

LimeNow must not present remote access as ready until the LimeSSH machine-mode
prototype passes every gate below. The prototype is based on Upterm commit
`1a8b11e43b117d4dcfc8d7d92d421cb3f1abbca9`, not Win32-OpenSSH or `sish`.

## Rejected baseline: portable OpenSSH

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

This harness remains in the repository as reproducible evidence for rejecting
Win32-OpenSSH as the foreground, non-administrator server. It is not the active
implementation path.

## Active prototype: LimeSSH machine mode

The active design is a focused Upterm-derived component that handles each SSH
channel as an independent machine session:

- interactive shell requests create a new ConPTY and current-user shell;
- exec requests create a separate process with Windows `cmd.exe /d /s /c`
  semantics and return its real exit status;
- SFTP remains available;
- `direct-tcpip` forwarding is enabled only for loopback destinations by
  default;
- authentication accepts only the configured public keys;
- the host and outbound tunnel use an ephemeral in-memory key;
- closing a channel kills its complete Windows process tree.

The LimeSSH host connects outbound to a self-hosted `uptermd` relay. The relay
allocates a random session ID, so a new GFN machine does not need a persistent
tunnel identity or other long-lived secret under `I:\Apps`.

The MVP deliberately uses a session-scoped address rather than promising a
stable `ssh limenow` alias. A stable protected alias requires a persistent
credential, a local discovery helper, or a device-authorization service and is
outside this phase.

## Validation gates

Run the prototype as an ordinary Windows foreground process and prove:

1. an interactive `ssh` session starts a new ConPTY shell;
2. `ssh ... "exit /b 7"` returns exit code 7;
3. simultaneous interactive and exec sessions remain independent;
4. current OpenSSH `scp` and `sftp` clients work;
5. local TCP forwarding to `127.0.0.1` and `::1` works;
6. forwarding to non-loopback destinations is rejected;
7. disconnecting a session kills its child process tree;
8. only configured public keys authenticate;
9. no private client key or long-lived relay credential is persisted;
10. the same binary passes through the self-hosted relay from a NAT-restricted
    Windows machine;
11. VS Code Remote SSH works with the remote platform set to Windows;
12. the prototype passes inside an actual GFN session.

Only after gates 1-12 pass may LimeNow integrate GitHub public-key enrollment,
display the session-scoped SSH command and VS Code configuration, or document
remote access as supported.

## Current prototype evidence

The pinned prototype currently passes a loopback self-hosted-relay test for:

- public-key-only authentication;
- independent non-interactive exec with expected stdout;
- propagation of Windows exit status 7;
- the SFTP subsystem.

This proves only part of gates 2, 4, 8, and 10 on the current Windows machine.
It does not yet prove interactive ConPTY sessions, concurrent channels, `scp`,
TCP forwarding, process cleanup, a NAT-restricted host, VS Code, or GFN.

## Completed independent work

The setup no longer installs or repairs Codex CLI or GitHub CLI. It removes
LimeNow-managed legacy launchers, shims, packages, and PATH entries while
retaining Node.js, npm, npx, Git, Visual Studio Code, and Windows Terminal.
