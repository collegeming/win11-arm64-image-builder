<#
  split-file.ps1 — split a large file into sub-2 GB parts so it can be published as a
  GitHub Release asset (2 GB per-asset limit) or uploaded as an artifact.

  Parts are named <name>.part01, <name>.part02, ... and are reassembled with join-files.ps1.
  A <name>.sha256 of the whole file is written alongside so the downloader can verify.

  Usage: powershell -ExecutionPolicy Bypass -File split-file.ps1 -Path big.qcow2 -OutDir parts
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$OutDir,
    [int]$PartSizeMB = 1900
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) { throw "file not found: $Path" }
$Path = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $OutDir) { $OutDir = Join-Path (Split-Path $Path -Parent) ((Split-Path $Path -Leaf) + '.parts') }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$partBytes = [int64]$PartSizeMB * 1MB
$name = Split-Path $Path -Leaf
$total = (Get-Item -LiteralPath $Path).Length
$count = [int][math]::Ceiling($total / [double]$partBytes)

Write-Host ("[split] {0} ({1:N2} GB) -> {2} part(s) of {3} MB into {4}" -f $name, ($total / 1GB), $count, $PartSizeMB, $OutDir)

# Note: do NOT name these $in/$out — PowerShell variable names are case-insensitive and
# would collide with unrelated names; use explicit names instead.
$source = [System.IO.File]::OpenRead($Path)
try {
    $buf = New-Object byte[] (4MB)
    for ($i = 1; $i -le $count; $i++) {
        $part = Join-Path $OutDir ("{0}.part{1:D2}" -f $name, $i)
        $chunk = [System.IO.File]::Create($part)
        try {
            [int64]$written = 0
            while ($written -lt $partBytes) {
                $want = [int][math]::Min([int64]$buf.Length, $partBytes - $written)
                $n = $source.Read($buf, 0, $want)
                if ($n -le 0) { break }
                $chunk.Write($buf, 0, $n)
                $written += $n
            }
        } finally { $chunk.Dispose() }
        Write-Host ("  {0}  {1:N2} GB" -f (Split-Path $part -Leaf), ((Get-Item $part).Length / 1GB))
    }
} finally { $source.Dispose() }

$sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
$sha | Out-File (Join-Path $OutDir ($name + '.sha256')) -Encoding ascii
Write-Host "[split] sha256 $sha"
Write-Host "[split] done -> $OutDir"
