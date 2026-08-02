# 🍋‍🟩 LimeNow

**A companion extension for [SalsaNOW](https://github.com/dpadGuy/SalsaNOW).**

LimeNow builds on an existing SalsaNOW installation and automates a few useful
session customizations: a persistent Modrinth App compatibility setup, German
QWERTZ, and the Windows timezone/certificate fixes needed for Microsoft
authentication on GeForce NOW machines.

> [!IMPORTANT]
> LimeNow is not a SalsaNOW replacement, fork, installer, or unlock method.
> Install and start SalsaNOW first. LimeNow then runs through SalsaNOW's
> supported `StartupBatch.bat` extension point.

## What LimeNow does

### General fixes & improvements

- fixes SalsaNOW's Windows timezone and NVIDIA proxy-certificate validation;
- applies German QWERTZ after the startup environment settles, with bounded
  retries and foreground-layout verification;
- enables the Windows taskbar input indicator and keeps an English-US layout
  available alongside German QWERTZ for quick keyboard switching;
- installs a managed block in SalsaNOW's `I:\Apps\SalsaNOW\StartupBatch.bat`;
- shows live setup progress in the existing session setup console without
  opening a redundant second command window;
- checks GitHub for LimeNow updates at launch and keeps the last known-good setup
  when the update is unavailable or invalid;
- preserves unrelated commands already present in `StartupBatch.bat`;
- repairs missing or damaged managed files whenever SalsaNOW starts.

### Development tools

- installs a persistent official Node.js LTS build with npm and npx;
- installs and repairs the official OpenAI Codex CLI;
- installs portable Git for Windows;
- installs the official GitHub CLI (`gh`) as a checksum-pinned portable tool;
- installs official Visual Studio Code in portable mode, including the `code` CLI;
- installs the official unpackaged Windows Terminal in portable mode, without
  administrator rights or the Microsoft Store;
- adds `node`, `npm`, `npx`, `codex`, `git`, `gh`, `code`, and `wt` to `PATH`;
- configures Node.js to use the trusted Windows certificate store on GeForce NOW;
- creates desktop launchers for Codex, Visual Studio Code, and Windows Terminal;
- opens Command Prompt inside Windows Terminal from its desktop launcher;
- keeps editor extensions, settings, terminal state, npm packages, and tools in
  SalsaNOW's persistent `I:\Apps` storage;
- keeps GitHub CLI configuration and opt-in authentication under
  `I:\Apps\LimeNow\GitHubCLI\Config`;
- keeps only Codex authentication, resumable sessions, and user configuration
  under `I:\Apps\LimeNow\Codex`.

> [!WARNING]
> Codex file-based authentication contains reusable access tokens. LimeNow
> stores that file in SalsaNOW's persistent `I:\Apps` storage so sign-in can
> survive a replacement GFN machine. Anyone or anything with access to that
> storage may be able to access the same credentials and session transcripts.
> LimeNow applies a current-user-and-SYSTEM ACL where the storage supports
> Windows permissions, but SalsaNOW's storage security remains the outer trust
> boundary. See [Codex persistence and security](docs/codex-persistence.md).

> [!WARNING]
> Persistent GitHub CLI sign-in stores a reusable OAuth token in plaintext under
> SalsaNOW's persistent storage because an ephemeral GFN credential vault cannot
> survive machine replacement. LimeNow restricts that directory to the current
> user and SYSTEM where the storage supports Windows ACLs, but anyone with access
> to the underlying SalsaNOW storage may be able to use the same GitHub access.
> See [GitHub CLI persistence and security](docs/github-cli-persistence.md).

### Remote development preview

LimeNow includes an opt-in LimeSSH preview for normal OpenSSH clients. It runs
as the current GFN user, creates an outbound reverse tunnel, and authorizes only
the public keys published by a configured GitHub username or a public key pasted
from the user's personal computer. No private SSH key, OAuth token, Windows
service, administrator right, or inbound port is required.

On first setup, LimeNow offers to configure remote access. It can also be
configured later from the **LimeSSH Remote Access** desktop shortcut. Every
session receives a new relay address. LimeNow copies a host-key-safe `ssh`
command to the clipboard and writes SSH, SCP, SFTP, and optional config examples
to **LimeSSH Connection.txt** on the desktop.

The desktop manager shows the active connection and offers Copy, Refresh Keys,
Retry, Configure, and Stop actions. Refreshing keys or retrying intentionally
creates a new session address.

The connection file also includes a one-time personal-PC SSH configuration that
keeps a separate known-hosts entry for every session. After adding it, future
sessions use the shorter standard form:

```shell
ssh SESSION_ID@uptermd.upterm.dev
```

This is a preview, not a production support claim. It currently defaults to the
public Upterm community relay, which is the MVP endpoint and an external
best-effort dependency. A LimeNow-operated relay is a future feature, not an
MVP requirement. VS Code Remote SSH is not documented as supported.

### Minecraft

- installs or repairs a portable Modrinth App compatibility build under `I:\Apps`;
- makes Microsoft/Minecraft authentication work with GeForce NOW's HTTPS proxy;
- persists Modrinth settings, instances, and Microsoft sessions across machines;
- verifies the compatibility archive and executable with SHA-256;
- restores the persistent Modrinth desktop shortcut;
- keeps the shorter persistent profile path needed by large modpacks.

### More coming

LimeNow is designed as a small SalsaNOW extension point rather than a replacement.
More session fixes and opt-in app integrations can be added as repeatable,
self-repairing modules.

## Install the extension on a SalsaNOW session

After SalsaNOW has started, open PowerShell and paste:

```powershell
Set-TimeZone -Id 'W. Europe Standard Time'; irm 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/install.ps1' | iex
```

The timezone command must run first because some SalsaNOW sessions expose a
Central European clock while Windows incorrectly labels it as UTC. That can
make NVIDIA's short-lived HTTPS proxy certificates appear expired.

## Automatic session updates

On each SalsaNOW launch, LimeNow opens a visible progress terminal and checks
the `main` branch for the latest setup. A downloaded setup must carry LimeNow's
script marker, expose the expected startup parameters, and pass PowerShell
syntax validation before it atomically replaces the installed copy. The prior
copy is retained as `SalsaNOW-EasySetup.ps1.previous`.

After the setup is verified, LimeNow also refreshes its Codex state manager and
LimeSSH manager. If GitHub is unavailable or any downloaded script is invalid,
the session continues with the installed known-good files. The progress window
closes automatically after showing the result. Automatic updates trust code
published to this repository's `main` branch over HTTPS.

## Persistent GitHub CLI sign-in

LimeNow creates a **GitHub CLI Sign In** desktop shortcut. It starts GitHub's
device flow in a terminal, shows an offline QR for GitHub's device page, and
then displays GitHub CLI's one-time code. Scan the QR with a phone, or open the
shown URL on the local computer, and enter the code there. LimeNow suppresses
browser launch inside the GeForce NOW session. Authorization includes GitHub's
`workflow` scope so Git can push changes to GitHub Actions workflow files; the
shortcut upgrades an existing sign-in if that permission is missing.

The flow deliberately passes `--insecure-storage` so the reusable token is
written beneath the persistent `GH_CONFIG_DIR` instead of the temporary
machine's Windows credential vault. The shortcut displays the storage warning
before authentication. Normal `gh` commands and Git HTTPS credential requests
are then routed through that same persistent directory.

## Audit before running

- [Read `install.ps1`](install.ps1)
- [Read the full extension setup](setup.ps1)
- [Inspect the startup update and progress tests](tools/Test-StartupExperience.ps1)
- [Inspect the GitHub CLI persistence tests](tools/Test-GitHubCliPersistence.ps1)
- [Read the Codex persistence and security model](docs/codex-persistence.md)
- [Read the GitHub CLI persistence and security model](docs/github-cli-persistence.md)
- [Read the remote-access validation status](docs/remote-access-validation.md)
- [Read the LimeSSH machine-mode prototype contract](docs/lime-ssh-machine-mode.md)
- [Inspect the pinned LimeSSH prototype patch](patches/0001-Add-LimeSSH-machine-mode.patch)

LimeNow never prints account passwords, Codex credentials, GitHub tokens,
private SSH keys, or API keys. It does not read or parse GitHub CLI's token. Its
Codex state manager copies the existing `auth.json` credential file between the
temporary profile and SalsaNOW's persistent storage without parsing or logging
its contents.
Modrinth itself stores its Microsoft session in its application database.
LimeNow places that unmodified database in SalsaNOW's persistent storage so the
session can survive a new machine; anyone with access to that storage should
treat it as sensitive.

## Why a compatibility build is needed

SalsaNOW runs inside GeForce NOW, whose caching proxy presents an NVIDIA HTTPS
certificate chain. Windows trusts that chain, but official Modrinth App builds
currently use bundled web-PKI roots instead of the Windows certificate store.
This breaks the final Microsoft OAuth token request even though sign-in succeeds
in the embedded browser.

LimeNow builds Modrinth reproducibly from an exact official source tag and
switches only its HTTP client to Windows-native TLS. Certificate validation
remains enabled. The build workflow, upstream source tag, GPL license, and
checksums are public in this repository. This is an unsigned LimeNow
compatibility build, not an official Modrinth release.

- [Inspect the reproducible build workflow](.github/workflows/build-modrinth-gfn.yml)
- [Inspect the official upstream Modrinth source](https://github.com/modrinth/code/tree/v0.16.1)

## Persistent locations

- Extension setup: `I:\Apps\SalsaNOW\EasySetup`
- Node.js: `I:\Apps\LimeNow\NodeJS`
- npm global packages: `I:\Apps\LimeNow\NpmGlobal`
- Codex launcher and minimal state: `I:\Apps\LimeNow\Codex`
  - authentication: `auth\auth.json`
  - active and archived rollouts: `sessions\active`, `sessions\archived`
  - user configuration: `config\config.toml` and `config\*.config.toml`
- Git for Windows: `I:\Apps\LimeNow\Git`
- GitHub CLI binary, launchers, configuration, and opt-in authentication:
  `I:\Apps\LimeNow\GitHubCLI`
- Visual Studio Code and portable data: `I:\Apps\LimeNow\VSCode`
- Windows Terminal and portable settings: `I:\Apps\LimeNow\WindowsTerminal`
- LimeSSH binary, public enrollment configuration, relay host key, license, and
  provenance: `I:\Apps\LimeNow\LimeSSH`
- Modrinth App: `I:\Apps\ModrinthApp`
- Modrinth data: `I:\Apps\ModrinthData`
- SalsaNOW extension hook: `I:\Apps\SalsaNOW\StartupBatch.bat`
- Repair log: `I:\Apps\SalsaNOW\EasySetup\setup.log`
- Current LimeSSH session state and authorized public keys:
  `%LOCALAPPDATA%\LimeNow\RemoteAccess`

## Relationship to SalsaNOW

LimeNow depends on SalsaNOW and its persistent-storage/startup features. It does
not modify or redistribute SalsaNOW itself. SalsaNOW remains a separate project
maintained by its respective authors.
