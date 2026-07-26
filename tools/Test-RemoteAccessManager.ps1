[CmdletBinding()]
param(
    [string]$LimeSshPath = (Join-Path $PSScriptRoot '..\artifacts\limessh-prototype.exe'),
    [string]$RelayPath = (Join-Path $PSScriptRoot '..\artifacts\uptermd-prototype.exe'),
    [string]$Server,
    [switch]$SkipGitHubEnrollment
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-RemoteAccess-E2E-' + [Guid]::NewGuid().ToString('N')
)
$relay = $null

function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

try {
    $requiredPaths = @($LimeSshPath)
    if (-not $Server) {
        $requiredPaths += $RelayPath
    }
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing prototype binary: $path"
        }
    }
    foreach ($command in @('ssh.exe', 'ssh-keygen.exe', 'scp.exe')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command is required for the remote-access manager test."
        }
    }

    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $isolatedLimeSshPath = Join-Path $testRoot 'LimeSSH-manager-test.exe'
    Copy-Item -LiteralPath $LimeSshPath -Destination $isolatedLimeSshPath
    $clientKey = Join-Path $testRoot 'client'
    $wrongKey = Join-Path $testRoot 'wrong-client'
    & ssh-keygen.exe -q -t ed25519 -N '' -f $clientKey
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the authorized test key.'
    }
    & ssh-keygen.exe -q -t ed25519 -N '' -f $wrongKey
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to create the rejected test key.'
    }

    if ($Server) {
        $serverAddress = $Server
    }
    else {
        $port = Get-FreeTcpPort
        $serverAddress = "ssh://127.0.0.1:$port"
        $relay = Start-Process `
            -FilePath $RelayPath `
            -ArgumentList '--ssh-addr', "127.0.0.1:$port" `
            -RedirectStandardOutput (Join-Path $testRoot 'relay.out') `
            -RedirectStandardError (Join-Path $testRoot 'relay.err') `
            -PassThru `
            -WindowStyle Hidden
        Start-Sleep -Seconds 1
        if ($relay.HasExited) {
            throw "uptermd exited during startup.`n$(Get-Content (Join-Path $testRoot 'relay.err') -Raw)"
        }
    }

    $manager = Join-Path $PSScriptRoot '..\remote-access.ps1'
    $installRoot = Join-Path $testRoot 'install'
    $stateRoot = Join-Path $testRoot 'state'
    $connectionPath = Join-Path $testRoot 'connection.txt'
    $publicKey = (Get-Content -LiteralPath "$clientKey.pub" -Raw).Trim()
    $managerArguments = @{
        InstallRoot = $installRoot
        StateRoot = $stateRoot
        LimeSshPath = $isolatedLimeSshPath
        ConnectionPath = $connectionPath
    }

    if (-not $SkipGitHubEnrollment) {
        $githubResult = & $manager `
            -Action Configure `
            -GitHubUser torvalds `
            -Server $serverAddress `
            @managerArguments
        $githubStatus = $githubResult |
            Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
            Select-Object -Last 1
        $githubConfig = Get-Content -LiteralPath (Join-Path $installRoot 'config.json') -Raw
        $githubAuthorizedKeys = Get-Content -LiteralPath (Join-Path $stateRoot 'authorized_keys')
        if (-not $githubStatus -or
            $githubConfig -notmatch '"GitHubUser":\s*"torvalds"' -or
            $githubAuthorizedKeys -notmatch '^ssh-') {
            throw 'GitHub public-key enrollment did not populate the authorized-key file.'
        }
        & $manager -Action Stop @managerArguments
    }

    $result = & $manager `
        -Action Configure `
        -PublicKey $publicKey `
        -Server $serverAddress `
        @managerArguments
    $status = $result |
        Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
        Select-Object -Last 1
    if (-not $status) {
        throw 'The manager did not return a LimeSSH session status.'
    }
    if ($status.SshCommand -notmatch '-o HostKeyAlias=limessh-' -or
        $status.SshCommand -notmatch '-o StrictHostKeyChecking=accept-new') {
        throw "The published SSH command lacks session-specific host-key protection: $($status.SshCommand)"
    }
    $shortPortOption = if ($status.Port -ne 22) { " -p $($status.Port)" } else { '' }
    $expectedShortCommand = "ssh$shortPortOption $($status.SessionId)@$($status.Host)"
    if ($status.ShortSshCommand -ne $expectedShortCommand -or
        $status.OneTimeClientConfig -notmatch 'StrictHostKeyChecking accept-new' -or
        $status.OneTimeClientConfig -notmatch [regex]::Escape(
            'UserKnownHostsFile ~/.ssh/limessh_known_hosts_%C'
        )) {
        throw 'The short SSH command or one-time host-key-safe client config is invalid.'
    }
    if ($status.ScpTemplate -notmatch [regex]::Escape("-o User=$($status.SessionId)") -or
        $status.SftpCommand -notmatch [regex]::Escape("-o User=$($status.SessionId)")) {
        throw 'SCP/SFTP commands do not safely pass the relay session as an explicit SSH user.'
    }
    $connectionText = if (Test-Path -LiteralPath $connectionPath) {
        Get-Content -LiteralPath $connectionPath -Raw
    }
    if (-not $connectionText -or
        $connectionText -notmatch [regex]::Escape($status.SshCommand) -or
        $connectionText -notmatch [regex]::Escape($status.ShortSshCommand) -or
        $connectionText -notmatch 'limessh_known_hosts_%C') {
        throw 'The manager did not write copyable connection details.'
    }
    $repeatResult = & $manager -Action Start @managerArguments
    $repeatStatus = $repeatResult |
        Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
        Select-Object -Last 1
    if (-not $repeatStatus -or $repeatStatus.ProcessId -ne $status.ProcessId) {
        throw 'A repeated start did not reuse the single managed LimeSSH process.'
    }

    $copyResult = & $manager -Action Copy @managerArguments
    $copyStatus = $copyResult |
        Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
        Select-Object -Last 1
    if (-not $copyStatus -or $copyStatus.ProcessId -ne $status.ProcessId) {
        throw 'The Copy action did not return the current managed session.'
    }

    $refreshResult = & $manager -Action Refresh @managerArguments
    $refreshStatus = $refreshResult |
        Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
        Select-Object -Last 1
    if (-not $refreshStatus -or
        $refreshStatus.SessionId -eq $status.SessionId -or
        $refreshStatus.StartedAt -eq $status.StartedAt) {
        throw 'The Refresh action did not fetch keys into a new relay session.'
    }

    $retryResult = & $manager -Action Retry @managerArguments
    $retryStatus = $retryResult |
        Where-Object { $_.PSObject.Properties.Name -contains 'SshCommand' } |
        Select-Object -Last 1
    if (-not $retryStatus -or
        $retryStatus.SessionId -eq $refreshStatus.SessionId -or
        $retryStatus.StartedAt -eq $refreshStatus.StartedAt) {
        throw 'The Retry action did not replace the relay session.'
    }
    $status = $retryStatus

    $target = "$($status.SessionId)@$($status.Host)"
    $common = @(
        '-T',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-p', ([string]$status.Port)
    )
    $wrongOutput = & ssh.exe @common -i $wrongKey $target 'echo REJECT_ME' 2>&1
    if ($LASTEXITCODE -eq 0) {
        throw "An unconfigured public key authenticated unexpectedly.`n$($wrongOutput -join [Environment]::NewLine)"
    }

    $execOutput = & ssh.exe @common -i $clientKey $target 'echo LIMESSH_MANAGER_OK' 2>&1
    if ($LASTEXITCODE -ne 0 -or $execOutput -notcontains 'LIMESSH_MANAGER_OK') {
        throw "The configured public key could not execute through LimeSSH.`n$($execOutput -join [Environment]::NewLine)"
    }

    $scpSource = Join-Path $testRoot 'manager-scp-source.txt'
    $scpRemote = Join-Path $testRoot 'manager-scp-remote.txt'
    Set-Content -LiteralPath $scpSource -Value 'LIMESSH_MANAGER_SCP_OK' -NoNewline
    $scpOutput = & scp.exe `
        -oBatchMode=yes `
        -oStrictHostKeyChecking=no `
        -oUserKnownHostsFile=NUL `
        "-oUser=$($status.SessionId)" `
        -i $clientKey `
        -P $status.Port `
        $scpSource `
        "$($status.Host):$scpRemote" 2>&1
    $scpContent = if (Test-Path -LiteralPath $scpRemote) {
        Get-Content -LiteralPath $scpRemote -Raw
    }
    if ($LASTEXITCODE -ne 0 -or $scpContent -ne 'LIMESSH_MANAGER_SCP_OK') {
        throw "The manager's SCP connection semantics failed.`n$($scpOutput -join [Environment]::NewLine)"
    }

    $config = Get-Content -LiteralPath (Join-Path $installRoot 'config.json') -Raw
    if ($config -notmatch [regex]::Escape($publicKey) -or
        $config -match 'BEGIN OPENSSH PRIVATE KEY') {
        throw 'The persisted configuration did not contain only expected public enrollment data.'
    }

    & $manager -Action Stop @managerArguments
    Start-Sleep -Seconds 1
    $stoppedOutput = & ssh.exe @common -i $clientKey $target 'echo SHOULD_NOT_RUN' 2>&1
    if ($LASTEXITCODE -eq 0) {
        throw "SSH access remained available after the LimeSSH process stopped.`n$($stoppedOutput -join [Environment]::NewLine)"
    }

    # The rejected post-stop SSH probe is the final native process in this
    # successful test. Do not leak its expected nonzero code to callers such as
    # the GitHub Actions PowerShell wrapper.
    $global:LASTEXITCODE = 0

    [pscustomobject]@{
        GitHubEnrollment = if ($SkipGitHubEnrollment) { 'skipped' } else { 'passed' }
        Enrollment = 'passed'
        SessionCommand = 'passed'
        ShortCommand = 'passed'
        CopyAction = 'passed'
        RefreshAction = 'passed'
        RetryAction = 'passed'
        SingleProcess = 'passed'
        AuthorizedKey = 'passed'
        RejectedKey = 'passed'
        ScpTemplate = 'passed'
        StopRevokesAccess = 'passed'
    }
}
finally {
    if ($relay -and -not $relay.HasExited) {
        $relay.Kill()
        $relay.WaitForExit(5000) | Out-Null
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRoot) -match '^LimeNow-RemoteAccess-E2E-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
