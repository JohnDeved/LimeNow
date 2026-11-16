[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:managerSource = Join-Path $repo 'koboldcpp.ps1'
$testRoot = Join-Path $env:TEMP ('LimeNow Hook Tests ' + [Guid]::NewGuid().ToString('N'))
$checks = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    $script:checks++
    Write-Host "PASS: $Message"
}
function Assert-Throws {
    param([scriptblock]$Body, [string]$Message)
    $failed = $false
    try { & $Body } catch { $failed = $true }
    Assert-True $failed $Message
}
# Extract only the helpers; never run the real installer or full session setup in CI.
foreach ($file in @('install.ps1', 'setup.ps1')) {
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $file), [ref]$null, [ref]$errors)
    if ($errors.Count) { throw "Syntax errors in ${file}: $($errors -join '; ')" }
    $names = if ($file -eq 'install.ps1') {
        @('Get-KoboldCppStartupContent', 'Install-KoboldCppIntegration')
    } else { @('Ensure-StartupHook') }
    foreach ($name in $names) {
        $nodes = @($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
        }, $true))
        if ($nodes.Count -ne 1) { throw "Expected exactly one $name function" }
        . ([scriptblock]::Create($nodes[0].Extent.Text))
    }
}
$script:downloadMode = 'valid'
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    if ($Uri -ne 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/koboldcpp.ps1') {
        throw 'Unexpected network request in installer test'
    }
    switch ($script:downloadMode) {
        'offline' { throw 'Simulated offline session' }
        'invalid' { [IO.File]::WriteAllText($OutFile, 'not a manager') }
        'valid' { Copy-Item -LiteralPath $script:managerSource -Destination $OutFile }
    }
}
function Resolve-LimeNowPowerShell { return 'C:\Program Files\PowerShell\7\pwsh.exe' }
function Write-SetupLog { param([string]$Message) }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $root = Join-Path $testRoot 'Local AI'
    $desktop = Join-Path $testRoot 'Desktop'
    $salsaRoot = Join-Path $testRoot 'SalsaNOW'
    New-Item -ItemType Directory -Path $salsaRoot | Out-Null
    $startupBatch = Join-Path $salsaRoot 'StartupBatch.bat'
    $remoteSetupUrl = 'https://example.invalid/setup.ps1'
    $original = "@echo off`r`necho keep this command`r`nexit /b 0`r`n"
    [IO.File]::WriteAllText($startupBatch, $original)
    Install-KoboldCppIntegration -Root $root -StartupPath $startupBatch -DesktopPath $desktop
    $hook = [IO.File]::ReadAllText($startupBatch)
    Assert-True ($hook.EndsWith($original)) 'Installer preserves unrelated startup commands, including exit /b'
    Assert-True ($hook.IndexOf('-Action Repair') -lt $hook.IndexOf('exit /b')) 'Repair hook runs before an existing exit'
    Assert-True ($hook -notmatch '-Action Launch|-Action Update') 'Startup never downloads the app or starts inference'
    Assert-True (Test-Path (Join-Path $desktop 'KoboldCpp.lnk')) 'Installer creates the optional desktop shortcut'
    Assert-True (-not (Test-Path (Join-Path $root 'Application'))) 'Installer does not download an executable'
    $jsonPath = Join-Path $root 'Config\LimeNow.kcpps'
    $bytes = [IO.File]::ReadAllBytes($jsonPath)
    Assert-True ($bytes[0] -eq 123) 'Initial configuration is UTF-8 JSON without a byte-order mark'
    $config = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
    Assert-True ($config.host -eq '127.0.0.1') 'Initial launcher configuration is loopback-only'
    Install-KoboldCppIntegration -Root $root -StartupPath $startupBatch -DesktopPath $desktop
    Assert-True ([IO.File]::ReadAllText($startupBatch) -ceq $hook) 'Repeated installation is idempotent'
    $managerPath = Join-Path $root 'koboldcpp.ps1'
    $managerHash = (Get-FileHash $managerPath).Hash
    $script:downloadMode = 'offline'
    Install-KoboldCppIntegration -Root $root -StartupPath $startupBatch -DesktopPath $desktop
    Assert-True ((Get-FileHash $managerPath).Hash -eq $managerHash) 'Offline refresh retains the existing manager'
    $script:downloadMode = 'invalid'
    Install-KoboldCppIntegration -Root $root -StartupPath $startupBatch -DesktopPath $desktop
    Assert-True ((Get-FileHash $managerPath).Hash -eq $managerHash) 'Invalid download cannot replace the existing manager'
    Assert-Throws {
        Install-KoboldCppIntegration -Root (Join-Path $testRoot 'Fresh AI') -StartupPath $startupBatch -DesktopPath $desktop
    } 'Invalid first download fails without executing it'
    Assert-True ([IO.File]::ReadAllText($startupBatch) -ceq $hook) 'Failed first install leaves startup commands unchanged'
    Ensure-StartupHook
    $afterCoreRepair = [IO.File]::ReadAllText($startupBatch)
    Assert-True ($afterCoreRepair.Contains('@rem >>> LIMENOW_KOBOLDCPP >>>')) 'Core LimeNow startup repair preserves the additional AI hook'
    Assert-True ($afterCoreRepair.Contains('REM === SALSANOW EASY SETUP BEGIN ===')) 'Core LimeNow startup hook remains present'
    $updated = Get-KoboldCppStartupContent -Content $afterCoreRepair -Root $root
    Assert-True ([regex]::Matches($updated, '(?m)^@rem >>> LIMENOW_KOBOLDCPP >>>').Count -eq 1) 'AI repair does not duplicate the managed block'
    Assert-True ($updated.Contains('REM === SALSANOW EASY SETUP BEGIN ===')) 'AI repair preserves core LimeNow startup'
    Assert-Throws { Get-KoboldCppStartupContent -Content '@rem >>> LIMENOW_KOBOLDCPP >>>' -Root $root } 'Incomplete AI block is rejected'
    Assert-Throws { Get-KoboldCppStartupContent -Content '' -Root 'C:\bad%PATH%' } 'Batch-variable path injection is rejected'
    Write-Host "Passed $checks KoboldCpp integration checks."
}
finally {
    if (Test-Path $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
