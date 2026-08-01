[CmdletBinding()]
param(
    [string]$TestParent = [IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
$setupPath = Join-Path $PSScriptRoot '..\setup.ps1'
$setupSource = Get-Content -LiteralPath $setupPath -Raw
$tokens = $null
$parseErrors = $null
$setupAst = [Management.Automation.Language.Parser]::ParseFile(
    $setupPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count) {
    throw "setup.ps1 failed syntax validation: $($parseErrors -join '; ')"
}

foreach ($functionName in @(
    'Test-GitHubCliInstall',
    'Resolve-LimeNowPowerShell',
    'Ensure-GitHubCliLaunchers',
    'Get-GitHubCliCredentialHelper'
)) {
    $definition = $setupAst.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $functionName
    }, $true)
    if (-not $definition) {
        throw "setup.ps1 is missing function $functionName."
    }
    Invoke-Expression $definition.Extent.Text
}

foreach ($requiredSetupText in @(
    "`$githubCliVersion = '2.97.0'",
    'https://github.com/cli/cli/releases/download/v2.97.0/gh_2.97.0_windows_amd64.zip',
    "`$githubCliArchiveHash = '35d7fe05c4dd1411ffda1e73dfc7c6f44b75c936ca51fa6595c657fdc0350cec'",
    'function Repair-GitHubCli',
    'function Protect-GitHubCliConfig',
    'function Ensure-GitHubCliLaunchers',
    'function Ensure-GitHubCliAuthentication',
    'function Get-GitHubCliCredentialHelper',
    "`$githubCliDeviceUrl = 'https://github.com/login/device'",
    "`$githubCliLoginScript = Join-Path `$githubCliRoot 'GitHub-CLI-Sign-In.ps1'",
    "'gh.cmd' = `$githubCliWrapper",
    'GH_CONFIG_DIR=',
    'auth git-credential',
    'Repair-GitHubCli',
    'Protect-GitHubCliConfig',
    'Ensure-GitHubCliLaunchers',
    'Ensure-GitHubCliAuthentication'
)) {
    if (-not $setupSource.Contains($requiredSetupText)) {
        throw "Setup is missing required GitHub CLI persistence integration: $requiredSetupText"
    }
}
if ($setupSource.Contains('function Remove-ObsoleteGitHubCli')) {
    throw 'Setup still removes the managed GitHub CLI installation.'
}
foreach ($aclText in @(
    "[Security.Principal.SecurityIdentifier]::new('S-1-5-18')",
    'SetAccessRuleProtection($true, $false)',
    '/inheritance:r',
    '/grant:r'
)) {
    if (-not $setupSource.Contains($aclText)) {
        throw "GitHub CLI credential protection is missing: $aclText"
    }
}

$testRoot = Join-Path $TestParent (
    'LimeNow-github-cli-persistence-test-' + [Guid]::NewGuid().ToString('N')
)
$originalAppData = $env:APPDATA
$originalHelperLog = $env:LIMENOW_GH_HELPER_LOG
$script:messages = @()

function Write-SetupLog {
    param([Parameter(Mandatory)][string]$Message)

    $script:messages += $Message
}

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Text.Contains($Expected)) {
        throw "$Message Missing '$Expected'."
    }
}

try {
    $githubCliRoot = Join-Path $testRoot 'Persistent\GitHubCLI'
    $githubCliBinRoot = Join-Path $githubCliRoot 'bin'
    $githubCliConfigRoot = Join-Path $githubCliRoot 'Config'
    $githubCliExecutable = Join-Path $githubCliBinRoot 'fake-gh.cmd'
    $githubCliWrapper = Join-Path $githubCliRoot 'gh.cmd'
    $githubCliLoginLauncher = Join-Path $githubCliRoot 'GitHub-CLI-Sign-In.cmd'
    $githubCliLoginScript = Join-Path $githubCliRoot 'GitHub-CLI-Sign-In.ps1'
    $githubCliDeviceUrl = 'https://github.com/login/device'
    $githubCliVersion = '2.97.0'
    New-Item -ItemType Directory -Path $githubCliBinRoot -Force | Out-Null
    @'
@echo off
if "%~1"=="--version" (
  echo gh version 2.97.0 ^(2026-07-31^)
  exit /b 0
)
if defined LIMENOW_GH_HELPER_LOG (
  >>"%LIMENOW_GH_HELPER_LOG%" echo CONFIG=%GH_CONFIG_DIR%
  >>"%LIMENOW_GH_HELPER_LOG%" echo ARGS=%*
)
echo CONFIG=%GH_CONFIG_DIR%
echo ARGS=%*
'@ | Set-Content -LiteralPath $githubCliExecutable -Encoding ascii

    if (-not (Test-GitHubCliInstall)) {
        throw 'The pinned-version GitHub CLI verification rejected a matching executable.'
    }
    Ensure-GitHubCliLaunchers

    foreach ($requiredPath in @(
        $githubCliWrapper,
        $githubCliLoginLauncher,
        $githubCliLoginScript
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "A managed GitHub CLI launcher was not created: $requiredPath"
        }
    }

    foreach ($profileName in @('first-gfn-profile', 'replacement-gfn-profile')) {
        $env:APPDATA = Join-Path $testRoot $profileName
        $output = (& $githubCliWrapper auth status) -join "`n"
        Assert-Contains `
            -Text $output `
            -Expected "CONFIG=$githubCliConfigRoot" `
            -Message 'The gh wrapper did not retain the persistent config directory.'
        Assert-Contains `
            -Text $output `
            -Expected 'ARGS=auth status' `
            -Message 'The gh wrapper did not preserve command arguments.'
    }

    $wrapperSource = Get-Content -LiteralPath $githubCliWrapper -Raw
    Assert-Contains `
        -Text $wrapperSource `
        -Expected "set `"GH_CONFIG_DIR=$githubCliConfigRoot`"" `
        -Message 'The managed gh command does not set persistent configuration.'

    $credentialHelper = Get-GitHubCliCredentialHelper
    Assert-Contains `
        -Text $credentialHelper `
        -Expected 'auth git-credential "$@"' `
        -Message 'The Git credential helper does not forward Git credential operations.'
    $helperLog = Join-Path $testRoot 'git-credential-helper.log'
    $env:LIMENOW_GH_HELPER_LOG = $helperLog
    $gitExecutable = Get-Command git.exe -ErrorAction Stop |
        Select-Object -ExpandProperty Source -First 1
    @"
protocol=https
host=github.com
username=fixture-user
password=fixture-password

"@ | & $gitExecutable `
        -c 'credential.helper=' `
        -c "credential.https://github.com.helper=$credentialHelper" `
        credential approve
    if ($LASTEXITCODE -ne 0) {
        throw "Git rejected the managed GitHub CLI credential helper with exit code $LASTEXITCODE."
    }
    $helperOutput = Get-Content -LiteralPath $helperLog -Raw
    Assert-Contains `
        -Text $helperOutput `
        -Expected "CONFIG=$($githubCliConfigRoot.Replace('\', '/'))" `
        -Message 'Git did not pass the persistent config directory to GitHub CLI.'
    Assert-Contains `
        -Text $helperOutput `
        -Expected 'ARGS=auth git-credential store' `
        -Message 'Git did not forward its credential operation to GitHub CLI.'

    $launcherSource = Get-Content -LiteralPath $githubCliLoginLauncher -Raw
    Assert-Contains `
        -Text $launcherSource `
        -Expected "-File `"$githubCliLoginScript`"" `
        -Message 'The sign-in command launcher does not invoke the managed PowerShell flow.'

    $loginSource = Get-Content -LiteralPath $githubCliLoginScript -Raw
    $loginTokens = $null
    $loginParseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $githubCliLoginScript,
        [ref]$loginTokens,
        [ref]$loginParseErrors
    ) | Out-Null
    if ($loginParseErrors.Count) {
        throw "The generated GitHub CLI sign-in script failed syntax validation: $($loginParseErrors -join '; ')"
    }
    foreach ($requiredLoginText in @(
        'https://github.com/login/device',
        '--hostname github.com',
        '--git-protocol https',
        '--web',
        '--scopes workflow',
        '--clipboard',
        '--insecure-storage',
        'auth refresh',
        '--json hosts',
        'reusable token in SalsaNOW persistent storage',
        "`$env:GH_BROWSER =",
        "'' | &",
        'No browser will open inside the GeForce NOW session.'
    )) {
        Assert-Contains `
            -Text $loginSource `
            -Expected $requiredLoginText `
            -Message 'The persistent GitHub CLI login flow is incomplete.'
    }
    $qrRowMatches = [regex]::Matches(
        $loginSource,
        "(?m)^\s*'(?<row>[ █▀▄]+)'\s*$"
    )
    if ($qrRowMatches.Count -ne 15) {
        throw "The offline GitHub device QR has $($qrRowMatches.Count) rows instead of 15."
    }
    $qrRows = @($qrRowMatches | ForEach-Object { $_.Groups['row'].Value })
    if ($qrRows.Where({ $_.Length -gt 29 }).Count -ne 0) {
        throw 'The offline GitHub device QR contains a row wider than its declared 29 modules.'
    }
    $qrBytes = [Text.Encoding]::UTF8.GetBytes(($qrRows -join "`n"))
    $qrHasher = [Security.Cryptography.SHA256]::Create()
    try {
        $qrHash = ($qrHasher.ComputeHash($qrBytes) | ForEach-Object { $_.ToString('x2') }) -join ''
    }
    finally {
        $qrHasher.Dispose()
    }
    if ($qrHash -ne 'd8912086f340b45cccb649220454dc144ab5ef7ae82a999ead2846fb79182f32') {
        throw "The offline GitHub device QR changed unexpectedly: $qrHash"
    }
    foreach ($forbiddenSecretText in @(
        'oauth_token:',
        'GH_TOKEN=',
        'GITHUB_TOKEN=',
        '--show-token'
    )) {
        if ($loginSource.Contains($forbiddenSecretText)) {
            throw "The login launcher embeds or handles a token directly: $forbiddenSecretText"
        }
    }

    $securityDoc = Get-Content `
        -LiteralPath (Join-Path $PSScriptRoot '..\docs\github-cli-persistence.md') `
        -Raw
    foreach ($requiredDocText in @(
        'reusable OAuth token',
        'plaintext',
        'current-user-and-SYSTEM-only ACL',
        'does not revoke the OAuth token'
    )) {
        Assert-Contains `
            -Text $securityDoc `
            -Expected $requiredDocText `
            -Message 'The GitHub CLI persistence security documentation is incomplete.'
    }

    Write-Output 'GitHub CLI persistence test passed: PinnedRelease, VerifiedArchiveHash, PersistentConfigWrapper, ReplacementProfile, HeadlessDeviceFlow, OfflineQr, InsecureStorageDisclosure, RestrictedAcl, GitCredentialRouting, CredentialOperationForwarding, NoTokenLogging'
}
finally {
    $env:APPDATA = $originalAppData
    $env:LIMENOW_GH_HELPER_LOG = $originalHelperLog
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedParent = [IO.Path]::GetFullPath($TestParent).TrimEnd('\') + '\'
        if (-not $resolvedRoot.StartsWith($resolvedParent, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolvedRoot) -notmatch '^LimeNow-github-cli-persistence-test-[a-f0-9]{32}$') {
            throw "Refusing to remove unexpected test directory: $resolvedRoot"
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}
