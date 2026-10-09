<#
  patch-esd-support.ps1 — make upstream windows/build.ps1 accept an ISO that ships
  sources\install.esd instead of sources\install.wim.

  Why: upstream hard-codes
      $wim = "${isoLetter}:\sources\install.wim"
      if (-not (Test-Path $wim)) { throw "$wim not found in ISO" }
  and throws on anything else. Microsoft's public (non-VL) ARM64 ISO is not
  guaranteed to carry install.wim; when it ships install.esd the build dies at
  step 2. With ESD_IMAGE_INDEX set we export the wanted edition to a real
  install.wim in the scratch dir and continue unchanged.

  Idempotent: re-running on a patched file is a no-op. If the upstream block is
  not found verbatim we FAIL LOUDLY instead of silently building a broken image —
  that means upstream changed and the patch must be re-derived.

  Usage: powershell -ExecutionPolicy Bypass -File patch-esd-support.ps1 -BuildPs1 <path\to\windows\build.ps1>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BuildPs1
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BuildPs1)) { throw "build.ps1 not found: $BuildPs1" }
$text = Get-Content -LiteralPath $BuildPs1 -Raw

$marker = 'DROIDVM-ESD-HANDLING'
if ($text.Contains($marker)) {
    Write-Host "[patch] already patched (found $marker) - nothing to do" -ForegroundColor Green
    exit 0
}

$old = @'
    $wim = "${isoLetter}:\sources\install.wim"
    if (-not (Test-Path $wim)) { throw "$wim not found in ISO" }
'@ -replace "`r`n", "`n"

$new = @'
    # DROIDVM-ESD-HANDLING: Microsoft's public ARM64 ISO may ship install.esd instead of
    # install.wim. Export the requested edition to a real wim in the scratch dir so the
    # rest of the build (dism /Apply-Image, /Add-Driver) is unchanged.
    $wim = "${isoLetter}:\sources\install.wim"
    if (-not (Test-Path $wim)) {
        $esd = "${isoLetter}:\sources\install.esd"
        if (-not (Test-Path $esd)) { throw "neither install.wim nor install.esd found in ISO ($isoLetter`:\sources\)" }
        $esdIdx = 0
        if ($env:ESD_IMAGE_INDEX) { [void][int]::TryParse($env:ESD_IMAGE_INDEX, [ref]$esdIdx) }
        if ($esdIdx -le 0) {
            throw "ISO ships install.esd and ESD_IMAGE_INDEX is not set. Set it to the edition index to export (0 = auto-pick 'Windows 11 Pro')."
        }
        Write-Host "[iso] install.esd -> exporting index $esdIdx to install.wim ..."
        $wim = Join-Path $WORK "install.wim"
        Export-WindowsImage -SourceImagePath $esd -SourceIndex $esdIdx -DestinationImagePath $wim -CompressionType Max -CheckIntegrity
        Write-Host "[iso] exported $wim ($('{0:N1} GB' -f ((Get-Item $wim).Length / 1GB)))"
    }
'@ -replace "`r`n", "`n"

# Normalize the file so the comparison is line-ending agnostic.
$normalized = $text -replace "`r`n", "`n"

if (-not $normalized.Contains($old)) {
    throw @"
[patch] FAILED: could not find the expected upstream block in $BuildPs1.
        Upstream win11-arm64-image-builder changed; re-derive this patch.
        Looked for:
$old
"@
}

$patched = $normalized.Replace($old, $new)
# Write back with CRLF (PowerShell script convention on Windows).
[System.IO.File]::WriteAllText($BuildPs1, ($patched -replace "`n", "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[patch] install.esd support patched into $BuildPs1" -ForegroundColor Green
