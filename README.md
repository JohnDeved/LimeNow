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
- installs, verifies, and keeps the official OpenAI Codex CLI on its latest
  stable release when the registry is reachable;
- installs portable Git for Windows;
- installs the official GitHub CLI (`gh`) as a checksum-verified portable tool;
- installs official Visual Studio Code in portable mode, including the `code` CLI;
- installs the official unpackaged Windows Terminal in portable mode, without
  administrator rights or the Microsoft Store;
- installs stable Chromium from the independent
  [Hibbiki Windows builds](https://github.com/Hibbiki/chromium-win64), with a
  persistent browser profile;
- checks for stable tool updates on every setup run, keeping Node.js on LTS;
- adds `node`, `npm`, `npx`, `codex`, `git`, `gh`, `code`, `wt`, and `chromium`
  to `PATH`;
- configures Node.js to use the trusted Windows certificate store on GeForce NOW;
- creates desktop launchers for Codex, Visual Studio Code, Windows Terminal,
  and Chromium;
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
its LimeSSH manager. Every setup run checks the publishers for stable Codex,
Node.js LTS, Git, GitHub CLI, VS Code, Windows Terminal, and Chromium releases.
New tool versions do not require a source change in LimeNow. npm and npx follow
the version bundled with the selected Node.js LTS release.

If a release check is unavailable, a usable installation stays in place. A new
installation can use the verified bootstrap release in `setup.ps1`. LimeNow
never downgrades a usable newer version and defers an update while a process
from that installation is running; close the app and rerun setup, or wait for
the next session, to apply it. Release checks have bounded timeouts and retry
on the next setup run, without a background updater or scheduled task.

Portable application archives must match their publisher's SHA-256 checksum.
LimeNow extracts and verifies the candidate before replacing application files,
preserves managed settings and profiles, and restores the previous installation
if promotion fails. An unsuccessful rollback retains its recovery files under
the setup directory and reports their location in `setup.log`. Later setup
runs stop if a recovery marker remains, so an unfinished update cannot silently
initialize replacement application data. Codex continues
to install through the official npm package and npm's integrity checks.

If GitHub is unavailable or any downloaded script is invalid,
the session continues with the installed known-good files. The progress window
closes automatically after showing the result. Automatic updates trust code
published to this repository's `main` branch and the tool publishers listed
below over HTTPS.

### Tool update channels

The Windows x64 bootstrap versions below were verified on 2026-10-17. They are
fallbacks for first installation; normal setup follows the update channels.

| Tool | Automatic update source | Bootstrap version |
| ---- | ----------------------- | ----------------- |
| Codex CLI | [`@openai/codex` stable npm release](https://registry.npmjs.org/@openai%2fcodex/latest) | `0.163.0` |
| Node.js, npm, npx | [Latest official Node.js LTS for Windows x64](https://nodejs.org/dist/index.json), with its bundled npm/npx | `24.22.0`, npm `11.19.1` |
| Git for Windows | [Latest official PortableGit release](https://github.com/git-for-windows/git/releases/latest) | `2.56.0.windows.2` |
| GitHub CLI | [Latest official portable release](https://github.com/cli/cli/releases/latest) | `2.102.0` |
| Visual Studio Code | [Official stable archive channel](https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest) | `1.142.0` |
| Windows Terminal | [Latest official unpackaged stable release](https://github.com/microsoft/terminal/releases/latest) | `1.25.2733.0` |
| Chromium | [Latest stable Hibbiki Windows x64 build](https://github.com/Hibbiki/chromium-win64/releases/latest) | `155.0.8059.85` |

LimeSSH remains on the [LimeNow `0.1.0` machine-mode preview](https://github.com/JohnDeved/LimeNow/releases/tag/limessh-v0.1.0)
and Modrinth remains on the [LimeNow `0.16.1` GFN compatibility build](https://github.com/JohnDeved/LimeNow/releases/tag/modrinth-gfn-v0.16.1).
These contain required LimeNow patches. Updating their upstream applications
requires rebuilding and validating those patches before publishing a new
compatible release.

## Persistent Chromium browser

Open the **Chromium** desktop shortcut or run `chromium` from a terminal:

```powershell
chromium
chromium "https://example.com"
chromium --headless --dump-dom "https://example.com"
```

The command forwards browser arguments and selects
`I:\Apps\LimeNow\Chromium\User Data` using Chromium's
[`--user-data-dir` option](https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md).
Application updates replace only the sibling `Application` directory, so
bookmarks, extensions, settings, and profile files remain in persistent storage.
Windows-encrypted cookies and passwords may still require a new sign-in when
GFN replaces the Windows machine; preserving the profile does not make those
credentials portable across machines.

Hibbiki is an independent Chromium builder. LimeNow verifies the selected
release archive against its GitHub SHA-256 digest, uses Windows' bundled
`tar.exe` to extract it, and keeps Chromium's normal sandbox and certificate
validation enabled. It creates its own `chromium` command and does not change
the system default browser.

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
- [Inspect the automatic tool update and rollback tests](tools/Test-ToolUpdates.ps1)
- [Inspect the Windows portable installer smoke tests](tools/Test-PortableToolInstall.ps1)
- [Inspect the Chromium profile, launcher, and browser smoke tests](tools/Test-Chromium.ps1)
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
- Chromium binaries: `I:\Apps\LimeNow\Chromium\Application`
- Chromium profile: `I:\Apps\LimeNow\Chromium\User Data`
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
