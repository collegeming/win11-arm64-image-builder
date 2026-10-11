[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$IsoPath,
    [int]$RequestedIndex = 0
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\select-pro-image.ps1"
if (-not (Test-Path -LiteralPath $IsoPath)) { throw "ISO not found: $IsoPath" }
$IsoPath = (Resolve-Path -LiteralPath $IsoPath).ProviderPath
$mounted = Mount-DiskImage -ImagePath $IsoPath -PassThru
try {
    $letter = ($mounted | Get-Volume).DriveLetter
    if (-not $letter) { throw 'Could not determine the mounted ISO drive letter' }
    $image = @("${letter}:\sources\install.wim", "${letter}:\sources\install.esd") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $image) { throw 'Neither install.wim nor install.esd was found in the ISO' }
    Get-ProImageIndex -ImagePath $image -RequestedIndex $RequestedIndex
}
finally {
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
}
