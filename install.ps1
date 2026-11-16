[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-KoboldCppStartupContent {
    param([AllowEmptyString()][string]$Content, [Parameter(Mandatory)][string]$Root)
    if ($Root -match '["\r\n%!]') { throw 'KoboldCpp startup path contains unsupported batch characters.' }
    $begin = '@rem >>> LIMENOW_KOBOLDCPP >>>'
    $end = '@rem <<< LIMENOW_KOBOLDCPP <<<'
    $pattern = '(?ms)^@rem >>> LIMENOW_KOBOLDCPP >>>\r?\n.*?^@rem <<< LIMENOW_KOBOLDCPP <<<\r?\n?'
    if (($Content.Contains($begin) -or $Content.Contains($end)) -and -not [regex]::IsMatch($Content, $pattern)) {
        throw 'Incomplete KoboldCpp startup block; leaving StartupBatch.bat unchanged.'
    }
    $unmanaged = [regex]::Replace($Content, $pattern, '')
    $manager = Join-Path $Root 'koboldcpp.ps1'
    $command = '@if exist "' + $manager + '" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' + $manager + '" -Action Repair -Root "' + $Root + '"'
    # Repair has no network or inference work. Place it before unrelated commands, including exit /b.
    return $begin + "`r`n" + $command + "`r`n" + $end + "`r`n" + $unmanaged
}

function Install-KoboldCppIntegration {
    param(
        [string]$Root = 'I:\Apps\LimeNow\KoboldCpp',
        [string]$StartupPath = 'I:\Apps\SalsaNOW\StartupBatch.bat',
        [string]$DesktopPath = [Environment]::GetFolderPath('Desktop')
    )
    if (-not (Test-Path -LiteralPath $StartupPath -PathType Leaf)) {
        throw 'Start SalsaNOW and complete the main LimeNow setup before adding local AI.'
    }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $manager = Join-Path $Root 'koboldcpp.ps1'
    $candidate = Join-Path $Root ('manager-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $hookCandidate = $StartupPath + '.koboldcpp-' + [Guid]::NewGuid().ToString('N')
    try {
        try {
            Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/koboldcpp.ps1' `
                -OutFile $candidate -UseBasicParsing -TimeoutSec 60
            $errors = $null
            [Management.Automation.Language.Parser]::ParseFile($candidate, [ref]$null, [ref]$errors) | Out-Null
            if ($errors.Count -or (Get-Content -LiteralPath $candidate -Raw) -notmatch '(?m)^# LIMENOW_KOBOLDCPP_SCRIPT\r?$') {
                throw 'The downloaded KoboldCpp manager failed validation.'
            }
            if (Test-Path -LiteralPath $manager -PathType Leaf) {
                [IO.File]::Replace($candidate, $manager, "$manager.previous", $true)
            }
            else { [IO.File]::Move($candidate, $manager) }
        }
        catch {
            if (-not (Test-Path -LiteralPath $manager -PathType Leaf)) { throw }
            Write-Warning "Could not refresh KoboldCpp manager; keeping the installed copy. $($_.Exception.Message)"
        }
        & $manager -Action Repair -Root $Root -DesktopPath $DesktopPath
        $content = [IO.File]::ReadAllText($StartupPath)
        $updated = Get-KoboldCppStartupContent -Content $content -Root $Root
        if ($updated -cne $content) {
            [IO.File]::WriteAllText($hookCandidate, $updated, [Text.UTF8Encoding]::new($false))
            [IO.File]::Replace($hookCandidate, $StartupPath, "$StartupPath.koboldcpp.previous", $true)
        }
        Write-Host 'KoboldCpp shortcut is ready. Open it to opt into the app download; no model is downloaded by setup.'
    }
    finally {
        Remove-Item -LiteralPath $candidate, $hookCandidate -Force -ErrorAction SilentlyContinue
    }
}

$lime = [char]::ConvertFromUtf32(0x1F34B) + [char]::ConvertFromUtf32(0x200D) + [char]::ConvertFromUtf32(0x1F7E9)
$sourceUrl = 'https://raw.githubusercontent.com/JohnDeved/LimeNow/main/setup.ps1'
$documents = [Environment]::GetFolderPath('MyDocuments')
$target = Join-Path $documents 'SalsaNOW-EasySetup.ps1'
$download = Join-Path ([IO.Path]::GetTempPath()) ('LimeNow-' + [Guid]::NewGuid().ToString('N') + '.ps1')

Write-Host "$lime LimeNow: preparing SalsaNOW..."

# SalsaNOW sessions can have a Central European clock mislabeled as UTC.
# Correct this before any authenticated HTTPS downloads.
try {
    Set-TimeZone -Id 'W. Europe Standard Time'
}
catch {
    Write-Warning "Could not change the time zone: $($_.Exception.Message)"
}

try {
    Invoke-WebRequest -Uri $sourceUrl -OutFile $download -UseBasicParsing -TimeoutSec 60

    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseFile(
        $download,
        [ref]$null,
        [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors) {
        throw 'The downloaded LimeNow setup script failed PowerShell syntax validation.'
    }

    Copy-Item -LiteralPath $download -Destination $target -Force
    & $target
    try { Install-KoboldCppIntegration }
    catch { Write-Warning "Optional local AI setup was skipped. $($_.Exception.Message)" }
}
finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force
    }
}

Write-Host "$lime LimeNow setup finished."
