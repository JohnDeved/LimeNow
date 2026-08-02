[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$setupSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\setup.ps1') -Raw

foreach ($requiredText in @(
    'function Ensure-LimeNowKeyboardNativeType',
    'function Convert-LimeNowKeyboardHandleToId',
    'function Get-LimeNowForegroundKeyboardLayout',
    'function Get-LimeNowUserLanguageList',
    'function New-LimeNowTypedUserLanguageList',
    'function Ensure-LimeNowTaskbarInputIndicator',
    'function Set-QwertzKeyboardState',
    'function Get-QwertzKeyboardState',
    'function Ensure-QwertzKeyboard',
    'Set-WinDefaultInputMethodOverride -InputTip $InputTip',
    'Set-WinLanguageBarOption -ErrorAction Stop',
    "-Name 'ShowStatus'",
    "-Value 4",
    "`$englishLanguageTag = 'en-US'",
    "`$englishInputTip = '0409:00000409'",
    '[BitConverter]::ToUInt32',
    'WmInputLangChangeRequest',
    'Start-Sleep -Seconds $retryDelaySeconds',
    'ActiveIsQwertz'
)) {
    if (-not $setupSource.Contains($requiredText)) {
        throw "Keyboard setup is missing required behavior: $requiredText"
    }
}

$keyboardStart = $setupSource.IndexOf('function Ensure-QwertzKeyboard')
$keyboardEnd = $setupSource.IndexOf('function Test-NodeInstall', $keyboardStart)
if ($keyboardStart -lt 0 -or $keyboardEnd -le $keyboardStart) {
    throw 'Could not locate the bounded QWERTZ retry function.'
}
$keyboardBlock = $setupSource.Substring($keyboardStart, $keyboardEnd - $keyboardStart)
foreach ($requiredKeyboardText in @(
    'for ($attempt = 1; $attempt -le $maxAttempts; $attempt++)',
    'if ($attempt -lt $maxAttempts)',
    'Write-SetupLog "WARNING: German QWERTZ was not verified'
)) {
    if (-not $keyboardBlock.Contains($requiredKeyboardText)) {
        throw "QWERTZ retry behavior is incomplete: $requiredKeyboardText"
    }
}

$managedBlockStart = $setupSource.IndexOf('$managedBlock = @"')
$managedBlockEnd = $setupSource.IndexOf('"@', $managedBlockStart)
if ($managedBlockStart -lt 0 -or $managedBlockEnd -le $managedBlockStart) {
    throw 'Could not locate the generated SalsaNOW startup block.'
}
$managedBlock = $setupSource.Substring($managedBlockStart, $managedBlockEnd - $managedBlockStart)
if ($managedBlock -match '(?i)\bPowerShell\.exe\b') {
    throw 'The generated startup block still invokes blocked legacy PowerShell.'
}
if (-not $managedBlock.Contains('"$powerShell" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SALSANOW_SETUP_MAIN%" -Startup')) {
    throw 'The generated startup block does not invoke the resolved PowerShell host directly.'
}
if ($managedBlock.Contains('start "LimeNow setup"') -or
    $managedBlock.Contains('-NonInteractive') -or
    $managedBlock.Contains('startup.log')) {
    throw 'The generated startup block still creates a redundant or hidden setup window.'
}

$mainStart = $setupSource.LastIndexOf('try {')
$mainEnd = $setupSource.IndexOf('catch {', $mainStart)
$mainBlock = $setupSource.Substring($mainStart, $mainEnd - $mainStart)
if ($mainBlock.IndexOf('Ensure-QwertzKeyboard') -lt
    $mainBlock.IndexOf('Ensure-ModrinthShortcut')) {
    throw 'QWERTZ verification still runs before the startup environment settles.'
}

Write-Output 'Keyboard layout regression test passed: typed language-list repair, selectable taskbar indicator, native foreground verification, bounded retry, visible resolved startup host, late startup ordering'
