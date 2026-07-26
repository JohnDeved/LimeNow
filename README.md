# 🍋‍🟩 LimeNow

One-command, self-repairing setup for persistent SalsaNOW / GeForce NOW
sessions.

LimeNow:

- fixes SalsaNOW's Windows timezone for Microsoft authentication;
- switches the keyboard to German QWERTZ;
- installs or repairs official portable Prism Launcher under `I:\Apps`;
- verifies Prism downloads against GitHub's published SHA-256 digest;
- restores the persistent Prism desktop shortcut;
- installs a managed `I:\Apps\SalsaNOW\StartupBatch.bat` block;
- preserves unrelated commands already present in `StartupBatch.bat`;
- keeps a fallback setup copy in `Documents`;
- restores the setup from this repository if both persistent copies vanish.

## Run on a new SalsaNOW instance

Open PowerShell and paste:

```powershell
Set-TimeZone -Id 'W. Europe Standard Time'; irm 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/install.ps1' | iex
```

The timezone command must run first because some SalsaNOW sessions expose a
Central European clock while Windows incorrectly labels it as UTC. That can
make NVIDIA's short-lived HTTPS proxy certificates appear expired.

## Audit before running

- [Read `install.ps1`](install.ps1)
- [Read the full setup](setup.ps1)

No account passwords, Microsoft tokens, API keys, or other credentials are
collected or stored by LimeNow.

## Persistent locations

- Setup: `I:\Apps\SalsaNOW\EasySetup`
- Prism Launcher: `I:\Apps\PrismLauncher`
- Startup hook: `I:\Apps\SalsaNOW\StartupBatch.bat`
- Repair log: `I:\Apps\SalsaNOW\EasySetup\setup.log`
