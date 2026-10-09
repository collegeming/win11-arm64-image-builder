<#
  resolve-image-index.ps1 — mount a Windows ISO and print the edition index to build.

  CI cannot answer upstream's interactive "Select image index" prompt (build.ps1
  throws when IMAGE_INDEX is unset and stdin is redirected), so we resolve the index
  ahead of time by name. Defaults to the first edition whose name matches ^Windows 11 Pro$
  (the ARM64 consumer ISO ships Home / Home N / Home SL / Education / Pro / Pro N ...).

  Works for install.wim AND install.esd (Get-WindowsImage reads both).

  Prints the index to stdout; all noise goes to stderr so it can be captured.
  Usage: powershell -ExecutionPolicy Bypass -File resolve-image-index.ps1 -IsoPath x.iso -Match '^Windows 11 Pro$'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [string]$Match = '^Windows 11 Pro$'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }
$IsoPath = (Resolve-Path -LiteralPath $IsoPath).ProviderPath

$mr = Mount-DiskImage -ImagePath $IsoPath -PassThru
try {
    $letter = ($mr | Get-Volume).DriveLetter
    if (-not $letter) { throw "could not determine the mounted ISO drive letter" }

    $img = $null
    foreach ($cand in @("${letter}:\sources\install.wim", "${letter}:\sources\install.esd")) {
        if (Test-Path $cand) { $img = $cand; break }
    }
    if (-not $img) { throw "neither install.wim nor install.esd found in $letter`:\sources\" }

    $images = @(Get-WindowsImage -ImagePath $img)
    Write-Host "[iso] $img carries $($images.Count) edition(s):" -ForegroundColor Cyan
    foreach ($im in $images) {
        Write-Host ("  [{0}] {1}" -f $im.ImageIndex, $im.ImageName) -ForegroundColor DarkGray
    }

    $pick = $images | Where-Object { $_.ImageName -match $Match } | Select-Object -First 1
    if (-not $pick) {
        $pick = $images | Select-Object -First 1
        Write-Host "[iso] no edition matched '$Match' -> falling back to index $($pick.ImageIndex) ($($pick.ImageName))" -ForegroundColor DarkYellow
    } else {
        Write-Host "[iso] matched '$Match' -> index $($pick.ImageIndex) ($($pick.ImageName))" -ForegroundColor Green
    }

    # stdout: the bare index, for the caller to capture.
    Write-Output $pick.ImageIndex
}
finally {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}
