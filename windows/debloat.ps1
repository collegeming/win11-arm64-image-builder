<#
  debloat.ps1 - first-logon half of the cleanup (runs on the target as the created account).

  Offline work (build.ps1 + debloat-tiny11.ps1) already removed the Tiny11 apps,
  OneDrive setup, optional features, Defender client package and WinRE, kept Edge/WebView2
  (as requested), and wrote the Tiny11 privacy/consumer policies, VBS-off and WU-off values.

  This script finishes the parts that need a running system:
    - memory compression: verify the MMAgent default and enable only if it is off
    - telemetry / non-essential services / telemetry tasks
    - a state snapshot for verification (MMAgent, DeviceGuard, LsaCfgFlags, WU, Defender, WinRE)
  Windows Update is deliberately not re-enabled: this image follows the Core behavior
  requested for it. Failures are logged and never abort the logon.
#>
$ErrorActionPreference = 'SilentlyContinue'
$logDir = 'C:\DroidVM'
$log = Join-Path $logDir 'debloat.log'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Log([string]$m) { "{0}  {1}" -f (Get-Date -Format o), $m | Out-File -Append -Encoding utf8 $log }
Log "start (as $(whoami))"

# 1) Memory compression.
# Research note: the supported control surface is the MMAgent provider. Its state is kept in
# Sysmain's internal StoreParameters store, not in a documented registry value; the offline
# image has no explicit value there, and Windows 11 enables memory compression by default
# (the previous image reported MemoryCompression=True). Verify first, enable only when off,
# and record the observed state instead of blindly re-applying the screenshot command.
try {
    $mm = Get-MMAgent -ErrorAction Stop
    if ($mm.MemoryCompression) {
        Log "MemoryCompression already enabled (Windows default)"
    } else {
        Enable-MMAgent -MemoryCompression -ErrorAction Stop
        Log "MemoryCompression was disabled; Enable-MMAgent -MemoryCompression applied"
    }
    Log ("Get-MMAgent.MemoryCompression=" + ((Get-MMAgent).MemoryCompression))
} catch {
    Log "MemoryCompression check/enable failed: $($_.Exception.Message)"
}

# 2) Disable telemetry / ads / content push (machine policies already set offline; keep idempotent)
$telemetry = @{
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' = @{ AllowTelemetry = 1 }
  'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'   = @{ DisableWindowsConsumerFeatures = 1; DisableCloudOptimizedContent = 1 }
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' = @{ Enabled = 0 }
}
foreach ($path in $telemetry.Keys) {
  New-Item -Path $path -Force | Out-Null
  foreach ($name in $telemetry[$path].Keys) {
    New-ItemProperty -Path $path -Name $name -Value $telemetry[$path][$name] -PropertyType DWord -Force | Out-Null
  }
}
Log "telemetry / ads policies set"

# 3) Non-essential services (Windows Search is intentionally left alone: Tiny11 keeps local search)
$svc = 'DiagTrack','dmwappushservice','XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','MapsBroker','RetailDemo'
foreach ($s in $svc) {
  Set-Service -Name $s -StartupType Disabled
  Stop-Service -Name $s -Force
}
Log "services disabled: $($svc -join ', ')"

# 4) Telemetry scheduled tasks
$tasks = '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
         '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
         '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
         '\Microsoft\Windows\Feedback\Siuf\DmClient',
         '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
foreach ($t in $tasks) { Disable-ScheduledTask -TaskPath (Split-Path $t) -TaskName (Split-Path $t -Leaf) | Out-Null }
Log "telemetry tasks disabled"

# 5) Windows Update: already disabled offline (services + policies). Do not place an enable .bat;
#    this image follows the requested Core behavior. Log the actual service state.
$wu = @(Get-Service wuauserv,UsoSvc,WaaSMedicSvc -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.Name)=$($_.Status)/$($_.StartType)" }) -join ', '
Log "Windows Update state: $wu"

# 6) State snapshot for the image verification step.
$snap = Join-Path $logDir 'firstboot-state.txt'
try {
    "== MMAgent ==" | Out-File -Encoding utf8 $snap
    Get-MMAgent | Out-File -Append -Encoding utf8 $snap
    "== DeviceGuard ==" | Out-File -Append -Encoding utf8 $snap
    Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
        Select-Object VirtualizationBasedSecurityStatus, SecurityServicesRunning, SecurityServicesConfigured |
        Format-List | Out-File -Append -Encoding utf8 $snap
    "== LsaCfgFlags ==" | Out-File -Append -Encoding utf8 $snap
    Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LsaCfgFlags -ErrorAction SilentlyContinue |
        Select-Object LsaCfgFlags | Format-List | Out-File -Append -Encoding utf8 $snap
    "== Windows Update ==" | Out-File -Append -Encoding utf8 $snap
    Get-Service wuauserv,UsoSvc,WaaSMedicSvc | Select-Object Name,Status,StartType |
        Format-Table -AutoSize | Out-File -Append -Encoding utf8 $snap
    "== Defender ==" | Out-File -Append -Encoding utf8 $snap
    Get-MpComputerStatus | Select-Object AMServiceEnabled,RealTimeProtectionEnabled,AntivirusEnabled |
        Format-List | Out-File -Append -Encoding utf8 $snap
    "== Recovery ==" | Out-File -Append -Encoding utf8 $snap
    reagentc /info | Out-File -Append -Encoding utf8 $snap
} catch {
    Log "state snapshot failed: $($_.Exception.Message)"
}
Log "done"
