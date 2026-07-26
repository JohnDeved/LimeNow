[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-Codex-State-' + [Guid]::NewGuid().ToString('N')
)
$stateScript = Join-Path $PSScriptRoot '..\codex-state.ps1'

function Invoke-StateScript {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$SessionHome,
        [string]$CodexCommand,
        [string[]]$Arguments,
        [switch]$ApplyAcl
    )

    $commandArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $stateScript,
        '-Action',
        $Action,
        '-PersistentRoot',
        (Join-Path $testRoot 'persistent'),
        '-SessionCodexHome',
        $SessionHome
    )
    if (-not $ApplyAcl) {
        $commandArguments += '-SkipAcl'
    }
    if ($CodexCommand) {
        $commandArguments += @('-CodexCommand', $CodexCommand)
    }
    if ($Arguments) {
        $commandArguments += $Arguments
    }
    $invocationId = [Guid]::NewGuid().ToString('N')
    $stdoutPath = Join-Path $testRoot "$invocationId.out"
    $stderrPath = Join-Path $testRoot "$invocationId.err"
    $powerShellPath = (Get-Process -Id $PID).Path
    $process = Start-Process `
        -FilePath $powerShellPath `
        -ArgumentList $commandArguments `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -Wait `
        -PassThru `
        -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        $diagnostic = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if ($diagnostic) {
            Write-Verbose $diagnostic
        }
    }
    return $process.ExitCode
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $firstHome = Join-Path $testRoot 'first-home'
    $firstSessions = Join-Path $firstHome 'sessions\2026\07\26'
    New-Item -ItemType Directory -Path $firstSessions -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $firstHome 'auth.json') -Value 'fake-auth-state' -NoNewline
    Set-Content -LiteralPath (Join-Path $firstHome 'config.toml') -Value 'model = "test-model"' -NoNewline
    Set-Content `
        -LiteralPath (Join-Path $firstHome 'review.config.toml') `
        -Value 'model = "review-model"' `
        -NoNewline
    $sessionFile = Join-Path $firstSessions 'rollout-test.jsonl'
    Set-Content -LiteralPath $sessionFile -Value 'fake-session-state'
    $partialSessionFile = Join-Path $firstSessions 'rollout-active.jsonl'
    Set-Content -LiteralPath $partialSessionFile -Value 'complete-fake-session-state'

    if ((Invoke-StateScript -Action Snapshot -SessionHome $firstHome -ApplyAcl) -ne 0) {
        throw 'Active-session-safe Codex state snapshot failed.'
    }
    $persistentActiveSession = Join-Path (
        $testRoot
    ) 'persistent\sessions\active\2026\07\26\rollout-active.jsonl'
    $completeSnapshotHash = (
        Get-FileHash -LiteralPath $persistentActiveSession -Algorithm SHA256
    ).Hash
    Set-Content `
        -LiteralPath $partialSessionFile `
        -Value 'incomplete-fake-session-state' `
        -NoNewline
    if ((Invoke-StateScript -Action Snapshot -SessionHome $firstHome) -ne 0) {
        throw 'Partial active-session snapshot validation failed.'
    }
    $snapshotSessionItem = Get-Item -LiteralPath (Join-Path $firstHome 'sessions') -Force
    if ($snapshotSessionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'The snapshot action changed the active session directory into a link.'
    }
    $retainedSnapshotHash = (
        Get-FileHash -LiteralPath $persistentActiveSession -Algorithm SHA256
    ).Hash
    if ($retainedSnapshotHash -ne $completeSnapshotHash) {
        throw 'A partial active rollout replaced the last complete persistent snapshot.'
    }
    if ((Invoke-StateScript -Action Initialize -SessionHome $firstHome) -ne 0) {
        throw 'Initial Codex state migration failed.'
    }
    $authPath = Join-Path $testRoot 'persistent\auth\auth.json'
    $emptyAcl = [Security.AccessControl.FileSecurity]::new()
    $emptyAcl.SetOwner([Security.Principal.WindowsIdentity]::GetCurrent().User)
    $emptyAcl.SetAccessRuleProtection($true, $false)
    Set-Acl -LiteralPath $authPath -AclObject $emptyAcl
    if ((Invoke-StateScript -Action Watch -SessionHome $firstHome -ApplyAcl) -ne 0) {
        throw 'Codex snapshot watcher or ACL-upgrade recovery validation failed.'
    }

    $persistentRoot = Join-Path $testRoot 'persistent'
    foreach ($protectedDirectory in @('auth', 'sessions', 'config')) {
        $acl = Get-Acl -LiteralPath (Join-Path $persistentRoot $protectedDirectory)
        if (-not $acl.AreAccessRulesProtected) {
            throw "Codex state permissions still inherit on: $protectedDirectory"
        }
    }
    foreach ($protectedFile in @(
        (Join-Path $persistentRoot 'auth\auth.json'),
        (Join-Path $persistentRoot 'config\config.toml'),
        (Join-Path $persistentRoot 'sessions\active\2026\07\26\rollout-test.jsonl')
    )) {
        $acl = Get-Acl -LiteralPath $protectedFile
        $currentUserRule = @(
            $acl.Access |
                Where-Object {
                    $_.IdentityReference -eq [Security.Principal.WindowsIdentity]::GetCurrent().Name -and
                    $_.AccessControlType -eq 'Allow' -and
                    ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq
                        [Security.AccessControl.FileSystemRights]::FullControl
                }
        )
        $allowedIdentities = @(
            $acl.Access |
                Where-Object { $_.AccessControlType -eq 'Allow' } |
                Select-Object -ExpandProperty IdentityReference -Unique
        )
        if (-not $acl.AreAccessRulesProtected -or
            $currentUserRule.Count -lt 1 -or
            $allowedIdentities.Count -ne 2 -or
            $allowedIdentities -notcontains 'NT AUTHORITY\SYSTEM') {
            throw "A persisted Codex file lacks a repeatable current-user ACL: $protectedFile"
        }
    }
    $expectedFiles = @(
        (Join-Path $persistentRoot 'auth\auth.json'),
        (Join-Path $persistentRoot 'config\config.toml'),
        (Join-Path $persistentRoot 'config\review.config.toml'),
        (Join-Path $persistentRoot 'sessions\active\2026\07\26\rollout-test.jsonl')
    )
    foreach ($path in $expectedFiles) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required Codex state was not persisted: $path"
        }
    }
    foreach ($excluded in @('history.jsonl', 'state_5.sqlite', 'logs_2.sqlite', 'cache')) {
        if (Test-Path -LiteralPath (Join-Path $persistentRoot $excluded)) {
            throw "Unverified Codex state was persisted: $excluded"
        }
    }

    $setupSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\setup.ps1') -Raw
    foreach ($requiredSetupText in @(
        'function Repair-CodexCli',
        'function Ensure-CodexLauncher',
        "'codex.cmd' = `$codexWrapper",
        'Repair-CodexCli',
        'Ensure-CodexLauncher'
    )) {
        if (-not $setupSource.Contains($requiredSetupText)) {
            throw "Setup is missing required Codex integration: $requiredSetupText"
        }
    }
    $removalStart = $setupSource.IndexOf('function Remove-ObsoleteGitHubCli')
    $removalEnd = $setupSource.IndexOf(
        'function Ensure-DeveloperDesktopShortcuts',
        $removalStart
    )
    if ($removalStart -lt 0 -or $removalEnd -le $removalStart) {
        throw 'Could not locate the managed GitHub CLI removal block.'
    }
    $removalBlock = $setupSource.Substring($removalStart, $removalEnd - $removalStart)
    if ($removalBlock -match '(?i)codex') {
        throw 'The GitHub CLI cleanup block still removes or mentions Codex.'
    }

    $replacementHome = Join-Path $testRoot 'replacement-home'
    if ((Invoke-StateScript -Action Initialize -SessionHome $replacementHome) -ne 0) {
        throw 'Replacement-machine Codex state restoration failed.'
    }
    foreach ($name in @('auth.json', 'config.toml', 'review.config.toml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $replacementHome $name) -PathType Leaf)) {
            throw "Replacement home is missing restored state: $name"
        }
    }
    $restoredSession = Join-Path $replacementHome 'sessions\2026\07\26\rollout-test.jsonl'
    if (-not (Test-Path -LiteralPath $restoredSession -PathType Leaf)) {
        throw 'Replacement home cannot discover the persisted session.'
    }
    $sessionItem = Get-Item -LiteralPath (Join-Path $replacementHome 'sessions') -Force
    if (-not ($sessionItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'The active session directory is not connected to persistent storage.'
    }

    $fakeCodex = Join-Path $testRoot 'fake-codex.cmd'
    @'
@echo off
echo %* | findstr /C:"cli_auth_credentials_store" >nul
if errorlevel 1 exit /b 31
> "%CODEX_HOME%\auth.json" <nul set /p="refreshed-fake-auth"
exit /b 7
'@ | Set-Content -LiteralPath $fakeCodex -Encoding utf8

    $runExit = Invoke-StateScript `
        -Action Run `
        -SessionHome $replacementHome `
        -CodexCommand $fakeCodex `
        -Arguments @('resume', '--last')
    if ($runExit -ne 7) {
        throw "The Codex launcher did not preserve the CLI exit code (received $runExit)."
    }
    $persistedAuthHash = (
        Get-FileHash -LiteralPath (Join-Path $persistentRoot 'auth\auth.json') -Algorithm SHA256
    ).Hash
    $replacementAuthHash = (
        Get-FileHash -LiteralPath (Join-Path $replacementHome 'auth.json') -Algorithm SHA256
    ).Hash
    if ($persistedAuthHash -ne $replacementAuthHash) {
        throw 'Refreshed authentication state was not synchronized after Codex exited.'
    }

    $fakeLogout = Join-Path $testRoot 'fake-codex-logout.cmd'
    @'
@echo off
del /q "%CODEX_HOME%\auth.json"
exit /b 0
'@ | Set-Content -LiteralPath $fakeLogout -Encoding utf8
    $logoutExit = Invoke-StateScript `
        -Action Run `
        -SessionHome $replacementHome `
        -CodexCommand $fakeLogout `
        -Arguments @('logout')
    if ($logoutExit -ne 0) {
        throw "The managed Codex logout failed (received $logoutExit)."
    }
    if (Test-Path -LiteralPath (Join-Path $persistentRoot 'auth\auth.json') -PathType Leaf) {
        throw 'A successful managed Codex logout left the persistent credential in place.'
    }

    $diagnosticText = Get-ChildItem -LiteralPath $testRoot -File |
        Where-Object { $_.Extension -in @('.out', '.err') } |
        Get-Content -Raw -ErrorAction SilentlyContinue
    if ($diagnosticText -match 'fake-auth-state|fake-session-state|refreshed-fake-auth|incomplete-fake-session-state') {
        throw 'Codex credential or session content appeared in launcher diagnostics.'
    }

    Write-Output 'Codex persistence test passed: SetupIntegration, ActiveSessionSnapshot, DeferredLinkSafety, SnapshotWatcher, AtomicSnapshotPromotion, UpgradeAclRecovery, Migration, RestrictedAcl, ReplacementRestore, SessionDiscovery, ForcedFileAuth, ExitCode, PostRunSync, LogoutPropagation, RedactedDiagnostics'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $resolvedTestRoot.StartsWith(
            $resolvedTempRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or (Split-Path -Leaf $resolvedTestRoot) -notmatch '^LimeNow-Codex-State-[a-f0-9]{32}$') {
            throw "Refusing to remove an unexpected test directory: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
