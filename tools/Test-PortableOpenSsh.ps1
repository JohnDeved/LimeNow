[CmdletBinding()]
param(
    [string]$OpenSshVersion = '10.0.0.0p2-Preview',
    [string]$ArchiveSha256 = '23f50f3458c4c5d0b12217c6a5ddfde0137210a30fa870e98b29827f7b43aba5',
    [ValidateRange(1024, 65535)][int]$Port = 42222
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-OpenSSH-Test-' + [Guid]::NewGuid().ToString('N')
)
$archive = Join-Path $testRoot 'OpenSSH-Win64.zip'
$packageRoot = Join-Path $testRoot 'OpenSSH-Win64'
$hostKey = Join-Path $testRoot 'ssh_host_ed25519_key'
$clientKey = Join-Path $testRoot 'client_ed25519'
$authorizedKeys = Join-Path $testRoot 'authorized_keys'
$config = Join-Path $testRoot 'sshd_config'
$serverLog = Join-Path $testRoot 'sshd.log'
$server = $null

function Invoke-TestSsh {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Name
    )

    $ssh = Join-Path $packageRoot 'ssh.exe'
    $output = & $ssh @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Name = $Name
        Passed = $exitCode -eq 0
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $archiveUrl = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/$OpenSshVersion/OpenSSH-Win64.zip"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing -TimeoutSec 120
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ArchiveSha256.ToLowerInvariant()) {
        throw "Archive checksum mismatch. Expected $ArchiveSha256 but received $actualHash."
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $testRoot

    $keygen = Join-Path $packageRoot 'ssh-keygen.exe'
    $sshd = Join-Path $packageRoot 'sshd.exe'
    foreach ($keyPath in @($hostKey, $clientKey)) {
        & $keygen -q -t ed25519 -N '' -f $keyPath
        if (-not $?) {
            throw "ssh-keygen failed for $keyPath."
        }
    }
    Copy-Item -LiteralPath "$clientKey.pub" -Destination $authorizedKeys

    $hostKeyConfig = $hostKey.Replace('\', '/')
    $authorizedKeysConfig = $authorizedKeys.Replace('\', '/')
    $pidFileConfig = (Join-Path $testRoot 'sshd.pid').Replace('\', '/')
    $sftpConfig = (Join-Path $packageRoot 'sftp-server.exe').Replace('\', '/')
    @"
Port $Port
ListenAddress 127.0.0.1
HostKey $hostKeyConfig
PidFile $pidFileConfig
AuthorizedKeysFile $authorizedKeysConfig
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitEmptyPasswords no
AllowAgentForwarding no
AllowTcpForwarding local
GatewayPorts no
X11Forwarding no
PermitTunnel no
StrictModes no
LogLevel DEBUG3
Subsystem sftp $sftpConfig
"@ | Set-Content -LiteralPath $config -Encoding ASCII

    & $sshd -t -f $config
    if (-not $?) {
        throw 'Generated sshd_config failed validation.'
    }

    $server = Start-Process -FilePath $sshd `
        -ArgumentList '-D', '-e', '-f', "`"$config`"" `
        -RedirectStandardError $serverLog -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 1
    if ($server.HasExited) {
        throw "sshd exited during startup.`n$(Get-Content -LiteralPath $serverLog -Raw)"
    }

    $common = @(
        '-T',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-i', $clientKey,
        '-p', ([string]$Port),
        "$env:USERNAME@127.0.0.1"
    )
    $commandResult = Invoke-TestSsh `
        -Name 'Non-interactive command' `
        -Arguments ($common + @('echo LIMENOW_OPENSSH_COMMAND_OK'))

    $sftp = Join-Path $packageRoot 'sftp.exe'
    $sftpOutput = 'pwd', 'quit' | & $sftp `
        -oBatchMode=yes `
        -oStrictHostKeyChecking=no `
        -oUserKnownHostsFile=NUL `
        -i $clientKey `
        -P $Port `
        "$env:USERNAME@127.0.0.1" 2>&1
    $sftpResult = [pscustomobject]@{
        Name = 'SFTP subsystem'
        Passed = $LASTEXITCODE -eq 0
        ExitCode = $LASTEXITCODE
        Output = ($sftpOutput -join [Environment]::NewLine)
    }

    $results = @($commandResult, $sftpResult)
    $results | Format-Table Name, Passed, ExitCode -AutoSize
    foreach ($result in $results | Where-Object { -not $_.Passed }) {
        Write-Host "`n$($result.Name):`n$($result.Output)"
    }
    if ($results.Passed -contains $false) {
        Write-Host "`nRelevant sshd log:"
        Get-Content -LiteralPath $serverLog |
            Select-String -Pattern 'token|shell:|spawn|CreateProcess|Starting session'
        throw 'Portable OpenSSH did not pass the Phase 1 baseline.'
    }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRoot) -match '^LimeNow-OpenSSH-Test-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
