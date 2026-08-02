[CmdletBinding()]
param(
    [string]$TestParent = [IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
$setupPath = Join-Path $PSScriptRoot '..\setup.ps1'
$tokens = $null
$parseErrors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile(
    $setupPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "setup.ps1 failed syntax validation: $($parseErrors -join '; ')"
}

foreach ($functionName in @(
    'Assert-PowerShellScriptSyntax',
    'Assert-LimeNowSetupCandidate',
    'Get-LimeNowManagedScriptCandidate',
    'Update-LimeNowSetup',
    'Ensure-StartupHook'
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

$testRoot = Join-Path $TestParent (
    'LimeNow-startup-experience-test-' + [Guid]::NewGuid().ToString('N')
)
$script:downloadPayload = $null
$script:downloadFailure = $null
$script:messages = @()

function Invoke-WebRequest {
    param(
        [string]$Uri,
        [string]$OutFile,
        [hashtable]$Headers,
        [switch]$UseBasicParsing,
        [int]$TimeoutSec
    )

    if ($script:downloadFailure) {
        throw $script:downloadFailure
    }
    Copy-Item -LiteralPath $script:downloadPayload -Destination $OutFile -Force
}

function Write-SetupLog {
    param([Parameter(Mandatory)][string]$Message)

    $script:messages += $Message
}

function Resolve-LimeNowPowerShell {
    return 'C:\Tools\PowerShell\pwsh.exe'
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but received '$Actual'."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $payloadPath = Join-Path $testRoot 'remote-setup.ps1'
    $destinationPath = Join-Path $testRoot 'SalsaNOW-EasySetup.ps1'
    $validPayload = @'
# LIMENOW_SETUP_SCRIPT
[CmdletBinding()]
param(
    [switch]$Startup,
    [switch]$SkipStartupUpdate,
    [switch]$RefreshManagedScripts
)
'updated setup'
'@
    $installedPayload = $validPayload.Replace("'updated setup'", "'installed setup'")
    Set-Content -LiteralPath $payloadPath -Value $validPayload -Encoding utf8 -NoNewline
    Set-Content -LiteralPath $destinationPath -Value $installedPayload -Encoding utf8 -NoNewline
    $script:downloadPayload = $payloadPath

    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Updated' -Message 'A valid changed setup was not installed.'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath $destinationPath -Raw) `
        -Expected $validPayload `
        -Message 'The updated setup content was not promoted.'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath "$destinationPath.previous" -Raw) `
        -Expected $installedPayload `
        -Message 'The previous known-good setup was not retained.'

    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Current' -Message 'An identical setup was not recognized as current.'

    $secondPayload = $validPayload.Replace("'updated setup'", "'second update'")
    Set-Content -LiteralPath $payloadPath -Value $secondPayload -Encoding utf8 -NoNewline
    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Updated' -Message 'A second valid update was not installed.'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath "$destinationPath.previous" -Raw) `
        -Expected $validPayload `
        -Message 'A repeated update did not rotate the known-good backup.'

    $beforeFailure = Get-Content -LiteralPath $destinationPath -Raw
    Set-Content `
        -LiteralPath $payloadPath `
        -Value "# LIMENOW_SETUP_SCRIPT`nparam([switch]`$Startup)" `
        -Encoding utf8 `
        -NoNewline
    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Fallback' -Message 'An incompatible setup was not rejected.'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath $destinationPath -Raw) `
        -Expected $beforeFailure `
        -Message 'A rejected setup changed the installed known-good copy.'

    Set-Content `
        -LiteralPath $payloadPath `
        -Value "# not a LimeNow setup`nparam()" `
        -Encoding utf8 `
        -NoNewline
    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Fallback' -Message 'A file without the LimeNow marker was not rejected.'

    $script:downloadFailure = 'simulated offline session'
    $status = Update-LimeNowSetup `
        -SourceUrl 'https://example.invalid/setup.ps1' `
        -DestinationPath $destinationPath
    Assert-Equal -Actual $status -Expected 'Fallback' -Message 'An offline update did not use the fallback path.'
    $script:downloadFailure = $null

    $managedLocal = Join-Path $testRoot 'installed-manager.ps1'
    $managedRemote = Join-Path $testRoot 'remote-manager.ps1'
    $managedCandidate = Join-Path $testRoot 'candidate-manager.ps1'
    Set-Content -LiteralPath $managedLocal -Value "'installed manager'" -Encoding utf8 -NoNewline
    Set-Content -LiteralPath $managedRemote -Value "'remote manager'" -Encoding utf8 -NoNewline
    $script:downloadPayload = $managedRemote
    $RefreshManagedScripts = $true
    Get-LimeNowManagedScriptCandidate `
        -LocalPath $managedLocal `
        -RemoteUrl 'https://example.invalid/manager.ps1' `
        -CandidatePath $managedCandidate `
        -Description 'test manager'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath $managedCandidate -Raw) `
        -Expected "'remote manager'" `
        -Message 'A verified startup did not refresh a managed script.'

    Set-Content -LiteralPath $managedRemote -Value '{' -Encoding utf8 -NoNewline
    Get-LimeNowManagedScriptCandidate `
        -LocalPath $managedLocal `
        -RemoteUrl 'https://example.invalid/manager.ps1' `
        -CandidatePath $managedCandidate `
        -Description 'test manager'
    Assert-Equal `
        -Actual (Get-Content -LiteralPath $managedCandidate -Raw) `
        -Expected "'installed manager'" `
        -Message 'An invalid managed-script update did not fall back to the installed copy.'

    $salsaRoot = Join-Path $testRoot 'SalsaNOW'
    $startupBatch = Join-Path $salsaRoot 'StartupBatch.bat'
    $remoteSetupUrl = 'https://example.invalid/setup.ps1'
    New-Item -ItemType Directory -Path $salsaRoot -Force | Out-Null
    @'
@echo off
REM === SALSANOW EASY SETUP BEGIN ===
echo obsolete LimeNow block
REM === SALSANOW EASY SETUP END ===
echo preserve-this-command
'@ | Set-Content -LiteralPath $startupBatch -Encoding ascii

    Ensure-StartupHook
    $hook = Get-Content -LiteralPath $startupBatch -Raw
    foreach ($requiredText in @(
        '"C:\Tools\PowerShell\pwsh.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SALSANOW_SETUP_MAIN%" -Startup',
        '-File "%SALSANOW_SETUP_MAIN%" -Startup',
        '-File "%SALSANOW_SETUP_FALLBACK%" -Startup',
        'echo preserve-this-command'
    )) {
        if (-not $hook.Contains($requiredText)) {
            throw "The generated startup hook is missing: $requiredText"
        }
    }
    foreach ($forbiddenText in @('PowerShell.exe', 'start "LimeNow setup"', '-NonInteractive', 'startup.log', 'obsolete LimeNow block')) {
        if ($hook.Contains($forbiddenText)) {
            throw "The generated startup hook contains redundant or obsolete launch behavior: $forbiddenText"
        }
    }
    if (([regex]::Matches($hook, 'REM === SALSANOW EASY SETUP BEGIN ===')).Count -ne 1) {
        throw 'The startup hook did not retain exactly one managed LimeNow block.'
    }

    $setupSource = Get-Content -LiteralPath $setupPath -Raw
    foreach ($progressText in @(
        'Show-StartupProgressHeader',
        'Updating and preparing this GeForce NOW session...',
        'Show-StartupProgressResult',
        'This window will close automatically.'
    )) {
        if (-not $setupSource.Contains($progressText)) {
            throw "The setup progress UX is missing: $progressText"
        }
    }

    Write-Output 'Startup experience test passed: SafeAutoUpdate, OfflineFallback, PreviousVersionBackup, ManagedScriptRefresh, SingleSetupWindow, PreservedStartupCommands, ProgressUX'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedParent = [IO.Path]::GetFullPath($TestParent).TrimEnd('\') + '\'
        if (-not $resolvedRoot.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedRoot) -notmatch '^LimeNow-startup-experience-test-[a-f0-9]{32}$') {
            throw "Refusing to remove unexpected test directory: $resolvedRoot"
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
