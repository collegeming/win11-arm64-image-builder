$ErrorActionPreference = 'Stop'
$expected = Get-Content -LiteralPath "$PSScriptRoot\image-metadata.json" -Raw | ConvertFrom-Json
$current = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = '{0}.{1}' -f $current.CurrentBuildNumber, $current.UBR
$passed = $current.EditionID -eq 'Professional' -and $current.DisplayVersion -eq $expected.display_version -and $build -eq $expected.target_build

# Evidence for the requested image tweaks. These are reported, not part of the pass/fail
# gate: the gate is still edition + version + exact target build.
$mmAgent = Get-MMAgent -ErrorAction SilentlyContinue
$deviceGuard = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction SilentlyContinue
$wu = @(Get-Service wuauserv,UsoSvc,WaaSMedicSvc -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.Name)=$($_.StartType)" }) -join ','
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
$winre = Test-Path -LiteralPath "$env:SystemRoot\System32\Recovery\winre.wim"
$edge = (Test-Path -LiteralPath "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") -or
        (Test-Path -LiteralPath "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") -or
        (Test-Path -LiteralPath "$env:SystemRoot\System32\Microsoft-Edge-Webview")
$lsa = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags -ErrorAction SilentlyContinue).LsaCfgFlags
$watermarkStrings = @()
$shellMui = Join-Path $env:SystemRoot 'System32\zh-CN\shell32.dll.mui'
if (Test-Path -LiteralPath $shellMui) {
    $bytes = [IO.File]::ReadAllBytes($shellMui)
    foreach ($text in @('测试模式', '%ws Build %ws', '评估副本。')) {
        if ([Text.Encoding]::Unicode.GetBytes($text).Length -gt 0) {
            $probe = [Text.Encoding]::Unicode.GetBytes($text)
            $found = $false
            for ($i = 0; $i -le $bytes.Length - $probe.Length; $i++) {
                $match = $true
                for ($j = 0; $j -lt $probe.Length; $j++) { if ($bytes[$i + $j] -ne $probe[$j]) { $match = $false; break } }
                if ($match) { $found = $true; break }
            }
            $watermarkStrings += "$text=$found"
        }
    }
}

$result = [ordered]@{
    passed = $passed
    edition_id = $current.EditionID
    display_version = $current.DisplayVersion
    build = $build
    required_kb = $expected.kb
    expected_build = $expected.target_build
    memory_compression = if ($mmAgent) { $mmAgent.MemoryCompression } else { $null }
    vbs_status = if ($deviceGuard) { $deviceGuard.VirtualizationBasedSecurityStatus } else { $null }
    vbs_services_running = if ($deviceGuard) { $deviceGuard.SecurityServicesRunning } else { $null }
    lsa_cfg_flags = $lsa
    edge_present = $edge
    windows_update_services = $wu
    defender_antivirus_enabled = if ($defender) { $defender.AntivirusEnabled } else { $null }
    winre_wim_present = $winre
    watermark_strings = $watermarkStrings
    verified_at = (Get-Date).ToString('o')
}
$result | ConvertTo-Json | Set-Content -LiteralPath "$PSScriptRoot\image-verification.json" -Encoding UTF8
if (-not $passed) { throw "Installed image does not match Professional $($expected.display_version) $($expected.target_build): $build" }
Write-Host "Verified Windows 11 Pro $($current.DisplayVersion), Build $build ($($expected.kb))"
Write-Host ("MMAgent MemoryCompression={0}; VBS={1}; LsaCfgFlags={2}; Edge={3}; WU={4}; WinRE={5}" -f $result.memory_compression, $result.vbs_status, $lsa, $edge, $wu, $winre)
