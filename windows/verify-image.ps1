$ErrorActionPreference = 'Stop'
$expected = Get-Content -LiteralPath "$PSScriptRoot\image-metadata.json" -Raw | ConvertFrom-Json
$current = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = '{0}.{1}' -f $current.CurrentBuildNumber, $current.UBR
$passed = $current.EditionID -eq 'Professional' -and $current.DisplayVersion -eq $expected.display_version -and $build -eq $expected.target_build
$result = [ordered]@{
    passed = $passed
    edition_id = $current.EditionID
    display_version = $current.DisplayVersion
    build = $build
    required_kb = $expected.kb
    expected_build = $expected.target_build
    verified_at = (Get-Date).ToString('o')
}
$result | ConvertTo-Json | Set-Content -LiteralPath "$PSScriptRoot\image-verification.json" -Encoding UTF8
if (-not $passed) { throw "Installed image does not match Professional $($expected.display_version) $($expected.target_build): $build" }
Write-Host "Verified Windows 11 Pro $($current.DisplayVersion), Build $build ($($expected.kb))"
