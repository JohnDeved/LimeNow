[CmdletBinding()]
param(
    [string]$UptermCommit = '1a8b11e43b117d4dcfc8d7d92d421cb3f1abbca9',
    [string]$GoVersion = '1.26.5',
    [string]$GoArchiveSha256 = '97e6b2a833b6d89f9ff17d25419ac0a7e3b482a044e9ab18cdef834bd834fd38',
    [string]$GoArchiveCachePath = (Join-Path $env:LOCALAPPDATA 'LimeNow\BuildCache\go1.26.5.windows-amd64.zip'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\artifacts\limessh-prototype.exe'),
    [string]$RelayOutputPath = (Join-Path $PSScriptRoot '..\artifacts\uptermd-prototype.exe')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$buildEnvironment = [ordered]@{
    CGO_ENABLED = '0'
    GOARCH = 'amd64'
    GOENV = 'off'
    GOFLAGS = ''
    GOOS = 'windows'
    GOAMD64 = 'v1'
    GOTOOLCHAIN = 'local'
}
$previousBuildEnvironment = @{}
foreach ($name in $buildEnvironment.Keys) {
    $previousBuildEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    [Environment]::SetEnvironmentVariable($name, $buildEnvironment[$name], 'Process')
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) (
    'LimeNow-LimeSSH-Build-' + [Guid]::NewGuid().ToString('N')
)
$goArchive = Join-Path $testRoot "go$GoVersion.windows-amd64.zip"
$goRoot = Join-Path $testRoot 'go'
$sourceRoot = Join-Path $testRoot 'upterm'
$patch = Join-Path $PSScriptRoot '..\patches\0001-Add-LimeSSH-machine-mode.patch'

try {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw 'Git is required to fetch and patch the pinned Upterm source.'
    }
    if (-not (Test-Path -LiteralPath $patch)) {
        throw "Missing LimeSSH patch: $patch"
    }

    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $cachedGoHash = if (Test-Path -LiteralPath $GoArchiveCachePath) {
        (Get-FileHash -LiteralPath $GoArchiveCachePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($cachedGoHash -ne $GoArchiveSha256.ToLowerInvariant()) {
        $cacheDirectory = Split-Path -Parent $GoArchiveCachePath
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
        $cacheDownload = "$GoArchiveCachePath.download"
        Invoke-WebRequest `
            -Uri "https://go.dev/dl/go$GoVersion.windows-amd64.zip" `
            -OutFile $cacheDownload `
            -UseBasicParsing `
            -TimeoutSec 300
        $downloadHash = (Get-FileHash -LiteralPath $cacheDownload -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadHash -ne $GoArchiveSha256.ToLowerInvariant()) {
            Remove-Item -LiteralPath $cacheDownload -Force -ErrorAction SilentlyContinue
            throw "Go archive checksum mismatch. Expected $GoArchiveSha256 but received $downloadHash."
        }
        Move-Item -LiteralPath $cacheDownload -Destination $GoArchiveCachePath -Force
    }
    Copy-Item -LiteralPath $GoArchiveCachePath -Destination $goArchive
    $actualGoHash = (Get-FileHash -LiteralPath $goArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualGoHash -ne $GoArchiveSha256.ToLowerInvariant()) {
        throw "Go archive checksum mismatch. Expected $GoArchiveSha256 but received $actualGoHash."
    }
    Expand-Archive -LiteralPath $goArchive -DestinationPath $testRoot

    & git.exe clone --filter=blob:none --no-checkout https://github.com/owenthereal/upterm.git $sourceRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to clone the Upterm source.'
    }
    & git.exe -C $sourceRoot checkout --detach $UptermCommit
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to check out pinned Upterm commit $UptermCommit."
    }
    & git.exe -C $sourceRoot apply --check $patch
    if ($LASTEXITCODE -ne 0) {
        throw 'The LimeSSH patch does not apply cleanly to the pinned Upterm source.'
    }
    & git.exe -C $sourceRoot apply $patch
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to apply the LimeSSH patch.'
    }

    $go = Join-Path $goRoot 'bin\go.exe'
    $gofmt = Join-Path $goRoot 'bin\gofmt.exe'
    & $gofmt -w `
        (Join-Path $sourceRoot 'cmd\upterm\command\host.go') `
        (Join-Path $sourceRoot 'host\host.go') `
        (Join-Path $sourceRoot 'host\internal\server.go') `
        (Join-Path $sourceRoot 'host\internal\machine_exec_other.go') `
        (Join-Path $sourceRoot 'host\internal\machine_exec_windows.go') `
        (Join-Path $sourceRoot 'host\internal\machine_mode_test.go') `
        (Join-Path $sourceRoot 'host\internal\sftp.go') `
        (Join-Path $sourceRoot 'host\signer.go') `
        (Join-Path $sourceRoot 'server\sshhandler.go')

    Push-Location $sourceRoot
    try {
        & $go test ./host/internal -run '^Test(IsLoopbackDestination|MachineModeRequiresAuthorizedKey)$' -count=1
        if ($LASTEXITCODE -ne 0) {
            throw 'LimeSSH machine-mode unit tests failed.'
        }
        & $go test ./host/internal ./host ./cmd/upterm/command ./server -run '^$'
        if ($LASTEXITCODE -ne 0) {
            throw 'LimeSSH packages failed to compile.'
        }

        $resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedOutput) -Force | Out-Null
        & $go build -trimpath -buildvcs=false -o $resolvedOutput ./cmd/upterm
        if ($LASTEXITCODE -ne 0) {
            throw 'LimeSSH prototype build failed.'
        }
        $resolvedRelayOutput = [IO.Path]::GetFullPath($RelayOutputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedRelayOutput) -Force | Out-Null
        & $go build -trimpath -buildvcs=false -o $resolvedRelayOutput ./cmd/uptermd
        if ($LASTEXITCODE -ne 0) {
            throw 'Pinned uptermd prototype build failed.'
        }
    }
    finally {
        Pop-Location
    }

    $binaryHash = (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        UptermCommit = $UptermCommit
        GoVersion = $GoVersion
        OutputPath = $resolvedOutput
        Sha256 = $binaryHash
        RelayOutputPath = $resolvedRelayOutput
        RelaySha256 = (Get-FileHash -LiteralPath $resolvedRelayOutput -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
finally {
    foreach ($name in $buildEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousBuildEnvironment[$name], 'Process')
    }

    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedRoot) -match '^LimeNow-LimeSSH-Build-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedRoot)) {
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
