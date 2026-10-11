$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\scripts\select-pro-image.ps1"
. "$root\scripts\image-metadata.ps1"

function Assert-Throws([scriptblock]$Action) {
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw 'Expected the operation to fail closed' }
}

$images = @(
    [pscustomobject]@{ImageIndex=1;ImageName='Home';EditionId='Core';Architecture=12},
    [pscustomobject]@{ImageIndex=3;ImageName='Localized Pro';EditionId='Professional';Architecture=12}
)
if ((Select-ProImage -Images $images).ImageIndex -ne 3) { throw 'Localized Pro selection failed' }
Assert-Throws { Select-ProImage -Images $images -RequestedIndex 1 }
Assert-Throws { Select-ProImage -Images @($images[0]) }
Assert-Throws { Select-ProImage -Images @($images[1], $images[1]) }
$wrongArch = [pscustomobject]@{ImageIndex=3;ImageName='Pro x64';EditionId='Professional';Architecture=9}
Assert-Throws { Select-ProImage -Images @($wrongArch) }

$metadata = [pscustomobject]@{edition_id='Professional';display_version='26H2';build='26300.9550'}
Assert-ImageMetadata -Metadata $metadata -DisplayVersion '26H2' -Build '26300.9550'
$metadata.edition_id = 'Core'
Assert-Throws { Assert-ImageMetadata -Metadata $metadata -DisplayVersion '26H2' -Build '26300.9550' }
$metadata.edition_id = 'Professional'
$metadata.build = '26300.9457'
Assert-Throws { Assert-ImageMetadata -Metadata $metadata -DisplayVersion '26H2' -Build '26300.9550' }
Assert-ImageMetadata -Metadata $metadata -DisplayVersion '26H2' -Build '26300.9550' -AllowPendingUpdate
$metadata.build = '26100.9457'
Assert-Throws { Assert-ImageMetadata -Metadata $metadata -DisplayVersion '26H2' -Build '26300.9550' -AllowPendingUpdate }

foreach ($file in Get-ChildItem $root -Filter *.ps1 -Recurse) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "PowerShell syntax errors in $($file.FullName): $errors" }
}
$vm = Get-Content "$root\vms.json" -Raw | ConvertFrom-Json
if ($vm.memory_mb -ne 1792 -or $vm.swiotlb_mb -ne 256 -or $vm.prepare_lend_mthp -ne 'disabled' -or -not $vm.screens.simplefb.enabled -or $vm.screens.'gpu-0'.enabled -or $vm.usb) { throw 'VM template does not match the tested host configuration' }
[xml](Get-Content "$root\windows\unattend.xml" -Raw) | Out-Null
Write-Host 'Edition selection, fail-closed version checks, PowerShell syntax and VM template tests passed'
