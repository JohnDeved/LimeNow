[CmdletBinding()]
param(
    [ValidateSet('Initialize', 'Run', 'Sync')]
    [string]$Action = 'Run',
    [string]$PersistentRoot = 'I:\Apps\LimeNow\Codex',
    [string]$SessionCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$CodexCommand = 'I:\Apps\LimeNow\NpmGlobal\codex.cmd',
    [switch]$SkipAcl,
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$CodexArguments
)

$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([Parameter(Mandatory)][string]$Path)

    return [IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Assert-ManagedRoot {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = Get-FullPath -Path $Path
    $pathRoot = [IO.Path]::GetPathRoot($fullPath).TrimEnd('\')
    if ($fullPath -eq $pathRoot) {
        throw "Refusing to manage a volume root: $fullPath"
    }
}

function Copy-FileIfDifferent {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return
    }

    $destinationParent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    $copyRequired = -not (Test-Path -LiteralPath $Destination -PathType Leaf)
    if (-not $copyRequired) {
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        $copyRequired = $sourceHash -ne $destinationHash
    }
    if ($copyRequired) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Copy-DirectoryMerge {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    $sourceRoot = (Get-FullPath -Path $Source) + '\'
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        $relativePath = $file.FullName.Substring($sourceRoot.Length)
        $target = Join-Path $Destination $relativePath
        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
            $file.LastWriteTimeUtc -gt (Get-Item -LiteralPath $target).LastWriteTimeUtc) {
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        }
    }
}

function Get-LinkTarget {
    param([Parameter(Mandatory)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        return $null
    }
    $target = @($item.Target) | Select-Object -First 1
    if (-not $target -and $item.PSObject.Properties.Name -contains 'LinkTarget') {
        $target = $item.LinkTarget
    }
    if (-not $target) {
        throw "Unable to resolve the existing directory link: $Path"
    }
    return Get-FullPath -Path $target
}

function Ensure-PersistentDirectoryLink {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$PersistentPath
    )

    New-Item -ItemType Directory -Path $PersistentPath -Force | Out-Null
    if (Test-Path -LiteralPath $LocalPath) {
        $existingTarget = Get-LinkTarget -Path $LocalPath
        if ($existingTarget) {
            if ($existingTarget -ne (Get-FullPath -Path $PersistentPath)) {
                throw "Preserved an unrelated directory link instead of replacing it: $LocalPath"
            }
            return
        }

        Copy-DirectoryMerge -Source $LocalPath -Destination $PersistentPath
        $backupPath = "$LocalPath.limenow-migrated-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
        Move-Item -LiteralPath $LocalPath -Destination $backupPath
        try {
            New-Item -ItemType Junction -Path $LocalPath -Target $PersistentPath | Out-Null
        }
        catch {
            Move-Item -LiteralPath $backupPath -Destination $LocalPath
            throw
        }
    }
    else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $LocalPath) -Force | Out-Null
        New-Item -ItemType Junction -Path $LocalPath -Target $PersistentPath | Out-Null
    }
}

function Protect-PersistentState {
    param([Parameter(Mandatory)][string[]]$Paths)

    if ($SkipAcl) {
        return
    }
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $userGrant = "*${userSid}:(OI)(CI)F"
    $systemGrant = '*S-1-5-18:(OI)(CI)F'
    foreach ($path in $Paths) {
        $aclSucceeded = $false
        try {
            & icacls.exe $path /inheritance:r /grant:r $userGrant $systemGrant /T /C /Q 2>$null |
                Out-Null
            $aclSucceeded = $LASTEXITCODE -eq 0
        }
        catch {
            # The warning below deliberately includes only the managed directory path.
        }
        if (-not $aclSucceeded) {
            Write-Warning "Could not restrict permissions on the managed Codex state directory: $path"
        }
    }
}

function Get-StateLayout {
    $authRoot = Join-Path $PersistentRoot 'auth'
    $sessionsRoot = Join-Path $PersistentRoot 'sessions'
    $configRoot = Join-Path $PersistentRoot 'config'
    return [pscustomobject]@{
        AuthRoot = $authRoot
        AuthFile = Join-Path $authRoot 'auth.json'
        SessionsRoot = $sessionsRoot
        ActiveSessions = Join-Path $sessionsRoot 'active'
        ArchivedSessions = Join-Path $sessionsRoot 'archived'
        ConfigRoot = $configRoot
        ConfigFile = Join-Path $configRoot 'config.toml'
    }
}

function Initialize-CodexState {
    Assert-ManagedRoot -Path $PersistentRoot
    Assert-ManagedRoot -Path $SessionCodexHome
    $layout = Get-StateLayout
    New-Item -ItemType Directory -Path @(
        $layout.AuthRoot,
        $layout.ActiveSessions,
        $layout.ArchivedSessions,
        $layout.ConfigRoot
    ) -Force | Out-Null
    Protect-PersistentState -Paths @(
        $layout.AuthRoot,
        $layout.SessionsRoot,
        $layout.ConfigRoot
    )

    New-Item -ItemType Directory -Path $SessionCodexHome -Force | Out-Null

    $localAuth = Join-Path $SessionCodexHome 'auth.json'
    if (-not (Test-Path -LiteralPath $layout.AuthFile -PathType Leaf)) {
        Copy-FileIfDifferent -Source $localAuth -Destination $layout.AuthFile
    }
    $localConfig = Join-Path $SessionCodexHome 'config.toml'
    if (-not (Test-Path -LiteralPath $layout.ConfigFile -PathType Leaf)) {
        Copy-FileIfDifferent -Source $localConfig -Destination $layout.ConfigFile
    }
    foreach ($profile in Get-ChildItem -LiteralPath $SessionCodexHome -Filter '*.config.toml' -File -Force) {
        $persistentProfile = Join-Path $layout.ConfigRoot $profile.Name
        if (-not (Test-Path -LiteralPath $persistentProfile -PathType Leaf)) {
            Copy-FileIfDifferent -Source $profile.FullName -Destination $persistentProfile
        }
    }

    Ensure-PersistentDirectoryLink `
        -LocalPath (Join-Path $SessionCodexHome 'sessions') `
        -PersistentPath $layout.ActiveSessions
    Ensure-PersistentDirectoryLink `
        -LocalPath (Join-Path $SessionCodexHome 'archived_sessions') `
        -PersistentPath $layout.ArchivedSessions

    Copy-FileIfDifferent -Source $layout.AuthFile -Destination $localAuth
    Copy-FileIfDifferent -Source $layout.ConfigFile -Destination $localConfig
    foreach ($profile in Get-ChildItem -LiteralPath $layout.ConfigRoot -Filter '*.config.toml' -File -Force) {
        Copy-FileIfDifferent `
            -Source $profile.FullName `
            -Destination (Join-Path $SessionCodexHome $profile.Name)
    }
}

function Sync-CodexState {
    param([switch]$RemoveMissingAuth)

    $layout = Get-StateLayout
    $localAuth = Join-Path $SessionCodexHome 'auth.json'
    if ($RemoveMissingAuth -and
        -not (Test-Path -LiteralPath $localAuth -PathType Leaf) -and
        (Test-Path -LiteralPath $layout.AuthFile -PathType Leaf)) {
        Remove-Item -LiteralPath $layout.AuthFile -Force
    }
    else {
        Copy-FileIfDifferent -Source $localAuth -Destination $layout.AuthFile
    }
    Copy-FileIfDifferent `
        -Source (Join-Path $SessionCodexHome 'config.toml') `
        -Destination $layout.ConfigFile
    foreach ($profile in Get-ChildItem -LiteralPath $SessionCodexHome -Filter '*.config.toml' -File -Force) {
        Copy-FileIfDifferent `
            -Source $profile.FullName `
            -Destination (Join-Path $layout.ConfigRoot $profile.Name)
    }
}

switch ($Action) {
    'Initialize' {
        Initialize-CodexState
        Write-Output 'Codex persistence is ready (auth, sessions, and config only).'
    }
    'Sync' {
        Initialize-CodexState
        Sync-CodexState
        Write-Output 'Codex auth and config state synchronized.'
    }
    'Run' {
        if (-not (Test-Path -LiteralPath $CodexCommand -PathType Leaf)) {
            throw "Codex command is missing: $CodexCommand"
        }
        Initialize-CodexState
        $env:CODEX_HOME = $SessionCodexHome
        $launchArguments = @(
            '-c',
            'cli_auth_credentials_store="file"'
        ) + @($CodexArguments)
        try {
            & $CodexCommand @launchArguments
            $codexExitCode = $LASTEXITCODE
        }
        finally {
            $successfulLogout = $codexExitCode -eq 0 -and
                $CodexArguments.Count -gt 0 -and
                $CodexArguments[0] -eq 'logout'
            Sync-CodexState -RemoveMissingAuth:$successfulLogout
        }
        exit $codexExitCode
    }
}
