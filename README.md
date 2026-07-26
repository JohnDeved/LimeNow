# 🍋‍🟩 LimeNow

**A companion extension for [SalsaNOW](https://github.com/dpadGuy/SalsaNOW).**

LimeNow builds on an existing SalsaNOW installation and automates a few useful
session customizations: persistent Prism Launcher setup, German QWERTZ, and the
Windows timezone fix needed for Microsoft authentication on some GeForce NOW
machines.

> [!IMPORTANT]
> LimeNow is not a SalsaNOW replacement, fork, installer, or unlock method.
> Install and start SalsaNOW first. LimeNow then runs through SalsaNOW's
> supported `StartupBatch.bat` extension point.

## What the extension adds

- fixes SalsaNOW's Windows timezone for Microsoft authentication;
- switches the keyboard to German QWERTZ;
- installs or repairs official portable Prism Launcher under `I:\Apps`;
- verifies Prism downloads against GitHub's published SHA-256 digest;
- restores the persistent Prism desktop shortcut;
- installs a managed block in SalsaNOW's `I:\Apps\SalsaNOW\StartupBatch.bat`;
- preserves unrelated commands already present in `StartupBatch.bat`;
- keeps a fallback setup copy in `Documents`;
- restores the extension from this repository if both persistent copies vanish.

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

No account passwords, Microsoft tokens, API keys, or other credentials are
collected or stored by LimeNow.

## Persistent locations

- Extension setup: `I:\Apps\SalsaNOW\EasySetup`
- Prism Launcher: `I:\Apps\PrismLauncher`
- SalsaNOW extension hook: `I:\Apps\SalsaNOW\StartupBatch.bat`
- Repair log: `I:\Apps\SalsaNOW\EasySetup\setup.log`

## Relationship to SalsaNOW

LimeNow depends on SalsaNOW and its persistent-storage/startup features. It does
not modify or redistribute SalsaNOW itself. SalsaNOW remains a separate project
maintained by its respective authors.
