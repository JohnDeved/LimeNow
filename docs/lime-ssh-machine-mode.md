# LimeSSH machine-mode prototype

## Source and license

LimeSSH starts from Upterm commit
`1a8b11e43b117d4dcfc8d7d92d421cb3f1abbca9`. Upterm is licensed under
Apache-2.0. The prototype must retain its license and attribution, and releases
must pin both the source commit and binary SHA-256 checksums.

The prototype is carried as
`patches/0001-Add-LimeSSH-machine-mode.patch`. Build and verify it from the
pinned source with:

```powershell
& .\tools\Build-LimeSshPrototype.ps1
& .\tools\Test-LimeSshPrototype.ps1
```

The build harness downloads the checksum-pinned Go toolchain into a temporary
directory (reusing only a checksum-verified archive cache), checks out the
pinned Upterm commit, verifies and applies the patch, runs the focused unit and
compile tests, and writes the prototype binary under `artifacts`. VCS metadata
embedding is disabled and two independent builds produced the same SHA-256:

```text
8b203f33c8d87756a054e1d7382456c926f13ec2ccbf5341bd41226cfdd109ec
```

`.github/workflows/build-limessh.yml` repeats that build on a Windows runner,
fails on any hash mismatch, and publishes the binaries, Apache-2.0 license,
provenance, and checksums as a prerelease after the workflow reaches `main`.

The end-to-end harness starts the pinned relay on loopback and
validates public-key authentication, interactive ConPTY, independent and
concurrent exec, exit status 7, SFTP, current `scp`, loopback forwarding,
to both `127.0.0.1` and `::1`, non-loopback rejection, and job cleanup after
both normal command/channel completion and forced client termination.
Temporary source, toolchain, keys, and relay state are removed afterward.

## Behavioral delta from Upterm

Normal Upterm hosts one shared command and requires a PTY when a client
attaches. Machine mode must leave that existing behavior unchanged and add a
separate opt-in path.

`--machine-mode` does not start a global shared command. The SSH server creates
one process lifecycle per session channel.

### Shell channels

- Require a PTY request.
- Start a fresh ConPTY for every channel.
- Start `cmd.exe` by default as the current user.
- Forward input and combined terminal output.
- Apply window-change requests.
- Place the process in a kill-on-close Windows job object.

### Exec channels

- Do not require a PTY.
- Use the raw SSH command as one argument to `cmd.exe /d /s /c`.
- Forward stdin, stdout, and stderr without merging stdout and stderr.
- Return the child process exit code in the SSH exit-status request.
- Cancel and kill the process tree when the channel closes.

### Subsystems and forwarding

- Retain Upterm's SFTP subsystem.
- Retain `direct-tcpip`, but accept only destinations that parse as loopback IP
  addresses or the exact hostname `localhost`.
- Resolve `localhost` locally; do not accept arbitrary hostnames that happen to
  resolve to loopback.

### Authentication and identity

- Require at least one configured authorized public key in machine mode.
- Do not read a client private key, `~/.ssh`, or an SSH agent on GFN.
- Generate the host/tunnel Ed25519 signer in memory for every LimeSSH run.
- Do not write that signer or a relay credential to persistent storage.

## Prototype test boundary

Unit tests must cover mode selection, command construction, exit-code
propagation, public-key-required validation, and forwarding destination policy.
Windows integration tests must cover ConPTY resize, concurrent channels, SFTP,
`scp`, loopback forwarding, and job-object cleanup.

Relay and product claims require separate end-to-end evidence on a
NAT-restricted Windows host, then on GFN. The public-relay probe has now passed
from an actual GFN VM, proving that outbound reverse-tunnel transport works
without an inbound port. A pinned self-hosted relay deployment remains a
separate production gate.

## LimeNow preview integration

`remote-access.ps1` implements the opt-in product lifecycle:

- enroll public keys from a GitHub username or a pasted public key;
- persist only public enrollment data and the relay URL;
- regenerate the active `authorized_keys` file on session-local storage;
- start at most one LimeSSH process during SalsaNOW startup;
- publish SSH, SCP, SFTP, and config examples with a session-specific
  `HostKeyAlias` and `StrictHostKeyChecking accept-new`;
- stop the managed process and revoke the relay session.

`setup.ps1` installs only the checksum-pinned prerelease binary and matching
Apache-2.0 license, offers first-run enrollment, creates the desktop manager
shortcut, and restarts an enabled session from SalsaNOW's existing startup
hook. The community relay is a preview default; the server URL is stored in
configuration so the production self-hosted endpoint can replace it without a
client design change.
