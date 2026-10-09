<#
  join-files.ps1 — reassemble the parts produced by split-file.ps1 and verify the SHA256.

  Usage: powershell -ExecutionPolicy Bypass -File join-files.ps1 -PartsDir parts -Out big.qcow2
         powershell -ExecutionPolicy Bypass -File join-files.ps1 -PartsDir parts   # name taken from the parts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PartsDir,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PartsDir)) { throw "parts dir not found: $PartsDir" }

$parts = Get-ChildItem -LiteralPath $PartsDir -Filter '*.part*' | Sort-Object Name
if (-not $parts) { throw "no .partNN files in $PartsDir" }

if (-not $OutFile) {
    $base = $parts[0].Name -replace '\.part\d+$', ''
    $OutFile = Join-Path (Split-Path $PartsDir -Parent) $base
}

Write-Host ("[join] {0} part(s) -> {1}" -f $parts.Count, $OutFile)

# Note: PowerShell variable names are case-insensitive, so do NOT name this $out —
# that would alias the $OutFile parameter and break it. Same trap in split-file.ps1.
$dest = [System.IO.File]::Create($OutFile)
try {
    foreach ($p in $parts) {
        Write-Host ("  + {0}" -f $p.Name)
        $reader = [System.IO.File]::OpenRead($p.FullName)
        try { $reader.CopyTo($dest) } finally { $reader.Dispose() }
    }
} finally { $dest.Dispose() }

$shaFile = Get-ChildItem -LiteralPath $PartsDir -Filter '*.sha256' | Select-Object -First 1
if ($shaFile) {
    $want = (Get-Content -LiteralPath $shaFile.FullName -Raw).Trim()
    $got = (Get-FileHash -LiteralPath $OutFile -Algorithm SHA256).Hash
    if ($want -eq $got) {
        Write-Host "[join] sha256 OK" -ForegroundColor Green
    } else {
        Write-Host "[join] SHA256 MISMATCH: expected $want got $got" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[join] done -> $OutFile" -ForegroundColor Green
