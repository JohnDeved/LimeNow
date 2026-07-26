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
- switches the keyboard to German QWERTZ;
- installs a managed block in SalsaNOW's `I:\Apps\SalsaNOW\StartupBatch.bat`;
- preserves unrelated commands already present in `StartupBatch.bat`;
- repairs missing or damaged managed files whenever SalsaNOW starts.

### Development tools

- installs a persistent official Node.js LTS build with npm and npx;
- installs the official OpenAI Codex CLI package through npm;
- installs portable Git for Windows and the official GitHub CLI (`gh`);
- installs official Visual Studio Code in portable mode, including the `code` CLI;
- installs the official unpackaged Windows Terminal in portable mode, without
  administrator rights or the Microsoft Store;
- adds `node`, `npm`, `npx`, `codex`, `git`, `gh`, `code`, and `wt` to `PATH`;
- configures Node.js to use the trusted Windows certificate store on GeForce NOW;
- creates desktop launchers for Codex, Visual Studio Code, and Windows Terminal;
- opens Command Prompt inside Windows Terminal from its desktop launcher;
- keeps editor extensions, settings, terminal state, npm packages, and tools in
  SalsaNOW's persistent `I:\Apps` storage.

Codex asks you to sign in when you first run it. LimeNow does not handle or
store Codex credentials. GitHub CLI similarly asks you to authenticate when you
first use an account command; LimeNow does not handle or store that login.

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

## Audit before running

- [Read `install.ps1`](install.ps1)
- [Read the full extension setup](setup.ps1)

LimeNow never asks for, reads, or transmits account passwords or tokens.
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
- npm global packages and Codex: `I:\Apps\LimeNow\NpmGlobal`
- Git for Windows: `I:\Apps\LimeNow\Git`
- GitHub CLI: `I:\Apps\LimeNow\GitHubCLI`
- Visual Studio Code and portable data: `I:\Apps\LimeNow\VSCode`
- Windows Terminal and portable settings: `I:\Apps\LimeNow\WindowsTerminal`
- Modrinth App: `I:\Apps\ModrinthApp`
- Modrinth data: `I:\Apps\ModrinthData`
- SalsaNOW extension hook: `I:\Apps\SalsaNOW\StartupBatch.bat`
- Repair log: `I:\Apps\SalsaNOW\EasySetup\setup.log`

## Relationship to SalsaNOW

LimeNow depends on SalsaNOW and its persistent-storage/startup features. It does
not modify or redistribute SalsaNOW itself. SalsaNOW remains a separate project
maintained by its respective authors.
