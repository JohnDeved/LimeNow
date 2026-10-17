# LIMENOW_SETUP_SCRIPT
[CmdletBinding()]
param(
    [switch]$Startup,
    [switch]$SkipStartupUpdate,
    [switch]$RefreshManagedScripts
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$setupRoot = 'I:\Apps\SalsaNOW\EasySetup'
$limeNowAppsRoot = 'I:\Apps\LimeNow'
$nodeRoot = Join-Path $limeNowAppsRoot 'NodeJS'
$npmGlobalRoot = Join-Path $limeNowAppsRoot 'NpmGlobal'
$npmCacheRoot = Join-Path $limeNowAppsRoot 'NpmCache'
$codexRoot = Join-Path $limeNowAppsRoot 'Codex'
$codexBinRoot = Join-Path $codexRoot 'bin'
$codexStateManager = Join-Path $codexRoot 'codex-state.ps1'
$codexStateManagerUrl = 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/codex-state.ps1'
$codexWrapper = Join-Path $codexBinRoot 'codex.cmd'
$codexVersion = '0.163.0'
$codexRegistryUrl = 'https://registry.npmjs.org/@openai%2fcodex/latest'
# Bootstrap fallbacks only; each setup checks the publishers for newer stable releases.
$nodeVersion = 'v24.22.0'
$nodeArchiveName = "node-$nodeVersion-win-x64.zip"
$nodeArchiveHash = 'f9683a19877e12a9b167305c8db71040d812876359de21f0d2e97c3f321f80c3'
$gitRoot = Join-Path $limeNowAppsRoot 'Git'
$gitVersion = '2.56.0.windows.2'
$gitArchiveUrl = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/PortableGit-2.56.0.2-64-bit.7z.exe'
$gitArchiveHash = '075e158ef8e1f0ab80b347e245405d3eca735c2dc88fd8e032e137d0ca61f61b'
$githubCliRoot = Join-Path $limeNowAppsRoot 'GitHubCLI'
$githubCliBinRoot = Join-Path $githubCliRoot 'bin'
$githubCliConfigRoot = Join-Path $githubCliRoot 'Config'
$githubCliExecutable = Join-Path $githubCliBinRoot 'gh.exe'
$githubCliWrapper = Join-Path $githubCliRoot 'gh.cmd'
$githubCliLoginLauncher = Join-Path $githubCliRoot 'GitHub-CLI-Sign-In.cmd'
$githubCliLoginScript = Join-Path $githubCliRoot 'GitHub-CLI-Sign-In.ps1'
$githubCliDeviceUrl = 'https://github.com/login/device'
$githubCliVersion = '2.102.0'
$githubCliArchiveUrl = 'https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_windows_amd64.zip'
$githubCliArchiveHash = 'ae64e556ecc240b200f7eba60d550e4bb60d78e860e69dd88c449405b86067f4'
$vscodeRoot = Join-Path $limeNowAppsRoot 'VSCode'
$vscodeVersion = '1.142.0'
$vscodeArchiveUrl = 'https://vscode.download.prss.microsoft.com/dbazure/download/stable/6d62b1d5dace93a33b3a6d3eca1317bd5e15bcb1/VSCode-win32-x64-1.142.0.zip'
$vscodeArchiveHash = 'ace1da7d1432d43c1ab4b2bbf643f6494f6d25dec07494976755eac522cd50d9'
$terminalRoot = Join-Path $limeNowAppsRoot 'WindowsTerminal'
$terminalVersion = '1.25.2733.0'
$terminalArchiveUrl = 'https://github.com/microsoft/terminal/releases/download/v1.25.2733.0/Microsoft.WindowsTerminal_1.25.2733.0_x64.zip'
$terminalArchiveHash = 'bf3ef2012f6c44d8340a4c58125acc9498d19b580f9890dc043cdf831852e796'
$chromiumRoot = Join-Path $limeNowAppsRoot 'Chromium'
$chromiumAppRoot = Join-Path $chromiumRoot 'Application'
$chromiumProfileRoot = Join-Path $chromiumRoot 'User Data'
$chromiumWrapper = Join-Path $chromiumRoot 'chromium.cmd'
$chromiumVersion = '155.0.8059.85'
$chromiumArchiveUrl = 'https://github.com/Hibbiki/chromium-win64/releases/download/v155.0.8059.85-r1697595/chrome.7z'
$chromiumArchiveHash = '80710739b1f92f87ca50b798826c2d9b9e21e06139f96f05b8a9a1b9d0d49cb3'
$limeSshRoot = Join-Path $limeNowAppsRoot 'LimeSSH'
$limeSshVersion = '0.1.0'
$limeSshExecutable = Join-Path $limeSshRoot 'LimeSSH.exe'
$limeSshAssetUrl = 'https://github.com/JohnDeved/LimeNow/releases/download/limessh-v0.1.0/LimeSSH.exe'
$limeSshAssetHash = '8b203f33c8d87756a054e1d7382456c926f13ec2ccbf5341bd41226cfdd109ec'
$limeSshLicenseUrl = 'https://github.com/JohnDeved/LimeNow/releases/download/limessh-v0.1.0/UPTERM-APACHE-2.0-LICENSE'
$limeSshLicenseHash = 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
$limeSshManager = Join-Path $limeSshRoot 'remote-access.ps1'
$limeSshManagerUrl = 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/remote-access.ps1'
$modrinthRoot = 'I:\Apps\ModrinthApp'
$modrinthDataRoot = 'I:\Apps\ModrinthData'
$modrinthAppData = Join-Path $env:APPDATA 'ModrinthApp'
$modrinthReleaseTag = 'modrinth-gfn-v0.16.1'
$modrinthAssetName = 'LimeNow-Modrinth-GFN-v0.16.1.zip'
$salsaRoot = 'I:\Apps\SalsaNOW'
$documentsRoot = [Environment]::GetFolderPath('MyDocuments')
$canonicalScript = Join-Path $setupRoot 'SalsaNOW-EasySetup.ps1'
$documentsScript = Join-Path $documentsRoot 'SalsaNOW-EasySetup.ps1'
$documentsBatch = Join-Path $documentsRoot 'SalsaNOW-EasySetup.bat'
$startupBatch = Join-Path $salsaRoot 'StartupBatch.bat'
$logPath = Join-Path $setupRoot 'setup.log'
$remoteSetupUrl = 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/setup.ps1'

function Initialize-SetupStorage {
    New-Item -ItemType Directory -Path $setupRoot -Force | Out-Null

    if (Test-Path -LiteralPath $logPath) {
        $log = Get-Item -LiteralPath $logPath
        if ($log.Length -gt 1MB) {
            Move-Item -LiteralPath $logPath -Destination "$logPath.previous" -Force
        }
    }
}

function Write-SetupLog {
    param([Parameter(Mandatory)][string]$Message)

    $line = '{0:yyyy-MM-dd HH:mm:ss zzz} [LimeNow] {1}' -f [DateTimeOffset]::Now, $Message
    Add-Content -LiteralPath $logPath -Value $line
    Write-Host $line
}

function Show-StartupProgressHeader {
    if (-not $Startup) {
        return
    }

    try {
        $Host.UI.RawUI.WindowTitle = 'LimeNow - Preparing GeForce NOW session'
    }
    catch {
        # Some non-console hosts do not expose a writable window title.
    }

    $lime = [char]::ConvertFromUtf32(0x1F34B) +
        [char]::ConvertFromUtf32(0x200D) +
        [char]::ConvertFromUtf32(0x1F7E9)
    Write-Host ''
    Write-Host "$lime LimeNow" -ForegroundColor Green
    Write-Host 'Updating and preparing this GeForce NOW session...' -ForegroundColor Cyan
    Write-Host "Live log: $logPath" -ForegroundColor DarkGray
    Write-Host ''
}

function Assert-PowerShellScriptSyntax {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Description
    )

    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$null,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count) {
        throw "$Description failed PowerShell syntax validation: $($parseErrors -join '; ')"
    }
}

function Assert-LimeNowSetupCandidate {
    param([Parameter(Mandatory)][string]$Path)

    $source = Get-Content -LiteralPath $Path -Raw
    if ($source -notmatch '(?m)^# LIMENOW_SETUP_SCRIPT\r?$') {
        throw 'The downloaded file is not a recognized LimeNow setup script.'
    }

    Assert-PowerShellScriptSyntax `
        -Path $Path `
        -Description 'The downloaded LimeNow setup script'

    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$null,
        [ref]$parseErrors
    )
    if ($parseErrors.Count) {
        throw "The downloaded LimeNow setup script failed syntax validation: $($parseErrors -join '; ')"
    }

    $parameterNames = @($ast.ParamBlock.Parameters | ForEach-Object {
        $_.Name.VariablePath.UserPath
    })
    foreach ($requiredParameter in @('Startup', 'SkipStartupUpdate', 'RefreshManagedScripts')) {
        if ($requiredParameter -notin $parameterNames) {
            throw "The downloaded LimeNow setup script is missing its $requiredParameter startup parameter."
        }
    }
}

function Get-LimeNowManagedScriptCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemoteUrl,
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$Description
    )

    $useLocalCopy = -not $RefreshManagedScripts
    if ($RefreshManagedScripts) {
        try {
            Invoke-WebRequest `
                -Uri $RemoteUrl `
                -OutFile $CandidatePath `
                -Headers @{ 'Cache-Control' = 'no-cache' } `
                -UseBasicParsing `
                -TimeoutSec 60
            Assert-PowerShellScriptSyntax -Path $CandidatePath -Description $Description
            Write-SetupLog "Checked GitHub for the latest $Description."
            return
        }
        catch {
            if (Test-Path -LiteralPath $CandidatePath) {
                Remove-Item -LiteralPath $CandidatePath -Force
            }
            if (-not (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
                throw
            }
            Write-SetupLog "WARNING: Could not refresh $Description; using the installed copy. $($_.Exception.Message)"
            $useLocalCopy = $true
        }
    }

    if ($useLocalCopy -and (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        Copy-Item -LiteralPath $LocalPath -Destination $CandidatePath
    }
    else {
        Invoke-WebRequest `
            -Uri $RemoteUrl `
            -OutFile $CandidatePath `
            -UseBasicParsing `
            -TimeoutSec 60
    }
    Assert-PowerShellScriptSyntax -Path $CandidatePath -Description $Description
}

function Update-LimeNowSetup {
    [CmdletBinding()]
    param(
        [string]$SourceUrl = $remoteSetupUrl,
        [string]$DestinationPath = $canonicalScript
    )

    $destinationDirectory = Split-Path -Parent $DestinationPath
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    $candidate = Join-Path $destinationDirectory (
        'setup-update-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    )

    try {
        Write-SetupLog 'Checking GitHub for LimeNow updates...'
        Invoke-WebRequest `
            -Uri $SourceUrl `
            -OutFile $candidate `
            -Headers @{ 'Cache-Control' = 'no-cache' } `
            -UseBasicParsing `
            -TimeoutSec 60
        Assert-LimeNowSetupCandidate -Path $candidate

        $candidateHash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
        if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
            $installedHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
            if ($candidateHash -eq $installedHash) {
                Write-SetupLog 'LimeNow is already up to date.'
                return 'Current'
            }

            [IO.File]::Replace(
                $candidate,
                $DestinationPath,
                "$DestinationPath.previous",
                $true
            )
        }
        else {
            [IO.File]::Move($candidate, $DestinationPath)
        }

        Write-SetupLog 'Installed the latest LimeNow setup from GitHub; continuing with the update.'
        return 'Updated'
    }
    catch {
        Write-SetupLog "WARNING: LimeNow auto-update failed; continuing with the installed setup. $($_.Exception.Message)"
        return 'Fallback'
    }
    finally {
        if (Test-Path -LiteralPath $candidate) {
            Remove-Item -LiteralPath $candidate -Force
        }
    }
}

function Show-StartupProgressResult {
    param([Parameter(Mandatory)][bool]$Succeeded)

    if (-not $Startup) {
        return
    }

    Write-Host ''
    if ($Succeeded) {
        Write-Host 'LimeNow is ready. This window will close automatically.' -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    else {
        Write-Host "LimeNow could not finish. Review $logPath for details." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
}

function Get-VerifiedDownload {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$ExpectedHash,
        [ValidateSet('SHA1', 'SHA256')][string]$Algorithm = 'SHA256'
    )

    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing -TimeoutSec 180
    $actualHash = (Get-FileHash -LiteralPath $Destination -Algorithm $Algorithm).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedHash.ToLowerInvariant()) {
        throw "$Algorithm checksum mismatch for $Uri. Expected $ExpectedHash but received $actualHash."
    }
}

function Remove-SetupRepairDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $separator = [IO.Path]::DirectorySeparatorChar
    $resolvedSetupRoot = [IO.Path]::GetFullPath($setupRoot).TrimEnd($separator) + $separator
    $leaf = Split-Path -Leaf $resolvedPath
    if (-not $resolvedPath.StartsWith($resolvedSetupRoot, [StringComparison]::OrdinalIgnoreCase) -or
        $leaf -notmatch '-repair-[a-f0-9]{32}$') {
        throw "Refusing to remove an unexpected repair directory: $resolvedPath"
    }
    if (Test-Path -LiteralPath $resolvedPath) {
        if (Test-Path -LiteralPath (Join-Path $resolvedPath 'LIMENOW-RECOVERY')) {
            Write-SetupLog "WARNING: Preserved update recovery files at $resolvedPath."
            return
        }
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
}

function Get-LimeNowJson {
    param([Parameter(Mandatory)][string]$Uri)

    $response = Invoke-RestMethod -Uri $Uri -TimeoutSec 20 -Headers @{
        'User-Agent' = 'LimeNow'
        'Cache-Control' = 'no-cache'
        'Accept' = 'application/json'
    }
    # Enumerate top-level JSON arrays consistently, including Windows PowerShell.
    return $response
}

function ConvertTo-LimeNowVersion {
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -cnotmatch '^v?(\d+)\.(\d+)\.(\d+)(?:\.(?:windows\.)?(\d+))?$') {
        throw "Invalid stable tool version: $Version"
    }
    $revision = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
    return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $revision)
}

function Get-LimeNowGitHubRelease {
    param([Parameter(Mandatory)][string]$Repository)

    if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw "Invalid GitHub release repository: $Repository"
    }
    $release = Get-LimeNowJson -Uri "https://api.github.com/repos/$Repository/releases/latest"
    if ($release.draft -isnot [bool] -or $release.draft -or
        $release.prerelease -isnot [bool] -or $release.prerelease -or
        [string]::IsNullOrWhiteSpace([string]$release.tag_name)) {
        throw "GitHub did not return a stable published release for $Repository."
    }
    return $release
}

function Get-LimeNowGitHubAsset {
    param(
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Name
    )

    $tag = [string]$Release.tag_name
    if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
        $tag -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$' -or
        $Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        throw 'The GitHub release asset has an unexpected repository, tag, or filename.'
    }
    $assets = @($Release.assets | Where-Object {
        [string]::Equals([string]$_.name, $Name, [StringComparison]::Ordinal)
    })
    if ($assets.Count -ne 1) {
        throw "GitHub did not return exactly one $Name asset for $Repository $tag."
    }
    $asset = $assets[0]
    $expectedUri = "https://github.com/$Repository/releases/download/$tag/$Name"
    if (-not [string]::Equals([string]$asset.browser_download_url, $expectedUri,
            [StringComparison]::Ordinal)) {
        throw "The download URL for $Name does not match its GitHub repository and release."
    }
    if ([string]$asset.digest -cnotmatch '^sha256:([a-fA-F0-9]{64})$') {
        throw "GitHub did not provide an SHA-256 digest for $Name."
    }
    return [pscustomobject]@{
        Uri = $expectedUri
        Hash = $Matches[1].ToLowerInvariant()
    }
}

function Get-LatestNodeRelease {
    $releases = @(Get-LimeNowJson -Uri 'https://nodejs.org/dist/index.json')
    $latest = $releases | Where-Object {
        $_.version -cmatch '^v\d+\.\d+\.\d+$' -and
        $_.lts -is [string] -and -not [string]::IsNullOrWhiteSpace($_.lts) -and
        $_.files -contains 'win-x64-zip'
    } | Sort-Object -Property @{ Expression = {
        ConvertTo-LimeNowVersion -Version $_.version
    }; Descending = $true } | Select-Object -First 1
    if (-not $latest) {
        throw 'Node.js did not publish a usable Windows x64 LTS release.'
    }
    $version = [string]$latest.version
    $archiveName = "node-$version-win-x64.zip"
    $releaseBase = "https://nodejs.org/dist/$version"
    $response = Invoke-WebRequest -Uri "$releaseBase/SHASUMS256.txt" `
        -UseBasicParsing -TimeoutSec 20 -Headers @{
            'User-Agent' = 'LimeNow'
            'Cache-Control' = 'no-cache'
        }
    $lines = [regex]::Matches([string]$response.Content,
        "(?m)^([a-fA-F0-9]{64})[ `t]+\*?$([regex]::Escape($archiveName))`r?$")
    if ($lines.Count -ne 1) {
        throw "Node.js did not publish exactly one checksum for $archiveName."
    }
    return [pscustomobject]@{
        Version = $version
        Uri = "$releaseBase/$archiveName"
        Hash = $lines[0].Groups[1].Value.ToLowerInvariant()
    }
}

function Get-LatestGitRelease {
    $repository = 'git-for-windows/git'
    $release = Get-LimeNowGitHubRelease -Repository $repository
    if ($release.tag_name -cnotmatch '^v(\d+\.\d+\.\d+)\.windows\.([1-9]\d*)$') {
        throw 'Git for Windows returned an unexpected stable release tag.'
    }
    $archiveVersion = $Matches[1]
    $revision = $Matches[2]
    if ([int]$revision -gt 1) {
        $archiveVersion += ".$revision"
    }
    $version = ([string]$release.tag_name).Substring(1)
    $null = ConvertTo-LimeNowVersion -Version $version
    $asset = Get-LimeNowGitHubAsset -Release $release -Repository $repository `
        -Name "PortableGit-$archiveVersion-64-bit.7z.exe"
    return [pscustomobject]@{ Version = $version; Uri = $asset.Uri; Hash = $asset.Hash }
}

function Get-LatestGitHubCliRelease {
    $repository = 'cli/cli'
    $release = Get-LimeNowGitHubRelease -Repository $repository
    if ($release.tag_name -cnotmatch '^v(\d+\.\d+\.\d+)$') {
        throw 'GitHub CLI returned an unexpected stable release tag.'
    }
    $version = $Matches[1]
    $null = ConvertTo-LimeNowVersion -Version $version
    $asset = Get-LimeNowGitHubAsset -Release $release -Repository $repository `
        -Name "gh_${version}_windows_amd64.zip"
    return [pscustomobject]@{ Version = $version; Uri = $asset.Uri; Hash = $asset.Hash }
}

function Get-LatestVSCodeRelease {
    $release = Get-LimeNowJson `
        -Uri 'https://update.code.visualstudio.com/api/update/win32-x64-archive/stable/latest'
    $version = [string]$release.productVersion
    if ($version -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'Visual Studio Code returned an invalid stable product version.'
    }
    $null = ConvertTo-LimeNowVersion -Version $version
    $uri = $null
    if (-not [uri]::TryCreate([string]$release.url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or $uri.Host -ne 'vscode.download.prss.microsoft.com' -or
        -not $uri.IsDefaultPort -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        $uri.AbsolutePath -cnotmatch "/stable/[a-fA-F0-9]{40}/VSCode-win32-x64-$([regex]::Escape($version))\.zip$") {
        throw 'Visual Studio Code returned an unexpected stable Windows x64 download URL.'
    }
    if ([string]$release.sha256hash -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw 'Visual Studio Code did not publish a valid SHA-256 checksum.'
    }
    return [pscustomobject]@{
        Version = $version
        Uri = $uri.AbsoluteUri
        Hash = ([string]$release.sha256hash).ToLowerInvariant()
    }
}

function Get-LatestWindowsTerminalRelease {
    $repository = 'microsoft/terminal'
    $release = Get-LimeNowGitHubRelease -Repository $repository
    if ($release.tag_name -cnotmatch '^v(\d+\.\d+\.\d+\.\d+)$') {
        throw 'Windows Terminal returned an unexpected stable release tag.'
    }
    $version = $Matches[1]
    $null = ConvertTo-LimeNowVersion -Version $version
    $asset = Get-LimeNowGitHubAsset -Release $release -Repository $repository `
        -Name "Microsoft.WindowsTerminal_${version}_x64.zip"
    return [pscustomobject]@{ Version = $version; Uri = $asset.Uri; Hash = $asset.Hash }
}

function Test-LimeNowToolRunning {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$ProcessNames = @()
    )

    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/') +
        [IO.Path]::DirectorySeparatorChar
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $processPath = $null
        try { $processPath = $process.Path } catch { }
        if ($processPath) {
            if ($processPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        elseif ($ProcessNames -contains $process.ProcessName) {
            # Some protected processes do not expose their executable path.
            return $true
        }
    }
    return $false
}

function Invoke-LimeNowToolUpdate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$FallbackRelease,
        [Parameter(Mandatory)][scriptblock]$GetInstalledVersion,
        [Parameter(Mandatory)][scriptblock]$GetLatestRelease,
        [Parameter(Mandatory)][scriptblock]$InstallRelease,
        [string[]]$ProcessNames = @()
    )

    $installedVersion = & $GetInstalledVersion $Root
    $installedComparable = if ($installedVersion) {
        ConvertTo-LimeNowVersion -Version $installedVersion
    } else { $null }
    $release = $null
    try {
        $release = & $GetLatestRelease
        if (-not $release) { throw 'No release metadata was returned.' }
        $null = ConvertTo-LimeNowVersion -Version $release.Version
    }
    catch {
        $release = $null
        Write-SetupLog "$Name update check unavailable: $($_.Exception.Message)"
    }
    if (-not $release -and $installedVersion) {
        Write-SetupLog "Verified usable $Name $installedVersion; update will retry on the next online setup."
        return
    }
    if (-not $release) {
        $release = $FallbackRelease
        Write-SetupLog "$Name will use the known-good bootstrap release $($release.Version)."
    }
    $fallbackComparable = ConvertTo-LimeNowVersion -Version $FallbackRelease.Version
    $targetComparable = ConvertTo-LimeNowVersion -Version $release.Version
    if ($targetComparable -lt $fallbackComparable) {
        Write-SetupLog "$Name metadata is older than the known-good floor; using $($FallbackRelease.Version)."
        $release = $FallbackRelease
        $targetComparable = $fallbackComparable
    }
    if ($installedComparable -and $installedComparable -ge $targetComparable) {
        Write-SetupLog "Verified $Name $installedVersion; the available release does not require an upgrade."
        return
    }
    if (Test-LimeNowToolRunning -Root $Root -ProcessNames $ProcessNames) {
        if ($installedVersion) {
            Write-SetupLog "$Name $installedVersion is running; update deferred until the next setup after it exits."
            return
        }
        throw "$Name needs installation but its files are in use. Close it and run LimeNow again."
    }

    Write-SetupLog "Installing $Name $($release.Version)."
    try {
        & $InstallRelease $release | Out-Null
        $updatedVersion = & $GetInstalledVersion $Root
        if (-not $updatedVersion -or
            (ConvertTo-LimeNowVersion -Version $updatedVersion) -ne $targetComparable) {
            throw "$Name verification failed after installation."
        }
        Write-SetupLog "Installed/repaired $Name $updatedVersion."
    }
    catch {
        if ($_.Exception.Data['LimeNowRecoveryRequired']) {
            # A runnable binary alone cannot prove that persistent state was restored.
            throw
        }
        $failure = $_.Exception.Message
        $retainedVersion = $null
        try {
            $retainedVersion = & $GetInstalledVersion $Root
            if ($installedComparable -and $retainedVersion -and
                (ConvertTo-LimeNowVersion -Version $retainedVersion) -ge $installedComparable) {
                Write-SetupLog "WARNING: $Name update failed; retained verified $retainedVersion. $failure"
                return
            }
        }
        catch { }
        throw "$Name installation/update failed: $failure"
    }
}

function Assert-LimeNowNoPendingToolRecovery {
    param(
        [Parameter(Mandatory)][string]$SetupRoot,
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SetupRoot -PathType Container)) { return }
    $pending = @(Get-ChildItem -LiteralPath $SetupRoot -Directory -Force | Where-Object {
        $_.Name -match '-repair-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'LIMENOW-RECOVERY') -PathType Leaf)
    })
    if ($DestinationPath) {
        $destination = [IO.Path]::GetFullPath($DestinationPath).TrimEnd([char[]]'\/')
        $pending = @($pending | Where-Object {
            @(Get-Content -LiteralPath (Join-Path $_.FullName 'LIMENOW-RECOVERY')) -contains "Destination=$destination"
        })
    }
    if ($pending.Count) {
        $failure = [IO.IOException]::new(
            "An unfinished tool update requires recovery before setup can continue. Review the retained files and setup.log: $($pending.FullName -join ', ')"
        )
        $failure.Data['LimeNowRecoveryRequired'] = $true
        throw $failure
    }
}

function Get-LimeNowUpdateMutexName {
    param([Parameter(Mandatory)][string]$DestinationPath)

    $destination = [IO.Path]::GetFullPath($DestinationPath).TrimEnd([char[]]'\/').ToUpperInvariant()
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($destination))
        $suffix = [BitConverter]::ToString($digest).Replace('-', '')
        return "LimeNowToolUpdate-$suffix"
    }
    finally {
        $algorithm.Dispose()
    }
}

function Move-LimeNowPath {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)][string]$Destination
    )

    # Move-Item can silently nest a directory inside an existing destination.
    # These same-volume moves instead fail atomically when the target exists.
    if ([IO.Directory]::Exists($LiteralPath)) {
        [IO.Directory]::Move($LiteralPath, $Destination)
    }
    else {
        [IO.File]::Move($LiteralPath, $Destination)
    }
}

function Install-LimeNowStagedDirectory {
    param(
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$RepairRoot,
        [string[]]$PreservePaths = @(),
        [scriptblock]$BeforeSwap,
        [Parameter(Mandatory)][scriptblock]$Verify
    )

    $candidate = [IO.Path]::GetFullPath($CandidatePath).TrimEnd([char[]]'\/')
    $destination = [IO.Path]::GetFullPath($DestinationPath).TrimEnd([char[]]'\/')
    $repair = [IO.Path]::GetFullPath($RepairRoot).TrimEnd([char[]]'\/')
    $repairPrefix = $repair + [IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destination + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($repairPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $destination.StartsWith($repairPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $repair.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $destination -eq $repair -or
        [IO.Path]::GetPathRoot($destination) -ne [IO.Path]::GetPathRoot($repair)) {
        throw 'The staged application and destination do not have safe, separate paths on the same volume.'
    }
    $backup = Join-Path $repair 'previous'
    $marker = Join-Path $repair 'LIMENOW-RECOVERY'
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $marker)) {
        throw "An unfinished application update already exists in $repair."
    }
    foreach ($relative in $PreservePaths) {
        if ([string]::IsNullOrWhiteSpace($relative) -or [IO.Path]::IsPathRooted($relative) -or
            @($relative.Replace('\', '/').Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
            throw "Invalid application state path: $relative"
        }
    }
    $verified = & $Verify $candidate
    if ($verified -isnot [bool] -or -not $verified) {
        throw 'The staged application failed verification; the installed application was left unchanged.'
    }
    $mutex = [Threading.Mutex]::new($false, (Get-LimeNowUpdateMutexName -DestinationPath $destination))
    $lockTaken = $false
    try {
        try {
            $lockTaken = $mutex.WaitOne(0)
        }
        catch [Threading.AbandonedMutexException] {
            # WaitOne grants ownership when the previous process terminated.
            $lockTaken = $true
        }
        if (-not $lockTaken) {
            throw 'Another setup is updating this application; installation is deferred.'
        }
        Assert-LimeNowNoPendingToolRecovery -SetupRoot (Split-Path -Parent $repair) -DestinationPath $destination
        if ($BeforeSwap) { & $BeforeSwap $destination | Out-Null }
        # Recheck under the update lock before touching the current installation.
        if (Test-LimeNowToolRunning -Root $destination) {
            throw 'The application was started during its update; installation is deferred.'
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Set-Content -LiteralPath $marker -Encoding UTF8 -Value @(
            "Destination=$destination", "Previous=$backup", "Candidate=$candidate"
        )
        $backupMoved = $false
        $candidatePromoted = $false
        $movedState = [Collections.Generic.List[string]]::new()
        try {
            if (Test-Path -LiteralPath $destination) {
                Move-LimeNowPath -LiteralPath $destination -Destination $backup
                $backupMoved = $true
                foreach ($relative in $PreservePaths) {
                    $previousState = Join-Path $backup $relative
                    if (-not (Test-Path -LiteralPath $previousState)) { continue }
                    $candidateState = Join-Path $candidate $relative
                    if (Test-Path -LiteralPath $candidateState) {
                        Remove-Item -LiteralPath $candidateState -Recurse -Force -ErrorAction Stop
                    }
                    New-Item -ItemType Directory -Path (Split-Path -Parent $candidateState) -Force | Out-Null
                    Move-LimeNowPath -LiteralPath $previousState -Destination $candidateState
                    $movedState.Add($relative)
                }
            }
            Move-LimeNowPath -LiteralPath $candidate -Destination $destination
            $candidatePromoted = $true
            $verified = & $Verify $destination
            if ($verified -isnot [bool] -or -not $verified) {
                throw 'The promoted application failed verification.'
            }
            Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
        }
        catch {
            $updateFailure = $_
            try {
                $stateRoot = if ($candidatePromoted) { $destination } else { $candidate }
                for ($i = $movedState.Count - 1; $i -ge 0; $i--) {
                    $relative = $movedState[$i]
                    $currentState = Join-Path $stateRoot $relative
                    $previousState = Join-Path $backup $relative
                    if (-not (Test-Path -LiteralPath $currentState) -or
                        (Test-Path -LiteralPath $previousState)) {
                        throw "Cannot safely restore application state: $relative"
                    }
                    New-Item -ItemType Directory -Path (Split-Path -Parent $previousState) -Force | Out-Null
                    Move-LimeNowPath -LiteralPath $currentState -Destination $previousState
                }
                if ($candidatePromoted) {
                    Move-LimeNowPath -LiteralPath $destination -Destination $candidate
                }
                if ($backupMoved) {
                    Move-LimeNowPath -LiteralPath $backup -Destination $destination
                }
                Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
            }
            catch {
                $recoveryFailure = [IO.IOException]::new(
                    "Application update failed: $($updateFailure.Exception.Message) Rollback failed: $($_.Exception.Message) Recovery files were retained in $repair."
                )
                $recoveryFailure.Data['LimeNowRecoveryRequired'] = $true
                throw $recoveryFailure
            }
            throw $updateFailure
        }
    }
    finally {
        if ($lockTaken) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-LimeNowInstalledVersion {
    param(
        [Parameter(Mandatory)][ValidateSet('Node', 'Git', 'GitHubCli', 'VSCode', 'WindowsTerminal', 'Chromium')][string]$Tool,
        [Parameter(Mandatory)][string]$Root,
        [string]$ExecutablePath
    )

    try {
        $executableName = switch ($Tool) {
            'Node' { 'node.exe' }
            'Git' { 'cmd\git.exe' }
            'GitHubCli' { 'bin\gh.exe' }
            'VSCode' { 'Code.exe' }
            'WindowsTerminal' { 'WindowsTerminal.exe' }
            'Chromium' { 'chrome.exe' }
        }
        if (-not $ExecutablePath) {
            $ExecutablePath = Join-Path $Root $executableName
        }
        if (-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) { return $null }

        switch ($Tool) {
            'Node' {
                foreach ($relativePath in @('npm.cmd', 'npx.cmd', 'node_modules\npm\package.json')) {
                    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) { return $null }
                }
                $output = (& $ExecutablePath --version 2>$null | Select-Object -First 1)
                if ($LASTEXITCODE -eq 0 -and $output -match '^v\d+\.\d+\.\d+$') { return [string]$output }
            }
            'Git' {
                if (-not (Test-Path -LiteralPath (Join-Path $Root 'usr\bin\sh.exe') -PathType Leaf)) { return $null }
                $output = (& $ExecutablePath --version 2>$null | Select-Object -First 1)
                if ($LASTEXITCODE -eq 0 -and $output -match '^git version (?<version>\d+\.\d+\.\d+\.windows\.\d+)$') {
                    return $Matches.version
                }
            }
            'GitHubCli' {
                $output = (& $ExecutablePath --version 2>$null | Select-Object -First 1)
                if ($LASTEXITCODE -eq 0 -and $output -match '^gh version (?<version>\d+\.\d+\.\d+)(?:\s|$)') {
                    return $Matches.version
                }
            }
            'VSCode' {
                if (-not (Test-Path -LiteralPath (Join-Path $Root 'bin\code.cmd') -PathType Leaf) -or
                    -not (Test-Path -LiteralPath (Join-Path $Root 'data') -PathType Container)) { return $null }
                $version = (Get-Item -LiteralPath $ExecutablePath).VersionInfo.ProductVersion
                if ($version -match '^(?<version>\d+\.\d+\.\d+)(?:[+ ].*)?$') { return $Matches.version }
            }
            'WindowsTerminal' {
                $marker = Join-Path $Root 'LIMENOW-VERSION'
                if (-not (Test-Path -LiteralPath (Join-Path $Root '.portable') -PathType Leaf) -or
                    -not (Test-Path -LiteralPath $marker -PathType Leaf)) { return $null }
                $version = (Get-Content -LiteralPath $marker -Raw).Trim()
                $fileVersion = (Get-Item -LiteralPath $ExecutablePath).VersionInfo.FileVersion
                # Terminal's package and PE build numbers differ; their major/minor must agree.
                if ($version -match '^(?<channel>\d+\.\d+)\.\d+\.\d+$' -and
                    $fileVersion -match "^$([regex]::Escape($Matches.channel))\.\d+\.\d+$") { return $version }
            }
            'Chromium' {
                $version = (Get-Item -LiteralPath $ExecutablePath).VersionInfo.ProductVersion
                if ($version -match '^\d+\.\d+\.\d+\.\d+$' -and
                    (Test-Path -LiteralPath (Join-Path $Root "$version\chrome.dll") -PathType Leaf)) { return $version }
            }
        }
    }
    catch {
        # Missing, unreadable, or non-working binaries are repaired by setup.
    }
    return $null
}

function Install-LimeNowPortableTool {
    param(
        [Parameter(Mandatory)][ValidateSet('Node', 'Git', 'GitHubCli', 'VSCode', 'WindowsTerminal', 'Chromium')][string]$Tool,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Release
    )

    $repairRoot = Join-Path $setupRoot ("$($Tool.ToLowerInvariant())-repair-" + [Guid]::NewGuid().ToString('N'))
    $extractPath = Join-Path $repairRoot 'extracted'
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    $extension = switch ($Tool) { 'Git' { '.7z.exe' }; 'Chromium' { '.7z' }; default { '.zip' } }
    $archivePath = Join-Path $repairRoot "package$extension"

    try {
        Get-VerifiedDownload -Uri $Release.Uri -Destination $archivePath -ExpectedHash $Release.Hash -Algorithm SHA256
        switch ($Tool) {
            'Git' {
                $process = Start-Process -FilePath $archivePath `
                    -ArgumentList '-y', "-o`"$extractPath`"" -Wait -PassThru -WindowStyle Hidden
                if ($process.ExitCode -ne 0) { throw "Portable Git extraction failed with exit code $($process.ExitCode)." }
            }
            'Chromium' {
                $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
                if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { throw 'Chromium extraction requires the tar.exe included with current Windows versions.' }
                & $tar -xf $archivePath -C $extractPath
                if ($LASTEXITCODE -ne 0) { throw "Chromium archive extraction failed with exit code $LASTEXITCODE." }
            }
            default { Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath }
        }

        $candidatePath = $extractPath
        $preservePaths = @()
        $processNames = @()
        switch ($Tool) {
            'Node' {
                $candidatePath = Join-Path $extractPath "node-$($Release.Version)-win-x64"
                $processNames = @('node')
            }
            'Git' { $processNames = @('git', 'git-remote-https', 'git-remote-http', 'ssh', 'bash', 'sh') }
            'GitHubCli' {
                if (-not (Test-Path -LiteralPath (Join-Path $extractPath 'bin\gh.exe') -PathType Leaf)) {
                    $packages = @(Get-ChildItem -LiteralPath $extractPath -Directory | Where-Object {
                        Test-Path -LiteralPath (Join-Path $_.FullName 'bin\gh.exe') -PathType Leaf
                    })
                    if ($packages.Count -ne 1) { throw 'The verified GitHub CLI archive has an unexpected layout.' }
                    $candidatePath = $packages[0].FullName
                }
                $preservePaths = @('Config', 'gh.cmd', 'GitHub-CLI-Sign-In.cmd', 'GitHub-CLI-Sign-In.ps1')
                $processNames = @('gh')
            }
            'VSCode' {
                New-Item -ItemType Directory -Path (Join-Path $candidatePath 'data') -Force | Out-Null
                $preservePaths = @('data')
                $processNames = @('Code')
            }
            'WindowsTerminal' {
                $packages = @(Get-ChildItem -LiteralPath $extractPath -Directory | Where-Object {
                    $_.Name -like 'terminal-*' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'WindowsTerminal.exe') -PathType Leaf)
                })
                if ($packages.Count -ne 1) { throw 'The verified Windows Terminal archive has an unexpected layout.' }
                $candidatePath = $packages[0].FullName
                New-Item -ItemType File -Path (Join-Path $candidatePath '.portable') -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $candidatePath 'LIMENOW-VERSION') -Value $Release.Version -Encoding ASCII
                $preservePaths = @('settings', '.portable')
                $processNames = @('WindowsTerminal', 'OpenConsole')
            }
            'Chromium' {
                $candidatePath = Join-Path $extractPath 'Chrome-bin'
                $processNames = @('chrome', 'crashpad_handler')
            }
        }

        # A download can take time; check again before touching the running installation.
        if (Test-LimeNowToolRunning -Root $Root -ProcessNames $processNames) {
            throw "$Tool is now running; its update will retry on the next setup."
        }
        $verify = {
            param($path)
            (Get-LimeNowInstalledVersion -Tool $Tool -Root $path) -eq $Release.Version
        }
        $beforeSwap = {
            param($path)
            $current = Get-LimeNowInstalledVersion -Tool $Tool -Root $path
            if ($current -and (ConvertTo-LimeNowVersion $current) -gt (ConvertTo-LimeNowVersion $Release.Version)) {
                throw "Another setup installed newer $Tool $current while this update was downloading; keeping it."
            }
        }
        Install-LimeNowStagedDirectory -CandidatePath $candidatePath -DestinationPath $Root `
            -RepairRoot $repairRoot -PreservePaths $preservePaths -BeforeSwap $beforeSwap -Verify $verify
    }
    finally {
        Remove-SetupRepairDirectory -Path $repairRoot
    }
}

function Get-LatestChromiumRelease {
    # Hibbiki publishes independent stable Chromium builds for Windows x64.
    $repository = 'Hibbiki/chromium-win64'
    $release = Get-LimeNowGitHubRelease -Repository $repository
    if ($release.draft -ne $false -or $release.prerelease -ne $false -or
        $release.tag_name -notmatch '^v(?<version>\d+\.\d+\.\d+\.\d+)-r\d+$') {
        throw 'The Chromium publisher returned an unsupported stable release.'
    }

    $version = (ConvertTo-LimeNowVersion $Matches['version']).ToString()
    $asset = Get-LimeNowGitHubAsset -Release $release -Repository $repository -Name 'chrome.7z'
    return [pscustomobject]@{
        Version = $version
        Uri = $asset.Uri
        Hash = $asset.Hash
    }
}

function Repair-Chromium {
    $fallback = [pscustomobject]@{
        Version = $chromiumVersion
        Uri = $chromiumArchiveUrl
        Hash = $chromiumArchiveHash
    }
    Invoke-LimeNowToolUpdate `
        -Name 'Chromium' `
        -Root $chromiumAppRoot `
        -FallbackRelease $fallback `
        -GetInstalledVersion {
            param($root)
            Get-LimeNowInstalledVersion -Tool Chromium -Root $root
        } `
        -GetLatestRelease { Get-LatestChromiumRelease } `
        -InstallRelease {
            param($release)
            Install-LimeNowPortableTool -Tool Chromium -Root $chromiumAppRoot -Release $release
        } `
        -ProcessNames @('chrome')
}

function Ensure-ChromiumLauncher {
    param([string]$DesktopPath = [Environment]::GetFolderPath('Desktop'))

    $executable = Join-Path $chromiumAppRoot 'chrome.exe'
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Chromium executable is missing: $executable"
    }
    New-Item -ItemType Directory -Path $chromiumRoot, $chromiumProfileRoot, $DesktopPath -Force |
        Out-Null

    # Relative paths keep the command portable if the persistent tree moves.
    # Do not use CALL: it would parse the forwarded arguments a second time.
    $wrapper = @'
@echo off
setlocal DisableDelayedExpansion
REM LimeNow managed Chromium launcher with a persistent profile
"%~dp0Application\chrome.exe" --user-data-dir="%~dp0User Data" %*
exit /b %ERRORLEVEL%
'@
    Set-Content -LiteralPath $chromiumWrapper -Value $wrapper -Encoding ASCII

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $DesktopPath 'Chromium.lnk'))
    $shortcut.TargetPath = $executable
    $shortcut.Arguments = "--user-data-dir=`"$chromiumProfileRoot`""
    $shortcut.WorkingDirectory = $documentsRoot
    $shortcut.Description = 'Chromium with a persistent LimeNow profile (Hibbiki stable build)'
    $shortcut.IconLocation = "$executable,0"
    $shortcut.Save()
    Write-SetupLog 'Verified the Chromium command, persistent profile, and desktop shortcut.'
}

function Copy-IfChanged {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null

    $copyRequired = -not (Test-Path -LiteralPath $Destination)
    if (-not $copyRequired) {
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        $copyRequired = $sourceHash -ne $destinationHash
    }

    if ($copyRequired) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
        Write-SetupLog "Repaired file: $Destination"
    }
}

function Resolve-LimeNowPowerShell {
    $powerShell = 'I:\Apps\SalsaNOW\SilentApps\Powershell\pwsh.exe'
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
        $powerShell = Get-Command pwsh.exe -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Source -First 1
    }
    if (-not $powerShell) {
        $hostExecutable = if ($PSVersionTable.PSEdition -eq 'Core') {
            'pwsh.exe'
        }
        else {
            'powershell.exe'
        }
        $powerShell = Join-Path $PSHOME $hostExecutable
    }
    if (-not (Test-Path -LiteralPath $powerShell -PathType Leaf)) {
        throw "Could not find a PowerShell executable for the LimeNow launcher: $powerShell"
    }
    return $powerShell
}

function Ensure-SetupCopies {
    $currentScript = $PSCommandPath
    $currentFullPath = [IO.Path]::GetFullPath($currentScript)
    $canonicalFullPath = [IO.Path]::GetFullPath($canonicalScript)
    $documentsFullPath = [IO.Path]::GetFullPath($documentsScript)

    if ($currentFullPath -ne $canonicalFullPath) {
        Copy-IfChanged -Source $currentScript -Destination $canonicalScript
    }
    if ($currentFullPath -ne $documentsFullPath) {
        Copy-IfChanged -Source $currentScript -Destination $documentsScript
    }

    $powerShell = Resolve-LimeNowPowerShell
    $launcher = @"
@echo off
set "SETUP_MAIN=I:\Apps\SalsaNOW\EasySetup\SalsaNOW-EasySetup.ps1"
set "SETUP_FALLBACK=%USERPROFILE%\Documents\SalsaNOW-EasySetup.ps1"
if exist "%SETUP_MAIN%" (
  "$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SETUP_MAIN%"
) else if exist "%SETUP_FALLBACK%" (
  "$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SETUP_FALLBACK%"
) else (
  echo SalsaNOW Easy Setup could not find its PowerShell script.
  pause
)
"@
    $launcherPath = Join-Path $setupRoot 'SalsaNOW-EasySetup.bat'
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII
    Copy-IfChanged -Source $launcherPath -Destination $documentsBatch
}

function Ensure-StartupHook {
    New-Item -ItemType Directory -Path $salsaRoot -Force | Out-Null

    $beginMarker = 'REM === SALSANOW EASY SETUP BEGIN ==='
    $endMarker = 'REM === SALSANOW EASY SETUP END ==='
    $powerShell = Resolve-LimeNowPowerShell
    $managedBlock = @"
$beginMarker
set "SALSANOW_SETUP_MAIN=I:\Apps\SalsaNOW\EasySetup\SalsaNOW-EasySetup.ps1"
set "SALSANOW_SETUP_FALLBACK=%USERPROFILE%\Documents\SalsaNOW-EasySetup.ps1"
if not exist "%SALSANOW_SETUP_MAIN%" if not exist "%SALSANOW_SETUP_FALLBACK%" (
  "$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Set-TimeZone -Id 'W. Europe Standard Time' -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Path 'I:\Apps\SalsaNOW\EasySetup' -Force | Out-Null; Invoke-WebRequest -Uri '$remoteSetupUrl' -OutFile '%SALSANOW_SETUP_MAIN%' -UseBasicParsing"
)
if exist "%SALSANOW_SETUP_MAIN%" (
  "$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SALSANOW_SETUP_MAIN%" -Startup
) else if exist "%SALSANOW_SETUP_FALLBACK%" (
  "$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SALSANOW_SETUP_FALLBACK%" -Startup
)
$endMarker
"@

    $existing = if (Test-Path -LiteralPath $startupBatch) {
        Get-Content -LiteralPath $startupBatch -Raw
    }
    else {
        "@echo off`r`n"
    }

    $managedPattern = '(?ms)^REM === SALSANOW EASY SETUP BEGIN ===\r?\n.*?^REM === SALSANOW EASY SETUP END ===\r?\n?'
    $unmanaged = [regex]::Replace($existing, $managedPattern, '')
    $unmanaged = [regex]::Replace($unmanaged, '(?im)^\s*@echo\s+off\s*\r?\n?', '')
    # Remove commands installed by the earlier, pre-bootstrap version of this setup.
    $unmanaged = [regex]::Replace(
        $unmanaged,
        '(?im)^\s*PowerShell\.exe .*Set-TimeZone -Id ''W\. Europe Standard Time''.*\r?\n?',
        ''
    )
    $unmanaged = [regex]::Replace(
        $unmanaged,
        '(?im)^\s*PowerShell\.exe .*set-qwertz-keyboard\.ps1.*\r?\n?',
        ''
    )
    $updated = "@echo off`r`n$managedBlock`r`n$($unmanaged.Trim())"
    if (-not $updated.EndsWith("`r`n")) {
        $updated += "`r`n"
    }

    $current = if (Test-Path -LiteralPath $startupBatch) {
        Get-Content -LiteralPath $startupBatch -Raw
    }
    else {
        ''
    }
    if ($current -ne $updated) {
        Set-Content -LiteralPath $startupBatch -Value $updated -Encoding ASCII -NoNewline
        Write-SetupLog "Repaired SalsaNOW startup hook: $startupBatch"
    }
}

function Ensure-TimeZone {
    $expectedTimeZone = 'W. Europe Standard Time'
    if ((Get-TimeZone).Id -ne $expectedTimeZone) {
        Set-TimeZone -Id $expectedTimeZone
        Write-SetupLog "Set Windows time zone to $expectedTimeZone for NVIDIA proxy certificate validation."
    }
}

function Ensure-LimeNowKeyboardNativeType {
    if (-not ([System.Management.Automation.PSTypeName]'LimeNowKeyboardNative').Type) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class LimeNowKeyboardNative
{
    public const uint KlfActivate = 0x00000001;
    public const uint WmInputLangChangeRequest = 0x0050;

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern IntPtr GetKeyboardLayout(uint idThread);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadKeyboardLayout(string pwszKLID, uint flags);

    [DllImport("user32.dll")]
    public static extern IntPtr ActivateKeyboardLayout(IntPtr hkl, uint flags);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
'@
    }
}

function Convert-LimeNowKeyboardHandleToId {
    param([Parameter(Mandatory)][IntPtr]$Handle)

    # HKL values can be sign-extended when returned as IntPtr. Reading the
    # low DWORD from the native byte representation avoids PowerShell 7's
    # overflow when a valid layout handle has its high bit set.
    $value = [BitConverter]::ToUInt32(
        [BitConverter]::GetBytes($Handle.ToInt64()),
        0
    )
    return '{0:X8}' -f $value
}

function Get-LimeNowForegroundKeyboardLayout {
    Ensure-LimeNowKeyboardNativeType
    $windowHandle = [LimeNowKeyboardNative]::GetForegroundWindow()
    if ($windowHandle -eq [IntPtr]::Zero) {
        return $null
    }

    $threadId = [LimeNowKeyboardNative]::GetWindowThreadProcessId(
        $windowHandle,
        [IntPtr]::Zero
    )
    if ($threadId -eq 0) {
        return $null
    }

    $layoutHandle = [LimeNowKeyboardNative]::GetKeyboardLayout($threadId)
    if ($layoutHandle -eq [IntPtr]::Zero) {
        return $null
    }

    $layoutId = Convert-LimeNowKeyboardHandleToId -Handle $layoutHandle
    return [pscustomobject]@{
        WindowHandle = $windowHandle
        LayoutId = $layoutId
        LanguageId = $layoutId.Substring($layoutId.Length - 4)
    }
}

function Get-LimeNowDefaultInputMethodTip {
    try {
        return Get-WinDefaultInputMethodOverride -ErrorAction Stop |
            Select-Object -ExpandProperty InputMethodTip -First 1
    }
    catch {
        return $null
    }
}

function Get-LimeNowUserLanguageList {
    # Get-WinUserLanguageList returns a generic List object under PowerShell 7.
    # Explicit enumeration keeps the individual WinUserLanguage objects intact
    # for filtering and for Set-WinUserLanguageList's typed parameter.
    $rawLanguages = Get-WinUserLanguageList -ErrorAction Stop
    return @(
        foreach ($language in $rawLanguages) {
            $language
        }
    )
}

function New-LimeNowTypedUserLanguageList {
    param([Parameter(Mandatory)][object[]]$Languages)

    $languageList = [System.Collections.Generic.List[Microsoft.InternationalSettings.Commands.WinUserLanguage]]::new()
    foreach ($language in $Languages) {
        [void]$languageList.Add($language)
    }
    return ,$languageList
}

function Ensure-LimeNowTaskbarInputIndicator {
    try {
        # The default language-bar mode is the modern per-user input indicator,
        # which is the selectable language menu in the taskbar. The legacy
        # desktop language bar hides that indicator on Windows 10/11.
        Set-WinLanguageBarOption -ErrorAction Stop

        # Keep the taskbar/docked preference for Windows builds that still read
        # this CTF value. In modern mode the shell owns the visual indicator.
        $langBarKey = 'HKCU:\Software\Microsoft\CTF\LangBar'
        New-Item -Path $langBarKey -Force | Out-Null
        New-ItemProperty `
            -Path $langBarKey `
            -Name 'ShowStatus' `
            -PropertyType DWord `
            -Value 4 `
            -Force | Out-Null

        Write-SetupLog 'Enabled the Windows taskbar keyboard-layout input indicator.'
    }
    catch {
        Write-SetupLog "WARNING: Could not enable the Windows taskbar keyboard-layout input indicator. $($_.Exception.Message)"
    }
}

function Set-QwertzKeyboardState {
    param(
        [Parameter(Mandatory)][string]$LanguageTag,
        [Parameter(Mandatory)][string]$InputTip
    )

    $languages = @(Get-LimeNowUserLanguageList)
    $german = $languages |
        Where-Object LanguageTag -eq $LanguageTag |
        Select-Object -First 1
    if (-not $german) {
        $german = New-WinUserLanguageList $LanguageTag | Select-Object -First 1
    }

    $inputMethods = @($german.InputMethodTips | ForEach-Object { [string]$_ })
    $hasGermanKeyboard = @(
        $inputMethods | Where-Object { $_ -match '(?i)^0407:(?:00000407|A0000407)$' }
    ).Count -gt 0
    if (-not $hasGermanKeyboard) {
        $german.InputMethodTips.Add($InputTip)
    }

    # Keep a second, familiar layout available so Windows has a real choice to
    # expose in the taskbar menu. Existing languages and input methods remain
    # untouched and are kept after German and English.
    $englishLanguageTag = 'en-US'
    $englishInputTip = '0409:00000409'
    $english = $languages |
        Where-Object LanguageTag -eq $englishLanguageTag |
        Select-Object -First 1
    if (-not $english) {
        $english = New-WinUserLanguageList $englishLanguageTag | Select-Object -First 1
    }
    $englishInputMethods = @($english.InputMethodTips | ForEach-Object { [string]$_ })
    $hasEnglishKeyboard = $englishInputMethods -contains $englishInputTip
    if (-not $hasEnglishKeyboard) {
        $english.InputMethodTips.Add($englishInputTip)
    }

    $orderedLanguages = @($german) + @(
        $english
    ) + @(
        $languages | Where-Object {
            $_.LanguageTag -ne $LanguageTag -and
            $_.LanguageTag -ne $englishLanguageTag
        }
    )
    $currentOrder = (@($languages | ForEach-Object LanguageTag) -join '|')
    $desiredOrder = (@($orderedLanguages | ForEach-Object LanguageTag) -join '|')
    if ($currentOrder -ne $desiredOrder -or
        -not $hasGermanKeyboard -or
        -not $hasEnglishKeyboard) {
        $typedLanguageList = New-LimeNowTypedUserLanguageList -Languages $orderedLanguages
        Set-WinUserLanguageList -LanguageList $typedLanguageList -Force
    }

    Set-WinDefaultInputMethodOverride -InputTip $InputTip
    Ensure-LimeNowKeyboardNativeType
    $layoutHandle = [LimeNowKeyboardNative]::LoadKeyboardLayout(
        $InputTip.Substring($InputTip.IndexOf(':') + 1),
        [LimeNowKeyboardNative]::KlfActivate
    )
    if ($layoutHandle -eq [IntPtr]::Zero) {
        throw "Windows could not load the requested keyboard layout: $InputTip"
    }
    [void][LimeNowKeyboardNative]::ActivateKeyboardLayout(
        $layoutHandle,
        [LimeNowKeyboardNative]::KlfActivate
    )

    $foreground = Get-LimeNowForegroundKeyboardLayout
    if ($foreground) {
        [void][LimeNowKeyboardNative]::PostMessage(
            $foreground.WindowHandle,
            [LimeNowKeyboardNative]::WmInputLangChangeRequest,
            [IntPtr]::Zero,
            $layoutHandle
        )
    }
}

function Get-QwertzKeyboardState {
    param([Parameter(Mandatory)][string]$LanguageTag)

    $languages = @(Get-LimeNowUserLanguageList)
    $defaultInputTip = Get-LimeNowDefaultInputMethodTip
    $foreground = Get-LimeNowForegroundKeyboardLayout
    return [pscustomobject]@{
        FirstLanguageTag = if ($languages) { [string]$languages[0].LanguageTag } else { $null }
        DefaultInputTip = if ($defaultInputTip) { [string]$defaultInputTip } else { $null }
        DefaultIsQwertz = [bool]($defaultInputTip -match '(?i)^0407:')
        ActiveLayoutId = if ($foreground) { $foreground.LayoutId } else { $null }
        ActiveIsQwertz = [bool]($foreground -and $foreground.LanguageId -eq '0407')
        ForegroundWindowAvailable = [bool]$foreground
    }
}

function Ensure-QwertzKeyboard {
    $languageTag = 'de-DE'
    $inputTip = '0407:00000407'
    $maxAttempts = 12
    $retryDelaySeconds = 2
    $lastState = $null
    $lastError = $null

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Set-QwertzKeyboardState -LanguageTag $languageTag -InputTip $inputTip
            $lastState = Get-QwertzKeyboardState -LanguageTag $languageTag
            if ($lastState.FirstLanguageTag -eq $languageTag -and
                $lastState.DefaultIsQwertz -and
                $lastState.ActiveIsQwertz) {
                Ensure-LimeNowTaskbarInputIndicator
                Write-SetupLog "Verified German QWERTZ after $attempt attempt(s); active layout $($lastState.ActiveLayoutId)."
                return
            }
            $lastError = if (-not $lastState.ForegroundWindowAvailable) {
                'No foreground input window is ready yet.'
            }
            else {
                "Foreground layout is $($lastState.ActiveLayoutId)."
            }
        }
        catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $maxAttempts) {
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }

    $defaultInputTip = if ($lastState) { $lastState.DefaultInputTip } else { $null }
    $activeLayoutId = if ($lastState) { $lastState.ActiveLayoutId } else { $null }
    Ensure-LimeNowTaskbarInputIndicator
    Write-SetupLog "WARNING: German QWERTZ was not verified after $maxAttempts attempt(s); default=$defaultInputTip active=$activeLayoutId reason=$lastError"
}

function Test-NodeInstall {
    return (Get-LimeNowInstalledVersion -Tool Node -Root $nodeRoot) -eq $nodeVersion
}

function Repair-NodeAndNpm {
    $fallback = [pscustomobject]@{
        Version = $nodeVersion
        Uri = "https://nodejs.org/dist/$nodeVersion/$nodeArchiveName"
        Hash = $nodeArchiveHash
    }
    Invoke-LimeNowToolUpdate -Name 'Node.js LTS and bundled npm' -Root $nodeRoot -FallbackRelease $fallback `
        -GetInstalledVersion { param($path) Get-LimeNowInstalledVersion -Tool Node -Root $path } `
        -GetLatestRelease { Get-LatestNodeRelease } `
        -InstallRelease { param($release) Install-LimeNowPortableTool -Tool Node -Root $nodeRoot -Release $release } `
        -ProcessNames @('node')
}

function Test-GitInstall {
    return (Get-LimeNowInstalledVersion -Tool Git -Root $gitRoot) -eq $gitVersion
}

function Repair-Git {
    $fallback = [pscustomobject]@{ Version = $gitVersion; Uri = $gitArchiveUrl; Hash = $gitArchiveHash }
    Invoke-LimeNowToolUpdate -Name 'Git for Windows' -Root $gitRoot -FallbackRelease $fallback `
        -GetInstalledVersion { param($path) Get-LimeNowInstalledVersion -Tool Git -Root $path } `
        -GetLatestRelease { Get-LatestGitRelease } `
        -InstallRelease { param($release) Install-LimeNowPortableTool -Tool Git -Root $gitRoot -Release $release } `
        -ProcessNames @('git', 'git-remote-https', 'git-remote-http', 'ssh', 'bash', 'sh')
}

function Test-GitHubCliInstall {
    return (Get-LimeNowInstalledVersion -Tool GitHubCli -Root $githubCliRoot -ExecutablePath $githubCliExecutable) -eq $githubCliVersion
}

function Repair-GitHubCli {
    $fallback = [pscustomobject]@{ Version = $githubCliVersion; Uri = $githubCliArchiveUrl; Hash = $githubCliArchiveHash }
    Invoke-LimeNowToolUpdate -Name 'GitHub CLI' -Root $githubCliRoot -FallbackRelease $fallback `
        -GetInstalledVersion { param($path) Get-LimeNowInstalledVersion -Tool GitHubCli -Root $path } `
        -GetLatestRelease { Get-LatestGitHubCliRelease } `
        -InstallRelease { param($release) Install-LimeNowPortableTool -Tool GitHubCli -Root $githubCliRoot -Release $release } `
        -ProcessNames @('gh')
}

function Protect-GitHubCliConfig {
    New-Item -ItemType Directory -Path $githubCliConfigRoot -Force | Out-Null
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $fullControl = [Security.AccessControl.FileSystemRights]::FullControl
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $aclSucceeded = $true
    $items = @(
        Get-Item -LiteralPath $githubCliConfigRoot -Force
    ) + @(
        Get-ChildItem `
            -LiteralPath $githubCliConfigRoot `
            -Force `
            -Recurse `
            -ErrorAction SilentlyContinue
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
                & icacls.exe `
                    $item.FullName `
                    /inheritance:r `
                    /grant:r `
                    $userGrant `
                    $systemGrant `
                    /Q `
                    2>$null |
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

    if ($aclSucceeded) {
        Write-SetupLog 'Restricted persistent GitHub CLI authentication storage to the current user and SYSTEM.'
    }
    else {
        Write-SetupLog 'WARNING: The storage filesystem could not fully restrict GitHub CLI authentication files.'
    }
}

function Ensure-GitHubCliLaunchers {
    New-Item -ItemType Directory -Path $githubCliRoot, $githubCliConfigRoot -Force | Out-Null
    $wrapper = @"
@echo off
set "GH_CONFIG_DIR=$githubCliConfigRoot"
"$githubCliExecutable" %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $githubCliWrapper -Value $wrapper -Encoding ASCII

    $loginScriptTemplate = @'
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:GH_CONFIG_DIR = '__GITHUB_CLI_CONFIG_ROOT__'
$env:GH_BROWSER = ((Join-Path $env:SystemRoot 'System32\cmd.exe').Replace('\', '/') + ' /d /c rem')
$env:NO_COLOR = '1'

try {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
}
catch {}
try {
    $Host.UI.RawUI.WindowTitle = 'LimeNow GitHub CLI sign in'
}
catch {}

function Wait-GitHubCliWindow {
    [void](Read-Host 'Press Enter to close')
}

Write-Host ''
Write-Host 'LimeNow GitHub CLI persistent sign in'
Write-Host '====================================='
Write-Host 'WARNING: GitHub CLI will store a reusable token in SalsaNOW persistent storage.'
Write-Host 'Anyone with access to that storage may be able to use the same GitHub account access.'
Write-Host ''

$refreshExistingAuthorization = $false
& '__GITHUB_CLI_EXECUTABLE__' auth status --hostname github.com *> $null
if ($LASTEXITCODE -eq 0) {
    $authMetadataJson = & '__GITHUB_CLI_EXECUTABLE__' auth status `
        --hostname github.com `
        --active `
        --json hosts `
        2>$null
    $activeAccount = if ($LASTEXITCODE -eq 0) {
        @((ConvertFrom-Json $authMetadataJson).hosts.'github.com')[0]
    }
    else {
        $null
    }
    $activeScopes = if ($activeAccount) {
        @(([string]$activeAccount.scopes) -split ',\s*')
    }
    else {
        @()
    }
    if ($activeScopes -contains 'workflow') {
        Write-Host 'GitHub CLI is already signed in with repository and workflow access:'
        & '__GITHUB_CLI_EXECUTABLE__' auth status --hostname github.com
        Write-Host ''
        Wait-GitHubCliWindow
        exit 0
    }

    $refreshExistingAuthorization = $true
    Write-Host 'GitHub CLI is signed in but needs the workflow permission.'
    Write-Host 'That permission lets Git push changes to GitHub Actions workflow files.'
    Write-Host 'GitHub will ask you to approve the additional permission.'
    Write-Host ''
}

# This compact offline QR encodes https://github.com/login/device. Each terminal
# row represents two QR rows with Unicode half-block characters.
$qrWidth = 29
$qrRows = @(
    '█▀▀▀▀▀█ █▄▀▄▄ ▄█▀█▀▀▀ █▀▀▀▀▀█'
    '█ ███ █ ▄▀▀ █▀▀▀▄▄▀ ▀ █ ███ █'
    '█ ▀▀▀ █   ▀█▀▀▄  ▄▄█▄ █ ▀▀▀ █'
    '▀▀▀▀▀▀▀ █ ▀ ▀▄█ ▀▄▀▄▀ ▀▀▀▀▀▀▀'
    '▀ ██▄▀▀█▄██▄█▀▀▄██▄▄▄ █▄▄▀ ▀█'
    '  █ ▄▀▀▄ ▄ █ ▄██  █▄██▄▀▄ ▀▀▄'
    '▄▀█▄▄█▀▀▄█▄▀ ▄  ▀█ █  ▄  ▀█▄▄'
    '██▀▄▀▄▀▀▄▄ ▄ ▄▀▄  ███▄█▄▄ ▀█▀'
    '  ▄▀  ▀ ▄▀  █▄    ▀▀▀  ▄▀█▄█'
    '▀ █▀▀▄▀▄ ▄▀▀▀  ▄▄▄▄ ▀ ███ █'
    ' ▀    ▀▀█▀▄ ██▄█▀▀▀ █▀▀▀███▄▄'
    '█▀▀▀▀▀█ ██ ▀█▀  ▀ ▀▀█ ▀ ██ █'
    '█ ███ █ ▄▀█▄▄▄██▄▀ ▄▀█▀██▄▀▄▀'
    '█ ▀▀▀ █ ▀▀▄▄ █▄     █▄ █ ▄▀▄▀'
    '▀▀▀▀▀▀▀ ▀ ▀ ▀▀▀   ▀▀▀▀▀    ▀'
)
$quietRow = ' ' * ($qrWidth + 8)

Write-Host 'Scan this QR with your phone to open GitHub on that device:'
foreach ($unused in 1..2) {
    Write-Host $quietRow -ForegroundColor Black -BackgroundColor White
}
foreach ($row in $qrRows) {
    $renderedRow = '    ' + $row.PadRight($qrWidth) + '    '
    Write-Host $renderedRow -ForegroundColor Black -BackgroundColor White
}
foreach ($unused in 1..2) {
    Write-Host $quietRow -ForegroundColor Black -BackgroundColor White
}
Write-Host ''
Write-Host 'If you cannot scan it, open this URL on your phone or local computer:'
Write-Host '__GITHUB_CLI_DEVICE_URL__'
Write-Host ''
Write-Host 'GitHub CLI will show an 8-character one-time code below.'
Write-Host 'Enter that code on your other device and approve GitHub CLI there.'
Write-Host 'No browser will open inside the GeForce NOW session.'
Write-Host ''

# Redirected stdin makes the managed GitHub CLI use its headless device flow: it
# prints the code, skips its local browser prompt, and immediately starts polling.
if ($refreshExistingAuthorization) {
    '' | & '__GITHUB_CLI_EXECUTABLE__' auth refresh --hostname github.com --scopes workflow --clipboard --insecure-storage
}
else {
    '' | & '__GITHUB_CLI_EXECUTABLE__' auth login --hostname github.com --git-protocol https --web --scopes workflow --clipboard --insecure-storage
}
$loginExitCode = $LASTEXITCODE
if ($loginExitCode -ne 0) {
    Write-Host ''
    Write-Host 'GitHub CLI authorization failed or was cancelled.'
    Wait-GitHubCliWindow
    exit $loginExitCode
}

Write-Host ''
Write-Host 'GitHub CLI authorization succeeded and will persist across GFN machines.'
& '__GITHUB_CLI_EXECUTABLE__' auth status --hostname github.com
Write-Host ''
Wait-GitHubCliWindow
'@
    $loginScript = $loginScriptTemplate.Replace(
        '__GITHUB_CLI_CONFIG_ROOT__',
        $githubCliConfigRoot.Replace("'", "''")
    )
    $loginScript = $loginScript.Replace(
        '__GITHUB_CLI_EXECUTABLE__',
        $githubCliExecutable.Replace("'", "''")
    )
    $loginScript = $loginScript.Replace(
        '__GITHUB_CLI_DEVICE_URL__',
        $githubCliDeviceUrl.Replace("'", "''")
    )
    [IO.File]::WriteAllText(
        $githubCliLoginScript,
        $loginScript,
        [Text.UTF8Encoding]::new($true)
    )

    $powerShell = Resolve-LimeNowPowerShell
    $loginLauncher = @"
@echo off
"$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$githubCliLoginScript"
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $githubCliLoginLauncher -Value $loginLauncher -Encoding ASCII
    Write-SetupLog 'Verified persistent GitHub CLI command and QR device sign-in launchers.'
}

function Test-GitHubCliAuthentication {
    & $githubCliWrapper auth status --hostname github.com *> $null
    return $LASTEXITCODE -eq 0
}

function Ensure-GitHubCliAuthentication {
    $hostsPath = Join-Path $githubCliConfigRoot 'hosts.yml'
    if (-not (Test-Path -LiteralPath $hostsPath -PathType Leaf)) {
        Write-SetupLog 'GitHub CLI is ready but not signed in. Use the GitHub CLI Sign In desktop shortcut.'
        return
    }

    if (Test-GitHubCliAuthentication) {
        Write-SetupLog 'Verified persistent GitHub CLI authentication.'
    }
    else {
        Write-SetupLog 'WARNING: Stored GitHub CLI authentication could not be verified; use the sign-in shortcut to repair it.'
    }
}

function Test-VSCodeInstall {
    return (Get-LimeNowInstalledVersion -Tool VSCode -Root $vscodeRoot) -eq $vscodeVersion
}

function Repair-VSCode {
    $fallback = [pscustomobject]@{ Version = $vscodeVersion; Uri = $vscodeArchiveUrl; Hash = $vscodeArchiveHash }
    Invoke-LimeNowToolUpdate -Name 'Visual Studio Code' -Root $vscodeRoot -FallbackRelease $fallback `
        -GetInstalledVersion { param($path) Get-LimeNowInstalledVersion -Tool VSCode -Root $path } `
        -GetLatestRelease { Get-LatestVSCodeRelease } `
        -InstallRelease { param($release) Install-LimeNowPortableTool -Tool VSCode -Root $vscodeRoot -Release $release } `
        -ProcessNames @('Code')
}

function Test-WindowsTerminalInstall {
    return (Get-LimeNowInstalledVersion -Tool WindowsTerminal -Root $terminalRoot) -eq $terminalVersion
}

function Repair-WindowsTerminal {
    $fallback = [pscustomobject]@{ Version = $terminalVersion; Uri = $terminalArchiveUrl; Hash = $terminalArchiveHash }
    Invoke-LimeNowToolUpdate -Name 'Windows Terminal' -Root $terminalRoot -FallbackRelease $fallback `
        -GetInstalledVersion { param($path) Get-LimeNowInstalledVersion -Tool WindowsTerminal -Root $path } `
        -GetLatestRelease { Get-LatestWindowsTerminalRelease } `
        -InstallRelease { param($release) Install-LimeNowPortableTool -Tool WindowsTerminal -Root $terminalRoot -Release $release } `
        -ProcessNames @('WindowsTerminal', 'OpenConsole')
}

function Get-GitHubCliCredentialHelper {
    $configRootForGit = $githubCliConfigRoot.Replace('\', '/')
    $ghExecutableForGit = $githubCliExecutable.Replace('\', '/')
    return "!f() { GH_CONFIG_DIR='$configRootForGit' '$ghExecutableForGit' auth git-credential `"`$@`"; }; f"
}

function Ensure-DeveloperEnvironment {
    New-Item -ItemType Directory -Path $npmGlobalRoot, $npmCacheRoot -Force | Out-Null
    $requiredPathEntries = @(
        $nodeRoot,
        $codexBinRoot,
        $npmGlobalRoot,
        $githubCliRoot,
        (Join-Path $gitRoot 'cmd'),
        (Join-Path $vscodeRoot 'bin'),
        $terminalRoot,
        $chromiumRoot
    )

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $userParts = @($userPath -split ';' | Where-Object { $_ })
    $newUserParts = @($requiredPathEntries)
    foreach ($part in $userParts) {
        if (-not ($newUserParts | Where-Object { $_ -eq $part })) {
            $newUserParts += $part
        }
    }
    $newUserPath = $newUserParts -join ';'
    if ($newUserPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    }

    $processParts = @($env:Path -split ';' | Where-Object { $_ })
    $newProcessParts = @($requiredPathEntries)
    foreach ($part in $processParts) {
        if (-not ($newProcessParts | Where-Object { $_ -eq $part })) {
            $newProcessParts += $part
        }
    }
    $env:Path = $newProcessParts -join ';'

    $env:NODE_USE_SYSTEM_CA = '1'
    $env:NPM_CONFIG_PREFIX = $npmGlobalRoot
    $env:NPM_CONFIG_CACHE = $npmCacheRoot
    $env:GH_CONFIG_DIR = $githubCliConfigRoot
    $env:GH_NO_UPDATE_NOTIFIER = '1'
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', '1', 'User')
    [Environment]::SetEnvironmentVariable('NPM_CONFIG_PREFIX', $npmGlobalRoot, 'User')
    [Environment]::SetEnvironmentVariable('NPM_CONFIG_CACHE', $npmCacheRoot, 'User')
    [Environment]::SetEnvironmentVariable('GH_CONFIG_DIR', $githubCliConfigRoot, 'User')
    [Environment]::SetEnvironmentVariable('GH_NO_UPDATE_NOTIFIER', '1', 'User')

    $gitExecutable = Join-Path $gitRoot 'cmd\git.exe'
    $credentialHelper = Get-GitHubCliCredentialHelper
    foreach ($credentialHost in @('github.com', 'gist.github.com')) {
        $credentialKey = "credential.https://$credentialHost.helper"
        & $gitExecutable config --global --replace-all $credentialKey ''
        if ($LASTEXITCODE -ne 0) {
            throw "Could not reset the Git credential helper for $credentialHost."
        }
        & $gitExecutable config --global --add $credentialKey $credentialHelper
        if ($LASTEXITCODE -ne 0) {
            throw "Could not configure persistent GitHub CLI credentials for $credentialHost."
        }
    }
    Write-SetupLog 'Verified persistent developer-tool PATH, GitHub CLI configuration, and Windows certificate-store support.'
}

function Get-InstalledCodexVersion {
    $codexCommand = Join-Path $npmGlobalRoot 'codex.cmd'
    $packageManifest = Join-Path $npmGlobalRoot 'node_modules\@openai\codex\package.json'
    if (-not (Test-Path -LiteralPath $codexCommand) -or
        -not (Test-Path -LiteralPath $packageManifest)) {
        return $null
    }

    try {
        $manifest = Get-Content -LiteralPath $packageManifest -Raw | ConvertFrom-Json
        $version = [string]$manifest.version
        if ($version -notmatch '^\d+\.\d+\.\d+$') {
            return $null
        }
        $versionOutput = (& $codexCommand --version 2>$null | Select-Object -First 1)
        if ($versionOutput -ne "codex-cli $version") {
            return $null
        }
        return $version
    }
    catch {
        return $null
    }
}

function Test-CodexInstall {
    param([Parameter(Mandatory)][string]$ExpectedVersion)

    return (Get-InstalledCodexVersion) -eq $ExpectedVersion
}

function Get-LatestCodexVersion {
    try {
        $metadata = Invoke-RestMethod `
            -Uri $codexRegistryUrl `
            -Headers @{ 'Cache-Control' = 'no-cache'; 'User-Agent' = 'LimeNow-Codex-Updater' } `
            -TimeoutSec 30
        $latestVersion = [string]$metadata.version
        if ($latestVersion -notmatch '^\d+\.\d+\.\d+$') {
            throw "The npm registry returned an invalid stable Codex version: $latestVersion"
        }
        Write-SetupLog "Checked npm for the latest stable Codex CLI: $latestVersion."
        return $latestVersion
    }
    catch {
        Write-SetupLog "Codex update check unavailable; keeping the installed version when it is usable. $($_.Exception.Message)"
        return $null
    }
}

function Repair-CodexCli {
    $installedVersion = Get-InstalledCodexVersion
    $latestVersion = Get-LatestCodexVersion
    if (-not $latestVersion) {
        if ($installedVersion) {
            Write-SetupLog "Verified usable official Codex CLI $installedVersion; update will retry on the next online setup."
            return
        }
        $latestVersion = $codexVersion
    }

    if ([version]$latestVersion -lt [version]$codexVersion) {
        Write-SetupLog "The registry reported older Codex CLI $latestVersion; using the known-good floor $codexVersion."
        $latestVersion = $codexVersion
    }
    if ($installedVersion -and [version]$latestVersion -lt [version]$installedVersion) {
        Write-SetupLog "Verified official Codex CLI $installedVersion; refusing to downgrade to registry version $latestVersion."
        return
    }

    if ($installedVersion -eq $latestVersion) {
        Write-SetupLog "Verified official Codex CLI $installedVersion (latest stable release)."
        return
    }

    if (Get-Process -Name 'codex' -ErrorAction SilentlyContinue) {
        if ($installedVersion) {
            Write-SetupLog "Codex CLI $installedVersion is currently running; update deferred until the next setup after Codex exits."
            return
        }
        throw 'Codex CLI needs installation but a Codex process is running. Close Codex and run LimeNow again.'
    }

    $npmCommand = Join-Path $nodeRoot 'npm.cmd'
    $action = if ($installedVersion) { 'updating' } else { 'installing' }
    Write-SetupLog "Codex CLI is ${action}: official @openai/codex@$latestVersion."
    & $npmCommand install --global "@openai/codex@$latestVersion" `
        --prefix $npmGlobalRoot `
        --cache $npmCacheRoot `
        --offline=false `
        --no-audit `
        --no-fund `
        --loglevel error
    $npmSucceeded = $?
    if (-not $npmSucceeded) {
        throw 'npm failed to install @openai/codex.'
    }
    if (-not (Test-CodexInstall -ExpectedVersion $latestVersion)) {
        throw 'Codex CLI verification failed after npm installation.'
    }

    Write-SetupLog "Installed/repaired official Codex CLI $latestVersion."
}

function Ensure-CodexStateManager {
    $localManager = Join-Path (Split-Path -Parent $PSCommandPath) 'codex-state.ps1'
    $repairRoot = Join-Path $setupRoot ('codex-state-repair-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null
        $candidate = Join-Path $repairRoot 'codex-state.ps1'
        Get-LimeNowManagedScriptCandidate `
            -LocalPath $localManager `
            -RemoteUrl $codexStateManagerUrl `
            -CandidatePath $candidate `
            -Description 'Codex state manager'
        Copy-IfChanged -Source $candidate -Destination $codexStateManager
    }
    finally {
        Remove-SetupRepairDirectory -Path $repairRoot
    }
}

function Ensure-CodexLauncher {
    $codexCommand = Join-Path $npmGlobalRoot 'codex.cmd'
    if (-not (Test-Path -LiteralPath $codexCommand)) {
        throw "Codex command is missing: $codexCommand"
    }
    $powerShell = Resolve-LimeNowPowerShell

    Ensure-CodexStateManager
    & $codexStateManager `
        -Action Initialize `
        -PersistentRoot $codexRoot `
        -SessionCodexHome (Join-Path $env:USERPROFILE '.codex') |
        ForEach-Object { Write-SetupLog $_ }

    New-Item -ItemType Directory -Path $codexBinRoot -Force | Out-Null
    $wrapper = @"
@echo off
REM LimeNow managed Codex persistence wrapper
"$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$codexStateManager" -Action Run -PersistentRoot "$codexRoot" -CodexCommand "$codexCommand" %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $codexWrapper -Value $wrapper -Encoding ASCII

    $launcherPath = Join-Path $limeNowAppsRoot 'Open-Codex.cmd'
    $launcher = @"
@echo off
set "NODE_USE_SYSTEM_CA=1"
set "NPM_CONFIG_PREFIX=$npmGlobalRoot"
set "NPM_CONFIG_CACHE=$npmCacheRoot"
set "PATH=$nodeRoot;$codexBinRoot;$npmGlobalRoot;%PATH%"
cd /d "%USERPROFILE%\Documents"
call "$codexWrapper" %*
"@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding ASCII

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Codex CLI.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $launcherPath
    $shortcut.WorkingDirectory = $documentsRoot
    $shortcut.Description = 'OpenAI Codex CLI with persistent LimeNow auth and sessions'
    $shortcut.IconLocation = "$(Join-Path $nodeRoot 'node.exe'),0"
    $shortcut.Save()
    Write-SetupLog 'Verified the Codex launcher, minimal persistent state, and desktop shortcut.'
}

function Ensure-DeveloperCommandShims {
    $shimRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    New-Item -ItemType Directory -Path $shimRoot -Force | Out-Null
    $commands = [ordered]@{
        'node.cmd' = Join-Path $nodeRoot 'node.exe'
        'npm.cmd' = Join-Path $nodeRoot 'npm.cmd'
        'npx.cmd' = Join-Path $nodeRoot 'npx.cmd'
        'codex.cmd' = $codexWrapper
        'git.cmd' = Join-Path $gitRoot 'cmd\git.exe'
        'gh.cmd' = $githubCliWrapper
        'code.cmd' = Join-Path $vscodeRoot 'bin\code.cmd'
        'wt.cmd' = Join-Path $terminalRoot 'WindowsTerminal.exe'
        'chromium.cmd' = $chromiumWrapper
    }

    foreach ($entry in $commands.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) { continue }
        $shimPath = Join-Path $shimRoot $entry.Key
        # Chromium is the final command in its shim; omit CALL to avoid parsing URLs twice.
        $callKeyword = if ($entry.Key -ne 'chromium.cmd' -and
            $entry.Value.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase)) {
            'call '
        }
        else {
            ''
        }
        $shim = @"
@echo off
REM LimeNow managed developer command shim
$callKeyword"$($entry.Value)" %*
"@
        if (Test-Path -LiteralPath $shimPath) {
            $existing = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
            if ($existing -and $existing -notmatch 'LimeNow managed developer command shim') {
                Write-SetupLog "WARNING: Preserved an unrelated command shim: $shimPath"
                continue
            }
        }
        Set-Content -LiteralPath $shimPath -Value $shim -Encoding ASCII
    }
    Write-SetupLog 'Verified immediate Node.js, npm, npx, Codex, Git, GitHub CLI, code, wt, and Chromium command shims.'
}

function Ensure-DeveloperDesktopShortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell

    $codeExecutable = Join-Path $vscodeRoot 'Code.exe'
    if (-not (Test-Path -LiteralPath $codeExecutable)) {
        throw "Visual Studio Code executable is missing: $codeExecutable"
    }
    $codeShortcut = $shell.CreateShortcut((Join-Path $desktop 'Visual Studio Code.lnk'))
    $codeShortcut.TargetPath = $codeExecutable
    $codeShortcut.WorkingDirectory = $documentsRoot
    $codeShortcut.Description = 'Visual Studio Code (persistent LimeNow portable installation)'
    $codeShortcut.IconLocation = "$codeExecutable,0"
    $codeShortcut.Save()

    $terminalExecutable = Join-Path $terminalRoot 'WindowsTerminal.exe'
    if (-not (Test-Path -LiteralPath $terminalExecutable)) {
        throw "Windows Terminal executable is missing: $terminalExecutable"
    }
    $terminalShortcut = $shell.CreateShortcut((Join-Path $desktop 'Windows Terminal.lnk'))
    $terminalShortcut.TargetPath = $terminalExecutable
    $terminalShortcut.Arguments = "-d `"$documentsRoot`" cmd.exe"
    $terminalShortcut.WorkingDirectory = $documentsRoot
    $terminalShortcut.Description = 'Portable Windows Terminal with Command Prompt (LimeNow)'
    $terminalShortcut.IconLocation = "$terminalExecutable,0"
    $terminalShortcut.Save()

    $githubShortcut = $shell.CreateShortcut((Join-Path $desktop 'GitHub CLI Sign In.lnk'))
    $githubShortcut.TargetPath = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $githubShortcut.Arguments = "/d /c `"`"$githubCliLoginLauncher`"`""
    $githubShortcut.WorkingDirectory = $documentsRoot
    $githubShortcut.Description = 'Sign in to GitHub CLI with persistent LimeNow authentication'
    $githubShortcut.IconLocation = "$githubCliExecutable,0"
    $githubShortcut.Save()

    Write-SetupLog 'Verified persistent Visual Studio Code, Windows Terminal, and GitHub CLI sign-in shortcuts.'
}

function Test-LimeSshInstall {
    $licensePath = Join-Path $limeSshRoot 'UPTERM-APACHE-2.0-LICENSE'
    $buildInfoPath = Join-Path $limeSshRoot 'LIMESSH-BUILD.txt'
    if (-not (Test-Path -LiteralPath $limeSshExecutable) -or
        -not (Test-Path -LiteralPath $licensePath) -or
        -not (Test-Path -LiteralPath $buildInfoPath)) {
        return $false
    }
    $binaryHash = (Get-FileHash -LiteralPath $limeSshExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    $licenseHash = (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $buildInfo = Get-Content -LiteralPath $buildInfoPath -Raw
    return $binaryHash -eq $limeSshAssetHash -and
        $licenseHash -eq $limeSshLicenseHash -and
        $buildInfo -match "LimeSSH $([regex]::Escape($limeSshVersion))"
}

function Repair-LimeSsh {
    if (Test-LimeSshInstall) {
        Write-SetupLog "Verified pinned LimeSSH $limeSshVersion preview."
        return
    }

    if (Test-Path -LiteralPath $limeSshManager) {
        try {
            & $limeSshManager -Action Stop -InstallRoot $limeSshRoot
        }
        catch {
            Write-SetupLog "WARNING: Unable to stop the old LimeSSH process before repair: $($_.Exception.Message)"
        }
    }

    Write-SetupLog "LimeSSH is missing or incomplete; installing pinned preview $limeSshVersion."
    $repairRoot = Join-Path $setupRoot ('limessh-repair-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null
        $downloadedBinary = Join-Path $repairRoot 'LimeSSH.exe'
        $downloadedLicense = Join-Path $repairRoot 'UPTERM-APACHE-2.0-LICENSE'
        Get-VerifiedDownload `
            -Uri $limeSshAssetUrl `
            -Destination $downloadedBinary `
            -ExpectedHash $limeSshAssetHash
        Get-VerifiedDownload `
            -Uri $limeSshLicenseUrl `
            -Destination $downloadedLicense `
            -ExpectedHash $limeSshLicenseHash

        New-Item -ItemType Directory -Path $limeSshRoot -Force | Out-Null
        Copy-Item -LiteralPath $downloadedBinary -Destination $limeSshExecutable -Force
        Copy-Item `
            -LiteralPath $downloadedLicense `
            -Destination (Join-Path $limeSshRoot 'UPTERM-APACHE-2.0-LICENSE') `
            -Force
        @"
LimeSSH $limeSshVersion

Upstream: https://github.com/owenthereal/upterm
Upstream commit: 1a8b11e43b117d4dcfc8d7d92d421cb3f1abbca9
Go toolchain: 1.26.5
LimeSSH SHA-256: $limeSshAssetHash
License: Apache-2.0 (UPTERM-APACHE-2.0-LICENSE)
"@ | Set-Content -LiteralPath (Join-Path $limeSshRoot 'LIMESSH-BUILD.txt') -Encoding utf8

        if (-not (Test-LimeSshInstall)) {
            throw 'LimeSSH verification failed after installation.'
        }
        Write-SetupLog "Installed pinned LimeSSH $limeSshVersion preview."
    }
    finally {
        Remove-SetupRepairDirectory -Path $repairRoot
    }
}

function Ensure-LimeSshManager {
    $localManager = Join-Path (Split-Path -Parent $PSCommandPath) 'remote-access.ps1'
    $repairRoot = Join-Path $setupRoot ('limessh-manager-repair-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null
        $candidate = Join-Path $repairRoot 'remote-access.ps1'
        Get-LimeNowManagedScriptCandidate `
            -LocalPath $localManager `
            -RemoteUrl $limeSshManagerUrl `
            -CandidatePath $candidate `
            -Description 'LimeSSH remote-access manager'
        Copy-IfChanged -Source $candidate -Destination $limeSshManager
    }
    finally {
        Remove-SetupRepairDirectory -Path $repairRoot
    }
}

function Ensure-LimeSshShortcut {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shell = New-Object -ComObject WScript.Shell
    $powerShell = Resolve-LimeNowPowerShell
    $shortcut = $shell.CreateShortcut((Join-Path $desktop 'LimeSSH Remote Access.lnk'))
    $shortcut.TargetPath = $powerShell
    $shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$limeSshManager`" -Action Manage"
    $shortcut.WorkingDirectory = $documentsRoot
    $shortcut.Description = 'Manage public-key-only LimeSSH remote access'
    $shortcut.Save()
    Write-SetupLog 'Verified the LimeSSH remote-access desktop shortcut.'
}

function Ensure-LimeSshRemoteAccess {
    try {
        Repair-LimeSsh
        Ensure-LimeSshManager
        Ensure-LimeSshShortcut

        $configPath = Join-Path $limeSshRoot 'config.json'
        if ($Startup) {
            if (Test-Path -LiteralPath $configPath) {
                & $limeSshManager -Action Start -Startup -InstallRoot $limeSshRoot | Out-Null
                Write-SetupLog 'Verified configured LimeSSH remote access.'
            }
            return
        }

        if (-not (Test-Path -LiteralPath $configPath)) {
            Write-Host ''
            Write-Host 'Remote development (preview)' -ForegroundColor Cyan
            Write-Host 'LimeSSH can expose this GFN session through public-key-only SSH.'
            $enable = Read-Host 'Enable remote access now? [y/N]'
            if ($enable -match '^(?i:y|yes)$') {
                & $limeSshManager -Action Configure -InstallRoot $limeSshRoot
            }
        }
        else {
            & $limeSshManager -Action Start -InstallRoot $limeSshRoot
        }
    }
    catch {
        Write-SetupLog "WARNING: LimeSSH preview setup failed without blocking LimeNow: $($_.Exception.Message)"
    }
}

function Get-LimeNowModrinthAsset {
    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'LimeNow-SalsaNOW-Extension'
    }
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/JohnDeved/LimeNow/releases/tags/$modrinthReleaseTag" `
        -Headers $headers `
        -TimeoutSec 30
    $asset = $release.assets |
        Where-Object name -EQ $modrinthAssetName |
        Select-Object -First 1

    if (-not $asset) {
        throw "The LimeNow Modrinth compatibility release has no $modrinthAssetName asset."
    }
    [pscustomobject]@{
        Version = $release.tag_name
        Name = $asset.name
        Url = $asset.browser_download_url
        Digest = $asset.digest
    }
}

function Test-ModrinthCompatibilityInstall {
    $executable = Join-Path $modrinthRoot 'Modrinth App.exe'
    $sumsPath = Join-Path $modrinthRoot 'SHA256SUMS'
    $buildInfo = Join-Path $modrinthRoot 'LIMENOW-BUILD.txt'
    if (-not (Test-Path -LiteralPath $executable) -or
        -not (Test-Path -LiteralPath $sumsPath) -or
        -not (Test-Path -LiteralPath $buildInfo)) {
        return $false
    }

    $sumLine = Get-Content -LiteralPath $sumsPath |
        Where-Object { $_ -match '^[a-fA-F0-9]{64}\s+\*?Modrinth App\.exe$' } |
        Select-Object -First 1
    if (-not $sumLine) {
        return $false
    }
    $expectedHash = ($sumLine -split '\s+', 2)[0].ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
    return $actualHash -eq $expectedHash
}

function Repair-ModrinthLauncher {
    if (Test-ModrinthCompatibilityInstall) {
        Write-SetupLog 'Verified portable Modrinth GFN compatibility files.'
        return
    }

    if (Get-Process -Name 'Modrinth App' -ErrorAction SilentlyContinue) {
        throw 'Modrinth needs repair but is running. Close Modrinth and run LimeNow again.'
    }

    Write-SetupLog 'Modrinth is missing or incomplete; starting compatibility self-repair.'
    $asset = Get-LimeNowModrinthAsset
    $repairRoot = Join-Path $setupRoot ('repair-' + [Guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $repairRoot $asset.Name
    $extractPath = Join-Path $repairRoot 'extracted'
    New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null

    try {
        Invoke-WebRequest -Uri $asset.Url -OutFile $archivePath -UseBasicParsing -TimeoutSec 120

        if (-not $asset.Digest -or -not $asset.Digest.StartsWith('sha256:')) {
            throw 'GitHub did not provide an SHA-256 digest for the Modrinth compatibility archive.'
        }
        $expectedHash = $asset.Digest.Substring(7).ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Modrinth archive checksum mismatch. Expected $expectedHash but received $actualHash."
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath
        $packageExecutable = Join-Path $extractPath 'Modrinth App.exe'
        $packageSums = Join-Path $extractPath 'SHA256SUMS'
        if (-not (Test-Path -LiteralPath $packageExecutable) -or
            -not (Test-Path -LiteralPath $packageSums)) {
            throw 'The verified Modrinth archive is missing its executable or checksum manifest.'
        }
        $sumLine = Get-Content -LiteralPath $packageSums |
            Where-Object { $_ -match '^[a-fA-F0-9]{64}\s+\*?Modrinth App\.exe$' } |
            Select-Object -First 1
        if (-not $sumLine) {
            throw 'The Modrinth compatibility checksum manifest is invalid.'
        }
        $expectedExecutableHash = ($sumLine -split '\s+', 2)[0].ToLowerInvariant()
        $actualExecutableHash = (Get-FileHash -LiteralPath $packageExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualExecutableHash -ne $expectedExecutableHash) {
            throw 'The Modrinth executable does not match its packaged SHA-256 checksum.'
        }

        New-Item -ItemType Directory -Path $modrinthRoot -Force | Out-Null
        Get-ChildItem -LiteralPath $extractPath -Force |
            Copy-Item -Destination $modrinthRoot -Recurse -Force
        if (-not (Test-ModrinthCompatibilityInstall)) {
            throw 'Modrinth verification failed after copying the compatibility build.'
        }
        Write-SetupLog "Installed/repaired portable Modrinth compatibility build $($asset.Version)."
    }
    finally {
        $resolvedRepairRoot = [IO.Path]::GetFullPath($repairRoot)
        $resolvedSetupRoot = [IO.Path]::GetFullPath($setupRoot)
        if ($resolvedRepairRoot.StartsWith($resolvedSetupRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolvedRepairRoot)) {
            Remove-Item -LiteralPath $resolvedRepairRoot -Recurse -Force
        }
    }
}

function Ensure-ModrinthPersistentData {
    New-Item -ItemType Directory -Path $modrinthDataRoot -Force | Out-Null
    $appDataParent = Split-Path -Parent $modrinthAppData
    New-Item -ItemType Directory -Path $appDataParent -Force | Out-Null

    if (Test-Path -LiteralPath $modrinthAppData) {
        $sourceItem = Get-Item -LiteralPath $modrinthAppData -Force
        if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $probeName = '.limenow-junction-check-' + [Guid]::NewGuid().ToString('N')
            $targetProbe = Join-Path $modrinthDataRoot $probeName
            $sourceProbe = Join-Path $modrinthAppData $probeName
            $probeValue = [Guid]::NewGuid().ToString('N')
            $probeCompleted = $false
            try {
                Set-Content -LiteralPath $targetProbe -Value $probeValue -Encoding ASCII -NoNewline
                $probeCompleted = (Test-Path -LiteralPath $sourceProbe) -and
                    (Get-Content -LiteralPath $sourceProbe -Raw) -eq $probeValue
            }
            catch {
                # SalsaNOW may make the persistent data directory read-only while
                # Modrinth is closing. A read-only target check is still safe when
                # the existing link names the expected data directory.
                $probeCompleted = $false
            }
            finally {
                if (Test-Path -LiteralPath $targetProbe) {
                    Remove-Item -LiteralPath $targetProbe -Force
                }
            }
            if ($probeCompleted) {
                Write-SetupLog 'Verified persistent Modrinth app-data junction.'
                return
            }

            $reportedTarget = ([string](@($sourceItem.Target)[0])).TrimEnd('\', '/')
            if ($reportedTarget -match '(?i)^ice\\harddiskvolume') {
                # PowerShell can omit the leading ``\\dev`` when displaying a
                # device-namespace symbolic-link target under constrained mode.
                $reportedTarget = '\dev' + $reportedTarget
            }
            $expectedTargetSuffix = ([IO.Path]::GetFullPath($modrinthDataRoot)).Substring(2).TrimEnd('\', '/')
            $readOnlyTargetMatches = $reportedTarget.EndsWith(
                $expectedTargetSuffix,
                [StringComparison]::OrdinalIgnoreCase
            ) -and (
                $reportedTarget -eq [IO.Path]::GetFullPath($modrinthDataRoot) -or
                $reportedTarget -match '(?i)(?:^|\\)device\\harddiskvolume\d+\\'
            )
            if ($readOnlyTargetMatches) {
                Write-SetupLog 'Verified persistent Modrinth app-data link using its read-only target metadata.'
                return
            }

            throw "Modrinth app data points to an unexpected junction target: $reportedTarget"
        }

        if (Get-Process -Name 'Modrinth App' -ErrorAction SilentlyContinue) {
            throw 'Modrinth data needs migration but the app is running. Close Modrinth and run LimeNow again.'
        }

        foreach ($item in Get-ChildItem -LiteralPath $modrinthAppData -Force) {
            $destination = Join-Path $modrinthDataRoot $item.Name
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                $item.Name -eq 'profiles') {
                continue
            }
            if ($item.PSIsContainer) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                Get-ChildItem -LiteralPath $item.FullName -Force |
                    Copy-Item -Destination $destination -Recurse -Force
            }
            else {
                Copy-Item -LiteralPath $item.FullName -Destination $destination -Force
            }
        }

        $resolvedSource = [IO.Path]::GetFullPath($modrinthAppData)
        $resolvedParent = [IO.Path]::GetFullPath($appDataParent)
        if (-not $resolvedSource.StartsWith($resolvedParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to move an unexpected Modrinth app-data path: $resolvedSource"
        }
        $backupPath = "$modrinthAppData.limenow-backup-$([DateTime]::Now.ToString('yyyyMMddHHmmss'))"
        Move-Item -LiteralPath $modrinthAppData -Destination $backupPath
        Write-SetupLog "Migrated Modrinth app data to persistent storage; original retained at $backupPath"
    }

    New-Item -ItemType Junction -Path $modrinthAppData -Target $modrinthDataRoot | Out-Null
    Write-SetupLog "Connected Modrinth app data to persistent SalsaNOW storage: $modrinthDataRoot"
}

function Ensure-ModrinthShortcut {
    $modrinthExecutable = Join-Path $modrinthRoot 'Modrinth App.exe'
    if (-not (Test-Path -LiteralPath $modrinthExecutable)) {
        throw "Modrinth executable is missing: $modrinthExecutable"
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop 'Modrinth App.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $modrinthExecutable
    $shortcut.WorkingDirectory = $modrinthRoot
    $shortcut.Description = 'Modrinth App (LimeNow compatibility build for SalsaNOW)'
    $shortcut.IconLocation = "$modrinthExecutable,0"
    $shortcut.Save()

    $oldPrismShortcut = Join-Path $desktop 'Prism Launcher.lnk'
    if (Test-Path -LiteralPath $oldPrismShortcut) {
        Remove-Item -LiteralPath $oldPrismShortcut -Force
        Write-SetupLog 'Removed the obsolete LimeNow Prism desktop shortcut.'
    }
    Write-SetupLog 'Verified persistent Modrinth desktop shortcut.'
}

function Test-MicrosoftLoginTls {
    try {
        $response = Invoke-WebRequest `
            -Uri 'https://login.live.com/' `
            -Method Head `
            -TimeoutSec 15 `
            -MaximumRedirection 3 `
            -UseBasicParsing
        Write-SetupLog "Microsoft login TLS check succeeded (HTTP $([int]$response.StatusCode))."
    }
    catch {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            Write-SetupLog "Microsoft login TLS check succeeded (HTTP $status)."
        }
        else {
            Write-SetupLog "WARNING: Microsoft login TLS check failed: $($_.Exception.Message)"
        }
    }
}

Initialize-SetupStorage
Show-StartupProgressHeader
Write-SetupLog "LimeNow setup started. StartupMode=$Startup"

$setupSucceeded = $false
$startupHandedOff = $false
try {
    Ensure-TimeZone
    if ($Startup -and -not $SkipStartupUpdate) {
        $updateStatus = Update-LimeNowSetup
        if ($updateStatus -eq 'Updated') {
            & $canonicalScript -Startup -SkipStartupUpdate -RefreshManagedScripts
            $startupHandedOff = $true
            return
        }
        if ($updateStatus -eq 'Current') {
            $RefreshManagedScripts = $true
        }
    }
    Ensure-SetupCopies
    Ensure-StartupHook
    Assert-LimeNowNoPendingToolRecovery -SetupRoot $setupRoot
    Repair-NodeAndNpm
    Repair-Git
    Repair-GitHubCli
    Protect-GitHubCliConfig
    Ensure-GitHubCliLaunchers
    Repair-VSCode
    Repair-WindowsTerminal
    Ensure-DeveloperEnvironment
    Repair-CodexCli
    Ensure-CodexLauncher
    Repair-Chromium
    Ensure-ChromiumLauncher
    Ensure-DeveloperCommandShims
    Ensure-DeveloperDesktopShortcuts
    Ensure-GitHubCliAuthentication
    Ensure-LimeSshRemoteAccess
    Ensure-ModrinthPersistentData
    Repair-ModrinthLauncher
    Ensure-ModrinthShortcut
    Ensure-QwertzKeyboard
    if (-not $Startup) {
        Test-MicrosoftLoginTls
    }
    Write-SetupLog 'LimeNow setup completed successfully.'
    $setupSucceeded = $true
}
catch {
    Write-SetupLog "ERROR: $($_.Exception.Message)"
    if (-not $Startup) {
        throw
    }
}
finally {
    if (-not $startupHandedOff) {
        Show-StartupProgressResult -Succeeded $setupSucceeded
    }
}
