[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('Initialize', 'Snapshot', 'Watch', 'Run', 'Sync')]
    [string]$Action = 'Run',
    [string]$PersistentRoot = 'I:\Apps\LimeNow\Codex',
    [string]$SessionCodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$CodexCommand = 'I:\Apps\LimeNow\NpmGlobal\codex.cmd',
    [ValidateRange(1, 3600)]
    [int]$WatchIntervalSeconds = 5,
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
        if ($Destination.EndsWith('.jsonl', [StringComparison]::OrdinalIgnoreCase)) {
            $sourceItem = Get-Item -LiteralPath $Source
            $destinationItem = Get-Item -LiteralPath $Destination
            $copyRequired = $sourceItem.Length -ne $destinationItem.Length -or
                $sourceItem.LastWriteTimeUtc -ne $destinationItem.LastWriteTimeUtc
        }
        else {
            $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
            $copyRequired = $sourceHash -ne $destinationHash
        }
    }
    if ($copyRequired) {
        $temporaryName = '.{0}.limenow-copy-{1}.tmp' -f (
            Split-Path -Leaf $Destination
        ), [Guid]::NewGuid().ToString('N')
        $temporaryPath = Join-Path $destinationParent $temporaryName
        try {
            Copy-Item -LiteralPath $Source -Destination $temporaryPath -Force
            if ($Destination.EndsWith('.jsonl', [StringComparison]::OrdinalIgnoreCase)) {
                $stream = [IO.File]::Open(
                    $temporaryPath,
                    [IO.FileMode]::Open,
                    [IO.FileAccess]::Read,
                    [IO.FileShare]::Read
                )
                try {
                    if ($stream.Length -eq 0) {
                        return
                    }
                    [void]$stream.Seek(-1, [IO.SeekOrigin]::End)
                    if ($stream.ReadByte() -ne 10) {
                        return
                    }
                }
                finally {
                    $stream.Dispose()
                }
            }
            Move-Item -LiteralPath $temporaryPath -Destination $Destination -Force
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }
}

function Copy-DirectoryMerge {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [switch]$BestEffort
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    $sourceRoot = (Get-FullPath -Path $Source) + '\'
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse -Force) {
        try {
            $relativePath = $file.FullName.Substring($sourceRoot.Length)
            $target = Join-Path $Destination $relativePath
            $targetParent = Split-Path -Parent $target
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or
                $file.LastWriteTimeUtc -gt (Get-Item -LiteralPath $target).LastWriteTimeUtc) {
                Copy-FileIfDifferent -Source $file.FullName -Destination $target
            }
        }
        catch {
            if (-not $BestEffort) {
                throw
            }
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
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $fullControl = [Security.AccessControl.FileSystemRights]::FullControl
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($rootPath in $Paths) {
        $aclSucceeded = $true
        $items = @(
            Get-Item -LiteralPath $rootPath -Force
        ) + @(
            Get-ChildItem -LiteralPath $rootPath -Force -Recurse -ErrorAction SilentlyContinue
        )
        foreach ($item in $items) {
            try {
                if ($item.PSIsContainer) {
                    $acl = [Security.AccessControl.DirectorySecurity]::new()
                    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
                    $propagation = [Security.AccessControl.PropagationFlags]::None
                    $acl.AddAccessRule(
                        [Security.AccessControl.FileSystemAccessRule]::new(
                            $userSid,
                            $fullControl,
                            $inheritance,
                            $propagation,
                            $allow
                        )
                    )
                    $acl.AddAccessRule(
                        [Security.AccessControl.FileSystemAccessRule]::new(
                            $systemSid,
                            $fullControl,
                            $inheritance,
                            $propagation,
                            $allow
                        )
                    )
                }
                else {
                    $acl = [Security.AccessControl.FileSecurity]::new()
                    $acl.AddAccessRule(
                        [Security.AccessControl.FileSystemAccessRule]::new(
                            $userSid,
                            $fullControl,
                            $allow
                        )
                    )
                    $acl.AddAccessRule(
                        [Security.AccessControl.FileSystemAccessRule]::new(
                            $systemSid,
                            $fullControl,
                            $allow
                        )
                    )
                }
                $acl.SetOwner($userSid)
                $acl.SetAccessRuleProtection($true, $false)
                Set-Acl -LiteralPath $item.FullName -AclObject $acl
            }
            catch {
                $grantSuffix = if ($item.PSIsContainer) {
                    '(OI)(CI)F'
                }
                else {
                    'F'
                }
                $userGrant = "*$($userSid.Value):$grantSuffix"
                $systemGrant = "*$($systemSid.Value):$grantSuffix"
                try {
                    & icacls.exe $item.FullName /inheritance:r /grant:r $userGrant $systemGrant /Q 2>$null |
                        Out-Null
                    if ($LASTEXITCODE -ne 0) {
                        throw 'ACL recovery grant failed.'
                    }
                }
                catch {
                    $aclSucceeded = $false
                }
            }
        }
        if (-not $aclSucceeded) {
            Write-Warning "Could not restrict every item in the managed Codex state directory: $rootPath"
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

function Initialize-StateLayout {
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
    foreach ($rootPath in @($layout.AuthRoot, $layout.SessionsRoot, $layout.ConfigRoot)) {
        Get-ChildItem `
            -LiteralPath $rootPath `
            -Filter '.*.limenow-copy-*.tmp' `
            -File `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue |
            Remove-Item -Force
    }

    New-Item -ItemType Directory -Path $SessionCodexHome -Force | Out-Null
    return $layout
}

function Sync-CodexState {
    param(
        [switch]$RemoveMissingAuth,
        [switch]$BestEffort
    )

    $layout = Get-StateLayout
    $localAuth = Join-Path $SessionCodexHome 'auth.json'
    if ($RemoveMissingAuth -and
        -not (Test-Path -LiteralPath $localAuth -PathType Leaf) -and
        (Test-Path -LiteralPath $layout.AuthFile -PathType Leaf)) {
        Remove-Item -LiteralPath $layout.AuthFile -Force
    }
    else {
        try {
            Copy-FileIfDifferent -Source $localAuth -Destination $layout.AuthFile
        }
        catch {
            if (-not $BestEffort) {
                throw
            }
        }
    }
    try {
        Copy-FileIfDifferent `
            -Source (Join-Path $SessionCodexHome 'config.toml') `
            -Destination $layout.ConfigFile
    }
    catch {
        if (-not $BestEffort) {
            throw
        }
    }
    foreach ($profile in Get-ChildItem -LiteralPath $SessionCodexHome -Filter '*.config.toml' -File -Force) {
        try {
            Copy-FileIfDifferent `
                -Source $profile.FullName `
                -Destination (Join-Path $layout.ConfigRoot $profile.Name)
        }
        catch {
            if (-not $BestEffort) {
                throw
            }
        }
    }
}

function Copy-CodexSessionSnapshots {
    $layout = Get-StateLayout
    foreach ($mapping in @(
        @{
            Local = Join-Path $SessionCodexHome 'sessions'
            Persistent = $layout.ActiveSessions
        },
        @{
            Local = Join-Path $SessionCodexHome 'archived_sessions'
            Persistent = $layout.ArchivedSessions
        }
    )) {
        if (-not (Test-Path -LiteralPath $mapping.Local -PathType Container)) {
            continue
        }
        $linkTarget = Get-LinkTarget -Path $mapping.Local
        if ($linkTarget -and $linkTarget -eq (Get-FullPath -Path $mapping.Persistent)) {
            continue
        }
        Copy-DirectoryMerge `
            -Source $mapping.Local `
            -Destination $mapping.Persistent `
            -BestEffort
    }
}

function Test-ShouldDeferSessionLinks {
    $defaultCodexHome = Get-FullPath -Path (Join-Path $env:USERPROFILE '.codex')
    if ((Get-FullPath -Path $SessionCodexHome) -ne $defaultCodexHome) {
        return $false
    }
    return @(Get-Process -Name 'codex' -ErrorAction SilentlyContinue).Count -gt 0
}

function Get-WatcherMutexName {
    $identity = '{0}|{1}' -f (
        Get-FullPath -Path $PersistentRoot
    ).ToLowerInvariant(), (
        Get-FullPath -Path $SessionCodexHome
    ).ToLowerInvariant()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))
    }
    finally {
        $sha256.Dispose()
    }
    $suffix = ([BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 24)
    return "Local\LimeNowCodexStateWatcher-$suffix"
}

function Start-CodexSnapshotWatcher {
    $powerShellPath = (Get-Process -Id $PID).Path
    $watcherArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $PSCommandPath,
        '-Action',
        'Watch',
        '-PersistentRoot',
        $PersistentRoot,
        '-SessionCodexHome',
        $SessionCodexHome,
        '-WatchIntervalSeconds',
        ([string]$WatchIntervalSeconds)
    )
    if ($SkipAcl) {
        $watcherArguments += '-SkipAcl'
    }
    Start-Process `
        -FilePath $powerShellPath `
        -ArgumentList $watcherArguments `
        -WindowStyle Hidden | Out-Null
}

function Watch-CodexState {
    $mutex = [Threading.Mutex]::new($false, (Get-WatcherMutexName))
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne(0)
        }
        catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            return
        }

        [void](Initialize-StateLayout)
        while ($true) {
            try {
                Sync-CodexState -BestEffort
                Copy-CodexSessionSnapshots
            }
            catch {
                # Keep the watcher silent and retry; state contents and file names
                # must not be copied into background diagnostics.
            }
            if (-not (Test-ShouldDeferSessionLinks)) {
                return
            }
            Start-Sleep -Seconds $WatchIntervalSeconds
        }
    }
    finally {
        if ($ownsMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Initialize-CodexState {
    param([switch]$DeferSessionLinks)

    $layout = Initialize-StateLayout
    if ($DeferSessionLinks) {
        Sync-CodexState -BestEffort
        Copy-CodexSessionSnapshots
        return $false
    }

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

    # Close the small race where Codex starts after the caller's initial process
    # check but before the local rollout directories are replaced.
    if (Test-ShouldDeferSessionLinks) {
        Sync-CodexState -BestEffort
        Copy-CodexSessionSnapshots
        return $false
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
    return $true
}

switch ($Action) {
    'Initialize' {
        $deferSessionLinks = Test-ShouldDeferSessionLinks
        $linksReady = Initialize-CodexState -DeferSessionLinks:$deferSessionLinks
        if ($linksReady) {
            Write-Output 'Codex persistence is ready (auth, sessions, and config only).'
        }
        else {
            Start-CodexSnapshotWatcher
            Write-Output 'Codex state was snapshotted; session links are deferred until Codex exits.'
        }
    }
    'Snapshot' {
        [void](Initialize-CodexState -DeferSessionLinks)
        Write-Output 'Codex state was snapshotted without changing active session directories.'
    }
    'Watch' {
        Watch-CodexState
    }
    'Sync' {
        $deferSessionLinks = Test-ShouldDeferSessionLinks
        $linksReady = Initialize-CodexState -DeferSessionLinks:$deferSessionLinks
        Sync-CodexState
        if (-not $linksReady) {
            Copy-CodexSessionSnapshots
        }
        Write-Output 'Codex auth and config state synchronized.'
    }
    'Run' {
        if (-not (Test-Path -LiteralPath $CodexCommand -PathType Leaf)) {
            throw "Codex command is missing: $CodexCommand"
        }
        $deferSessionLinks = Test-ShouldDeferSessionLinks
        $linksReady = Initialize-CodexState -DeferSessionLinks:$deferSessionLinks
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
            if (-not $linksReady) {
                Copy-CodexSessionSnapshots
            }
        }
        exit $codexExitCode
    }
}
