[CmdletBinding()]
param(
    [ValidateSet('Start', 'Configure', 'Status', 'Stop')]
    [string]$Action = 'Start',
    [string]$GitHubUser,
    [string[]]$PublicKey,
    [string]$Server,
    [switch]$Disable,
    [switch]$Startup,
    [string]$InstallRoot = 'I:\Apps\LimeNow\LimeSSH',
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'LimeNow\RemoteAccess'),
    [string]$LimeSshPath,
    [string]$ConnectionPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$scriptArguments = @{} + $PSBoundParameters

if (-not $LimeSshPath) {
    $LimeSshPath = Join-Path $InstallRoot 'LimeSSH.exe'
}
$configPath = Join-Path $InstallRoot 'config.json'
$knownHostsPath = Join-Path $InstallRoot 'relay_known_hosts'
$authorizedKeysPath = Join-Path $StateRoot 'authorized_keys'
$statusPath = Join-Path $StateRoot 'session.json'
$hostOutputPath = Join-Path $StateRoot 'host.out'
$hostErrorPath = Join-Path $StateRoot 'host.err'
$managerLogPath = Join-Path $StateRoot 'manager.log'
if (-not $ConnectionPath) {
    $ConnectionPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'LimeSSH Connection.txt'
}
$connectionPath = $ConnectionPath
$defaultServer = 'ssh://uptermd.upterm.dev:22'

function Initialize-RemoteAccessStorage {
    New-Item -ItemType Directory -Path $InstallRoot, $StateRoot -Force | Out-Null
}

function Write-RemoteAccessLog {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0:yyyy-MM-dd HH:mm:ss zzz} [LimeSSH] {1}' -f [DateTimeOffset]::Now, $Message
    Add-Content -LiteralPath $managerLogPath -Value $line
    if (-not $Startup) {
        Write-Host $Message
    }
}

function Read-RemoteAccessConfig {
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "Remote-access configuration is invalid: $configPath"
    }
    if ($config.Version -ne 1) {
        throw "Unsupported remote-access configuration version: $($config.Version)"
    }
    return $config
}

function Write-RemoteAccessConfig {
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [AllowEmptyString()][string]$ConfiguredGitHubUser,
        [string[]]$ConfiguredPublicKeys,
        [Parameter(Mandatory)][string]$ConfiguredServer
    )

    $configuration = [ordered]@{
        Version = 1
        Enabled = $Enabled
        GitHubUser = $ConfiguredGitHubUser
        PublicKeys = @($ConfiguredPublicKeys)
        Server = $ConfiguredServer
    }
    $configuration |
        ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $configPath -Encoding utf8
}

function Test-GitHubUserName {
    param([Parameter(Mandatory)][string]$UserName)

    return $UserName.Length -le 39 -and
        $UserName -match '^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$' -and
        $UserName -notmatch '--'
}

function Test-SshPublicKey {
    param([Parameter(Mandatory)][string]$Key)

    return $Key.Trim() -match '^(?:ssh-(?:ed25519|rsa)|ecdsa-sha2-nistp(?:256|384|521)|sk-(?:ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com)\s+[A-Za-z0-9+/]+={0,3}(?:\s+.*)?$'
}

function Get-GitHubPublicKeys {
    param([Parameter(Mandatory)][string]$UserName)

    if (-not (Test-GitHubUserName -UserName $UserName)) {
        throw "Invalid GitHub username: $UserName"
    }
    $encodedUser = [Uri]::EscapeDataString($UserName)
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'LimeNow-LimeSSH'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $response = Invoke-RestMethod `
        -Uri "https://api.github.com/users/$encodedUser/keys" `
        -Headers $headers `
        -TimeoutSec 30
    return @($response | ForEach-Object key)
}

function Get-ConfiguredPublicKeys {
    param([Parameter(Mandatory)]$Config)

    $keys = [Collections.Generic.List[string]]::new()
    if ($Config.GitHubUser) {
        foreach ($key in Get-GitHubPublicKeys -UserName ([string]$Config.GitHubUser)) {
            $keys.Add(([string]$key).Trim())
        }
    }
    foreach ($key in @($Config.PublicKeys)) {
        if ($key) {
            $keys.Add(([string]$key).Trim())
        }
    }

    $uniqueKeys = @($keys | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($key in $uniqueKeys) {
        if (-not (Test-SshPublicKey -Key $key)) {
            throw 'The configured key list contains an invalid SSH public key.'
        }
    }
    if ($uniqueKeys.Count -eq 0) {
        $source = if ($Config.GitHubUser) {
            "GitHub user '$($Config.GitHubUser)' currently publishes no SSH keys"
        }
        else {
            'No SSH public keys are configured'
        }
        throw "$source. Add a public key before enabling remote access."
    }
    return $uniqueKeys
}

function Get-SessionStatus {
    if (-not (Test-Path -LiteralPath $statusPath)) {
        return $null
    }
    try {
        return Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-ManagedHostProcess {
    $status = Get-SessionStatus
    if (-not $status -or -not $status.ProcessId) {
        return $null
    }
    $process = Get-Process -Id ([int]$status.ProcessId) -ErrorAction SilentlyContinue
    if (-not $process) {
        return $null
    }
    try {
        $actualPath = [IO.Path]::GetFullPath($process.Path)
        $expectedPath = [IO.Path]::GetFullPath($LimeSshPath)
    }
    catch {
        return $null
    }
    if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    return $process
}

function Get-LimeSshProcesses {
    $processName = [IO.Path]::GetFileNameWithoutExtension($LimeSshPath)
    $expectedPath = [IO.Path]::GetFullPath($LimeSshPath)
    return @(Get-Process -Name $processName -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                [IO.Path]::GetFullPath($_.Path).Equals(
                    $expectedPath,
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
            catch {
                $false
            }
        })
}

function Remove-StaleSessionState {
    if (-not (Get-ManagedHostProcess)) {
        Remove-Item -LiteralPath $statusPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-SshConnectionDetails {
    param([Parameter(Mandatory)][string]$TargetLine)

    if ($TargetLine -notmatch '^\s*ssh\s+([^@\s]+)@([^\s]+?)(?:\s+-p\s+(\d+))?\s*$') {
        throw "Unable to parse the LimeSSH session address: $TargetLine"
    }
    $sessionUser = $Matches[1]
    $sessionHost = $Matches[2]
    $sessionPort = if ($Matches[3]) { [int]$Matches[3] } else { 22 }
    $safeSession = $sessionUser -replace '[^A-Za-z0-9_.-]', '-'
    $alias = "limessh-$safeSession"
    $portOption = if ($sessionPort -ne 22) { " -p $sessionPort" } else { '' }
    $commonOptions = "-o HostKeyAlias=$alias -o StrictHostKeyChecking=accept-new"
    $userOption = "-o User=$sessionUser"
    $target = "$sessionUser@$sessionHost"
    $sshCommand = "ssh $commonOptions$portOption $target"
    $scpPortOption = if ($sessionPort -ne 22) { " -P $sessionPort" } else { '' }
    $config = @"
Host $alias
    HostName $sessionHost
    User $sessionUser
    Port $sessionPort
    HostKeyAlias $alias
    StrictHostKeyChecking accept-new
"@
    return [pscustomobject]@{
        SessionId = $sessionUser
        Host = $sessionHost
        Port = $sessionPort
        Alias = $alias
        SshCommand = $sshCommand
        ScpTemplate = "scp $commonOptions $userOption$scpPortOption FILE $sessionHost`:DESTINATION"
        SftpCommand = "sftp $commonOptions $userOption$scpPortOption $sessionHost"
        SshConfig = $config
    }
}

function Show-ConnectionDetails {
    param([Parameter(Mandatory)]$Status)

    $text = @"
Remote access ready

$($Status.SshCommand)

SCP:
$($Status.ScpTemplate)

SFTP:
$($Status.SftpCommand)

Optional SSH config:
$($Status.SshConfig)
"@
    Set-Content -LiteralPath $connectionPath -Value $text -Encoding utf8
    if (-not $Startup) {
        Write-Host ''
        Write-Host 'Remote access ready' -ForegroundColor Green
        Write-Host ''
        Write-Host $Status.SshCommand -ForegroundColor Cyan
        Write-Host ''
        try {
            Set-Clipboard -Value $Status.SshCommand
            Write-Host 'The SSH command was copied to the clipboard.'
        }
        catch {
            Write-Host "Connection details were written to $connectionPath"
        }
    }
}

function Stop-LimeSsh {
    foreach ($process in Get-LimeSshProcesses) {
        $process.Kill()
        $process.WaitForExit(5000) | Out-Null
        Write-RemoteAccessLog "Stopped LimeSSH process $($process.Id)."
    }
    Remove-Item -LiteralPath $statusPath, $connectionPath -Force -ErrorAction SilentlyContinue
}

function Start-LimeSsh {
    $config = Read-RemoteAccessConfig
    if (-not $config -or -not $config.Enabled) {
        Write-RemoteAccessLog 'Remote access is not configured or is disabled.'
        return
    }
    if (-not (Test-Path -LiteralPath $LimeSshPath)) {
        throw "LimeSSH is not installed: $LimeSshPath"
    }

    $existing = Get-ManagedHostProcess
    $existingStatus = Get-SessionStatus
    if ($existing -and $existingStatus -and $existingStatus.SshCommand) {
        Show-ConnectionDetails -Status $existingStatus
        return $existingStatus
    }
    Remove-StaleSessionState
    foreach ($orphan in Get-LimeSshProcesses) {
        $orphan.Kill()
        $orphan.WaitForExit(5000) | Out-Null
        Write-RemoteAccessLog "Stopped orphaned LimeSSH process $($orphan.Id) before restart."
    }

    $keys = Get-ConfiguredPublicKeys -Config $config
    Set-Content -LiteralPath $authorizedKeysPath -Value $keys -Encoding ascii
    Remove-Item -LiteralPath $hostOutputPath, $hostErrorPath -Force -ErrorAction SilentlyContinue

    $arguments = @(
        'host',
        '--server', ([string]$config.Server),
        '--machine-mode',
        '--authorized-keys', $authorizedKeysPath,
        '--accept',
        '--skip-host-key-check',
        '--known-hosts', $knownHostsPath
    )
    $process = Start-Process `
        -FilePath $LimeSshPath `
        -ArgumentList $arguments `
        -RedirectStandardOutput $hostOutputPath `
        -RedirectStandardError $hostErrorPath `
        -PassThru `
        -WindowStyle Hidden

    try {
        $targetLine = $null
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        while ([DateTime]::UtcNow -lt $deadline -and -not $targetLine) {
            Start-Sleep -Milliseconds 250
            if ($process.HasExited) {
                $errorText = if (Test-Path -LiteralPath $hostErrorPath) {
                    Get-Content -LiteralPath $hostErrorPath -Raw
                }
                throw "LimeSSH exited during startup with code $($process.ExitCode).`n$errorText"
            }
            if (Test-Path -LiteralPath $hostOutputPath) {
                $targetLine = Get-Content -LiteralPath $hostOutputPath |
                    Where-Object { $_ -match '^\s*ssh\s+[^@\s]+@[^\s]+' } |
                    Select-Object -First 1
            }
        }
        if (-not $targetLine) {
            throw "Timed out waiting for LimeSSH to publish its session address. See $hostErrorPath"
        }

        $details = Get-SshConnectionDetails -TargetLine $targetLine
        $status = [ordered]@{
            Version = 1
            ProcessId = $process.Id
            StartedAt = [DateTimeOffset]::Now.ToString('o')
            Server = [string]$config.Server
            SessionId = $details.SessionId
            Host = $details.Host
            Port = $details.Port
            Alias = $details.Alias
            SshCommand = $details.SshCommand
            ScpTemplate = $details.ScpTemplate
            SftpCommand = $details.SftpCommand
            SshConfig = $details.SshConfig
        }
        $status |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $statusPath -Encoding utf8
        $statusObject = [pscustomobject]$status
        Show-ConnectionDetails -Status $statusObject
        Write-RemoteAccessLog "Started LimeSSH process $($process.Id) for session $($details.SessionId)."
        return $statusObject
    }
    catch {
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
        throw
    }
}

function Configure-LimeSsh {
    $existing = Read-RemoteAccessConfig
    $configuredServer = if ($Server) {
        $Server
    }
    elseif ($existing -and $existing.Server) {
        [string]$existing.Server
    }
    else {
        $defaultServer
    }

    if ($Disable) {
        Stop-LimeSsh
        Write-RemoteAccessConfig `
            -Enabled $false `
            -ConfiguredGitHubUser '' `
            -ConfiguredPublicKeys @() `
            -ConfiguredServer $configuredServer
        Write-RemoteAccessLog 'Remote access was disabled.'
        return
    }

    $configuredGitHubUser = $GitHubUser
    $configuredPublicKeys = @($PublicKey | Where-Object { $_ })
    $interactiveEnrollment = -not $scriptArguments.ContainsKey('GitHubUser') -and
        -not $scriptArguments.ContainsKey('PublicKey')
    if ($interactiveEnrollment) {
        $defaultUser = if ($existing) { [string]$existing.GitHubUser } else { '' }
        $prompt = 'GitHub username for remote access'
        if ($defaultUser) {
            $prompt += " [$defaultUser]"
        }
        $configuredGitHubUser = Read-Host "$prompt (leave blank to paste a public key)"
        if (-not $configuredGitHubUser -and $defaultUser) {
            $configuredGitHubUser = $defaultUser
        }
        if (-not $configuredGitHubUser) {
            $pastedKey = Read-Host 'Paste your personal PC SSH public key (leave blank to disable)'
            if ($pastedKey) {
                $configuredPublicKeys = @($pastedKey)
            }
        }
    }

    if (-not $configuredGitHubUser -and $configuredPublicKeys.Count -eq 0) {
        Stop-LimeSsh
        Write-RemoteAccessConfig `
            -Enabled $false `
            -ConfiguredGitHubUser '' `
            -ConfiguredPublicKeys @() `
            -ConfiguredServer $configuredServer
        Write-RemoteAccessLog 'Remote access remains disabled because no public key was configured.'
        return
    }
    if ($configuredGitHubUser -and -not (Test-GitHubUserName -UserName $configuredGitHubUser)) {
        throw "Invalid GitHub username: $configuredGitHubUser"
    }
    foreach ($key in $configuredPublicKeys) {
        if (-not (Test-SshPublicKey -Key $key)) {
            throw 'The pasted value is not a supported SSH public key.'
        }
    }

    $candidate = [pscustomobject]@{
        GitHubUser = $configuredGitHubUser
        PublicKeys = $configuredPublicKeys
    }
    try {
        [void](Get-ConfiguredPublicKeys -Config $candidate)
    }
    catch {
        if (-not $interactiveEnrollment -or
            -not $configuredGitHubUser -or
            $configuredPublicKeys.Count -gt 0) {
            throw
        }
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        $fallbackKey = Read-Host 'Paste your personal PC SSH public key instead (leave blank to cancel)'
        if (-not $fallbackKey) {
            throw
        }
        if (-not (Test-SshPublicKey -Key $fallbackKey)) {
            throw 'The pasted value is not a supported SSH public key.'
        }
        $configuredPublicKeys = @($fallbackKey)
        $candidate.PublicKeys = $configuredPublicKeys
        [void](Get-ConfiguredPublicKeys -Config $candidate)
    }
    Stop-LimeSsh
    Write-RemoteAccessConfig `
        -Enabled $true `
        -ConfiguredGitHubUser $configuredGitHubUser `
        -ConfiguredPublicKeys $configuredPublicKeys `
        -ConfiguredServer $configuredServer
    Write-RemoteAccessLog 'Saved public-key-only remote-access configuration.'
    return Start-LimeSsh
}

Initialize-RemoteAccessStorage

try {
    switch ($Action) {
        'Configure' {
            Configure-LimeSsh
        }
        'Start' {
            Start-LimeSsh
        }
        'Status' {
            Remove-StaleSessionState
            $status = Get-SessionStatus
            if ($status) {
                Show-ConnectionDetails -Status $status
                $status
            }
            else {
                Write-RemoteAccessLog 'LimeSSH is not running.'
            }
        }
        'Stop' {
            Stop-LimeSsh
        }
    }
}
catch {
    Write-RemoteAccessLog "ERROR: $($_.Exception.Message)"
    if (-not $Startup) {
        throw
    }
}
