function Get-OfflineImageMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$MountDir)

    $hiveName = 'DVMVERSION_' + [guid]::NewGuid().ToString('N')
    & reg.exe load "HKLM\$hiveName" (Join-Path $MountDir 'Windows\System32\config\SOFTWARE') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not load the image SOFTWARE hive' }
    try {
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("$hiveName\Microsoft\Windows NT\CurrentVersion")
        try {
            return [pscustomobject]@{
                edition_id = [string]$key.GetValue('EditionID')
                product_name = [string]$key.GetValue('ProductName')
                display_version = [string]$key.GetValue('DisplayVersion')
                build = '{0}.{1}' -f $key.GetValue('CurrentBuildNumber'), $key.GetValue('UBR')
                architecture = 'arm64'
            }
        }
        finally { if ($key) { $key.Dispose() } }
    }
    finally {
        & reg.exe unload "HKLM\$hiveName" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not unload the image SOFTWARE hive' }
    }
}

function Assert-ImageMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Metadata,
        [Parameter(Mandatory = $true)][string]$DisplayVersion,
        [Parameter(Mandatory = $true)][string]$Build,
        [switch]$AllowPendingUpdate
    )

    if ($Metadata.edition_id -ne 'Professional') { throw "Expected Professional, got $($Metadata.edition_id)" }
    if ($Metadata.display_version -ne $DisplayVersion) { throw "Expected $DisplayVersion, got $($Metadata.display_version)" }
    if ($Metadata.build -ne $Build) {
        if (-not $AllowPendingUpdate -or ($Metadata.build.Split('.')[0] -ne $Build.Split('.')[0])) {
            throw "Expected build $Build, got $($Metadata.build)"
        }
        Write-Warning "Update is pending first boot: offline build=$($Metadata.build), required online build=$Build"
    }
}
