# Codex persistence and security

LimeNow installs the pinned official `@openai/codex@0.145.0` npm package under
`I:\Apps\LimeNow\NpmGlobal` and places its managed `codex` wrapper before the
npm package directory on `PATH`. The wrapper prepares a temporary
`%USERPROFILE%\.codex` home, launches the official CLI, and synchronizes only
the state verified below.

## Verified state for Codex CLI 0.145.0

The implementation was checked against the installed Windows package and the
matching `rust-v0.145.0` OpenAI Codex source:

| Purpose               | Temporary Codex path | Persistent LimeNow path      | Handling                                              |
| --------------------- | -------------------- | ---------------------------- | ----------------------------------------------------- |
| File-based login      | `auth.json`          | `Codex\auth\auth.json`       | Restore before launch; synchronize after exit         |
| User configuration    | `config.toml`        | `Codex\config\config.toml`   | Restore before launch; synchronize after exit         |
| Named config profiles | `*.config.toml`      | `Codex\config\*.config.toml` | Restore before launch; synchronize after exit         |
| Active rollouts       | `sessions\`          | `Codex\sessions\active\`     | Directory junction; writes are immediately persistent |
| Archived rollouts     | `archived_sessions\` | `Codex\sessions\archived\`   | Directory junction; writes are immediately persistent |

The wrapper forces `cli_auth_credentials_store="file"` for managed launches.
That avoids relying on a temporary machine's Windows credential store. Codex
still receives its normal temporary `CODEX_HOME`; LimeNow does not redirect the
entire home to persistent storage.

Codex 0.145.0 discovers and resumes conversations from rollout files under
`sessions`. Its `state_5.sqlite` database indexes those rollouts and can
backfill from them, so LimeNow intentionally lets that database be recreated on
each temporary machine. This avoids persisting SQLite lock/WAL files and
unrelated goals, memory, or diagnostic databases.

## Deliberately excluded

LimeNow does not persist Codex caches, downloaded sandbox binaries, plugins,
skills, logs, command history, installation identifiers, model caches, MCP
OAuth locks, goals, memories, or SQLite databases. Repository-local
`.codex\config.toml` files remain with their repositories and are outside this
profile-state synchronization.

The official Codex package itself remains in the persistent npm global
directory, so setup verifies the existing installation before considering an
npm repair.

## Migration and replacement-machine behavior

On the first managed run, LimeNow copies an existing `auth.json`,
`config.toml`, named profiles, and session rollouts into the dedicated layout.
It then replaces only the two temporary session directories with junctions.
The original temporary directories are renamed with a
`.limenow-migrated-<timestamp>` suffix as a recoverable migration backup; they
are not copied into persistent storage.

On a replacement GFN machine, setup restores auth and config files and recreates
the two junctions. The official CLI can then discover the persistent rollouts
and rebuild its temporary index. A normal `codex login`, token refresh, or
configuration change is synchronized when the managed CLI exits. Session
rollouts are already persistent while Codex is running.

## Security boundary

`auth.json` contains reusable access tokens and must be treated like a password.
Session rollout files contain conversation content, prompts, paths, command
output, and other work context. LimeNow never writes either file's contents to
setup logs or support output.

The state manager attempts to remove inherited permissions from the persistent
auth, session, and config directories and grants access only to the current
Windows identity and `SYSTEM`. Some SalsaNOW-backed storage may not fully honor
Windows ACLs; setup reports that limitation without printing state contents.
The files therefore inherit the security, availability, backup, and account
access properties of SalsaNOW's `I:\Apps` storage. Do not use this feature if
that trust boundary is inappropriate for the Codex account or source material.

Signing out through the managed `codex logout` command updates the temporary
home and synchronizes it on exit. Before giving up the SalsaNOW storage itself,
also remove `I:\Apps\LimeNow\Codex\auth\auth.json` from a trusted session.
