[CmdletBinding()]
param(
    [string]$LimeSshPath = (Join-Path $PSScriptRoot '..\artifacts\limessh-prototype.exe'),
    [string]$RelayPath = (Join-Path $PSScriptRoot '..\artifacts\uptermd-prototype.exe'),
    [ValidateRange(1024, 65535)][int]$Port = 43222
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-LimeSSH-E2E-' + [Guid]::NewGuid().ToString('N')
)
$relay = $null
$hostProcess = $null

try {
    foreach ($path in @($LimeSshPath, $RelayPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing prototype binary: $path. Run tools\Build-LimeSshPrototype.ps1 first."
        }
    }
    foreach ($command in @('ssh.exe', 'ssh-keygen.exe', 'sftp.exe')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command is required for the end-to-end test."
        }
    }

    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $clientKey = Join-Path $testRoot 'client'
    & ssh-keygen.exe -q -t ed25519 -N '' -f $clientKey
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the temporary client key.'
    }

    $relay = Start-Process `
        -FilePath $RelayPath `
        -ArgumentList '--ssh-addr', "127.0.0.1:$Port" `
        -RedirectStandardOutput (Join-Path $testRoot 'relay.out') `
        -RedirectStandardError (Join-Path $testRoot 'relay.err') `
        -PassThru `
        -WindowStyle Hidden
    Start-Sleep -Seconds 1
    if ($relay.HasExited) {
        throw "uptermd exited during startup.`n$(Get-Content (Join-Path $testRoot 'relay.err') -Raw)"
    }

    $hostOutput = Join-Path $testRoot 'host.out'
    $hostError = Join-Path $testRoot 'host.err'
    $hostProcess = Start-Process `
        -FilePath $LimeSshPath `
        -ArgumentList @(
            'host',
            '--server', "ssh://127.0.0.1:$Port",
            '--machine-mode',
            '--authorized-keys', "$clientKey.pub",
            '--accept',
            '--skip-host-key-check',
            '--known-hosts', (Join-Path $testRoot 'known_hosts')
        ) `
        -RedirectStandardOutput $hostOutput `
        -RedirectStandardError $hostError `
        -PassThru `
        -WindowStyle Hidden

    $sshTarget = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline -and -not $sshTarget) {
        Start-Sleep -Milliseconds 250
        if ($hostProcess.HasExited) {
            throw "LimeSSH exited during startup.`n$(Get-Content $hostError -Raw)"
        }
        if (Test-Path -LiteralPath $hostOutput) {
            $line = Get-Content -LiteralPath $hostOutput |
                Where-Object { $_ -match "^\s+ssh (.+@127\.0\.0\.1) -p $Port$" } |
                Select-Object -First 1
            if ($line -match "^\s+ssh (.+@127\.0\.0\.1) -p $Port$") {
                $sshTarget = $Matches[1]
            }
        }
    }
    if (-not $sshTarget) {
        throw 'Timed out waiting for LimeSSH to publish its session address.'
    }

    $common = @(
        '-T',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-i', $clientKey,
        '-p', ([string]$Port),
        $sshTarget
    )
    $execOutput = & ssh.exe @common 'echo LIMESSH_EXEC_OK' 2>&1
    if ($LASTEXITCODE -ne 0 -or $execOutput -notcontains 'LIMESSH_EXEC_OK') {
        throw "Machine-mode exec failed.`n$($execOutput -join [Environment]::NewLine)"
    }

    & ssh.exe @common 'exit /b 7' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 7) {
        throw "Machine-mode exit status was $LASTEXITCODE instead of 7."
    }

    $sessionUser, $sessionHost = $sshTarget -split '@', 2
    $sftpOutput = 'pwd', 'quit' | & sftp.exe `
        -oBatchMode=yes `
        -oStrictHostKeyChecking=no `
        -oUserKnownHostsFile=NUL `
        "-oUser=$sessionUser" `
        -i $clientKey `
        -P $Port `
        $sessionHost 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SFTP validation failed.`n$($sftpOutput -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        SessionTarget = $sshTarget
        Exec = 'passed'
        ExitStatus = 'passed'
        Sftp = 'passed'
    }
}
finally {
    foreach ($process in @($hostProcess, $relay)) {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRoot) -match '^LimeNow-LimeSSH-E2E-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
