<#
  debloat-tiny11.ps1 - offline Tiny11 Original cleanup for the DroidVM Windows image.

  The removal set follows ntdevlabs/tiny11builder 0.2.0's "Tiny11" preset
  (CleanupCatalog.ForPreset(Original)): every bundled-app option, Edge/WebView2,
  OneDrive setup binaries, XPS / Work Folders / legacy IE / Recall, and the
  Tiny11 policy set. LanguageFeatures and the legacy capability payloads are
  intentionally NOT removed, so a zh-CN image keeps its IME, fonts and OCR.

  On top of Tiny11, the caller may ask for the Core-only extras the user wants:
  Windows Update disabled, Defender disabled/removed, and WinRE removed.

  Usage (normally by build.ps1):
    debloat-tiny11.ps1 -MountDir 'X:\' [-Level standard|minimal|off] [-KeepCjk]
                       [-RemoveWindowsUpdate] [-RemoveDefender] [-RemoveRecovery]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MountDir,
    [ValidateSet('standard', 'minimal', 'off')][string]$Level = 'standard',
    [bool]$KeepCjk = $true,
    # Tiny11 Original removes Edge/WebView2. The caller can retain them; the default for
    # this image is keep, because WebView2 is a dependency of many desktop apps.
    [bool]$KeepEdge = $true,
    [switch]$RemoveWindowsUpdate,
    [switch]$RemoveDefender,
    [switch]$RemoveRecovery
)

$ErrorActionPreference = 'Continue'
$W = $MountDir.TrimEnd('\')
if ($Level -eq 'off') { Write-Host '[tiny11] disabled (level=off)'; return }

$script:removedApps = 0
$script:keptApps = 0
$script:failed = 0

function Write-Log([string]$Message, [string]$Color = 'Gray') {
    Write-Host "[tiny11] $Message" -ForegroundColor $Color
}

function Remove-PathTree([string]$Relative, [switch]$Protected) {
    $path = Join-Path $W $Relative
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        if ($Protected) {
            & takeown.exe /f $path /r /d Y *> $null
            & icacls.exe $path /grant '*S-1-5-32-544:F' /T /C *> $null
        }
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        Write-Log "removed $Relative" 'DarkGray'
        return $true
    } catch {
        $script:failed++
        Write-Log "remove failed: $Relative ($($_.Exception.Message))" 'DarkYellow'
        return $false
    }
}

function Set-RegValue([string]$Hive, [string]$Key, [string]$Name, $Value, [string]$Type = 'REG_DWORD') {
    $null = & reg.exe add "$Hive\$Key" /v $Name /t $Type /d "$Value" /f 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "registry write failed: $Hive\$Key\$Name" 'DarkYellow'
    }
}

# ---------------------------------------------------------------------------------------------
# 1) Provisioned Appx - the exact targets listed by Tiny11's "Bundled apps" options.
# ---------------------------------------------------------------------------------------------
$AppTargets = @(
    'Microsoft.Copilot', 'Microsoft.Windows.Copilot', 'Microsoft.549981C3F5F10',
    'Microsoft.OutlookForWindows', 'microsoft.windowscommunicationsapps',
    'MSTeams', 'MicrosoftTeams', 'Microsoft.Windows.Teams',
    'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch',
    'Microsoft.MicrosoftOfficeHub', 'Microsoft.OfficePushNotificationUtility',
    'Clipchamp.Clipchamp', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.YourPhone', 'Microsoft.Windows.CrossDevice',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.Windows.DevHome', 'Microsoft.PowerAutomateDesktop',
    'Microsoft.People', 'Microsoft.Todos', 'Microsoft.SkypeApp', 'MicrosoftCorporationII.MicrosoftFamily',
    'Microsoft.WindowsMaps', 'Microsoft.MixedReality.Portal',
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
    'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftStickyNotes',
    'MicrosoftCorporationII.QuickAssist',
    'Microsoft.Paint', 'Microsoft.MSPaint', 'Microsoft.Microsoft3DViewer', 'Microsoft.Office.OneNote',
    'Microsoft.WindowsCamera', 'Microsoft.WindowsTerminal',
    'AppUp.IntelManagementandSecurityStatus',
    'DolbyLaboratories.DolbyAccess', 'DolbyLaboratories.DolbyDigitalPlusDecoderOEM'
)

# Packages that must survive even if a future target list grows too far.
$KeepPatterns = @(
    'VCLibs', 'NET\.Native', 'UI\.Xaml', 'WindowsAppRuntime',
    'Store', 'StorePurchaseApp', 'DesktopAppInstaller', 'SecHealth',
    'ShellExperienceHost', 'StartMenuExperienceHost', 'Windows\.Client',
    'LanguageExperience', 'InputApp', 'AAD\.BrokerPlugin', 'AccountsControl',
    'CredDialogHost', 'LockApp', 'ParentalControls', 'ClientWebExperience'
)
if ($KeepCjk) {
    $KeepPatterns += @('LanguageFeatures', 'IME', 'zh-CN', 'zh-TW', 'Chinese')
}

function Test-AppKept([string]$Name) {
    foreach ($pattern in $KeepPatterns) { if ($Name -match $pattern) { return $true } }
    return $false
}

Write-Log "Appx pass (level=$Level, keep-cjk=$KeepCjk)" 'Cyan'
try {
    $provisioned = @(Get-AppxProvisionedPackage -Path $W -ErrorAction Stop)
    Write-Log "$($provisioned.Count) provisioned package(s) present"
    foreach ($pkg in $provisioned) {
        $display = [string]$pkg.DisplayName
        $packageName = [string]$pkg.PackageName
        $match = $null
        foreach ($target in $AppTargets) {
            if ($packageName -like "$target`_*") { $match = $target; break }
            if ($display -and $display -ieq $target) { $match = $target; break }
        }
        if (-not $match) { $script:keptApps++; continue }
        if (Test-AppKept $packageName) { $script:keptApps++; continue }
        try {
            Remove-AppxProvisionedPackage -Path $W -PackageName $packageName -ErrorAction Stop | Out-Null
            $script:removedApps++
            Write-Log "  - $display"
        } catch {
            $script:failed++
            Write-Log "  ! $display ($($_.Exception.Message))" 'DarkYellow'
        }
    }
} catch {
    Write-Log "provisioned-Appx pass skipped: $($_.Exception.Message)" 'DarkYellow'
}
Write-Log "Appx: removed=$script:removedApps kept=$script:keptApps failed=$script:failed"

# ---------------------------------------------------------------------------------------------
# 2) Edge / WebView2 files and their offline uninstall entries.
#    Tiny11 Original removes them; this image keeps them by default because WebView2 is a
#    dependency of many desktop applications. Set -KeepEdge:$false to apply the Tiny11 removal.
# ---------------------------------------------------------------------------------------------
if ($KeepEdge) {
    Write-Log 'Keeping Edge / WebView2 (Tiny11 edge-files not applied)' 'Yellow'
} else {
    Write-Log 'Removing Edge / WebView2 files'
    foreach ($base in @('Program Files', 'Program Files (x86)')) {
        foreach ($name in @('Edge', 'EdgeCore', 'EdgeUpdate', 'EdgeWebView')) {
            $null = Remove-PathTree (Join-Path $base "Microsoft\$name") -Protected
        }
    }
    $null = Remove-PathTree 'Windows\System32\Microsoft-Edge-Webview' -Protected
    $edgeStore = Join-Path $W 'Windows\WinSxS'
    if (Test-Path -LiteralPath $edgeStore) {
        Get-ChildItem -LiteralPath $edgeStore -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*microsoft-edge-webview*' } |
            ForEach-Object { $null = Remove-PathTree ("Windows\WinSxS\$($_.Name)") -Protected }
    }
}

# ---------------------------------------------------------------------------------------------
# 3) OneDrive setup binaries.
# ---------------------------------------------------------------------------------------------
foreach ($oneDrive in @('Windows\System32\OneDriveSetup.exe', 'Windows\SysWOW64\OneDriveSetup.exe')) {
    $path = Join-Path $W $oneDrive
    if (Test-Path -LiteralPath $path) {
        try {
            & takeown.exe /f $path *> $null
            & icacls.exe $path /grant '*S-1-5-32-544:F' *> $null
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            Write-Log "removed $oneDrive" 'DarkGray'
        } catch {
            $script:failed++
            Write-Log "remove failed: $oneDrive ($($_.Exception.Message))" 'DarkYellow'
        }
    }
}

# ---------------------------------------------------------------------------------------------
# 4) Tiny11 optional features (payload removal; safe to skip when absent).
# ---------------------------------------------------------------------------------------------
$featureNames = @(
    'Printing-XPSServices-Features',
    'WorkFolders-Client',
    'Internet-Explorer-Optional-arm64',
    'Internet-Explorer-Optional-amd64',
    'Recall'
)
foreach ($feature in $featureNames) {
    & dism.exe "/Image:$W" /Disable-Feature "/FeatureName:$feature" /Remove /NoRestart *> $null
    if ($LASTEXITCODE -in 0, 3010) { Write-Log "feature removed: $feature" 'DarkGray' }
    else { Write-Log "feature not removed (absent or blocked): $feature" 'DarkYellow' }
}

# ---------------------------------------------------------------------------------------------
# 5) Defender client package (Tiny11 Core behavior requested by the caller).
# ---------------------------------------------------------------------------------------------
if ($RemoveDefender) {
    Write-Log 'Removing Windows Defender client package'
    try {
        $defender = @(Get-WindowsPackage -Path $W -ErrorAction Stop |
            Where-Object { $_.PackageName -match 'Windows-Defender-Client-Package' })
        if ($defender.Count -eq 0) { Write-Log 'Defender client package not present' 'DarkYellow' }
        foreach ($pkg in $defender) {
            try {
                Remove-WindowsPackage -Path $W -PackageName $pkg.PackageName -NoRestart -ErrorAction Stop | Out-Null
                Write-Log "defender package removed: $($pkg.PackageName)" 'DarkGray'
            } catch {
                $script:failed++
                Write-Log "defender package removal failed: $($_.Exception.Message)" 'DarkYellow'
            }
        }
    } catch {
        Write-Log "defender package query failed: $($_.Exception.Message)" 'DarkYellow'
    }
}

# ---------------------------------------------------------------------------------------------
# 6) Offline registry: Tiny11 policies, VBS off, WU/Defender off, watermark cosmetic keys.
# ---------------------------------------------------------------------------------------------
$script:hives = @{}
function Mount-Hive([string]$Name, [string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Log "hive missing: $Path" 'DarkYellow'; return $false }
    & reg.exe load "HKLM\$Name" $Path *> $null
    if ($LASTEXITCODE -ne 0) { Write-Log "hive load failed: $Path" 'DarkYellow'; return $false }
    $script:hives[$Name] = $true
    return $true
}
function Unmount-Hives {
    foreach ($name in @($script:hives.Keys)) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        & reg.exe unload "HKLM\$name" *> $null
    }
    $script:hives.Clear()
}

try {
    $soft = Mount-Hive 'DVMSOFT' (Join-Path $W 'Windows\System32\config\SOFTWARE')
    $sys = Mount-Hive 'DVMSYS' (Join-Path $W 'Windows\System32\config\SYSTEM')
    $def = Mount-Hive 'DVMDEF' (Join-Path $W 'Windows\System32\config\DEFAULT')
    $nt = Mount-Hive 'DVMNT' (Join-Path $W 'Users\Default\NTUSER.DAT')
    $current = 1
    if ($sys) {
        $select = (& reg.exe query 'HKLM\DVMSYS\Select' /v Current 2>$null) -join "`n"
        if ($select -match 'Current\s+REG_DWORD\s+0x([0-9a-fA-F]+)') { $current = [Convert]::ToInt32($Matches[1], 16) }
    }
    $controlSets = @('ControlSet001')
    if ($current -ne 1) { $controlSets += ('ControlSet{0:D3}' -f $current) }

    if ($soft) {
        Write-Log 'Applying Tiny11 policies (SOFTWARE hive)'

        # ads / consumer content
        foreach ($name in @('DisableWindowsConsumerFeatures', 'DisableConsumerAccountStateContent', 'DisableCloudOptimizedContent')) {
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\CloudContent' $name 1
        }
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Teams' 'DisableInstallation' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 1

        # privacy
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1

        # Credential Guard policy value (Microsoft: LsaCfgFlags=0 disables it; deleting is not enough)
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\DeviceGuard' 'LsaCfgFlags' 0

        # copilot
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1

        # widgets / search
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' 0
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0

        # onedrive / edge
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Edge' 'HideFirstRunExperience' 1
        foreach ($name in @('HubsSidebarEnabled', 'ShowRecommendationsEnabled', 'UserFeedbackAllowed', 'SpotlightExperiencesAndRecommendationsEnabled')) {
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Edge' $name 0
        }

        # oobe
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\OOBE' 'DisablePrivacyExperience' 1
        Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 3

        # reserved storage
        Set-RegValue 'HKLM\DVMSOFT' 'Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 0

        # Edge offline uninstall entries (only when the files were removed)
        if (-not $KeepEdge) {
            foreach ($root in @('Microsoft\Windows\CurrentVersion\Uninstall', 'WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')) {
                foreach ($key in @('Microsoft Edge', 'Microsoft Edge Update', 'Microsoft EdgeWebView', 'Microsoft Edge WebView', 'Microsoft Edge WebView2 Runtime')) {
                    & reg.exe delete "HKLM\DVMSOFT\$root\$key" /f *> $null
                }
            }
        }

        if ($RemoveWindowsUpdate) {
            Write-Log 'Disabling Windows Update (Core behavior)'
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\WindowsUpdate' 'DisableWindowsUpdateAccess' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows\WindowsUpdate' 'DoNotConnectToWindowsUpdateInternetLocations' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'hide:virus;windowsupdate' 'REG_SZ'
        }
        if ($RemoveDefender) {
            Write-Log 'Disabling Windows Defender policies'
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows Defender' 'DisableAntiSpyware' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows Defender' 'DisableAntiVirus' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Policies\Microsoft\Windows Defender\Real-Time Protection' 'DisableRealtimeMonitoring' 1
            Set-RegValue 'HKLM\DVMSOFT' 'Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'hide:virus;windowsupdate' 'REG_SZ'
        }

        # Watermark cosmetics: never ask shell32 to paint the build string.
        Set-RegValue 'HKLM\DVMSOFT' 'Microsoft\Windows NT\CurrentVersion' 'PaintDesktopVersion' 0
    }

    if ($def) {
        Write-Log 'Applying Tiny11 policies (DEFAULT hive)'
        foreach ($name in @('DisableWindowsSpotlightFeatures', 'DisableThirdPartySuggestions', 'DisableTailoredExperiencesWithDiagnosticData')) {
            Set-RegValue 'HKLM\DVMDEF' 'Software\Policies\Microsoft\Windows\CloudContent' $name 1
        }
        foreach ($name in @(
            'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
            'SilentInstalledAppsEnabled', 'SoftLandingEnabled', 'SubscribedContentEnabled', 'SystemPaneSuggestionsEnabled',
            'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
            'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled'
        )) {
            Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $name 0
        }
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Input\TIPC' 'Enabled' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
        Set-RegValue 'HKLM\DVMDEF' 'Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
        Set-RegValue 'HKLM\DVMDEF' 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 0
        Set-RegValue 'HKLM\DVMDEF' 'Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
        Set-RegValue 'HKLM\DVMDEF' 'Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
        Set-RegValue 'HKLM\DVMDEF' 'Control Panel\Desktop' 'PaintDesktopVersion' 0
    }

    if ($nt) {
        # Mirror the default-profile cosmetic and privacy values into the template user hive.
        Set-RegValue 'HKLM\DVMNT' 'Control Panel\Desktop' 'PaintDesktopVersion' 0
        Set-RegValue 'HKLM\DVMNT' 'Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-RegValue 'HKLM\DVMNT' 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
        Set-RegValue 'HKLM\DVMNT' 'Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 0
        Set-RegValue 'HKLM\DVMNT' 'Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 0
    }

    if ($sys) {
        Write-Log 'Disabling VBS / HVCI / Credential Guard (SYSTEM hive)'
        # Microsoft's own values: VBS off = DeviceGuard\EnableVirtualizationBasedSecurity=0;
        # memory integrity off = Scenarios\HypervisorEnforcedCodeIntegrity\Enabled=0;
        # Credential Guard off = Control\Lsa\LsaCfgFlags=0 (and the policy key in SOFTWARE).
        # Locked=0 prevents a UEFI lock from keeping the setting alive. WasEnabledBy=0 records
        # that no enable source is configured (the docs use 2 only for a normally behaving UI).
        foreach ($cs in $controlSets) {
            $dg = "$cs\Control\DeviceGuard"
            Set-RegValue 'HKLM\DVMSYS' $dg 'EnableVirtualizationBasedSecurity' 0
            Set-RegValue 'HKLM\DVMSYS' $dg 'RequirePlatformSecurityFeatures' 0
            Set-RegValue 'HKLM\DVMSYS' $dg 'Locked' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" 'Enabled' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" 'EnabledBootId' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" 'WasEnabledBy' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\HypervisorEnforcedCodeIntegrity" 'Locked' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\CredentialGuard" 'Enabled' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\CredentialGuard" 'WasEnabledBy' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\CredentialGuard" 'Locked' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\SystemGuard" 'Enabled' 0
            Set-RegValue 'HKLM\DVMSYS' "$dg\Scenarios\KernelShadowStacks" 'Enabled' 0
            Set-RegValue 'HKLM\DVMSYS' "$cs\Control\Lsa" 'LsaCfgFlags' 0
            Set-RegValue 'HKLM\DVMSYS' "$cs\Control\BitLocker" 'PreventDeviceEncryption' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\LabConfig" 'BypassCPUCheck' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\LabConfig" 'BypassRAMCheck' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\LabConfig" 'BypassSecureBootCheck' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\LabConfig" 'BypassStorageCheck' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\LabConfig" 'BypassTPMCheck' 1
            Set-RegValue 'HKLM\DVMSYS' "$cs\Setup\MoSetup" 'AllowUpgradesWithUnsupportedTPMOrCPU' 1

            if ($RemoveWindowsUpdate) {
                foreach ($svc in @('wuauserv', 'UsoSvc', 'WaaSMedicSvc')) {
                    Set-RegValue 'HKLM\DVMSYS' "$cs\Services\$svc" 'Start' 4
                }
            }
            if ($RemoveDefender) {
                foreach ($svc in @('WinDefend', 'WdNisSvc', 'WdNisDrv', 'WdFilter', 'Sense')) {
                    Set-RegValue 'HKLM\DVMSYS' "$cs\Services\$svc" 'Start' 4
                }
            }
        }
    }
} finally {
    Unmount-Hives
}

# ---------------------------------------------------------------------------------------------
# 7) Recovery: remove WinRE payload (Tiny11 Core behavior requested by the caller).
# ---------------------------------------------------------------------------------------------
if ($RemoveRecovery) {
    Write-Log 'Removing Windows Recovery Environment payload'
    $winre = Join-Path $W 'Windows\System32\Recovery\winre.wim'
    if (Test-Path -LiteralPath $winre) {
        & takeown.exe /f $winre *> $null
        & icacls.exe $winre /grant '*S-1-5-32-544:F' *> $null
        try {
            Remove-Item -LiteralPath $winre -Force -ErrorAction Stop
            New-Item -Path $winre -ItemType File -Force | Out-Null
            Write-Log 'winre.wim replaced with an empty placeholder' 'DarkGray'
        } catch {
            Write-Log "winre.wim removal failed: $($_.Exception.Message)" 'DarkYellow'
        }
    } else {
        Write-Log 'winre.wim not present'
    }
    foreach ($recoveryDir in @('Recovery\WindowsRE')) {
        $path = Join-Path $W $recoveryDir
        if (Test-Path -LiteralPath $path) {
            & takeown.exe /f $path /r /d Y *> $null
            & icacls.exe $path /grant '*S-1-5-32-544:F' /T /C *> $null
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "removed $recoveryDir" 'DarkGray'
        }
    }
}

# ---------------------------------------------------------------------------------------------
# 8) CJK guards: verify the Chinese UI fonts and IME directories survived every removal.
# ---------------------------------------------------------------------------------------------
$cjkFonts = @('msyh.ttc', 'msyh.ttf', 'msyhbd.ttc', 'msyhl.ttc', 'simsun.ttc', 'simhei.ttf',
              'simkai.ttf', 'simfang.ttf', 'Deng.ttf', 'Dengb.ttf', 'Dengl.ttf',
              'mingliu.ttc', 'msjh.ttc', 'msjhbd.ttc', 'MicrosoftYaHei.ttf')
$fontDir = Join-Path $W 'Windows\Fonts'
if (Test-Path -LiteralPath $fontDir) {
    $have = @(Get-ChildItem -LiteralPath $fontDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $present = @($cjkFonts | Where-Object { $have -contains $_ })
    Write-Log ("CJK fonts present: {0}/{1}" -f $present.Count, $cjkFonts.Count)
    if ($KeepCjk -and $present.Count -eq 0) { Write-Log 'WARNING: no CJK font found' 'Yellow' }
}
foreach ($ime in @('CHS', 'CHT')) {
    $dir = Join-Path $W "Windows\System32\InputMethod\$ime"
    if (Test-Path -LiteralPath $dir) { Write-Log "InputMethod\$ime present (kept)" 'DarkGray' }
    elseif ($KeepCjk) { New-Item -ItemType Directory -Force -Path $dir | Out-Null; Write-Log "recreated InputMethod\$ime" 'Yellow' }
}

Write-Log "debloat complete (failed steps: $script:failed)" 'Green'
