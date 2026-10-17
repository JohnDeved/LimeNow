[CmdletBinding()]
param(
    [string]$TestParent = [IO.Path]::GetTempPath(),
    [string]$SetupPath = (Join-Path $PSScriptRoot '..\setup.ps1'),
    [switch]$LiveDownload
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$tokens = $null
$parseErrors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile(
    $SetupPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "setup.ps1 failed syntax validation: $($parseErrors -join '; ')"
}

foreach ($functionName in @(
    'ConvertTo-LimeNowVersion',
    'Get-LimeNowGitHubAsset',
    'Get-LatestChromiumRelease',
    'Repair-Chromium',
    'Ensure-ChromiumLauncher',
    'Ensure-DeveloperCommandShims'
)) {
    $definition = $setupAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if (-not $definition) {
        throw "setup.ps1 is missing function $functionName."
    }
    Invoke-Expression $definition.Extent.Text
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) {
        throw "$Message Expected '$Expected' but received '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try {
        & $Action | Out-Null
    }
    catch {
        return
    }
    throw $Message
}

function Write-SetupLog {
    param([string]$Message)
    $script:messages += $Message
}

function New-ChromiumReleaseFixture {
    $tag = 'v155.0.8059.85-r1697595'
    return [pscustomobject]@{
        draft = $false
        prerelease = $false
        tag_name = $tag
        assets = @([pscustomobject]@{
            name = 'chrome.7z'
            state = 'uploaded'
            digest = 'sha256:' + ('a' * 64)
            browser_download_url = "https://github.com/Hibbiki/chromium-win64/releases/download/$tag/chrome.7z"
        })
    }
}

function Get-LimeNowGitHubRelease {
    param([string]$Repository)
    $script:releaseRepository = $Repository
    return $script:releaseFixture
}

function Get-LimeNowInstalledVersion {
    param([string]$Tool, [string]$Root)
    Assert-Equal $Tool 'Chromium' 'The update queried a different tool.'
    Assert-Equal $Root $chromiumAppRoot 'Version detection targeted the persistent profile tree.'
    return '155.0.8059.40'
}

function Install-LimeNowPortableTool {
    param([string]$Tool, [string]$Root, $Release)
    Assert-Equal $Tool 'Chromium' 'The updater invoked a different installer.'
    Assert-Equal $Root $chromiumAppRoot 'The update would replace the persistent profile tree.'
    # Simulate replacing every installed application file. Profile data must survive.
    Remove-Item -LiteralPath $Root -Recurse -Force
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'chrome.exe') -Value 'new application fixture'
    $script:installedRelease = $Release
}

function Invoke-LimeNowToolUpdate {
    param(
        [string]$Name,
        [string]$Root,
        $FallbackRelease,
        [scriptblock]$GetInstalledVersion,
        [scriptblock]$GetLatestRelease,
        [scriptblock]$InstallRelease,
        [string[]]$ProcessNames
    )
    Assert-Equal $Name 'Chromium' 'The update did not identify Chromium.'
    Assert-Equal $Root $chromiumAppRoot 'The updater owns more than the application directory.'
    Assert-Equal ($ProcessNames -join ',') 'chrome' 'The updater did not identify Chromium processes.'
    Assert-Equal $FallbackRelease.Version $chromiumVersion 'The verified fallback version changed.'
    Assert-Equal $FallbackRelease.Uri $chromiumArchiveUrl 'The verified fallback URL changed.'
    Assert-Equal $FallbackRelease.Hash $chromiumArchiveHash 'The verified fallback checksum changed.'
    $null = & $GetInstalledVersion $Root
    $latest = & $GetLatestRelease
    & $InstallRelease $latest
}

# Capture the shortcut without writing to the desktop or requiring COM on Linux.
function New-Object {
    param([string]$ComObject)
    Assert-Equal $ComObject 'WScript.Shell' 'The launcher requested an unexpected COM object.'
    $shell = [pscustomobject]@{}
    Add-Member -InputObject $shell -MemberType ScriptMethod -Name CreateShortcut -Value {
        param([string]$Path)
        $script:shortcut = [pscustomobject]@{
            Path = $Path
            TargetPath = ''
            Arguments = ''
            WorkingDirectory = ''
            Description = ''
            IconLocation = ''
            Saved = $false
        }
        Add-Member -InputObject $script:shortcut -MemberType ScriptMethod -Name Save -Value {
            $this.Saved = $true
        }
        return $script:shortcut
    }
    return $shell
}

$testRoot = Join-Path $TestParent ('LimeNow Chromium test ' + [Guid]::NewGuid().ToString('N'))
$originalArgumentLog = $env:LIMENOW_CHROMIUM_TEST_ARGUMENT_LOG
$originalLocalAppData = $env:LOCALAPPDATA
$script:messages = @()
$onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

try {
    $script:releaseFixture = New-ChromiumReleaseFixture
    $release = Get-LatestChromiumRelease
    Assert-Equal $script:releaseRepository 'Hibbiki/chromium-win64' 'Chromium used an unexpected publisher.'
    Assert-Equal $release.Version '155.0.8059.85' 'The revision suffix was not removed from the browser version.'
    Assert-Equal $release.Uri $script:releaseFixture.assets[0].browser_download_url 'The wrong Chromium asset was selected.'
    Assert-Equal $release.Hash ('a' * 64) 'Chromium did not use the asset SHA-256.'

    foreach ($invalidTag in @('v155.0.8059.85', 'v155.0.8059.85-r1697595-beta', 'latest', 'v155.0.8059-r1697595')) {
        $script:releaseFixture = New-ChromiumReleaseFixture
        $script:releaseFixture.tag_name = $invalidTag
        Assert-Throws { Get-LatestChromiumRelease } "Chromium accepted unsupported release tag $invalidTag."
    }
    foreach ($releaseFlag in @('draft', 'prerelease')) {
        $script:releaseFixture = New-ChromiumReleaseFixture
        $script:releaseFixture.$releaseFlag = $true
        Assert-Throws { Get-LatestChromiumRelease } "Chromium accepted a $releaseFlag release."
    }
    foreach ($assetMutation in @(
        { $script:releaseFixture.assets = @() },
        { $script:releaseFixture.assets += $script:releaseFixture.assets[0] },
        { $script:releaseFixture.assets[0].name = 'mini_installer.exe' },
        { $script:releaseFixture.assets[0].digest = $null },
        { $script:releaseFixture.assets[0].digest = 'sha1:' + ('b' * 40) },
        { $script:releaseFixture.assets[0].browser_download_url = 'https://example.invalid/chrome.7z' }
    )) {
        $script:releaseFixture = New-ChromiumReleaseFixture
        & $assetMutation
        Assert-Throws { Get-LatestChromiumRelease } 'Chromium accepted an absent, ambiguous, or unverified portable asset.'
    }

    $chromiumRoot = Join-Path $testRoot 'Persistent Apps\Chromium'
    $chromiumAppRoot = Join-Path $chromiumRoot 'Application'
    $chromiumProfileRoot = Join-Path $chromiumRoot 'User Data'
    $chromiumWrapper = Join-Path $chromiumRoot 'chromium.cmd'
    $chromiumVersion = '155.0.8059.85'
    $chromiumArchiveUrl = 'https://github.com/Hibbiki/chromium-win64/releases/download/v155.0.8059.85-r1697595/chrome.7z'
    $chromiumArchiveHash = '80710739b1f92f87ca50b798826c2d9b9e21e06139f96f05b8a9a1b9d0d49cb3'
    $documentsRoot = Join-Path $testRoot 'Documents With Spaces'
    $desktop = Join-Path $testRoot 'Desktop With Spaces'
    New-Item -ItemType Directory -Path $chromiumAppRoot, (Join-Path $chromiumProfileRoot 'Default'), $documentsRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $chromiumAppRoot 'chrome.exe') -Value 'old application fixture'
    $bookmarks = Join-Path $chromiumProfileRoot 'Default\Bookmarks'
    Set-Content -LiteralPath $bookmarks -Value '{"bookmark":"preserve across browser updates"}' -Encoding UTF8
    $profileHash = (Get-FileHash -LiteralPath $bookmarks -Algorithm SHA256).Hash

    $script:releaseFixture = New-ChromiumReleaseFixture
    Repair-Chromium
    Assert-Equal $script:installedRelease.Version '155.0.8059.85' 'The update did not install the resolved stable release.'
    Assert-Equal (Get-FileHash -LiteralPath $bookmarks -Algorithm SHA256).Hash $profileHash 'The application update changed the persistent profile.'

    Ensure-ChromiumLauncher -DesktopPath $desktop
    Ensure-ChromiumLauncher -DesktopPath $desktop
    Assert-Equal (Get-FileHash -LiteralPath $bookmarks -Algorithm SHA256).Hash $profileHash 'Refreshing launchers changed the profile.'
    Assert-Equal $script:shortcut.Path (Join-Path $desktop 'Chromium.lnk') 'The launcher did not create the Chromium shortcut.'
    Assert-Equal $script:shortcut.TargetPath (Join-Path $chromiumAppRoot 'chrome.exe') 'The desktop shortcut would open a command window.'
    Assert-Equal $script:shortcut.Arguments ('--user-data-dir="' + $chromiumProfileRoot + '"') 'The desktop shortcut lost the persistent profile argument.'
    Assert-Equal $script:shortcut.WorkingDirectory $documentsRoot 'The shortcut changed the working directory.'
    Assert-Equal $script:shortcut.Saved $true 'The Chromium shortcut was not saved.'

    $wrapper = Get-Content -LiteralPath $chromiumWrapper -Raw
    foreach ($requiredText in @(
        'setlocal DisableDelayedExpansion',
        '"%~dp0Application\chrome.exe" --user-data-dir="%~dp0User Data" %*',
        'exit /b %ERRORLEVEL%'
    )) {
        if (-not $wrapper.Contains($requiredText)) {
            throw "The Chromium command wrapper is missing: $requiredText"
        }
    }
    if ($wrapper.Contains($chromiumRoot)) {
        throw 'The command wrapper embeds a path that would break after relocating the persistent tree.'
    }
    if ($wrapper -match '(?i)--(?:no-sandbox|disable-web-security|ignore-certificate-errors|allow-running-insecure-content|disable-features)\b') {
        throw 'The Chromium launcher weakens browser security.'
    }
    if (Test-Path -LiteralPath (Join-Path $chromiumRoot 'chrome.cmd')) {
        throw 'The managed Chromium launcher shadows a separate Chrome installation.'
    }

    if ($onWindows) {
        $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
            throw 'The Windows argument-forwarding fixture requires the .NET Framework C# compiler.'
        }
        $fixtureSource = Join-Path $testRoot 'argument-fixture.cs'
        @'
using System;
using System.IO;
using System.Text;
internal static class ChromiumArgumentFixture {
    private static int Main(string[] args) {
        var encoded = Array.ConvertAll(args, arg => Convert.ToBase64String(Encoding.UTF8.GetBytes(arg)));
        File.WriteAllLines(Environment.GetEnvironmentVariable("LIMENOW_CHROMIUM_TEST_ARGUMENT_LOG"), encoded, new UTF8Encoding(false));
        return 37;
    }
}
'@ | Set-Content -LiteralPath $fixtureSource -Encoding ASCII
        & $compiler /nologo /target:exe ("/out:" + (Join-Path $chromiumAppRoot 'chrome.exe')) $fixtureSource
        if ($LASTEXITCODE -ne 0) {
            throw 'Compiling the native Windows argument fixture failed.'
        }
        $env:LIMENOW_CHROMIUM_TEST_ARGUMENT_LOG = Join-Path $testRoot 'arguments.log'
        $env:LOCALAPPDATA = Join-Path $testRoot 'Local AppData'
        $missingToolRoot = Join-Path $testRoot 'Uninstalled tools'
        $nodeRoot = $missingToolRoot
        $gitRoot = $missingToolRoot
        $vscodeRoot = $missingToolRoot
        $terminalRoot = $missingToolRoot
        $codexWrapper = Join-Path $missingToolRoot 'codex.cmd'
        $githubCliWrapper = Join-Path $missingToolRoot 'gh.cmd'
        $chromiumShim = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\chromium.cmd'
        $fixtureUrl = 'https://example.invalid/a%20b?one=1&two=2'
        foreach ($relocate in @($false, $true)) {
            if ($relocate) {
                $relocatedParent = Join-Path $testRoot 'Relocated Apps With Spaces'
                New-Item -ItemType Directory -Path $relocatedParent -Force | Out-Null
                Move-Item -LiteralPath $chromiumRoot -Destination $relocatedParent
                $chromiumRoot = Join-Path $relocatedParent 'Chromium'
                $chromiumAppRoot = Join-Path $chromiumRoot 'Application'
                $chromiumWrapper = Join-Path $chromiumRoot 'chromium.cmd'
                $chromiumProfileRoot = Join-Path $chromiumRoot 'User Data'
            }
            Ensure-DeveloperCommandShims
            if (-not (Test-Path -LiteralPath $chromiumShim -PathType Leaf)) {
                throw 'The developer command shims did not include Chromium.'
            }
            foreach ($entryPoint in @($chromiumWrapper, $chromiumShim)) {
                $command = '"' + $entryPoint + '" "relative folder\preview.html" "' + $fixtureUrl + '" "argument with spaces"'
                $startInfo = [Diagnostics.ProcessStartInfo]::new()
                $startInfo.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
                $startInfo.Arguments = '/d /s /c "' + $command + '"'
                $startInfo.WorkingDirectory = $documentsRoot
                $startInfo.UseShellExecute = $false
                $startInfo.CreateNoWindow = $true
                $process = [Diagnostics.Process]::Start($startInfo)
                try {
                    if (-not $process.WaitForExit(15000)) {
                        $process.Kill()
                        throw "The Chromium argument fixture did not exit through $entryPoint."
                    }
                    Assert-Equal $process.ExitCode 37 "The Chromium entry point lost the browser exit code: $entryPoint."
                }
                finally {
                    $process.Dispose()
                }
                $arguments = @(Get-Content -LiteralPath $env:LIMENOW_CHROMIUM_TEST_ARGUMENT_LOG | ForEach-Object {
                    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))
                })
                Assert-Equal $arguments.Count 4 'The command wrapper or shim split or dropped quoted arguments.'
                Assert-Equal $arguments[0] ('--user-data-dir=' + $chromiumProfileRoot) 'The portable wrapper selected the wrong profile.'
                Assert-Equal $arguments[1] 'relative folder\preview.html' 'The wrapper or shim changed a relative path with spaces.'
                Assert-Equal $arguments[2] $fixtureUrl 'The wrapper or shim reparsed a quoted URL containing percent encoding and an ampersand.'
                Assert-Equal $arguments[3] 'argument with spaces' 'The wrapper or shim split a quoted argument.'
            }
        }
    }
    else {
        Write-Host 'Windows command argument and exit-code execution checks skipped on this platform.'
    }

    if ($LiveDownload) {
        if (-not $onWindows) {
            throw '-LiveDownload requires Windows to test bundled tar.exe and the Chromium executable.'
        }
        # Replace the unit-test doubles with the production installation pipeline.
        Remove-Item -Path Function:\New-Object
        foreach ($functionName in @(
            'Write-SetupLog',
            'Get-LimeNowJson',
            'Get-LimeNowGitHubRelease',
            'Get-VerifiedDownload',
            'Remove-SetupRepairDirectory',
            'Get-LimeNowInstalledVersion',
            'Test-LimeNowToolRunning',
            'Get-LimeNowUpdateMutexName',
            'Assert-LimeNowNoPendingToolRecovery',
            'Move-LimeNowPath',
            'Install-LimeNowStagedDirectory',
            'Install-LimeNowPortableTool'
        )) {
            $definition = $setupAst.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -eq $functionName
            }, $true)
            if (-not $definition) {
                throw "The live Chromium test is missing setup helper $functionName."
            }
            Invoke-Expression $definition.Extent.Text
        }

        $liveRoot = Join-Path $testRoot 'Live Chromium'
        $setupRoot = Join-Path $liveRoot 'Setup'
        $logPath = Join-Path $setupRoot 'setup.log'
        $liveApplicationRoot = Join-Path $liveRoot 'Chromium\Application'
        $liveProfileRoot = Join-Path $liveRoot 'Chromium\User Data'
        New-Item -ItemType Directory -Path $setupRoot, $liveProfileRoot -Force | Out-Null
        $profileFixture = Join-Path $liveProfileRoot 'LimeNow-profile-fixture.txt'
        Set-Content -LiteralPath $profileFixture -Value 'Retain the existing profile when installing Chromium.' -Encoding UTF8
        $profileFixtureHash = (Get-FileHash -LiteralPath $profileFixture -Algorithm SHA256).Hash

        $liveRelease = Get-LatestChromiumRelease
        Install-LimeNowPortableTool -Tool Chromium -Root $liveApplicationRoot -Release $liveRelease
        $installedVersion = Get-LimeNowInstalledVersion -Tool Chromium -Root $liveApplicationRoot
        Assert-Equal $installedVersion $liveRelease.Version 'The production installer did not install the resolved Chromium release.'
        Assert-Equal (Get-FileHash -LiteralPath $profileFixture -Algorithm SHA256).Hash $profileFixtureHash 'The production installer changed sibling Chromium profile data.'
        $executable = Join-Path $liveApplicationRoot 'chrome.exe'
        $smokePage = Join-Path $liveRoot 'inert-page.html'
        Set-Content -LiteralPath $smokePage -Value '<!doctype html><html><body>LimeNow Chromium smoke check</body></html>' -Encoding UTF8
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $executable
        $startInfo.Arguments = '--headless --no-first-run --no-default-browser-check --user-data-dir="' + $liveProfileRoot + '" --dump-dom "' + ([Uri]$smokePage).AbsoluteUri + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [Diagnostics.Process]::Start($startInfo)
        try {
            $outputTask = $process.StandardOutput.ReadToEndAsync()
            $errorTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(45000)) {
                & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $process.Id /T /F | Out-Null
                throw 'Chromium did not finish the headless smoke check within 45 seconds.'
            }
            $output = $outputTask.GetAwaiter().GetResult()
            $errorOutput = $errorTask.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0 -or -not $output.Contains('LimeNow Chromium smoke check')) {
                throw "Chromium failed the default-sandbox headless smoke check. Exit: $($process.ExitCode). Error: $errorOutput"
            }
        }
        finally {
            $process.Dispose()
        }
        Assert-Equal (Get-FileHash -LiteralPath $profileFixture -Algorithm SHA256).Hash $profileFixtureHash 'Chromium startup changed the retained profile fixture.'
        Write-Host "Verified Chromium $($liveRelease.Version): production download verification, staged Windows tar installation, retained profile, PE version, and headless launch with default sandbox settings."
    }

    Write-Host 'Chromium release, profile preservation, and launcher checks passed.'
}
finally {
    $env:LIMENOW_CHROMIUM_TEST_ARGUMENT_LOG = $originalArgumentLog
    $env:LOCALAPPDATA = $originalLocalAppData
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
