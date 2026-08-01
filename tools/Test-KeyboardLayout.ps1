[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$setupSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\setup.ps1') -Raw

foreach ($requiredText in @(
    'function Ensure-LimeNowKeyboardNativeType',
    'function Get-LimeNowForegroundKeyboardLayout',
    'function Set-QwertzKeyboardState',
    'function Get-QwertzKeyboardState',
    'function Ensure-QwertzKeyboard',
    'Set-WinDefaultInputMethodOverride -InputTip $InputTip',
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
if (-not $managedBlock.Contains('"$powerShell" -NoProfile -NonInteractive')) {
    throw 'The generated startup block does not use the resolved PowerShell host.'
}

$mainStart = $setupSource.LastIndexOf('try {')
$mainEnd = $setupSource.IndexOf('catch {', $mainStart)
$mainBlock = $setupSource.Substring($mainStart, $mainEnd - $mainStart)
if ($mainBlock.IndexOf('Ensure-QwertzKeyboard') -lt
    $mainBlock.IndexOf('Ensure-ModrinthShortcut')) {
    throw 'QWERTZ verification still runs before the startup environment settles.'
}

Write-Output 'Keyboard layout regression test passed: native foreground verification, bounded retry, resolved startup host, late startup ordering'
