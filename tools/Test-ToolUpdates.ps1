[CmdletBinding()]
param(
    [string]$TestParent = [IO.Path]::GetTempPath(),
    [string]$SourcePath = (Join-Path $PSScriptRoot '..\setup.ps1')
)

$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile(
    $SourcePath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "Updater source failed syntax validation: $($parseErrors -join '; ')"
}
foreach ($functionName in @(
    'Get-LimeNowJson', 'ConvertTo-LimeNowVersion', 'Get-LimeNowGitHubRelease',
    'Get-LimeNowGitHubAsset', 'Get-LatestNodeRelease', 'Get-LatestGitRelease',
    'Get-LatestGitHubCliRelease', 'Get-LatestVSCodeRelease',
    'Get-LatestWindowsTerminalRelease', 'Test-LimeNowToolRunning',
    'Invoke-LimeNowToolUpdate', 'Assert-LimeNowNoPendingToolRecovery', 'Get-LimeNowUpdateMutexName',
    'Move-LimeNowPath', 'Install-LimeNowStagedDirectory', 'Get-LimeNowInstalledVersion'
)) {
    $definition = $setupAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if (-not $definition) { throw "Updater source is missing $functionName." }
    Invoke-Expression $definition.Extent.Text
}

$testRoot = Join-Path $TestParent ('LimeNow-tool-updates-test-' + [Guid]::NewGuid().ToString('N'))
$script:messages = @()
$script:jsonResponse = $null
$script:sumsText = ''
$script:processes = @()
$script:movePolicy = $null
$hash = 'a' * 64

function Write-SetupLog {
    param([string]$Message)
    $script:messages += $Message
}

function Invoke-RestMethod {
    param([string]$Uri, [int]$TimeoutSec, [hashtable]$Headers)
    if ($TimeoutSec -ne 20 -or $Headers['User-Agent'] -ne 'LimeNow' -or
        $Headers['Cache-Control'] -ne 'no-cache') {
        throw 'Release discovery omitted its bounded timeout or update request headers.'
    }
    $script:lastMetadataUri = $Uri
    # Invoke-RestMethod keeps a top-level JSON array together on its pipeline.
    Write-Output -NoEnumerate $script:jsonResponse
}

function Invoke-WebRequest {
    param([string]$Uri, [switch]$UseBasicParsing, [int]$TimeoutSec, [hashtable]$Headers)
    $script:lastChecksumUri = $Uri
    return [pscustomobject]@{ Content = $script:sumsText }
}

function Get-Process {
    [CmdletBinding()]
    param()
    return $script:processes
}

$script:strictMove = ${function:Move-LimeNowPath}
function Move-LimeNowPath {
    [CmdletBinding()]
    param([string]$LiteralPath, [string]$Destination, [switch]$Force)
    if ($script:movePolicy) { & $script:movePolicy $LiteralPath $Destination }
    & $script:strictMove @PSBoundParameters
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; received '$Actual'."
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message, [switch]$RecoveryRequired)
    $threw = $false
    $failure = $null
    try { & $Action | Out-Null } catch { $threw = $true; $failure = $_ }
    if (-not $threw) { throw $Message }
    if ($RecoveryRequired -and -not $failure.Exception.Data['LimeNowRecoveryRequired']) {
        throw 'A rollback failure lost its recovery-required signal.'
    }
}

function New-ReleaseFixture {
    param([string]$Repository, [string]$Tag, [string]$AssetName)
    return [pscustomobject]@{
        tag_name = $Tag
        draft = $false
        prerelease = $false
        assets = @([pscustomobject]@{
            name = $AssetName
            browser_download_url = "https://github.com/$Repository/releases/download/$Tag/$AssetName"
            digest = "sha256:$hash"
        })
    }
}

function Invoke-TestUpdate {
    Invoke-LimeNowToolUpdate -Name 'Fixture tool' -Root $script:toolRoot `
        -FallbackRelease ([pscustomobject]@{ Version = '1.0.0'; Uri = 'fallback'; Hash = $hash }) `
        -GetInstalledVersion { param($Root) $script:installedVersion } `
        -GetLatestRelease {
            if ($script:metadataFailure) { throw 'simulated offline/rate-limited metadata' }
            return $script:latestRelease
        } -InstallRelease {
            param($Release)
            $script:installCalls++
            if ($script:installMode -eq 'FailKeep') { throw 'simulated download failure' }
            if ($script:installMode -eq 'FailRemove') {
                $script:installedVersion = $null
                throw 'simulated unrecoverable installation failure'
            }
            if ($script:installMode -eq 'RecoveryRequired') {
                $script:installedVersion = $Release.Version
                $failure = [IO.IOException]::new('simulated incomplete state rollback')
                $failure.Data['LimeNowRecoveryRequired'] = $true
                throw $failure
            }
            $script:installedVersion = $Release.Version
        } -ProcessNames @('fixture')
}

function Reset-UpdateFixture {
    $script:installedVersion = '1.0.0'
    $script:latestRelease = [pscustomobject]@{ Version = '1.1.0'; Uri = 'latest'; Hash = $hash }
    $script:metadataFailure = $false
    $script:installMode = 'Success'
    $script:installCalls = 0
    $script:processes = @()
}

function New-TransactionFixture {
    param([string]$Name)
    $caseRoot = Join-Path $testRoot $Name
    $destination = Join-Path $caseRoot 'installed'
    $repair = Join-Path $caseRoot ('tool-repair-' + [Guid]::NewGuid().ToString('N'))
    $candidate = Join-Path $repair 'extracted'
    New-Item -ItemType Directory -Path (Join-Path $destination 'Config'),
        (Join-Path $destination 'settings'), (Join-Path $candidate 'Config') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $destination 'app.bin') -Value 'old' -NoNewline
    Set-Content -LiteralPath (Join-Path $destination 'obsolete.dll') -Value 'old-only' -NoNewline
    Set-Content -LiteralPath (Join-Path $destination 'Config\hosts.yml') -Value 'fixture-auth' -NoNewline
    Set-Content -LiteralPath (Join-Path $destination 'settings\state.json') -Value 'fixture-settings' -NoNewline
    Set-Content -LiteralPath (Join-Path $destination '.portable') -Value 'portable-marker' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidate 'app.bin') -Value 'new' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidate 'new.dll') -Value 'new-only' -NoNewline
    Set-Content -LiteralPath (Join-Path $candidate 'Config\defaults.yml') -Value 'package-default' -NoNewline
    return [pscustomobject]@{ Destination = $destination; Repair = $repair; Candidate = $candidate }
}

function Assert-OldInstallation {
    param($Fixture)
    Assert-Equal (Get-Content -LiteralPath (Join-Path $Fixture.Destination 'app.bin') -Raw) 'old' 'Rollback did not restore the old executable.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $Fixture.Destination 'Config\hosts.yml') -Raw) 'fixture-auth' 'Rollback lost authentication state.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $Fixture.Destination 'settings\state.json') -Raw) 'fixture-settings' 'Rollback lost application settings.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $Fixture.Repair 'LIMENOW-RECOVERY')) $false 'A successful rollback retained its incomplete-recovery marker.'
}

$verifyCandidate = {
    param($Path)
    return (Get-Content -LiteralPath (Join-Path $Path 'app.bin') -Raw) -eq 'new'
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $script:toolRoot = Join-Path $testRoot 'managed-tool'
    $onWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $nativeProbe = Join-Path $testRoot $(if ($onWindows) { 'fake-gh.cmd' } else { 'fake-gh.sh' })
    $nativeSource = if ($onWindows) {
        "@echo off`r`necho gh version 2.102.0`r`necho fixture release details`r`nexit /b __EXIT__`r`n"
    }
    else {
        "#!/bin/sh`necho 'gh version 2.102.0'`necho 'fixture release details'`nexit __EXIT__`n"
    }
    $previousExitCode = $global:LASTEXITCODE
    $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        Set-Content -LiteralPath $nativeProbe -Value $nativeSource.Replace('__EXIT__', '19') -Encoding ASCII
        if (-not $onWindows) {
            & chmod +x $nativeProbe
            if ($LASTEXITCODE -ne 0) { throw 'The native version probe fixture could not be made executable.' }
        }
        & $nativeProbe *> $null
        Assert-Equal $LASTEXITCODE 19 'The native probe did not seed a failing exit code.'
        Set-Content -LiteralPath $nativeProbe -Value $nativeSource.Replace('__EXIT__', '0') -Encoding ASCII
        Assert-Equal (Get-LimeNowInstalledVersion -Tool GitHubCli -Root $testRoot -ExecutablePath $nativeProbe) '2.102.0' 'A successful native version probe inherited an earlier exit code.'
        Set-Content -LiteralPath $nativeProbe -Value $nativeSource.Replace('__EXIT__', '23') -Encoding ASCII
        Assert-Equal (Get-LimeNowInstalledVersion -Tool GitHubCli -Root $testRoot -ExecutablePath $nativeProbe) $null 'A failing native probe was accepted because it printed a matching version.'
    }
    finally {
        $global:LASTEXITCODE = $previousExitCode
        $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }

    Assert-Equal (ConvertTo-LimeNowVersion 'v2.56.0.windows.2').ToString() '2.56.0.2' 'Git release normalization failed.'
    Assert-Equal (ConvertTo-LimeNowVersion '1.2.3') (ConvertTo-LimeNowVersion 'v1.2.3.0') 'Three- and four-part versions compare differently.'
    foreach ($invalidVersion in @('1.2', '1.2.3-beta.1', 'v1.2.3+metadata', '1.2.3.4.5', '../1.2.3')) {
        Assert-Throws { ConvertTo-LimeNowVersion $invalidVersion } "Invalid version was accepted: $invalidVersion"
    }

    $script:jsonResponse = @(
        [pscustomobject]@{ version = 'v28.0.0'; lts = $false; files = @('win-x64-zip') },
        [pscustomobject]@{ version = 'v24.99.0'; lts = 'Older'; files = @('win-x64-zip') },
        [pscustomobject]@{ version = 'v26.2.0'; lts = 'Newer'; files = @('win-arm64-zip') },
        [pscustomobject]@{ version = 'v26.1.0'; lts = 'Newer'; files = @('win-x64-zip') },
        [pscustomobject]@{ version = 'v26.3.0-rc.1'; lts = 'Newer'; files = @('win-x64-zip') }
    )
    $script:sumsText = "$hash  node-v26.1.0-win-x64.zip`r`n$('b' * 64)  node-v26.1.0-win-arm64.zip`r`n"
    $node = Get-LatestNodeRelease
    Assert-Equal $node.Version 'v26.1.0' 'Node did not select the highest stable LTS with an x64 archive.'
    Assert-Equal $node.Hash $hash 'Node used the checksum of a different archive.'
    Assert-Equal $script:lastChecksumUri 'https://nodejs.org/dist/v26.1.0/SHASUMS256.txt' 'Node fetched checksums for another version.'
    $script:sumsText += "$hash  node-v26.1.0-win-x64.zip`n"
    Assert-Throws { Get-LatestNodeRelease } 'Duplicate Node archive checksum entries were accepted.'

    foreach ($revision in @(1, 2)) {
        $assetVersion = if ($revision -eq 1) { '2.56.0' } else { '2.56.0.2' }
        $script:jsonResponse = New-ReleaseFixture 'git-for-windows/git' "v2.56.0.windows.$revision" "PortableGit-$assetVersion-64-bit.7z.exe"
        $git = Get-LatestGitRelease
        Assert-Equal $git.Version "2.56.0.windows.$revision" 'Git dropped its Windows build revision.'
        Assert-Equal $git.Hash $hash 'Git did not select its matching PortableGit archive.'
    }
    $script:jsonResponse = New-ReleaseFixture 'cli/cli' 'v2.102.0' 'gh_2.102.0_windows_amd64.zip'
    Assert-Equal (Get-LatestGitHubCliRelease).Version '2.102.0' 'GitHub CLI release parsing failed.'
    $script:jsonResponse.prerelease = $true
    Assert-Throws { Get-LatestGitHubCliRelease } 'A prerelease was accepted as stable.'
    $script:jsonResponse.prerelease = $false
    $script:jsonResponse.draft = $true
    Assert-Throws { Get-LatestGitHubCliRelease } 'A draft release was accepted.'
    $script:jsonResponse.draft = $false
    $script:jsonResponse.assets[0].digest = 'sha1:invalid'
    Assert-Throws { Get-LatestGitHubCliRelease } 'A release without SHA-256 was accepted.'
    $script:jsonResponse.assets[0].digest = "sha256:$hash"
    $script:jsonResponse.assets[0].browser_download_url = 'https://example.invalid/download.zip'
    Assert-Throws { Get-LatestGitHubCliRelease } 'An asset from another host was accepted.'
    $script:jsonResponse = New-ReleaseFixture 'cli/cli' 'v2.102.0' 'gh_2.102.0_windows_arm64.zip'
    Assert-Throws { Get-LatestGitHubCliRelease } 'An archive for another architecture was accepted.'
    $script:jsonResponse = New-ReleaseFixture 'cli/cli' 'v2.102.0' 'gh_2.102.0_windows_amd64.zip'
    $script:jsonResponse.assets += $script:jsonResponse.assets[0]
    Assert-Throws { Get-LatestGitHubCliRelease } 'Duplicate exact assets were accepted.'
    $script:jsonResponse = New-ReleaseFixture 'microsoft/terminal' 'v1.25.2733.0' 'Microsoft.WindowsTerminal_1.25.2733.0_x64.zip'
    Assert-Equal (Get-LatestWindowsTerminalRelease).Version '1.25.2733.0' 'Terminal lost its fourth version component.'

    $script:jsonResponse = [pscustomobject]@{
        productVersion = '1.142.0'
        version = 'b' * 40
        url = "https://vscode.download.prss.microsoft.com/dbazure/download/stable/$('b' * 40)/VSCode-win32-x64-1.142.0.zip"
        sha256hash = $hash
    }
    Assert-Equal (Get-LatestVSCodeRelease).Version '1.142.0' 'VS Code compared its commit instead of product version.'
    $script:jsonResponse.url = $script:jsonResponse.url.Replace('win32-x64', 'win32-arm64')
    Assert-Throws { Get-LatestVSCodeRelease } 'VS Code accepted the wrong architecture.'

    $script:processes = @([pscustomobject]@{ ProcessName = 'fixture'; Path = (Join-Path $testRoot 'unrelated\fixture.exe') })
    Assert-Equal (Test-LimeNowToolRunning -Root $script:toolRoot -ProcessNames 'fixture') $false 'An unrelated process prevented a managed update.'
    $script:processes = @([pscustomobject]@{ ProcessName = 'helper'; Path = (Join-Path $script:toolRoot 'helpers\child.exe') })
    Assert-Equal (Test-LimeNowToolRunning -Root $script:toolRoot) $true 'A managed child process was missed.'
    $script:processes = @([pscustomobject]@{ ProcessName = 'fixture'; Path = $null })
    Assert-Equal (Test-LimeNowToolRunning -Root $script:toolRoot -ProcessNames 'fixture') $true 'An inaccessible matching process was not deferred.'

    Reset-UpdateFixture
    Invoke-TestUpdate
    Assert-Equal $script:installedVersion '1.1.0' 'An available stable update was not installed.'
    Reset-UpdateFixture
    $script:metadataFailure = $true
    $script:installedVersion = '0.9.0'
    Invoke-TestUpdate
    Assert-Equal $script:installCalls 0 'An offline session replaced a usable existing installation.'
    $script:installedVersion = $null
    Invoke-TestUpdate
    Assert-Equal $script:installedVersion '1.0.0' 'An offline new installation did not select the bootstrap fallback.'
    Reset-UpdateFixture
    $script:installedVersion = '2.0.0'
    Invoke-TestUpdate
    Assert-Equal $script:installCalls 0 'A newer usable installed version was downgraded.'
    Reset-UpdateFixture
    $script:installedVersion = '0.9.0'
    $script:latestRelease.Version = '0.8.0'
    Invoke-TestUpdate
    Assert-Equal $script:installedVersion '1.0.0' 'Stale upstream metadata bypassed the known-good floor.'
    Reset-UpdateFixture
    $script:latestRelease.Version = '2.0.0-beta.1'
    Invoke-TestUpdate
    Assert-Equal $script:installCalls 0 'Malformed metadata caused a usable installation to be replaced.'
    Reset-UpdateFixture
    $script:processes = @([pscustomobject]@{ ProcessName = 'fixture'; Path = (Join-Path $script:toolRoot 'fixture.exe') })
    Invoke-TestUpdate
    Assert-Equal $script:installCalls 0 'A busy managed program was replaced.'
    $script:installedVersion = $null
    Assert-Throws { Invoke-TestUpdate } 'A missing but busy installation was reported ready.'
    Reset-UpdateFixture
    $script:installMode = 'FailKeep'
    Invoke-TestUpdate
    Assert-Equal $script:installedVersion '1.0.0' 'A failed download discarded the healthy installed version.'
    $script:installMode = 'Success'
    Invoke-TestUpdate
    Assert-Equal $script:installedVersion '1.1.0' 'A safely failed update prevented later setup work.'
    Reset-UpdateFixture
    $script:installMode = 'FailRemove'
    Assert-Throws { Invoke-TestUpdate } 'An unusable installation was falsely reported as retained after failure.'
    Reset-UpdateFixture
    $script:installMode = 'RecoveryRequired'
    Assert-Throws { Invoke-TestUpdate } 'A runnable binary concealed incomplete state recovery.' -RecoveryRequired

    $script:processes = @()
    $fixture = New-TransactionFixture 'success'
    Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
        -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings', '.portable') -Verify $verifyCandidate
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination 'app.bin') -Raw) 'new' 'The verified application was not promoted.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination 'Config\hosts.yml') -Raw) 'fixture-auth' 'Authentication state was replaced by archive defaults.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination 'settings\state.json') -Raw) 'fixture-settings' 'Application settings did not survive upgrade.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination '.portable') -Raw) 'portable-marker' 'The portable mode marker did not survive upgrade.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Destination 'obsolete.dll')) $false 'The update left stale program files behind.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Repair 'LIMENOW-RECOVERY')) $false 'A successful update left a recovery marker.'

    $fixture = New-TransactionFixture 'first-install'
    Remove-Item -LiteralPath $fixture.Destination -Recurse -Force
    Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
        -RepairRoot $fixture.Repair -PreservePaths 'Config' -Verify $verifyCandidate
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination 'app.bin') -Raw) 'new' 'A first installation could not be promoted without a previous directory.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Repair 'LIMENOW-RECOVERY')) $false 'A first installation left a recovery marker.'

    $fixture = New-TransactionFixture 'started-during-download'
    $script:processes = @([pscustomobject]@{ ProcessName = 'helper'; Path = (Join-Path $fixture.Destination 'app.exe') })
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths 'Config' -Verify $verifyCandidate
    } 'An application started during its download was replaced.'
    $script:processes = @()
    Assert-OldInstallation $fixture

    $fixture = New-TransactionFixture 'invalid-candidate'
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths 'Config' -Verify { param($Path) $false }
    } 'An invalid candidate was installed.'
    Assert-OldInstallation $fixture

    $fixture = New-TransactionFixture 'failed-promotion'
    $script:blockedCandidate = $fixture.Candidate
    $script:movePolicy = {
        param($Source, $Destination)
        if ($Source -eq $script:blockedCandidate) { throw 'simulated promotion lock' }
    }
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $verifyCandidate
    } 'A simulated promotion failure was ignored.'
    $script:movePolicy = $null
    Assert-OldInstallation $fixture

    $fixture = New-TransactionFixture 'failed-verification'
    $script:validCandidate = $fixture.Candidate
    $failPromotedVerification = { param($Path) $Path -eq $script:validCandidate }
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $failPromotedVerification
    } 'Failed final verification was ignored.'
    Assert-OldInstallation $fixture

    $fixture = New-TransactionFixture 'failed-state-move'
    $script:blockedState = Join-Path $fixture.Repair 'previous\settings'
    $script:movePolicy = {
        param($Source, $Destination)
        if ($Source -eq $script:blockedState) { throw 'simulated state lock' }
    }
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $verifyCandidate
    } 'A partially failed state migration was ignored.'
    $script:movePolicy = $null
    Assert-OldInstallation $fixture

    $fixture = New-TransactionFixture 'failed-rollback'
    $script:validCandidate = $fixture.Candidate
    $script:blockedBackup = Join-Path $fixture.Repair 'previous'
    $script:movePolicy = {
        param($Source, $Destination)
        if ($Source -eq $script:blockedBackup) { throw 'simulated rollback lock' }
    }
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $failPromotedVerification
    } 'A rollback failure was ignored.' -RecoveryRequired
    $script:movePolicy = $null
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Repair 'LIMENOW-RECOVERY')) $true 'A failed rollback discarded its recovery marker.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Repair 'previous\Config\hosts.yml') -Raw) 'fixture-auth' 'Recovery authentication files were lost.'

    $fixture = New-TransactionFixture 'recreated-destination'
    $script:recreatedCandidate = $fixture.Candidate
    $script:recreatedDestination = $fixture.Destination
    $script:movePolicy = {
        param($Source, $Destination)
        if ($Source -eq $script:recreatedCandidate -and $Destination -eq $script:recreatedDestination) {
            # A second writer recreates the target with the same version after
            # the original installation and its state have been moved aside.
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Destination 'app.bin') -Value 'new' -NoNewline
        }
    }
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $verifyCandidate
    } 'A same-version recreated destination concealed a failed promotion.' -RecoveryRequired
    $script:movePolicy = $null
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Destination 'extracted')) $false 'The candidate was nested in a recreated destination.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Destination 'previous')) $false 'Rollback nested the old installation in a recreated destination.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Repair 'previous\Config\hosts.yml') -Raw) 'fixture-auth' 'A destination collision misplaced authentication state.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Repair 'previous\settings\state.json') -Raw) 'fixture-settings' 'A destination collision misplaced application settings.'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Repair 'LIMENOW-RECOVERY')) $true 'A destination collision discarded its recovery marker.'

    $fixture = New-TransactionFixture 'concurrent-update'
    $ready = [Threading.ManualResetEvent]::new($false)
    $releaseLock = [Threading.ManualResetEvent]::new($false)
    $lockOwner = [PowerShell]::Create()
    $holdMutex = {
        param($Name, $Ready, $ReleaseLock)
        $mutex = [Threading.Mutex]::new($false, $Name)
        $held = $false
        try {
            $held = $mutex.WaitOne(5000)
            if (-not $held) { throw 'The concurrency fixture could not acquire its mutex.' }
            [void]$Ready.Set()
            [void]$ReleaseLock.WaitOne(15000)
        }
        finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
    $null = $lockOwner.AddScript($holdMutex.ToString()).AddArgument(
        (Get-LimeNowUpdateMutexName -DestinationPath $fixture.Destination)
    ).AddArgument($ready).AddArgument($releaseLock)
    $pendingLockOwner = $lockOwner.BeginInvoke()
    try {
        if (-not $ready.WaitOne(10000)) { throw 'The concurrency fixture did not become ready.' }
        Assert-Throws {
            Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
                -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $verifyCandidate
        } 'A second update entered the critical section while its destination was locked.'
        Assert-OldInstallation $fixture
        Assert-Equal (Test-Path -LiteralPath (Join-Path $fixture.Candidate 'app.bin')) $true 'A deferred concurrent update moved its candidate.'
    }
    finally {
        [void]$releaseLock.Set()
        $lockOwner.EndInvoke($pendingLockOwner) | Out-Null
        $lockOwner.Dispose()
        $ready.Dispose()
        $releaseLock.Dispose()
    }
    Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
        -RepairRoot $fixture.Repair -PreservePaths @('Config', 'settings') -Verify $verifyCandidate
    Assert-Equal (Get-Content -LiteralPath (Join-Path $fixture.Destination 'Config\hosts.yml') -Raw) 'fixture-auth' 'Retrying a deferred update lost authentication state.'

    $fixture = New-TransactionFixture 'superseded-update'
    Assert-Throws {
        Install-LimeNowStagedDirectory -CandidatePath $fixture.Candidate -DestinationPath $fixture.Destination `
            -RepairRoot $fixture.Repair -PreservePaths 'Config' -Verify $verifyCandidate `
            -BeforeSwap { param($Path) throw 'A newer release was installed while downloading.' }
    } 'A rejected update continued to swap the live application.'
    Assert-OldInstallation $fixture

    $recoveryRoot = Join-Path $testRoot 'pending-recovery'
    $oldRepair = Join-Path $recoveryRoot ('gh-repair-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $oldRepair -Force | Out-Null
    $marker = Join-Path $oldRepair 'LIMENOW-RECOVERY'
    Set-Content -LiteralPath $marker -Value "Destination=$($fixture.Destination)"
    Assert-Throws {
        Assert-LimeNowNoPendingToolRecovery -SetupRoot $recoveryRoot
    } 'A new setup ignored retained recovery files.' -RecoveryRequired
    Assert-Throws {
        Assert-LimeNowNoPendingToolRecovery -SetupRoot $recoveryRoot -DestinationPath $fixture.Destination
    } 'A new swap ignored retained recovery for its destination.' -RecoveryRequired
    Assert-LimeNowNoPendingToolRecovery -SetupRoot $recoveryRoot -DestinationPath (Join-Path $testRoot 'another-app')
    Assert-Equal (Test-Path -LiteralPath $marker) $true 'Recovery detection changed retained files.'
    Remove-Item -LiteralPath $marker
    Assert-LimeNowNoPendingToolRecovery -SetupRoot $recoveryRoot

    Write-Host 'Tool update discovery, fallback, process deferral, state preservation, rollback, pending recovery, and concurrent-update tests passed.'
}
finally {
    $script:movePolicy = $null
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ((Split-Path -Leaf $resolvedTestRoot) -match '^LimeNow-tool-updates-test-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedTestRoot)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
