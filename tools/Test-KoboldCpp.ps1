[CmdletBinding()]
param([switch]$LiveDownload)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = Split-Path -Parent $PSScriptRoot
$manager = Join-Path $repo 'koboldcpp.ps1'
foreach ($file in @($manager, (Join-Path $repo 'setup.ps1'), $PSCommandPath)) {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "PowerShell syntax error in ${file}: $($errors -join '; ')" }
}
. $manager
$testRoot = Join-Path $env:TEMP ('LimeNow Kobold Tests ' + [Guid]::NewGuid().ToString('N'))
$script:checks = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
    Write-Host "PASS: $Message"
}
function Assert-Throws {
    param([scriptblock]$Body, [string]$Message)
    $threw = $false
    try { & $Body } catch { $threw = $true }
    Assert-True $threw $Message
}
function Get-TestHash {
    param([string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function New-TestRelease {
    param([string]$Version, [string]$Text)
    [pscustomobject]@{
        Version = $Version
        Url = "https://github.com/LostRuins/koboldcpp/releases/download/v$Version/koboldcpp.exe"
        Sha256 = Get-TestHash $Text
    }
}
$originalDownload = ${function:Receive-KoboldCppExecutable}
$originalProbe = ${function:Invoke-KoboldCppProbe}
$originalRunning = ${function:Test-KoboldCppRunning}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $root = Join-Path $testRoot 'Persistent Data'
    # Repair is the only action executed by session setup: no network, exe or model download.
    & $manager -Action Repair -Root $root -DesktopPath (Join-Path $testRoot 'Desktop')
    Assert-True (-not (Test-Path (Join-Path $root 'Application'))) 'Repair does not install an executable'
    Assert-True (@(Get-ChildItem (Join-Path $root 'Models')).Count -eq 0) 'Repair does not download a model'
    $configPath = Join-Path $root 'Config\LimeNow.kcpps'
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Assert-True ($config.host -eq '127.0.0.1' -and -not $config.remotetunnel) 'Initial config is loopback-only without a tunnel'
    Assert-True ($config.contextsize -eq 4096 -and $config.gpulayers -eq -1) 'Initial config uses modest context and automatic GPU layers'
    $config.contextsize = 6144
    $config | ConvertTo-Json | Set-Content $configPath -Encoding UTF8
    $before = (Get-FileHash $configPath).Hash
    Initialize-KoboldCppStorage -Root $root
    Assert-True ((Get-FileHash $configPath).Hash -eq $before) 'Repair preserves an existing user configuration byte-for-byte'
    Set-Content (Join-Path $root 'Models\user.gguf') 'model sentinel'
    Set-Content (Join-Path $root 'Saves\user.json') 'save sentinel'
    $shell = New-Object -ComObject WScript.Shell
    $shortcutPath = Join-Path $testRoot 'Desktop\KoboldCpp.lnk'
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert-True ($shortcut.Arguments.Contains('-Action Launch') -and $shortcut.Arguments.Contains('"' + $root + '"')) 'Desktop shortcut quotes paths containing spaces'
    Remove-Item $shortcutPath
    Ensure-KoboldCppShortcut -Root $root -DesktopPath (Join-Path $testRoot 'Desktop')
    Assert-True (Test-Path $shortcutPath) 'A missing session desktop shortcut is recreated'
    $launch = @(Get-KoboldCppArguments -Root $root)
    Assert-True ($launch -contains '--showgui' -and $launch -contains '127.0.0.1') 'Launcher opens the GUI with a loopback host'
    Assert-True ($launch -contains (Join-Path $root 'Models') -and $launch -contains (Join-Path $root 'Saves\stories.jsondb')) 'Models and explicit server saves use persistent paths'
    Assert-True ($launch -notcontains '--nocertify' -and $launch -notcontains '--remotetunnel') 'Launcher neither disables TLS checks nor creates a public tunnel'

    $metadata = [pscustomobject]@{
        draft = $false; prerelease = $false; tag_name = 'v1.124.2'
        assets = @([pscustomobject]@{
            name = 'koboldcpp.exe'
            browser_download_url = 'https://github.com/LostRuins/koboldcpp/releases/download/v1.124.2/koboldcpp.exe'
            digest = 'sha256:' + ('a' * 64)
        })
    }
    $selected = ConvertTo-KoboldCppRelease $metadata
    Assert-True ($selected.Version -eq '1.124.2' -and $selected.Sha256 -eq ('a' * 64)) 'Stable release selects the official Windows CUDA/Vulkan executable'
    $metadata.assets[0].digest = $null
    Assert-Throws { ConvertTo-KoboldCppRelease $metadata } 'Missing release checksum is rejected'
    $metadata.assets[0].digest = 'sha256:' + ('a' * 64)
    $metadata.assets[0].browser_download_url = 'https://example.com/koboldcpp.exe'
    Assert-Throws { ConvertTo-KoboldCppRelease $metadata } 'Unexpected binary source is rejected'
    $metadata.prerelease = $true
    Assert-Throws { ConvertTo-KoboldCppRelease $metadata } 'Prerelease is rejected'

    $script:payload = 'verified executable version one'
    $script:probeVersion = '1.0.0'
    $script:busy = $false
    $script:downloadCount = 0
    function Receive-KoboldCppExecutable {
        param([string]$Uri, [string]$Destination)
        $script:downloadCount++
        [IO.File]::WriteAllText($Destination, $script:payload, (New-Object Text.UTF8Encoding($false)))
    }
    function Invoke-KoboldCppProbe { param([string]$Executable) return $script:probeVersion }
    function Test-KoboldCppRunning { return $script:busy }
    $v1 = New-TestRelease '1.0.0' $script:payload
    Install-KoboldCpp -Root $root -Release $v1
    Assert-True ((Read-KoboldCppInstallation $root).Version -eq '1.0.0') 'Verified executable and manifest are promoted together'
    $script:payload = 'tampered download'
    $v2 = New-TestRelease '2.0.0' 'expected second executable'
    Assert-Throws { Install-KoboldCpp -Root $root -Release $v2 } 'Bad download checksum aborts the update'
    Assert-True ((Read-KoboldCppInstallation $root).Version -eq '1.0.0') 'Failed download preserves the known-good installation'
    $script:payload = 'expected second executable'
    $script:probeVersion = '9.9.9'
    Assert-Throws { Install-KoboldCpp -Root $root -Release $v2 } 'Incorrect executable version aborts promotion'
    $script:probeVersion = '2.0.0'
    $script:busy = $true
    Assert-Throws { Install-KoboldCpp -Root $root -Release $v2 } 'Running application defers installation'
    $script:busy = $false
    $held = [IO.File]::Open((Join-Path $root 'install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try { Assert-Throws { Install-KoboldCpp -Root $root -Release $v2 } 'Concurrent installer is excluded by the lock' }
    finally { $held.Dispose() }
    Install-KoboldCpp -Root $root -Release $v2
    Assert-True ((Read-KoboldCppInstallation $root).Version -eq '2.0.0') 'A valid update succeeds'
    $downloads = $script:downloadCount
    Install-KoboldCpp -Root $root -Release $v1
    Assert-True ($script:downloadCount -eq $downloads) 'A newer installed version is not downgraded'
    Assert-True ((Get-FileHash $configPath).Hash -eq $before) 'Updates do not replace user configuration'
    Assert-True ((Get-Content (Join-Path $root 'Models\user.gguf')) -eq 'model sentinel') 'Updates preserve model files'
    Assert-True ((Get-Content (Join-Path $root 'Saves\user.json')) -eq 'save sentinel') 'Updates preserve saved chats'
    New-Item -ItemType Directory -Path (Join-Path $root 'Application.previous') | Out-Null
    Assert-Throws { Install-KoboldCpp -Root $root -Release $v2 } 'Unfinished recovery blocks another update'
    Remove-Item (Join-Path $root 'Application.previous')
    Set-Content (Join-Path $root 'Application\koboldcpp.exe') 'damaged local exe'
    Assert-True ($null -eq (Read-KoboldCppInstallation $root)) 'Damaged installed executable fails validation'
    Assert-True (@(Get-ChildItem $root -Filter 'Application-stage-*').Count -eq 0) 'Failed and successful installs clean staging folders'

    Set-Item function:Receive-KoboldCppExecutable $originalDownload
    Set-Item function:Invoke-KoboldCppProbe $originalProbe
    Set-Item function:Test-KoboldCppRunning $originalRunning
    if ($LiveDownload) {
        $liveRoot = Join-Path $testRoot 'Live App'
        Initialize-KoboldCppStorage $liveRoot
        $release = Get-KoboldCppBootstrapRelease
        Install-KoboldCpp -Root $liveRoot -Release $release
        Assert-True ((Read-KoboldCppInstallation $liveRoot).Version -eq $release.Version) 'Official Windows executable downloads, verifies and runs its version probe'
        $exe = Join-Path $liveRoot 'Application\koboldcpp.exe'
        $help = & $exe --help | Out-String
        Assert-True ($LASTEXITCODE -eq 0) 'Official Windows executable runs --help'
        foreach ($flag in @('--showgui', '--host', '--port', '--downloaddir', '--savedatafile', '--config', '--nomodel', '--skiplauncher')) {
            Assert-True ($help.Contains($flag)) "Official executable supports $flag"
        }
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $listener.Stop()
        $process = $null
        try {
            $process = Start-Process -FilePath $exe -ArgumentList @('--nomodel', '--skiplauncher', '--host', '127.0.0.1', '--port', "$port") `
                -WorkingDirectory $liveRoot -PassThru -RedirectStandardOutput (Join-Path $testRoot 'live.stdout.txt') `
                -RedirectStandardError (Join-Path $testRoot 'live.stderr.txt')
            $deadline = [DateTime]::UtcNow.AddSeconds(90)
            $response = $null
            while ([DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
                try {
                    $response = Invoke-WebRequest "http://127.0.0.1:$port/" -UseBasicParsing -TimeoutSec 2
                    if ($response.StatusCode -eq 200) { break }
                }
                catch { Start-Sleep -Milliseconds 500 }
            }
            Assert-True ($null -ne $response -and $response.StatusCode -eq 200 -and $response.Content.Length -gt 1000) 'Bundled chat UI is served by the official Windows binary'
            $addresses = @(Get-NetTCPConnection -State Listen -LocalPort $port | Select-Object -ExpandProperty LocalAddress)
            Assert-True ($addresses.Count -gt 0 -and @($addresses | Where-Object { $_ -ne '127.0.0.1' }).Count -eq 0) 'Live server listens only on loopback'
        }
        finally {
            if ($process) {
                if (-not $process.HasExited) { & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F 2>$null | Out-Null }
                $process.Dispose()
            }
        }
        Write-Host 'Live test validates the executable and web server only: no GFN GPU or 31B inference claim.'
    }
    Write-Host "Passed $script:checks KoboldCpp checks."
}
finally {
    Set-Item function:Receive-KoboldCppExecutable $originalDownload
    Set-Item function:Invoke-KoboldCppProbe $originalProbe
    Set-Item function:Test-KoboldCppRunning $originalRunning
    if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
}
