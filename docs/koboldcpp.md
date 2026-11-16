# Local AI with KoboldCpp

LimeNow adds a **KoboldCpp** desktop shortcut. It is opt-in: ordinary session
setup repairs the shortcut and small configuration files, but does not download
an executable, a model, or start an inference server.

## Use it

1. Open **KoboldCpp**. On first use, confirm the roughly 600 MB official portable
   application download. LimeNow verifies its SHA-256 and runs a version probe
   before making it available. No administrator prompt, Python installation,
   CUDA Toolkit, Windows service, or firewall change is requested.
2. Download a **GGUF** model with Chromium and save it under
   `I:\Apps\LimeNow\KoboldCpp\Models`. The original Hugging Face safetensors
   repository is not a GGUF file. Choose a quantization that fits the current
   session, not just the advertised GPU tier. For split GGUFs, download all parts
   to the same folder and select the first part.
3. In the native KoboldCpp launcher, select **GGUF Text Model**, select the GPU
   backend, and click **Launch**. Automatic backend selection is left available;
   try CUDA on NVIDIA, or Vulkan if that backend cannot initialize. Verify the
   load log actually reports GPU layers: requesting CUDA is not proof of offload.
   CPU mode is useful for diagnosis, not a promise of usable 31B performance.
4. The bundled chat UI opens in the browser at `http://127.0.0.1:5001`. It also
   exposes an OpenAI-compatible API at `http://127.0.0.1:5001/v1` for local clients.
   This is the browser inside the GFN session, not your personal computer's
   localhost. This integration does not expose a public endpoint.
5. Click **Save Config** and save to
   `I:\Apps\LimeNow\KoboldCpp\Config\LimeNow.kcpps` to remember the selected
   model and backend. The shortcut loads that file and opens the settings GUI
   each time. Initial context is 4,096 tokens; GPU layers use automatic fitting.

**Chat persistence is explicit.** Use KoboldAI Lite's Save to Server option
(`Saves\stories.jsondb`) or export your conversations/character cards to
`Saves`. Browser autosave alone may disappear with the session's default
browser profile. LimeNow's persistent Chromium can also open the same loopback
URL; this integration does not change the system default browser.

Only save your own trusted configurations. KoboldCpp configurations can include
shell commands and plaintext credentials. LimeNow does not create API keys or
save credentials. Models, configurations and conversations are stored on
SalsaNOW's persistent drive: anyone with access to that storage can read them.

## Why KoboldCpp rather than LM Studio or Jan?

KoboldCpp ships an official standalone Windows x64 executable with the model
runtime, graphical launcher and browser chat interface bundled. That is a
smaller integration surface for a replaceable, non-admin Windows session than
managing a desktop application's installer and per-user runtime downloads.
Its launcher already provides the model/backend/quantization-file selection
needed here; LimeNow does not introduce another chat frontend.

## What is and is not compatible with GeForce NOW

| Constraint | Integration / remaining check |
| --- | --- |
| Windows x64, non-admin session | User-mode executable, PowerShell 5.1 launcher and per-user shortcut; no service or driver installer. |
| Replaceable Windows profile | App, selected config, model folder and explicit server saves live on `I:\Apps`. Shortcut is repaired each session. |
| NVIDIA HTTPS proxy | Executable downloads use Windows-native PowerShell HTTPS and keep certificate validation enabled. |
| Model downloads through that proxy | Prefer Chromium downloads. KoboldCpp's embedded Python downloader may trust a different certificate store. Do not use `--nocertify` or disable certificate validation. |
| GPU backend | CUDA and Vulkan are included in the selected build, but access to either must be checked on the assigned GFN machine. A display adapter name does not establish compute access. |
| Model memory | RAM, usable VRAM, context cache and storage must all fit. A 31B model is not guaranteed to fit or perform well on every rig. |
| Executable extraction | The one-file executable extracts bundled libraries to user temporary storage. Leave at least about 1 GB free there, in addition to the application and model files. |
| Host application policy | An unsigned executable can be blocked. LimeNow does not change antivirus, application-control policies, drivers or privileges. |
| Networking | Loopback defaults; no incoming firewall rule or reverse/public tunnel is created. User changes in the native GUI/config remain the user's responsibility. |

The tested bootstrap is **KoboldCpp 1.124.2**. Its upstream release includes
Gemma 4 support/fixes, which makes a compatible Wicked-Tutu-31B-Final GGUF a
reasonable candidate. This is an architecture compatibility assessment, **not
an end-to-end test of that 31B model on a GFN machine**. First validate a small
GGUF with a 4K context, then try the desired larger model. Only add speech
recognition/TTS after text inference works; those also consume memory and GPU
resources. This PR does not automatically configure a voice pipeline.

## Updates and repairs

The manager script follows LimeNow's normal syntax-validated startup refresh.
The application is downloaded on first use, not during session startup. To
explicitly check for and install the latest official stable executable, close
KoboldCpp and run:

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
to size models: that property can misrepresent modern VRAM sizes. Check the
actual backend allocation/load log and, where available, NVIDIA's own tooling.

## Validation

Run deterministic installer, checksum, config/persistence, shortcut and update
checks on Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\tools\Test-KoboldCpp.ps1
```

The live smoke test downloads the official Windows executable, checks its
version/CLI, serves its bundled chat UI with `--nomodel`, and checks that the
listener is bound only to loopback:

```powershell
powershell.exe -NoProfile -File .\tools\Test-KoboldCpp.ps1 -LiveDownload
```

These tests are not a GFN session, GPU benchmark, GUI interaction test, or
31B-model inference test. Actual GFN acceptance still requires opening the
shortcut as the ordinary session user, downloading a small GGUF through the
proxy, verifying CUDA/Vulkan offload and a response, saving the configuration
and a chat, then verifying both after a new SalsaNOW session. Also check disk
space, free RAM/VRAM and behavior when the model is too large.

## Sources

- [Official repository and binary downloads](https://github.com/LostRuins/koboldcpp)
- [Verified bootstrap release](https://github.com/LostRuins/koboldcpp/releases/tag/v1.124.2)
- [Windows packaging and temporary storage](https://koboldcpp.net/docs/install/windows/)
- [CLI flags, GPU selection, loopback and save file](https://koboldcpp.net/docs/reference/flags/)
- [Saving and loading launcher configurations](https://koboldcpp.net/docs/settings/config-files/)
- [LM Studio system requirements](https://lmstudio.ai/docs/app/system-requirements)
