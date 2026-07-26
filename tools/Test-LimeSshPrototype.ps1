[CmdletBinding()]
param(
    [string]$LimeSshPath = (Join-Path $PSScriptRoot '..\artifacts\limessh-prototype.exe'),
    [string]$RelayPath = (Join-Path $PSScriptRoot '..\artifacts\uptermd-prototype.exe'),
    [string]$MachineShell = 'cmd.exe /d /q /k',
    [switch]$SkipInteractive,
    [ValidateRange(1024, 65535)][int]$Port = 43222
)

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-LimeSSH-E2E-' + [Guid]::NewGuid().ToString('N')
)
$relay = $null
$hostProcess = $null
$testProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()

function Start-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.RedirectStandardInput = $true
    foreach ($argument in $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start $FilePath."
    }
    $testProcesses.Add($process)
    return $process
}

function Complete-CapturedProcess {
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 30
    )

    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        $Process.Kill($true)
        throw "Process $($Process.StartInfo.FileName) timed out."
    }
    [pscustomobject]@{
        ExitCode = $Process.ExitCode
        Stdout = $Process.StandardOutput.ReadToEnd()
        Stderr = $Process.StandardError.ReadToEnd()
    }
}

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
    foreach ($path in @($LimeSshPath, $RelayPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Missing prototype binary: $path. Run tools\Build-LimeSshPrototype.ps1 first."
        }
    }
    foreach ($command in @('ssh.exe', 'ssh-keygen.exe', 'sftp.exe', 'scp.exe')) {
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
            '--machine-shell', "`"$MachineShell`"",
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

    $interactiveStatus = 'skipped'
    if (-not $SkipInteractive) {
        $interactive = Start-CapturedProcess `
            -FilePath (Get-Command ssh.exe).Source `
            -Arguments @(
                '-tt',
                '-o', 'BatchMode=yes',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=NUL',
                '-i', $clientKey,
                '-p', ([string]$Port),
                $sshTarget
        )
        $interactive.StandardInput.WriteLine('echo LIMESSH_INTERACTIVE_OK')
        $interactive.StandardInput.Flush()
        $interactiveLines = [Collections.Generic.List[string]]::new()
        $interactiveDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while ([DateTime]::UtcNow -lt $interactiveDeadline -and
            -not ($interactiveLines -match 'LIMESSH_INTERACTIVE_OK')) {
            $lineTask = $interactive.StandardOutput.ReadLineAsync()
            if (-not $lineTask.Wait(1000)) {
                break
            }
            if ($null -eq $lineTask.Result) {
                break
            }
            $interactiveLines.Add($lineTask.Result)
        }
        $interactive.StandardInput.WriteLine('exit')
        $interactive.StandardInput.Flush()
        $interactiveResult = Complete-CapturedProcess -Process $interactive
        if ($interactiveResult.ExitCode -ne 0 -or
            $interactiveLines -notmatch 'LIMESSH_INTERACTIVE_OK') {
            throw "Interactive ConPTY validation failed (exit $($interactiveResult.ExitCode)).`nstdout:`n$($interactiveLines -join [Environment]::NewLine)`n$($interactiveResult.Stdout)`nstderr:`n$($interactiveResult.Stderr)"
        }
        $interactiveStatus = 'passed'
    }

    $concurrentArgs = @(
        '-T',
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=no',
        '-o', 'UserKnownHostsFile=NUL',
        '-i', $clientKey,
        '-p', ([string]$Port),
        $sshTarget
    )
    $first = Start-CapturedProcess `
        -FilePath (Get-Command ssh.exe).Source `
        -Arguments ($concurrentArgs + @('ping -n 3 127.0.0.1 >NUL & echo LIMESSH_CONCURRENT_ONE'))
    $second = Start-CapturedProcess `
        -FilePath (Get-Command ssh.exe).Source `
        -Arguments ($concurrentArgs + @('ping -n 3 127.0.0.1 >NUL & echo LIMESSH_CONCURRENT_TWO'))
    $firstResult = Complete-CapturedProcess -Process $first
    $secondResult = Complete-CapturedProcess -Process $second
    if ($firstResult.ExitCode -ne 0 -or
        $firstResult.Stdout -notmatch 'LIMESSH_CONCURRENT_ONE' -or
        $secondResult.ExitCode -ne 0 -or
        $secondResult.Stdout -notmatch 'LIMESSH_CONCURRENT_TWO') {
        throw "Concurrent exec validation failed.`nFirst: $($firstResult | Out-String)`nSecond: $($secondResult | Out-String)"
    }

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

    $scpSource = Join-Path $testRoot 'scp-source.txt'
    $scpRemote = Join-Path $testRoot 'scp-remote.txt'
    $scpDownload = Join-Path $testRoot 'scp-download.txt'
    Set-Content -LiteralPath $scpSource -Value 'LIMESSH_SCP_OK' -NoNewline
    $scpUploadOutput = & scp.exe `
        -oBatchMode=yes `
        -oStrictHostKeyChecking=no `
        -oUserKnownHostsFile=NUL `
        "-oUser=$sessionUser" `
        -i $clientKey `
        -P $Port `
        $scpSource `
        "${sessionHost}:$scpRemote" 2>&1
    $scpUploadCode = $LASTEXITCODE
    $scpRemoteContent = if (Test-Path -LiteralPath $scpRemote) {
        Get-Content -LiteralPath $scpRemote -Raw
    }
    if ($scpUploadCode -ne 0 -or $scpRemoteContent -ne 'LIMESSH_SCP_OK') {
        throw "SCP upload validation failed (exit $scpUploadCode, remote exists: $(Test-Path -LiteralPath $scpRemote), content: '$scpRemoteContent').`n$($scpUploadOutput -join [Environment]::NewLine)"
    }
    $scpDownloadOutput = & scp.exe `
        -oBatchMode=yes `
        -oStrictHostKeyChecking=no `
        -oUserKnownHostsFile=NUL `
        "-oUser=$sessionUser" `
        -i $clientKey `
        -P $Port `
        "${sessionHost}:$scpRemote" `
        $scpDownload 2>&1
    if ($LASTEXITCODE -ne 0 -or
        (Get-Content -LiteralPath $scpDownload -Raw) -ne 'LIMESSH_SCP_OK') {
        throw "SCP download validation failed.`n$($scpDownloadOutput -join [Environment]::NewLine)"
    }

    $targetListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $forwardClient = $null
    $targetClient = $null
    $forwardProcess = $null
    try {
        $targetListener.Start()
        $targetPort = ([Net.IPEndPoint]$targetListener.LocalEndpoint).Port
        $forwardPort = Get-FreeTcpPort
        $acceptTask = $targetListener.AcceptTcpClientAsync()
        $forwardProcess = Start-CapturedProcess `
            -FilePath (Get-Command ssh.exe).Source `
            -Arguments @(
                '-N',
                '-o', 'BatchMode=yes',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=NUL',
                '-i', $clientKey,
                '-p', ([string]$Port),
                '-L', "127.0.0.1:${forwardPort}:127.0.0.1:$targetPort",
                $sshTarget
            )

        $forwardDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $forwardClient -and [DateTime]::UtcNow -lt $forwardDeadline) {
            try {
                $candidate = [Net.Sockets.TcpClient]::new()
                $candidate.Connect('127.0.0.1', $forwardPort)
                $forwardClient = $candidate
            }
            catch {
                if ($candidate) {
                    $candidate.Dispose()
                }
                Start-Sleep -Milliseconds 100
            }
        }
        if (-not $forwardClient) {
            throw 'Timed out connecting to the local forwarded port.'
        }
        if (-not $acceptTask.Wait(10000)) {
            throw 'The loopback target did not receive the forwarded connection.'
        }
        $targetClient = $acceptTask.Result
        $forwardStream = $forwardClient.GetStream()
        $targetStream = $targetClient.GetStream()
        $forwardStream.ReadTimeout = 5000
        $targetStream.ReadTimeout = 5000
        $requestBytes = [Text.Encoding]::UTF8.GetBytes('LIMESSH_FORWARD_REQUEST')
        $forwardStream.Write($requestBytes, 0, $requestBytes.Length)
        $requestBuffer = [byte[]]::new($requestBytes.Length)
        $requestCount = $targetStream.Read($requestBuffer, 0, $requestBuffer.Length)
        if ([Text.Encoding]::UTF8.GetString($requestBuffer, 0, $requestCount) -ne 'LIMESSH_FORWARD_REQUEST') {
            throw 'The loopback target received incorrect forwarded data.'
        }
        $responseBytes = [Text.Encoding]::UTF8.GetBytes('LIMESSH_FORWARD_RESPONSE')
        $targetStream.Write($responseBytes, 0, $responseBytes.Length)
        $responseBuffer = [byte[]]::new($responseBytes.Length)
        $responseCount = $forwardStream.Read($responseBuffer, 0, $responseBuffer.Length)
        if ([Text.Encoding]::UTF8.GetString($responseBuffer, 0, $responseCount) -ne 'LIMESSH_FORWARD_RESPONSE') {
            throw 'The forwarding client received incorrect response data.'
        }
    }
    finally {
        if ($forwardProcess -and -not $forwardProcess.HasExited) {
            $forwardProcess.Kill($true)
            $forwardProcess.WaitForExit()
        }
        if ($targetClient) {
            $targetClient.Dispose()
        }
        if ($forwardClient) {
            $forwardClient.Dispose()
        }
        $targetListener.Stop()
    }

    if (-not [Net.Sockets.Socket]::OSSupportsIPv6) {
        throw 'IPv6 is required to validate forwarding to ::1.'
    }
    $ipv6Listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback, 0)
    $ipv6ForwardClient = $null
    $ipv6TargetClient = $null
    $ipv6ForwardProcess = $null
    try {
        $ipv6Listener.Start()
        $ipv6TargetPort = ([Net.IPEndPoint]$ipv6Listener.LocalEndpoint).Port
        $ipv6ForwardPort = Get-FreeTcpPort
        $ipv6AcceptTask = $ipv6Listener.AcceptTcpClientAsync()
        $ipv6ForwardProcess = Start-CapturedProcess `
            -FilePath (Get-Command ssh.exe).Source `
            -Arguments @(
                '-N',
                '-o', 'BatchMode=yes',
                '-o', 'ExitOnForwardFailure=yes',
                '-o', 'StrictHostKeyChecking=no',
                '-o', 'UserKnownHostsFile=NUL',
                '-i', $clientKey,
                '-p', ([string]$Port),
                '-L', "127.0.0.1:${ipv6ForwardPort}:[::1]:$ipv6TargetPort",
                $sshTarget
            )
        $ipv6Deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $ipv6ForwardClient -and [DateTime]::UtcNow -lt $ipv6Deadline) {
            try {
                $candidate = [Net.Sockets.TcpClient]::new()
                $candidate.Connect('127.0.0.1', $ipv6ForwardPort)
                $ipv6ForwardClient = $candidate
            }
            catch {
                if ($candidate) {
                    $candidate.Dispose()
                }
                Start-Sleep -Milliseconds 100
            }
        }
        if (-not $ipv6ForwardClient -or -not $ipv6AcceptTask.Wait(10000)) {
            throw 'IPv6 loopback forwarding did not establish.'
        }
        $ipv6TargetClient = $ipv6AcceptTask.Result
        $ipv6ForwardStream = $ipv6ForwardClient.GetStream()
        $ipv6TargetStream = $ipv6TargetClient.GetStream()
        $ipv6TargetStream.ReadTimeout = 5000
        $ipv6Probe = [Text.Encoding]::UTF8.GetBytes('LIMESSH_IPV6_FORWARD_OK')
        $ipv6ForwardStream.Write($ipv6Probe, 0, $ipv6Probe.Length)
        $ipv6Buffer = [byte[]]::new($ipv6Probe.Length)
        $ipv6Count = $ipv6TargetStream.Read($ipv6Buffer, 0, $ipv6Buffer.Length)
        if ([Text.Encoding]::UTF8.GetString($ipv6Buffer, 0, $ipv6Count) -ne
            'LIMESSH_IPV6_FORWARD_OK') {
            throw 'The IPv6 loopback target received incorrect forwarded data.'
        }
    }
    finally {
        if ($ipv6ForwardProcess -and -not $ipv6ForwardProcess.HasExited) {
            $ipv6ForwardProcess.Kill($true)
            $ipv6ForwardProcess.WaitForExit()
        }
        if ($ipv6TargetClient) {
            $ipv6TargetClient.Dispose()
        }
        if ($ipv6ForwardClient) {
            $ipv6ForwardClient.Dispose()
        }
        $ipv6Listener.Stop()
    }

    $rejectedPort = Get-FreeTcpPort
    $rejectedForward = Start-CapturedProcess `
        -FilePath (Get-Command ssh.exe).Source `
        -Arguments @(
            '-N',
            '-o', 'BatchMode=yes',
            '-o', 'ExitOnForwardFailure=yes',
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=NUL',
            '-i', $clientKey,
            '-p', ([string]$Port),
            '-L', "127.0.0.1:${rejectedPort}:192.0.2.1:9",
            $sshTarget
        )
    $rejectedClient = $null
    try {
        $rejectDeadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $rejectedClient -and [DateTime]::UtcNow -lt $rejectDeadline) {
            try {
                $candidate = [Net.Sockets.TcpClient]::new()
                $candidate.Connect('127.0.0.1', $rejectedPort)
                $rejectedClient = $candidate
            }
            catch {
                if ($candidate) {
                    $candidate.Dispose()
                }
                Start-Sleep -Milliseconds 100
            }
        }
        if (-not $rejectedClient) {
            throw 'Timed out connecting to the rejected forwarding listener.'
        }
        $rejectStream = $rejectedClient.GetStream()
        $rejectStream.ReadTimeout = 3000
        $probe = [Text.Encoding]::UTF8.GetBytes('MUST_NOT_FORWARD')
        $rejectStream.Write($probe, 0, $probe.Length)
        try {
            $rejectBuffer = [byte[]]::new(1)
            $rejectRead = $rejectStream.Read($rejectBuffer, 0, 1)
            if ($rejectRead -ne 0) {
                throw 'Non-loopback forwarding unexpectedly returned target data.'
            }
        }
        catch [IO.IOException] {
            # A reset or timeout is expected because the server rejects the channel.
        }
        Start-Sleep -Milliseconds 250
    }
    finally {
        if ($rejectedClient) {
            $rejectedClient.Dispose()
        }
        if (-not $rejectedForward.HasExited) {
            $rejectedForward.Kill($true)
            $rejectedForward.WaitForExit()
        }
    }
    $rejectedError = $rejectedForward.StandardError.ReadToEnd()
    if ($rejectedError -notmatch 'administratively prohibited') {
        throw "Non-loopback forwarding was not explicitly rejected.`n$rejectedError"
    }

    $cleanupBatch = Join-Path $testRoot 'cleanup-tree.cmd'
    Set-Content -LiteralPath $cleanupBatch -Encoding ASCII -Value @(
        '@echo off',
        'start "" /b ping.exe -n 60 127.0.0.2 >NUL',
        'echo LIMESSH_CHILD_STARTED',
        'ping.exe -n 5 127.0.0.1 >NUL'
    )
    $existingPingIds = @(
        Get-Process ping -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id
    )
    $cleanupSession = Start-CapturedProcess `
        -FilePath (Get-Command ssh.exe).Source `
        -Arguments ($concurrentArgs + @($cleanupBatch))
    Start-Sleep -Seconds 1
    $remotePingIds = @(
        Get-Process ping -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -notin $existingPingIds } |
            Select-Object -ExpandProperty Id
    )
    if ($remotePingIds.Count -lt 2) {
        if (-not $cleanupSession.HasExited) {
            $cleanupSession.Kill($true)
            $cleanupSession.WaitForExit()
        }
        throw "Expected a remote parent and child ping process, found $($remotePingIds.Count).`nstdout:`n$($cleanupSession.StandardOutput.ReadToEnd())`nstderr:`n$($cleanupSession.StandardError.ReadToEnd())"
    }
    $cleanupResult = Complete-CapturedProcess -Process $cleanupSession -TimeoutSeconds 15
    if ($cleanupResult.ExitCode -ne 0 -or
        $cleanupResult.Stdout -notmatch 'LIMESSH_CHILD_STARTED') {
        throw "Remote process-tree command failed.`n$($cleanupResult | Out-String)"
    }
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while ((Get-Process -Id $remotePingIds -ErrorAction SilentlyContinue) -and
        [DateTime]::UtcNow -lt $cleanupDeadline) {
        Start-Sleep -Milliseconds 100
    }
    $survivors = @(Get-Process -Id $remotePingIds -ErrorAction SilentlyContinue)
    if ($survivors.Count -ne 0) {
        throw "Remote child process survived command/channel completion: $($survivors.Id -join ', ')."
    }

    [pscustomobject]@{
        SessionTarget = $sshTarget
        Interactive = $interactiveStatus
        Exec = 'passed'
        ExitStatus = 'passed'
        ConcurrentExec = 'passed'
        Sftp = 'passed'
        Scp = 'passed'
        LoopbackForwarding = 'passed'
        IPv6LoopbackForwarding = 'passed'
        NonLoopbackRejection = 'passed'
        ProcessTreeCleanupOnExit = 'passed'
    }
}
finally {
    foreach ($process in $testProcesses) {
        if (-not $process.HasExited) {
            $process.Kill($true)
        }
        $process.Dispose()
    }
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
