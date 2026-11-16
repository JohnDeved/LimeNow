# LIMENOW_KOBOLDCPP_SCRIPT
# Windows PowerShell 5.1 compatible. Dot-source to load functions without side effects.
[CmdletBinding()]
param(
    [ValidateSet('Repair', 'Launch', 'Update', 'Diagnose')]
    [string]$Action = 'Launch',
    [string]$Root = 'I:\Apps\LimeNow\KoboldCpp',
    [string]$DesktopPath = [Environment]::GetFolderPath('Desktop'),
    [switch]$NoShortcut
)

function Get-KoboldCppBootstrapRelease {
    # Official Windows x64 CUDA/Vulkan build, verified against GitHub on 2026-11-16.
    [pscustomobject]@{
        Version = '1.124.2'
        Url = 'https://github.com/LostRuins/koboldcpp/releases/download/v1.124.2/koboldcpp.exe'
        Sha256 = 'e306b58f9770fbca5265c7a0a6cc1c096d1bc3535a6d7e1f8e78c6810564faf7'
    }
}

function ConvertTo-KoboldCppRelease {
    param([Parameter(Mandatory)]$Release)
    if ($Release.draft -or $Release.prerelease -or
        [string]$Release.tag_name -notmatch '^v(\d+\.\d+(?:\.\d+)?)$') {
        throw 'KoboldCpp release is not a recognized stable version.'
    }
    $version = $Matches[1]
    $assets = @($Release.assets | Where-Object { $_.name -ceq 'koboldcpp.exe' })
    if ($assets.Count -ne 1) { throw 'Expected one official Windows x64 KoboldCpp executable.' }
    $asset = $assets[0]
    $expectedUrl = "https://github.com/LostRuins/koboldcpp/releases/download/$($Release.tag_name)/koboldcpp.exe"
    if ([string]$asset.browser_download_url -cne $expectedUrl -or
        [string]$asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw 'KoboldCpp release is missing a trusted URL or SHA-256 digest.'
    }
    [pscustomobject]@{ Version = $version; Url = $expectedUrl; Sha256 = $Matches[1].ToLowerInvariant() }
}

function Get-KoboldCppRelease {
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/LostRuins/koboldcpp/releases/latest' `
            -TimeoutSec 20 -Headers @{ 'User-Agent' = 'LimeNow'; 'Accept' = 'application/vnd.github+json' }
        ConvertTo-KoboldCppRelease -Release $release
    }
    catch {
        Write-Warning "Release check failed; using the verified bootstrap release. $($_.Exception.Message)"
        Get-KoboldCppBootstrapRelease
    }
}

function Read-KoboldCppInstallation {
    param([Parameter(Mandatory)][string]$Root)
    $manifest = Join-Path $Root 'Application\install.json'
    $exe = Join-Path $Root 'Application\koboldcpp.exe'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or
        -not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $null }
    try {
        $info = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ([string]$info.Version -notmatch '^\d+\.\d+(?:\.\d+)?$' -or
            [string]$info.Sha256 -notmatch '^[a-fA-F0-9]{64}$') { return $null }
        if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ine $info.Sha256) { return $null }
        return $info
    }
    catch { return $null }
}

function Test-KoboldCppRunning {
    # Conservatively defer updates even when Windows will not disclose a process path.
    return [bool](Get-Process -Name 'koboldcpp' -ErrorAction SilentlyContinue)
}

function Receive-KoboldCppExecutable {
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$Destination)
    # Windows-native HTTPS uses the session's trusted proxy certificates. Never disable TLS checks.
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec 600
}

function Invoke-KoboldCppProbe {
    param([Parameter(Mandatory)][string]$Executable, [int]$TimeoutSeconds = 60)
    $stdout = Join-Path ([IO.Path]::GetTempPath()) ('LimeNow-Kobold-' + [Guid]::NewGuid().ToString('N') + '.txt')
    $stderr = $stdout + '.err'
    $process = $null
    try {
        $process = Start-Process -FilePath $Executable -ArgumentList '--version' -PassThru `
            -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Hold a process handle so Windows PowerShell can retrieve the exit code after it exits.
        $null = $process.Handle
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            throw 'KoboldCpp did not finish its startup probe. Check temporary disk space and application policy.'
        }
        $process.WaitForExit()
        $text = (Get-Content -LiteralPath $stdout -Raw) + (Get-Content -LiteralPath $stderr -Raw)
        $text = [regex]::Replace([string]$text, '\x1b\[[0-9;]*m', '')
        $version = [regex]::Match($text, '(?im)(?:^\s*v?|\bkoboldcpp[^\r\n]*?)(?<version>\d+\.\d+(?:\.\d+)?)(?:\b|$)')
        if ($process.ExitCode -ne 0 -or -not $version.Success) {
            throw "KoboldCpp version probe failed (exit code $($process.ExitCode)). Output: $($text.Trim()). No driver or security settings were changed."
        }
        return $version.Groups['version'].Value
    }
    finally {
        if ($process) {
            if (-not $process.HasExited) {
                # PyInstaller can spawn a child with the same executable name.
                & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null
            }
            $process.Dispose()
        }
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Install-KoboldCpp {
    param([Parameter(Mandatory)][string]$Root, $Release = (Get-KoboldCppRelease))
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    # An exclusive lock covers download, verification and promotion across simultaneous launchers.
    $lock = $null
    $stage = $null
    $backup = Join-Path $Root 'Application.previous'
    $application = Join-Path $Root 'Application'
    try {
        $lock = [IO.File]::Open((Join-Path $Root 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        if (Test-KoboldCppRunning) { throw 'Close KoboldCpp before installing or updating it.' }
        if (Test-Path -LiteralPath $backup) {
            throw "An unfinished update needs attention. Recovery files are in $backup; no files were replaced."
        }
        $installed = Read-KoboldCppInstallation -Root $Root
        if ($installed -and [version]$installed.Version -ge [version]$Release.Version) { return }
        if ([string]$Release.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            [string]$Release.Url -notmatch '^https://github\.com/LostRuins/koboldcpp/releases/download/v\d+\.\d+(?:\.\d+)?/koboldcpp\.exe$') {
            throw 'Refusing an unverified executable source.'
        }
        $stage = Join-Path $Root ('Application-stage-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage | Out-Null
        $candidate = Join-Path $stage 'koboldcpp.exe'
        Write-Host "Downloading official KoboldCpp $($Release.Version). Models are not included."
        Receive-KoboldCppExecutable -Uri $Release.Url -Destination $candidate
        if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -ine $Release.Sha256) {
            throw 'KoboldCpp SHA-256 verification failed. The installed application was not changed.'
        }
        $actualVersion = Invoke-KoboldCppProbe -Executable $candidate
        if ([version]$actualVersion -ne [version]$Release.Version) {
            throw "KoboldCpp reported version $actualVersion, expected $($Release.Version)."
        }
        $Release | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'install.json') -Encoding UTF8
        # A launcher might have been opened while the download was running.
        if (Test-KoboldCppRunning) { throw 'KoboldCpp was opened during download. Update deferred.' }
        $movedOld = $false
        try {
            if (Test-Path -LiteralPath $application) {
                Move-Item -LiteralPath $application -Destination $backup
                $movedOld = $true
            }
            Move-Item -LiteralPath $stage -Destination $application
            $stage = $null
        }
        catch {
            if ($movedOld -and -not (Test-Path -LiteralPath $application)) {
                Move-Item -LiteralPath $backup -Destination $application
            }
            throw
        }
        if ($movedOld) { Remove-Item -LiteralPath $backup -Recurse -Force }
    }
    finally {
        try {
            if ($stage -and (Test-Path -LiteralPath $stage)) {
                Remove-Item -LiteralPath $stage -Recurse -Force
            }
        }
        finally { if ($lock) { $lock.Dispose() } }
    }
}

function Initialize-KoboldCppStorage {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($directory in @('', 'Models', 'Config', 'Saves')) {
        $path = $Root
        if ($directory) { $path = Join-Path $Root $directory }
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    $configPath = Join-Path $Root 'Config\LimeNow.kcpps'
    if (-not (Test-Path -LiteralPath $configPath)) {
        $json = [ordered]@{
            host = '127.0.0.1'; port = 5001; port_param = 5001
            contextsize = 4096; gpulayers = -1; showgui = $true
            launch = $true; remotetunnel = $false
            downloaddir = (Join-Path $Root 'Models')
            savedatafile = (Join-Path $Root 'Saves\stories.jsondb')
        } | ConvertTo-Json
        # Windows PowerShell's Set-Content -Encoding UTF8 adds a BOM, unlike Python's JSON writer.
        [IO.File]::WriteAllText($configPath, $json, [Text.UTF8Encoding]::new($false))
    }
}

function Ensure-KoboldCppShortcut {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$DesktopPath)
    New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $DesktopPath 'KoboldCpp.lnk'))
    # Reuse SalsaNOW's existing PowerShell host when present, as core LimeNow does.
    $powerShell = 'I:\Apps\SalsaNOW\SilentApps\Powershell\pwsh.exe'
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
        $powerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    }
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Root 'koboldcpp.ps1') + '" -Action Launch -Root "' + $Root + '"'
    $shortcut.WorkingDirectory = $Root
    $shortcut.Description = 'Local AI: choose a GGUF model and GPU backend. Installs KoboldCpp only on request.'
    $shortcut.Save()
}

function Get-KoboldCppArguments {
    param([Parameter(Mandatory)][string]$Root)
    # Full flag names override saved values, except the upstream default-port special case.
    # The native GUI still allows deliberate user changes.
    return @('--config', (Join-Path $Root 'Config\LimeNow.kcpps'), '--showgui',
        '--host', '127.0.0.1', '--port', '5001', '--downloaddir', (Join-Path $Root 'Models'),
        '--savedatafile', (Join-Path $Root 'Saves\stories.jsondb'), '--launch')
}

function Show-KoboldCppDiagnostics {
    param([Parameter(Mandatory)][string]$Root)
    Write-Host 'KoboldCpp session diagnostics (this does not prove GPU compute access):'
    try {
        $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5
        Write-Host ('Available RAM: {0:N1} GiB' -f ($os.FreePhysicalMemory / 1MB))
        Get-CimInstance Win32_VideoController -OperationTimeoutSec 5 | ForEach-Object {
            Write-Host "Display device: $($_.Name); driver $($_.DriverVersion)"
        }
        # Win32_VideoController.AdapterRAM is often truncated above 4 GB. Do not use it to size models.
    }
    catch { Write-Warning "Hardware information is unavailable: $($_.Exception.Message)" }
    Write-Host "Models: $(Join-Path $Root 'Models')"
    Write-Host 'Use the KoboldCpp load log to confirm CUDA/Vulkan and actual offloaded layers.'
    Write-Host 'Start with a small GGUF and 4096 context. A 31B model is not guaranteed to fit a GFN rig.'
}

function Start-LimeNowKoboldCpp {
    param([Parameter(Mandatory)][string]$Root)
    Initialize-KoboldCppStorage -Root $Root
    if (-not (Read-KoboldCppInstallation -Root $Root)) {
        Add-Type -AssemblyName System.Windows.Forms
        $answer = [Windows.Forms.MessageBox]::Show(
            "Download the official portable KoboldCpp app (about 600 MB)?`n`nNo administrator rights, Python or CUDA Toolkit are needed. No model will be downloaded. Models and saved chats use persistent SalsaNOW storage.",
            'LimeNow - Set up local AI', 'YesNo', 'Question')
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) { return }
        Install-KoboldCpp -Root $Root
    }
    if (Test-KoboldCppRunning) { throw 'KoboldCpp is already running. Use its existing launcher or browser window.' }
    Show-KoboldCppDiagnostics -Root $Root
    Write-Host "Save Config to $(Join-Path $Root 'Config\LimeNow.kcpps') to remember model/backend choices."
    Write-Host 'Use Save to Server in KoboldAI Lite or export chats to the Saves folder. Browser autosave alone may be ephemeral.'
    Write-Host 'For proxy certificate errors downloading a model, use Chromium to download the GGUF into Models; do not disable TLS checks.'
    Push-Location $Root
    try {
        $arguments = Get-KoboldCppArguments -Root $Root
        & (Join-Path $Root 'Application\koboldcpp.exe') @arguments
        if ($LASTEXITCODE -ne 0) { throw "KoboldCpp exited with code $LASTEXITCODE. See the console for the backend/model error." }
    }
    finally { Pop-Location }
}

if ($MyInvocation.InvocationName -ne '.') {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess -or
        $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This integration requires Windows x64 and 64-bit PowerShell.'
    }
    try {
        switch ($Action) {
            'Repair' {
                Initialize-KoboldCppStorage -Root $Root
                if (-not $NoShortcut) { Ensure-KoboldCppShortcut -Root $Root -DesktopPath $DesktopPath }
            }
            'Launch' { Start-LimeNowKoboldCpp -Root $Root }
            'Update' { Install-KoboldCpp -Root $Root }
            'Diagnose' { Show-KoboldCppDiagnostics -Root $Root }
        }
    }
    catch {
        if ($Action -eq 'Launch') {
            Write-Warning $_.Exception.Message
            Read-Host 'Press Enter to close' | Out-Null
        }
        else { throw }
    }
}
