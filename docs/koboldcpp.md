# Local AI with KoboldCpp

LimeNow's installer adds a **KoboldCpp** desktop shortcut. It is opt-in: the
session startup hook repairs the shortcut and default configuration only. It
does not download an executable, download a model, or start an inference server.

**The normal LimeNow startup updater installs/repairs the KoboldCpp manager
and shortcut automatically**, even for existing installations. No separate
LimeNow GitHub release or installer rerun is necessary. The executable and
models remain opt-in downloads.

## Use it

1. Run the normal LimeNow installer after SalsaNOW has started, then open the
   **KoboldCpp** desktop shortcut. On first use, confirm the roughly 600 MB
   official portable application download. LimeNow verifies its SHA-256 and
   runs a version probe before making it available. No administrator prompt,
   Python installation, CUDA Toolkit, Windows service, or firewall change is
   requested.
2. Download a **GGUF** model with Chromium and save it under
   `I:\Apps\LimeNow\KoboldCpp\Models`. The original Hugging Face safetensors
   repository is not a GGUF file. Choose a quantization that fits the current
   session, not just the advertised GPU tier. For split GGUFs, download all parts
   to the same folder and select the first part.
3. In the native KoboldCpp launcher, select **GGUF Text Model**, select the GPU
   backend, and click **Launch**. Try CUDA on NVIDIA, or Vulkan if CUDA cannot
   initialize. Verify the load log actually reports GPU layers: requesting CUDA
   is not proof of offload. CPU mode is useful for diagnosis, not a promise of
   usable 31B performance.
4. The bundled chat UI opens in the browser, initially at
   `http://127.0.0.1:5001`. Its OpenAI-compatible API is at
   `http://127.0.0.1:5001/v1`. These addresses refer to the GFN session, not your
   personal computer. A deliberately changed port in a saved configuration
   takes precedence over the default; use the address printed by KoboldCpp.
5. Click **Save Config** and save to
   `I:\Apps\LimeNow\KoboldCpp\Config\LimeNow.kcpps` to remember the selected
   model and backend. The shortcut loads that file and opens the settings GUI
   each time. Initial context is 4,096 tokens; GPU layers use automatic fitting.

**Chat persistence is explicit.** Use KoboldAI Lite's Save to Server option
(`Saves\stories.jsondb`) or export conversations/character cards to `Saves`.
Browser autosave alone may disappear with the session's default browser profile.
LimeNow's persistent Chromium can also open the same loopback URL; this
integration does not change the system default browser.

Only load trusted configurations. KoboldCpp configurations can contain shell
commands and plaintext credentials. This integration does not create API keys
or save credentials. Models, configurations and conversations use SalsaNOW's
persistent drive: anyone with access to that storage can read them.

## Why KoboldCpp?

KoboldCpp ships an official standalone Windows x64 executable with the model
runtime, graphical launcher and browser chat interface bundled. That is a
smaller integration surface for a replaceable, non-admin Windows session than
managing another desktop application's installer and per-user runtime downloads.
Its launcher already supplies the model/backend selection; LimeNow does not
introduce another chat frontend or install LM Studio/Jan alongside it.

## Compatibility with GeForce NOW

| Constraint | Integration / remaining check |
| --- | --- |
| Windows x64, non-admin session | User-mode executable and per-user shortcut; no service or driver installer. Scripts support PowerShell 5.1; the desktop launcher prefers SalsaNOW's existing portable PowerShell host when present. |
| Replaceable Windows profile | App, selected configuration, models and explicit server saves live on `I:\Apps`. The added startup hook repairs the shortcut each session. |
| NVIDIA HTTPS proxy | Executable downloads use PowerShell HTTPS with certificate validation enabled and the Windows trust configuration. |
| Model downloads through that proxy | Prefer Chromium downloads. KoboldCpp's embedded Python downloader may trust a different certificate store. Do not use `--nocertify` or disable certificate validation. |
| GPU backend | CUDA and Vulkan are included in the selected build, but access must be tested on the assigned GFN machine. A display adapter name does not establish compute access. |
| Model memory | RAM, usable VRAM, context cache and storage must all fit. A 31B model is not guaranteed to fit or perform well on every rig. |
| Executable extraction | The single-file application extracts libraries to user temporary storage. Leave about 1 GB free there, in addition to the application and model files. |
| Host application policy | An unsigned executable can be blocked. LimeNow does not change antivirus, application-control policies, drivers or privileges. |
| Networking | Loopback defaults; no incoming firewall rule or public tunnel is created. Deliberate changes in the native GUI/config remain the user's responsibility. |

The pinned bootstrap is **KoboldCpp 1.124.2**. Its upstream release includes
Gemma 4 support/fixes, making a compatible Wicked-Tutu-31B-Final GGUF a candidate.
This is an architecture compatibility assessment, **not an end-to-end test of
that 31B model on a GFN machine**. First validate a small GGUF with a 4K context,
then try the desired larger model. Add speech recognition/TTS only after text
inference works; those also consume memory and GPU resources. This integration
does not automatically configure a voice pipeline.

## Updates and repairs

Normal LimeNow session startup retrieves or refreshes the small manager
script from `main`, checks PowerShell syntax, the script marker and parameters,
and retains the prior copy on invalid or unavailable updates. It then repairs
the shortcut and local configuration. Existing installations that used the
older separate KoboldCpp startup hook can also continue to work.

**Session startup never downloads the KoboldCpp executable or a model.**

The application is downloaded on first deliberate use. To explicitly check for
and install the latest official stable executable, close KoboldCpp and run:

```powershell
& 'I:\Apps\LimeNow\KoboldCpp\koboldcpp.ps1' -Action Update
```

Release metadata must identify the exact official `koboldcpp.exe` asset and
include a SHA-256 digest. If metadata is unavailable, the pinned, verified
1.124.2 bootstrap is available; a verified newer installation is not downgraded.
Candidates are staged, checksum-verified and version-probed before promotion.
A running application or concurrent installer blocks replacement. Only
`Application` is replaced, never `Models`, `Config` or `Saves`. A failed
promotion restores the previous directory when possible; an unresolved
`Application.previous` stops subsequent updates and retains recovery data.
Do not delete that directory until its contents have been checked/recovered.

For basic session diagnostics:

```powershell
& 'I:\Apps\LimeNow\KoboldCpp\koboldcpp.ps1' -Action Diagnose
```

The diagnostic intentionally does not use `Win32_VideoController.AdapterRAM`
to size models because it can misrepresent modern VRAM sizes. Check the actual
backend allocation/load log and, where available, NVIDIA's own tooling.

## Validation

Run the installer, checksum, configuration/persistence, shortcut, update and
startup-hook checks on Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\tools\Test-KoboldCpp.ps1
powershell.exe -NoProfile -File .\tools\Test-KoboldCppIntegration.ps1
```

The live smoke test downloads the official Windows executable, checks its
version/CLI, serves the bundled chat UI with `--nomodel`, and checks that the
listener is bound only to loopback:

```powershell
powershell.exe -NoProfile -File .\tools\Test-KoboldCpp.ps1 -LiveDownload
```

The read-only `Test KoboldCpp` CI workflow runs these checks and the existing
startup/tool-update regression suites. It does not publish binaries or modify
repository contents.

These tests are not a GFN session, GPU benchmark, GUI interaction test, or
31B inference test. Actual GFN acceptance requires opening the shortcut as the
ordinary session user, downloading a small GGUF through the proxy, verifying
CUDA/Vulkan offload and a response, saving configuration and a chat, and checking
both after a new SalsaNOW session. Also check free disk/RAM/VRAM and behavior
when a model is too large.

## Sources

- [Official repository and binary downloads](https://github.com/LostRuins/koboldcpp)
- [Pinned bootstrap release](https://github.com/LostRuins/koboldcpp/releases/tag/v1.124.2)
- [Windows packaging and temporary storage](https://koboldcpp.net/docs/install/windows/)
- [CLI flags, GPU selection, loopback and saves](https://koboldcpp.net/docs/reference/flags/)
- [Launcher configurations](https://koboldcpp.net/docs/settings/config-files/)
