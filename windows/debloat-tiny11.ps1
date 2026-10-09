<#
  debloat-tiny11.ps1 — tiny11-style offline debloat, CJK-safe.

  Called by windows/build.ps1 (step 6) after the image is applied to $W:.

  WHAT THIS IS
    A port of ntdevlabs/tiny11builder's removal list into the offline DISM flow used by
    Droid-VM/win11-arm64-image-builder. tiny11builder builds a bootable ISO; this builds a
    disk image that must still boot on Gunyah, so the removals here are the *standard*
    tiny11 set (serviceable), never the Core set. Core deletes the component store and
    Windows Update, which would leave an image that can never be patched — and since the
    image still has to run first-boot OOBE plus driver enumeration on the phone, that is
    the wrong trade.

  CJK SAFETY — why this differs from upstream tiny11builder
    tiny11builder is written for en-US and deletes things Chinese users need:

      * Fonts: it removes `mingli*` `msjh*` `msyh*` (Microsoft YaHei) etc. Those ARE the
        Simplified/Traditional Chinese UI fonts. Removing them is the documented cause of
        the "boxes / garbled Chinese" reports. We keep every CJK font.
      * Language Features: it strips LanguageFeatures-{Basic,Handwriting,OCR,Speech,
        TextToSpeech}-<$languageCode>. On a zh-CN image those carry the IME, handwriting,
        OCR and TTS pieces. We keep them.
      * InputMethod\CHS: removed in the Core script; it is the Simplified Chinese IME
        directory. We keep it.

    Consequence: building from a zh-CN ISO yields a natively Chinese system with working
    Pinyin input and correct glyphs — no post-install language pack, no font package.

  Safety model
    Every removal is best-effort: a failure logs and continues, because a partially
    debloated image that boots is strictly better than an aborted build. The keep-list is
    applied as a regex deny-filter over provisioned Appx, so unseen packages are only
    removed when they are not protected.

  Usage (normally by build.ps1):
    debloat-tiny11.ps1 -MountDir 'X:\' [-Level standard|minimal] [-KeepCjk]
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MountDir,
    [ValidateSet('minimal', 'standard')][string]$Level = 'standard',
    # Keep CJK fonts / language features / IME. Default ON: the target device is a Chinese
    # phone and a mangled UI is a worse outcome than a slightly larger image.
    [bool]$KeepCjk = $true
)

$ErrorActionPreference = 'Continue'
$W = $MountDir.TrimEnd('\')

# --- tiny11builder's removal list, as package-name prefixes -----------------------------
# Kept verbatim in spirit from ntdevlabs/tiny11builder (tiny11maker.ps1 $packagePrefixes) so
# behaviour matches a known-good tiny11. Matching is "contains", mirroring upstream.
$Tiny11Prefixes = @(
    'AppUp.IntelManagementandSecurityStatus'
    'Clipchamp.Clipchamp'
    'DolbyLaboratories.DolbyAccess'
    'DolbyLaboratories.DolbyDigitalPlusDecoderOEM'
    'Microsoft.BingNews'
    'Microsoft.BingSearch'
    'Microsoft.BingWeather'
    'Microsoft.Copilot'
    'Microsoft.Windows.CrossDevice'
    'Microsoft.GamingApp'
    'Microsoft.GetHelp'
    'Microsoft.Getstarted'
    'Microsoft.Microsoft3DViewer'
    'Microsoft.MicrosoftOfficeHub'
    'Microsoft.MicrosoftSolitaireCollection'
    'Microsoft.MicrosoftStickyNotes'
    'Microsoft.MixedReality.Portal'
    'Microsoft.MSPaint'
    'Microsoft.Office.OneNote'
    'Microsoft.OfficePushNotificationUtility'
    'Microsoft.OutlookForWindows'
    'Microsoft.People'
    'Microsoft.PowerAutomateDesktop'
    'Microsoft.SkypeApp'
    'Microsoft.StartExperiencesApp'
    'Microsoft.Todos'
    'Microsoft.Wallet'
    'Microsoft.Windows.DevHome'
    'Microsoft.Windows.Copilot'
    'Microsoft.Windows.Teams'
    'Microsoft.WindowsAlarms'
    'Microsoft.WindowsCamera'
    'microsoft.windowscommunicationsapps'
    'Microsoft.WindowsFeedbackHub'
    'Microsoft.WindowsMaps'
    'Microsoft.WindowsSoundRecorder'
    'Microsoft.Xbox.TCUI'
    'Microsoft.XboxApp'
    'Microsoft.XboxGameOverlay'
    'Microsoft.XboxGamingOverlay'
    'Microsoft.XboxIdentityProvider'
    'Microsoft.XboxSpeechToTextOverlay'
    'Microsoft.YourPhone'
    'Microsoft.ZuneMusic'
    'Microsoft.ZuneVideo'
    'MicrosoftCorporationII.MicrosoftFamily'
    'MicrosoftCorporationII.QuickAssist'
    'MSTeams'
    'MicrosoftTeams'
    'Microsoft.549981C3F5F10'
)

# --- Hard keep-list: never remove these, whatever the removal list says -----------------
# A small image that cannot boot or cannot install its drivers is worthless, so the
# runtime/framework packages and the Store stack are protected explicitly.
$KeepPattern = @(
    'VCLibs'                 # VCLibs / VCLibs.Desktop - dependency of many frameworks
    'NET\.Native'
    'UI\.Xaml'
    'WindowsAppRuntime'      # WinAppSDK runtime; several inbox apps hard-depend on it
    'Store'                  # Microsoft Store
    'StorePurchaseApp'
    'DesktopAppInstaller'    # winget
    'SecHealth'              # Windows Security UI
    'Notepad'
    'Photos'
    'Terminal'
    'WindowsTerminal'
    'Calculator'             # cheap, genuinely used, tiny
    'Paint'
    'SnippingTool'
    'WebpImageExtension'
    'RawImageExtension'
    'HEIFImageExtension'
    'VP9VideoExtensions'
    'WebMediaExtensions'
    'ShellExperienceHost'
    'StartMenuExperienceHost'
    'Windows.Client'         # shell / search / settings host packages
    'LanguageExperience'     # language/IME surface - do not remove on any locale
    'InputApp'
    'Microsoft.Windows.CloudExperienceHost'
    'AAD.BrokerPlugin'
    'AccountsControl'
    'CredDialogHost'
    'LockApp'
    'ParentalControls'
    'ClientWebExperience'
    'XboxGamingOverlay$'     # Game Bar is in the remove list upstream; keep on a tablet
)

# CJK-protected patterns, only applied when -KeepCjk.
$CjkKeep = @(
    'LanguageExperience'
    'LanguageFeatures'       # Basic / Handwriting / OCR / Speech / TextToSpeech
    'IME'
    'zh-CN'
    'zh-TW'
    'Chinese'
)

function Test-Protected([string]$Name, [bool]$Cjk) {
    foreach ($p in $KeepPattern) { if ($Name -match $p) { return $true } }
    if ($Cjk) { foreach ($p in $CjkKeep) { if ($Name -match $p) { return $true } } }
    return $false
}

function Test-Removable([string]$Name) {
    foreach ($p in $Tiny11Prefixes) { if ($Name -like "*$p*") { return $true } }
    return $false
}

Write-Host "[tiny11] debloat (level=$Level, keep-cjk=$KeepCjk) on $W" -ForegroundColor Cyan

# === 1) Provisioned Appx ============================================================================
# Two modes:
#   standard -> remove only what tiny11builder removes (curated, low risk)
#   minimal  -> also remove any other non-protected provisioned app (more aggressive)
$removed = 0; $kept = 0; $failed = 0
try {
    $prov = @(Get-AppxProvisionedPackage -Path $W -ErrorAction Stop)
    Write-Host "[tiny11] $($prov.Count) provisioned package(s) present"
    foreach ($pkg in $prov) {
        $name = $pkg.DisplayName
        if (-not $name) { continue }

        if (Test-Protected $name $KeepCjk) { $kept++; continue }

        $shouldRemove = Test-Removable $name
        if (-not $shouldRemove -and $Level -eq 'minimal') { $shouldRemove = $true }

        if ($shouldRemove) {
            try {
                Remove-AppxProvisionedPackage -Path $W -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                $removed++
                Write-Host ("  - {0}" -f $name) -ForegroundColor DarkGray
            } catch {
                $failed++
                Write-Host ("  ! {0}  ({1})" -f $name, $_.Exception.Message) -ForegroundColor DarkYellow
            }
        } else {
            $kept++
        }
    }
} catch {
    Write-Host "[tiny11] provisioned-Appx pass skipped: $($_.Exception.Message)" -ForegroundColor DarkYellow
}
Write-Host "[tiny11] Appx: removed=$removed kept=$kept failed=$failed"

# === 2) Capability / language-feature packages ======================================================
# On a zh-CN image the LanguageFeatures capabilities carry IME + OCR + handwriting. tiny11builder
# deletes them (that is the documented cause of broken Chinese). We delete them ONLY when the
# caller opted out of CJK preservation, and even then we never touch a *-Basic-* package.
if (-not $KeepCjk) {
    Write-Host "[tiny11] removing non-CJK language features ..." -ForegroundColor DarkYellow
    try {
        $pkgs = @(Get-WindowsPackage -Path $W -ErrorAction Stop |
                  Where-Object { $_.PackageName -match 'LanguageFeatures' -and $_.PackageName -notmatch 'LanguageFeatures-Basic' })
        foreach ($p in $pkgs) {
            try { Remove-WindowsPackage -Path $W -PackageName $p.PackageName -NoRestart -ErrorAction Stop | Out-Null }
            catch { Write-Host ("  ! {0}" -f $p.PackageName) -ForegroundColor DarkYellow }
        }
    } catch { Write-Host "  (language-feature pass skipped: $($_.Exception.Message))" -ForegroundColor DarkYellow }
} else {
    Write-Host "[tiny11] keeping LanguageFeatures / IME capabilities (CJK preserved)" -ForegroundColor Green
}

# === 3) CJK font guard ==============================================================================
# tiny11builder deletes msyh*/mingli*/msjh* and friends. That is exactly what turns Chinese text
# into boxes. Nothing here deletes fonts; this pass only *restores* awareness — if a CJK font is
# somehow missing we say so loudly instead of shipping a system that cannot render its own UI.
$cjkFonts = @('msyh.ttc', 'msyh.ttf', 'msyhbd.ttc', 'msyhl.ttc',
              'simsun.ttc', 'simhei.ttf', 'simkai.ttf', 'simfang.ttf',
              'Deng.ttf', 'Dengb.ttf', 'Dengl.ttf',
              'mingliu.ttc', 'msjh.ttc', 'msjhbd.ttc',
              'MicrosoftYaHei.ttf')
$fontDir = Join-Path $W 'Windows\Fonts'
if (Test-Path $fontDir) {
    $have = @(Get-ChildItem -Path $fontDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    $present = @($cjkFonts | Where-Object { $have -contains $_ })
    Write-Host ("[tiny11] CJK fonts present: {0}/{1}" -f $present.Count, $cjkFonts.Count)
    if ($KeepCjk -and $present.Count -eq 0) {
        Write-Host "[tiny11] WARNING: no CJK font found. If this is a zh-CN build the UI will show boxes." -ForegroundColor Yellow
    }
}

# === 4) InputMethod\CHS + CHT guard =================================================================
# The Simplified/Traditional Chinese IME payload lives here. tiny11 Core deletes it; we must not.
# We only verify, and recreate the directory if a previous tool left it missing.
foreach ($ime in @('CHS', 'CHT')) {
    $dir = Join-Path $W "Windows\System32\InputMethod\$ime"
    if (Test-Path $dir) { Write-Host "[tiny11] InputMethod\$ime present (kept)" -ForegroundColor DarkGray }
    elseif ($KeepCjk) {
        # Recreate empty rather than fatal: Windows repopulates it, and an absent directory is
        # what actually breaks IME registration.
        New-Item -ItemType Directory -Force $dir | Out-Null
        Write-Host "[tiny11] recreated missing InputMethod\$ime" -ForegroundColor Yellow
    }
}

Write-Host "[tiny11] debloat complete" -ForegroundColor Green
