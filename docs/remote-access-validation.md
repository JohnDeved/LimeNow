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

For the MVP, the LimeSSH host connects outbound to the public
`uptermd.upterm.dev` community relay. The relay allocates a random session ID,
so a new GFN machine does not need a persistent tunnel identity or other
long-lived secret under `I:\Apps`. A LimeNow-operated relay is a future feature
and does not block the MVP.

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
10. the same binary passes through the public community relay from a
    NAT-restricted Windows machine;
11. VS Code Remote SSH works with the remote platform set to Windows;
12. the prototype passes inside an actual GFN session.

The normal-OpenSSH path may be integrated behind an explicitly labeled preview
after its local and GFN public-relay gates pass. The community relay is an
external best-effort MVP dependency; a managed LimeNow relay is a future
feature. Gate 11 independently blocks any VS Code Remote SSH support claim; the
preview must not imply that VS Code is supported.

## Current prototype evidence

The pinned prototype currently passes a loopback relay test for:

- public-key-only authentication;
- an interactive `cmd.exe` ConPTY shell;
- independent non-interactive exec with expected stdout;
- propagation of Windows exit status 7;
- simultaneous independent exec channels;
- the SFTP subsystem and current OpenSSH `scp` upload/download;
- TCP forwarding to both `127.0.0.1` and `::1`, including bidirectional data
  validation through the IPv4 path;
- explicit rejection of a non-loopback forwarding destination;
- termination of a background child through the Windows job object after the
  primary command and SSH channel complete;
- prompt termination of an active command after the local OpenSSH process is
  forcibly terminated.

The same binary was then run inside the actual GFN VM
(`GEFORCE-NOW\kiosk` on computer `GEFORCE-NOW`) against the public
`ssh://uptermd.upterm.dev:22` relay. A second OpenSSH client reached the
session-scoped address through that relay, executed
`echo LIMESSH_PUBLIC_RELAY_OK`, and returned exit code 0. This proves the
outbound-tunnel and relayed SSH transport from GFN; the machine does not need
an inbound port.

Together these results prove gates 1-9 and the public-relay transport portions
of gates 10 and 12. The complete public-relay matrix remains to be exercised
before gate 10 is closed. VS Code Remote SSH is deferred: the GFN image blocks
legacy Windows PowerShell, which the current Microsoft bootstrap invokes even
when PowerShell 7 is available. That limitation does not affect normal OpenSSH
shell, exec, SFTP, SCP, or forwarding clients.

The opt-in LimeNow manager now also passes a loopback-relay product-lifecycle
test for:

- fetching a GitHub account's published SSH keys into the active authorized-key
  file;
- enrolling a directly pasted public key without persisting private material;
- rejecting an unconfigured client key;
- emitting a copyable session-specific SSH command with `HostKeyAlias` and
  `StrictHostKeyChecking accept-new`;
- emitting SCP/SFTP commands that safely handle relay usernames containing
  colons;
- reusing the single managed process on repeated startup;
- executing through the enrolled key; and
- revoking access when the managed LimeSSH process stops.

Run this integration gate with:

```powershell
& .\tools\Test-RemoteAccessManager.ps1
```

Run the same product lifecycle through the public relay from GFN with:

```powershell
& .\tools\Test-RemoteAccessManager.ps1 `
    -Server 'ssh://uptermd.upterm.dev:22' `
    -SkipGitHubEnrollment
```

## Completed independent work

The setup no longer installs or repairs Codex CLI or GitHub CLI. It removes
LimeNow-managed legacy launchers, shims, packages, and PATH entries while
retaining Node.js, npm, npx, Git, Visual Studio Code, and Windows Terminal.
