[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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
}
finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force
    }
}

Write-Host "$lime LimeNow setup finished."
