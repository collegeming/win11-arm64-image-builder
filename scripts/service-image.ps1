[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MountDir,
    [Parameter(Mandatory = $true)][string]$CacheDir,
    [Parameter(Mandatory = $true)][string]$MetadataPath,
    [string]$UpdateManifest = "$PSScriptRoot\..\windows\updates.json"
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\image-metadata.ps1"
$update = Get-Content -LiteralPath $UpdateManifest -Raw | ConvertFrom-Json
$before = Get-OfflineImageMetadata -MountDir $MountDir
if ($before.edition_id -ne 'Professional' -or $before.display_version -ne $update.display_version) {
    throw "Source must be Windows 11 Pro $($update.display_version); got $($before.edition_id) $($before.display_version)"
}
if ([version]$before.build -gt [version]$update.build) {
    throw "Source $($before.build) is newer than the exact target $($update.build); use the matching source ISO"
}

New-Item -ItemType Directory -Force $CacheDir | Out-Null
$msu = Join-Path $CacheDir ([IO.Path]::GetFileName(([uri]$update.package.url).AbsolutePath))
if (-not (Test-Path -LiteralPath $msu)) {
    & curl.exe -L --fail --retry 5 --retry-all-errors -C - -o "$msu.part" $update.package.url
    if ($LASTEXITCODE -ne 0) { throw "Download failed for $($update.kb)" }
    Move-Item -LiteralPath "$msu.part" -Destination $msu
}
$hash = (Get-FileHash -LiteralPath $msu -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $update.package.sha256) { throw "Catalog SHA256 mismatch for $($update.kb)" }

if ($before.build -ne $update.build) {
    Write-Host "[update] Applying $($update.kb) to $($before.build), target=$($update.build)"
    & dism.exe "/Image:$MountDir" /Add-Package "/PackagePath:$msu" /NoRestart
    if ($LASTEXITCODE -notin 0, 3010) { throw "DISM update failed ($LASTEXITCODE)" }
}

$revision = $update.build.Split('.')[1]
# 24H2/25H2/26H2 share a servicing baseline; the package version can remain 26100.
$packagePattern = '~arm64~~(26100|26200|26300)\.' + [regex]::Escape($revision) + '\.'
$packages = @(Get-WindowsPackage -Path $MountDir | Where-Object {
    $_.PackageName -like '*RollupFix*' -and $_.PackageName -match $packagePattern -and
    [string]$_.PackageState -in 'Installed', 'InstallPending'
})
if (-not $packages) { throw "No installed or pending ARM64 RollupFix package for $($update.build)" }
$pending = @($packages | Where-Object { [string]$_.PackageState -eq 'InstallPending' }).Count -gt 0
$metadata = Get-OfflineImageMetadata -MountDir $MountDir
Assert-ImageMetadata -Metadata $metadata -DisplayVersion $update.display_version -Build $update.build -AllowPendingUpdate:$pending
$metadata | Add-Member -NotePropertyName target_build -NotePropertyValue $update.build
$metadata | Add-Member -NotePropertyName kb -NotePropertyValue $update.kb
$metadata | Add-Member -NotePropertyName update_sha256 -NotePropertyValue $hash
$metadata | Add-Member -NotePropertyName update_pending_first_boot -NotePropertyValue $pending
$metadata | Add-Member -NotePropertyName packages -NotePropertyValue @($packages | Select-Object PackageName, @{n='state';e={[string]$_.PackageState}})
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $MetadataPath -Encoding UTF8
Copy-Item -LiteralPath $MetadataPath -Destination (Join-Path $MountDir 'Windows\Temp\droidvm-image-metadata.json')
Write-Host ($metadata | ConvertTo-Json -Depth 6)
