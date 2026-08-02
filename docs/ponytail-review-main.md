# Ponytail review of `main`

Reviewed commit: `abb7b5f2034c5ddfe85b16f5b44590e92a498d62`

This is a documentation-only review. It proposes no code changes and intentionally evaluates only avoidable complexity, speculative flexibility, duplication, and historical residue. It does not replace correctness, security, performance, or product validation reviews.

## Executive summary

LimeNow's current design is understandable, but `main` now carries several layers that are larger than the product requirements they serve:

- historical validation code for an implementation path that was rejected;
- a background Codex migration watcher for a one-time edge case;
- multiple SSH command and restart experiences that converge on the same behavior;
- duplicate script-installation, path-management, cleanup, and documentation flows;
- product configurability and release artifacts for a future relay that is explicitly outside the MVP.

A conservative cleanup should be able to remove approximately **700–900 lines** without dropping an advertised feature. Two conditional simplifications could raise that to roughly **950–1,150 lines**:

1. require Codex to be closed during its one-time persistence migration instead of supporting migration while Codex is already running;
2. keep LimeSSH's machine mode Windows-specific until another platform is actually supported.

## Keep as-is

The following complexity is justified by current requirements and should not be removed merely to reduce line count:

- pinned upstream commits, tool versions, binary hashes, licenses, and provenance;
- public-key-only LimeSSH authentication;
- loopback-only forwarding policy;
- kill-on-close Windows job-object handling;
- the narrow Codex state allowlist instead of persisting all of `CODEX_HOME`;
- atomic replacement of sensitive or actively written state;
- the core LimeSSH end-to-end integration matrix;
- the cross-process LimeSSH startup mutex.

## Findings

### 1. Delete the rejected Win32 OpenSSH harness and baseline narrative

**Category:** `delete`

**Files:**

- `tools/Test-PortableOpenSsh.ps1`
- `docs/remote-access-validation.md`

The repository retains a 149-line executable harness for an architecture that the project has already rejected. The active LimeSSH workflow does not run it, and issue history already records the reason the approach failed.

Keep a short architectural-decision paragraph in the active remote-access document and delete the executable harness plus its detailed failure transcript.

**Estimated reduction:** 180–200 lines.

### 2. Remove the hidden Codex snapshot watcher if live migration is not a hard requirement

**Category:** `yagni` — conditional

**Files:**

- `codex-state.ps1`
- `tools/Test-CodexPersistence.ps1`
- `docs/codex-persistence.md`

The persistence manager supports setup being run while an unmanaged Codex process is already active. That requirement creates:

- deferred junction creation;
- snapshot-only mode;
- a hidden background PowerShell process;
- a named mutex;
- polling every five seconds;
- best-effort merging of live rollout files;
- complete-line checks for JSONL promotion;
- additional startup race handling and test cases.

A smaller contract is available: if Codex is running during first-time migration, tell the user to close it and rerun setup. Managed Codex launches already initialize persistence before starting the CLI, so the complex path exists mainly for migration from an unmanaged active process.

Choose the watcher only if uninterrupted live migration is a deliberate product requirement rather than an implementation convenience.

**Estimated reduction:** 180–260 lines across runtime, tests, and documentation.

### 3. Replace per-item ACL construction with one native recursive ACL operation per root

**Category:** `native`

**File:** `codex-state.ps1`

`Protect-PersistentState` recursively enumerates every item, constructs separate .NET ACL objects for files and directories, applies them individually, and then falls back to `icacls` item by item.

Use a root-level native ACL operation with inherited current-user and `SYSTEM` access, applying recursively only when upgrading an existing tree. Keep the warning when the backing storage does not honor ACLs.

This preserves the security boundary while removing a large custom ACL engine.

**Estimated reduction:** 55–80 lines.

### 4. Remove generic command shims that duplicate `PATH`

**Category:** `delete`

**File:** `setup.ps1`

`Ensure-DeveloperEnvironment` already places Node.js, npm, npx, Git, VS Code, Windows Terminal, the Codex wrapper, and npm globals into both the current process and user `PATH`. `Ensure-DeveloperCommandShims` then generates another command-resolution layer under `%LOCALAPPDATA%\Microsoft\WindowsApps`.

Keep the Codex wrapper because it provides persistence behavior. Remove the generic `node`, `npm`, `npx`, `git`, `code`, and `wt` shims unless a concrete environment has been demonstrated where the updated process/user `PATH` is insufficient.

**Estimated reduction:** 35–45 lines.

### 5. Consolidate the two managed PowerShell-script installers

**Category:** `shrink`

**File:** `setup.ps1`

`Ensure-CodexStateManager` and `Ensure-LimeSshManager` perform the same sequence:

1. choose a repository-local source when present;
2. otherwise download from raw GitHub;
3. parse-check the candidate;
4. copy only when changed;
5. clean the repair directory.

Replace both with one helper accepting source name, URL, destination, and validation error text.

**Estimated reduction:** 30–45 lines.

### 6. Collapse the duplicate user/process `PATH` merge loops

**Category:** `shrink`

**File:** `setup.ps1`

The user `PATH` and current-process `PATH` are rebuilt through nearly identical loops. Use one small function that accepts an existing path string and returns the merged value.

**Estimated reduction:** 12–20 lines.

### 7. Reuse the repair-directory cleanup helper everywhere

**Category:** `shrink`

**File:** `setup.ps1`

`Remove-SetupRepairDirectory` exists, but the Node.js and Modrinth repair paths repeat custom full-path and prefix checks in their `finally` blocks.

Use the helper consistently.

**Estimated reduction:** 12–18 lines.

### 8. Use pinned archive hashes instead of runtime release discovery where versions are already fixed

**Category:** `shrink`

**File:** `setup.ps1`

Most tools use a fixed version, direct URL, and expected hash. Node.js instead downloads `SHASUMS256.txt` and parses it at runtime. Modrinth calls the GitHub Releases API to rediscover an asset whose tag and name are already constants.

For consistency and less runtime machinery:

- store the Node.js archive hash beside `nodeVersion` and reuse `Get-VerifiedDownload`;
- store a direct Modrinth release URL and archive hash beside `modrinthReleaseTag` and reuse the same helper.

The release workflows can remain the place where those hashes are generated and verified.

**Estimated reduction:** 40–65 lines.

### 9. Install LimeSSH only after opt-in

**Category:** `yagni`

**File:** `setup.ps1`

`Ensure-LimeSshRemoteAccess` downloads and verifies the LimeSSH binary, installs the manager, and creates the desktop shortcut before asking whether remote access should be enabled.

For an opt-in preview:

- on first setup, ask first and install only after acceptance;
- on startup, do nothing unless an enabled configuration exists;
- install or repair the binary and manager only for configured users.

This mainly removes unnecessary startup and persistent-storage work rather than many source lines, but it narrows the default product surface.

### 10. Merge `Refresh Keys` and `Retry`

**Category:** `delete`

**Files:**

- `remote-access.ps1`
- `tools/Test-RemoteAccessManager.ps1`
- `README.md`
- LimeSSH documentation

Both actions stop the current host and call the same start path. Every start already refetches keys for a configured GitHub username, so `Refresh Keys` and `Retry` differ only in their log message.

Expose one `Restart` action.

**Estimated reduction:** 20–35 lines plus duplicated tests and documentation.

### 11. Drop the short-command and one-time `%C` client configuration feature

**Category:** `yagni`

**Files:**

- `remote-access.ps1`
- `tools/Test-RemoteAccessManager.ps1`
- `README.md`
- LimeSSH documentation

The manager already emits a complete safe SSH command using a session-specific `HostKeyAlias` and `StrictHostKeyChecking=accept-new`. It additionally generates:

- a short command;
- a persistent one-time client rule;
- extra status fields;
- a connection-file section;
- compatibility reconstruction for older status files;
- dedicated tests and documentation.

For an MVP with a new session address every run, copying the complete safe command is the simpler user contract. Reintroduce a local helper only after repeated user demand for a persistent short form.

**Estimated reduction:** 70–110 lines across runtime, tests, and documentation.

### 12. Remove the unreleased `session.json` compatibility reconstruction

**Category:** `delete`

**File:** `remote-access.ps1`

`Get-SessionStatus` reconstructs missing `ShortSshCommand` and `OneTimeClientConfig` fields from an older status shape. LimeSSH's manager and status format landed together, so there is no established stable format that requires this migration branch.

This finding becomes automatic if the short-command feature is removed.

**Estimated reduction:** 15–25 lines.

### 13. Merge duplicate LimeSSH process lookup helpers

**Category:** `shrink`

**File:** `remote-access.ps1`

`Get-ManagedHostProcess` and `Get-LimeSshProcesses` both resolve the expected executable path and validate process paths. Return the matching process set once, then select the status PID from that set where needed.

**Estimated reduction:** 15–25 lines.

### 14. Keep relay override test-only until a second relay exists

**Category:** `yagni`

**Files:**

- `remote-access.ps1`
- LimeSSH documentation

The product persists an arbitrary relay URL in `config.json` even though the only supported MVP service is `uptermd.upterm.dev` and a LimeNow-operated relay is explicitly future work.

Hardcode the MVP relay in user configuration. Retain a non-persisted `-Server` override for integration tests and development.

**Estimated reduction:** 15–25 lines and one configuration field.

### 15. Stop publishing `uptermd.exe` as a LimeNow release asset

**Category:** `delete`

**Files:**

- `.github/workflows/build-limessh.yml`
- `tools/Build-LimeSshPrototype.ps1`
- LimeSSH documentation

The loopback integration test needs a relay binary, but the product does not operate or distribute a LimeNow relay yet. Build `uptermd.exe` transiently for CI and local tests, but publish only the client binary, license, provenance, and checksums needed by LimeNow users.

**Estimated reduction:** 15–30 lines and a smaller release surface.

### 16. Keep machine mode Windows-specific until another platform is required

**Category:** `yagni` — conditional

**Files:**

- `patches/0001-Add-LimeSSH-machine-mode.patch`
- `tools/Build-LimeSshPrototype.ps1`

LimeNow targets Windows on GeForce NOW, but the patch adds a non-Windows execution file, a runtime `GOOS` branch, and configurable machine-shell plumbing.

Until a second platform or shell is supported, hardcode the Windows `cmd.exe` contract and remove the unused portability layer. Keep this only if the patch is intentionally being prepared for upstream contribution.

**Estimated reduction:** 25–45 lines.

### 17. Consolidate remote-access documentation

**Category:** `shrink`

**Files:**

- `README.md`
- `docs/lime-ssh-machine-mode.md`
- `docs/remote-access-validation.md`

The same source pin, community-relay model, forwarding restrictions, validation matrix, limitations, and manager behavior appear in all three places.

Use:

- README: brief user-facing capability, warning, and one link;
- one LimeSSH document: architecture, build provenance, validation evidence, and current limitations.

Delete historical narrative and the stale `Completed independent work` section that says setup no longer installs Codex.

**Estimated reduction:** 90–140 lines.

### 18. Time-box one-release migration cleanup

**Category:** `delete later`

**File:** `setup.ps1`

`Remove-ObsoleteGitHubCli` is appropriate for users upgrading from the previous main branch, but it should not become permanent setup behavior.

Add a removal milestone after one transition release or a documented support window.

**Future reduction:** 15–25 lines.

## Suggested implementation sequence

1. Delete historical OpenSSH artifacts and consolidate documentation.
2. Simplify the LimeSSH user contract: one safe command and one restart action.
3. Make LimeSSH truly opt-in and remove product relay configurability.
4. Deduplicate setup helpers, path handling, and cleanup.
5. Simplify archive verification inputs.
6. Replace custom ACL traversal with native root-level handling.
7. Decide explicitly whether live Codex migration and non-Windows machine mode are product requirements.
8. Remove the GitHub CLI migration code after its support window.

## Expected result

The project would keep the same core capabilities while having fewer background processes, fewer persistent formats, fewer user-facing SSH variants, fewer runtime network discovery steps, and less duplicated setup and documentation code.
