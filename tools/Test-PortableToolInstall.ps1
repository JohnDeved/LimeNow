# Explicit Windows integration test: downloads and installs current upstream releases
# into disposable folders. It does not change user PATH, authentication, or shortcuts.
[CmdletBinding()]
param(
    [string]$TestParent = [IO.Path]::GetTempPath(),
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\setup.ps1')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host 'Portable application installation checks require Windows; skipped.'
    return
}

$tokens = $null
$parseErrors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile(
    $SourcePath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "setup.ps1 failed syntax validation: $($parseErrors -join '; ')"
}
foreach ($functionName in @(
    'Get-VerifiedDownload', 'Remove-SetupRepairDirectory', 'Get-LimeNowJson',
    'ConvertTo-LimeNowVersion', 'Get-LimeNowGitHubRelease', 'Get-LimeNowGitHubAsset',
    'Get-LatestNodeRelease', 'Get-LatestGitRelease', 'Get-LatestGitHubCliRelease',
    'Get-LatestVSCodeRelease', 'Get-LatestWindowsTerminalRelease',
    'Test-LimeNowToolRunning', 'Assert-LimeNowNoPendingToolRecovery', 'Get-LimeNowUpdateMutexName', 'Move-LimeNowPath',
    'Install-LimeNowStagedDirectory',
    'Get-LimeNowInstalledVersion', 'Install-LimeNowPortableTool'
)) {
    $definition = $setupAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if (-not $definition) { throw "setup.ps1 is missing $functionName." }
    Invoke-Expression $definition.Extent.Text
}

$testRoot = Join-Path $TestParent ('LimeNow-portable-install-test-' + [Guid]::NewGuid().ToString('N'))
$setupRoot = Join-Path $testRoot 'setup'
$appsRoot = Join-Path $testRoot 'apps'
$toolRoots = @{}
$releases = @{}
$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

function Write-SetupLog {
    param([string]$Message)
    Write-Host "[portable-install] $Message"
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; received '$Actual'."
    }
}

function Assert-InstalledRelease {
    param([string]$Tool)
    $actual = Get-LimeNowInstalledVersion -Tool $Tool -Root $toolRoots[$Tool]
    Assert-Equal $actual $releases[$Tool].Version "$Tool failed its installed-version probe."
}

function Write-PersistentFixture {
    param([string]$Tool, [string]$RelativePath, [string]$Content)
    $path = Join-Path $toolRoots[$Tool] $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -LiteralPath $path -Value $Content -Encoding UTF8 -NoNewline
    return [pscustomobject]@{
        Path = $path
        Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $setupRoot, $appsRoot -Force | Out-Null
    $resolvers = [ordered]@{
        Node = 'Get-LatestNodeRelease'
        Git = 'Get-LatestGitRelease'
        GitHubCli = 'Get-LatestGitHubCliRelease'
        VSCode = 'Get-LatestVSCodeRelease'
        WindowsTerminal = 'Get-LatestWindowsTerminalRelease'
    }
    foreach ($entry in $resolvers.GetEnumerator()) {
        $tool = [string]$entry.Key
        $toolRoots[$tool] = Join-Path $appsRoot $tool
        $releases[$tool] = & $entry.Value
        Write-Host "Installing and probing $tool $($releases[$tool].Version) from its verified upstream archive."
        Install-LimeNowPortableTool -Tool $tool -Root $toolRoots[$tool] -Release $releases[$tool]
        Assert-InstalledRelease -Tool $tool
    }

    # Exercise the packaged npm/npx launchers, using the Node executable beside them.
    $npmManifest = Get-Content -LiteralPath (Join-Path $toolRoots.Node 'node_modules\npm\package.json') -Raw | ConvertFrom-Json
    foreach ($command in @('npm.cmd', 'npx.cmd')) {
        $output = @(& (Join-Path $toolRoots.Node $command) --version)
        if ($LASTEXITCODE -ne 0) { throw "The portable $command command failed." }
        Assert-Equal (($output -join "`n").Trim()) $npmManifest.version "The bundled $command command reported another version."
    }
    $shellOutput = @(& (Join-Path $toolRoots.Git 'usr\bin\sh.exe') -c 'printf limenow-portable-shell')
    if ($LASTEXITCODE -ne 0 -or ($shellOutput -join '') -ne 'limenow-portable-shell') {
        throw 'Portable Git installed without a working bundled shell.'
    }

    # Terminal embeds a build version that differs from its release tag. Verify its
    # real PE metadata and runtime files, in addition to the checksum-backed marker.
    $terminalExecutable = Join-Path $toolRoots.WindowsTerminal 'WindowsTerminal.exe'
    $terminalProductVersion = (Get-Item -LiteralPath $terminalExecutable).VersionInfo.ProductVersion
    $terminalReleaseVersion = ConvertTo-LimeNowVersion $releases.WindowsTerminal.Version
    if ($terminalProductVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$' -or
        -not $terminalProductVersion.StartsWith("$($terminalReleaseVersion.Major).$($terminalReleaseVersion.Minor).")) {
        throw "Windows Terminal has unexpected executable metadata: $terminalProductVersion"
    }
    foreach ($relative in @('.portable', 'LIMENOW-VERSION', 'OpenConsole.exe', 'TerminalApp.dll', 'Microsoft.Terminal.Control.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $toolRoots.WindowsTerminal $relative) -PathType Leaf)) {
            throw "Windows Terminal is missing a portable runtime file: $relative"
        }
    }

    $state = @{
        GitHubCli = @(
            (Write-PersistentFixture -Tool GitHubCli -RelativePath 'Config\fixture-state.txt' -Content 'persistent-cli-config'),
            (Write-PersistentFixture -Tool GitHubCli -RelativePath 'gh.cmd' -Content '@rem persistent-wrapper'),
            (Write-PersistentFixture -Tool GitHubCli -RelativePath 'GitHub-CLI-Sign-In.cmd' -Content '@rem persistent-sign-in-command'),
            (Write-PersistentFixture -Tool GitHubCli -RelativePath 'GitHub-CLI-Sign-In.ps1' -Content '# persistent-sign-in-script')
        )
        VSCode = @(
            (Write-PersistentFixture -Tool VSCode -RelativePath 'data\user-data\User\settings.json' -Content '{"editor.fontSize":15}'),
            (Write-PersistentFixture -Tool VSCode -RelativePath 'data\extensions\fixture-extension\package.json' -Content '{"name":"fixture-extension","version":"1.0.0"}')
        )
        WindowsTerminal = @(
            (Write-PersistentFixture -Tool WindowsTerminal -RelativePath 'settings\settings.json' -Content '{"theme":"dark"}'),
            (Write-PersistentFixture -Tool WindowsTerminal -RelativePath 'settings\state.json' -Content '{"fixture":"persistent-terminal-state"}')
        )
    }
    foreach ($tool in @('GitHubCli', 'VSCode', 'WindowsTerminal')) {
        $obsoleteFile = Join-Path $toolRoots[$tool] 'LIMENOW-OBSOLETE-TEST-FILE'
        Set-Content -LiteralPath $obsoleteFile -Value 'stale program content' -NoNewline
        Write-Host "Reinstalling $tool $($releases[$tool].Version) to validate persistent state with a real package."
        Install-LimeNowPortableTool -Tool $tool -Root $toolRoots[$tool] -Release $releases[$tool]
        Assert-InstalledRelease -Tool $tool
        foreach ($fixture in $state[$tool]) {
            Assert-Equal (Test-Path -LiteralPath $fixture.Path -PathType Leaf) $true "$tool lost persistent state."
            Assert-Equal (Get-FileHash -LiteralPath $fixture.Path -Algorithm SHA256).Hash $fixture.Hash "$tool changed persistent state bytes."
        }
        Assert-Equal (Test-Path -LiteralPath $obsoleteFile) $false "$tool retained an obsolete application file after replacement."
    }

    $unfinished = @(Get-ChildItem -LiteralPath $setupRoot -Force)
    if ($unfinished.Count) {
        throw "Successful application installs left staging or recovery directories in $setupRoot."
    }
    Write-Host 'Windows portable install checks passed: Node/npm/npx, Git, GitHub CLI, VS Code, Terminal, and persistent-state reinstalls.'
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ((Split-Path -Leaf $resolvedTestRoot) -match '^LimeNow-portable-install-test-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
