# =====================================================================
# windows_build.ps1 — entry point for Route A (x64 Windows). Edit the variables below to your own, then right-click "Run as administrator",
#   Requirements: x64 Windows (administrator), built-in dism/bcdboot/diskpart, qemu-img (QEMU for Windows; when it is
#   missing the build offers to install it with winget -- set QEMU_IMG_INSTALL=1 to skip the question).
#   Usage:  powershell -ExecutionPolicy Bypass -File windows_build.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # Relaunch elevated. UAC starts the child in System32 whatever the caller's directory was, so hand the
    # current directory over on the command line and cd back to it before the script runs.
    $cwd = (Get-Location).ProviderPath.Replace("'", "''")
    $me = $PSCommandPath.Replace("'", "''")
    Start-Process powershell "-NoExit -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$cwd'; & '$me'`"" -Verb RunAs
    exit
}



if (-not $env:SRC_ISO) { throw 'Set SRC_ISO to a genuine Windows 11 26H2 ARM64 ISO before running this entry point.' }
if (-not $env:IMAGE_INDEX) { $env:IMAGE_INDEX = '0' }
$env:OUT_QCOW      = "win11-droidvm-final.qcow2"
$env:OUT_VMPKG     = "win11-droidvm-final.vmpkg"
$env:DRIVERS_DIR   = "https://github.com/HuJK/gunyah-guest-drivers-windows/releases/download/dev/gunyah-arm64-drivers.zip"
$env:OPENSSH_SRC   = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-ARM64-v10.0.0.0.msi"

$env:DVM_USERNAME      = "USER"
$env:DVM_PASSWORD      = "DroidVM"
if (-not $env:SSH_PUBKEY) { $env:SSH_PUBKEY = '' }
if (-not $env:DROIDVM_LOCALE) { $env:DROIDVM_LOCALE = 'zh-CN' }

$env:DISK_SIZE_MB      = "40960" # 40GB
$env:VMPKG_COMPRESSION = "auto"
$env:EMS_SAC_SOURCE    = "online"

$env:DRIVER_DIR     = "ZIP/drivers"
$env:DRIVER_INSTALL = "NetKVM rdmapool pvmpower vioinput viostor vioscsi viosnd viofs"
$env:DRIVER_CERT    = "ZIP/DroidVM_Test.cer"

$env:PATH        = "C:\Program Files\qemu;" + $env:PATH
$env:QEMU_IMG_INSTALL = "1"




Write-Host "==== DroidVM Windows builder (DISM offline driver injection) ====" -ForegroundColor Cyan
& "$PSScriptRoot\windows\build.ps1"
