# win11-arm64-image-builder — Chinese fork with tiny11 debloat

A fork of [Droid-VM/win11-arm64-image-builder](https://github.com/Droid-VM/win11-arm64-image-builder)
that adds three things the upstream lacks:

1. **Native Chinese (zh-CN) support** — build from a Chinese ISO and get a genuinely Chinese
   system, not an English one with a language pack bolted on.
2. **tiny11-style debloat, CJK-safe** — the removals from ntdevlabs/tiny11builder, minus the
   parts that break Chinese.
3. **Fully automated GitHub Actions build** — downloads the current official ISO and produces a
   ready-to-import `.vmpkg` with no local machine involved.

---

## Why "tiny11 + Chinese" normally breaks, and what we do differently

This is the single most important thing to understand here. tiny11builder is written for en-US
and deletes three things that Chinese Windows needs:

| What tiny11builder deletes | Why it breaks Chinese |
|---|---|
| `msyh*`, `mingli*`, `msjh*` fonts | Microsoft YaHei **is** the Chinese UI font. Removing it is the documented cause of the "boxes and garbled text" reports. |
| `LanguageFeatures-{Handwriting,OCR,Speech,TextToSpeech}-<lang>` | On a zh-CN image these carry IME, handwriting, OCR and TTS. |
| `System32\InputMethod\CHS` (Core script) | The Simplified Chinese IME payload. |

The usual workaround is to install an English tiny11 and then add a Chinese language pack — but
that path is fragile. `LanguageFeatures-*` capabilities install fine, while the
`Microsoft-Windows-Client-Language-Pack` cab famously fails with `dism` errors on a debloated
image, and `tiny11 Core` cannot accept *any* language at all because its component store is gone.
Users then resort to copying fonts by hand and restarting.

**This fork avoids the problem entirely: no language pack, no font hack.** `debloat-tiny11.ps1`
protects CJK fonts, `LanguageFeatures*`, `IME`, and `InputMethod\CHS`/`CHT` by default, so the
image keeps the Chinese resources it shipped with. Combined with a zh-CN ISO, the result is a
Chinese system with working Pinyin input and correct glyphs from first boot.

Because the UI locale must match the ISO, `unattend.xml` takes its locale from `DROIDVM_LOCALE`
(`zh-CN` by default in the workflow) instead of the hardcoded `en-US` upstream ships. Building a
zh-CN ISO without this would give the classic half-translated result: English shell chrome over
Chinese resources.

### Debloat levels

| Level | Behaviour |
|---|---|
| `standard` (default) | Removes exactly the curated tiny11 set, as frozen in `debloat-tiny11.ps1`. Low risk. |
| `minimal` | Also strips any provisioned app not in the protect-list. Smaller, slightly riskier. |
| `off` | No debloat. |

A hard protect-list always wins, regardless of level: `VCLibs`, `.NET Native`, `UI.Xaml`,
`WindowsAppRuntime`, Store/`DesktopAppInstaller` (winget), `SecHealth`, the shell and
`LanguageExperience` hosts, and — when `keep_cjk` is on — everything CJK. We never remove the
component store or Windows Update, so the image stays serviceable and patchable. That is the
deliberate difference from `tiny11 Core`: an image that cannot be updated is a poor trade for a
VM that still has to run first-boot driver enumeration on the phone.

---

## Which image should you build?

`tiny11` (the downloadable thing) and **the tiny11 builder** are different tools, and neither is
a substitute for this repository:

| | tiny11builder | this fork |
|---|---|---|
| Output | trimmed install **ISO** | bootable **qcow2 / .vmpkg** |
| VirtIO drivers | none | injected offline (required for Gunyah) |
| Boot files (UEFI, testsigning, EMS/SAC) | untouched | configured |
| Account / OOBE / RDP / SSH | MS-account bypass only | unattended, staged |
| Chinese | breaks by default (see above) | preserved natively |

A tiny11 ISO **cannot be booted directly in DroidVM**: with no VirtIO drivers the guest sees no
disk controller and no input devices, so the installer cannot even find a disk. tiny11 is only
useful as a source, and it would still need this driver-injection pipeline afterwards.

On prebuilt Chinese tiny11 ISOs floating around Chinese forums: those are ISOs, made for physical
PCs. They do not help with DroidVM for the reason above. Building from a zh-CN Microsoft ISO
through this fork gives the same Chinese experience plus the drivers and boot configuration that
a VM actually needs.

---

## Usage

### GitHub Actions (recommended — no local machine needed)

Run **Build Windows 11 ARM64 image for DroidVM** from the Actions tab. Relevant inputs:

- `iso_lang` — `Chinese (Simplified)` for a native Chinese build.
- `dvm_locale` — `zh-CN` (default) to match; set `en-US` for an English image.
- `debloat_level` — `standard` / `minimal` / `off`.
- `keep_cjk` — leave `true` unless you deliberately want the CJK pieces stripped.
- `win_release` — `26H2` (current), or `Latest`.
- `runner` — **leave on `windows-2022`**. `windows-2025`/`windows-latest` only expose ~32 GB on
  `C:` and the build needs ~50 GB. The preflight step fails fast with a clear message rather than
  producing a truncated image.

The ISO is fetched with [Fido](https://github.com/pbatard/Fido) from Microsoft's own
software-download API, so it is always the current release. Verified working for
`zh-CN` + ARM64 + 26H2:

```
Windows11_Client_arm64_zh-cn_26300_9457.iso    (~8.5 GB)
```

Output: an artifact of ~1.9 GB parts, plus a GitHub Release when `publish_release=true`
(release assets cap at 2 GB, hence the split).

### Locally on x64 Windows

```powershell
# requirements: x64 Windows with Administrator rights, qemu-img on PATH, ~50 GB free

# 1) resolve + download the current official zh-CN ARM64 ISO
Invoke-WebRequest -UseBasicParsing `
  -Uri 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' -OutFile Fido.ps1
$url = .\Fido.ps1 -Win 11 -Rel 26H2 -Ed 'Windows 11 Home/Pro/Edu' `
         -Lang 'Chinese (Simplified)' -Arch ARM64 -GetUrl | Select-Object -Last 1
curl.exe -L --retry 5 -o win11-zh.iso $url

# 2) configure and build (windows_build.ps1 self-elevates via UAC)
$env:SRC_ISO            = (Resolve-Path .\win11-zh.iso).Path
$env:DROIDVM_LOCALE     = 'zh-CN'
$env:DROIDVM_DEBLOAT_LEVEL = 'standard'
$env:DROIDVM_KEEP_CJK   = '1'
$env:DRIVER_INSTALL     = 'NetKVM rdmapool pvmpower vioinput viostor vioscsi viosnd viofs'
$env:QEMU_IMG_INSTALL   = '1'
powershell -ExecutionPolicy Bypass -File .\windows_build.ps1
```

### Reassembling the parts

```powershell
.\scripts\join-files.ps1 -PartsDir .\parts -OutFile win11-arm64.qcow2
```

Then in DroidVM: **Home → 导入虚拟机** for the `.vmpkg`.

---

## What this fork changed vs upstream

| File | Change |
|---|---|
| `windows/debloat-tiny11.ps1` | **New.** tiny11 removal set + CJK protect-list + font/IME guards. |
| `windows/build.ps1` | Step 6 now calls the module above; `install.esd` support; locale/InputLocale token substitution. |
| `windows/unattend.xml` | Locale fields tokenised (`@@LOCALE@@`, `@@INPUTLOCALE@@`) instead of hardcoded `en-US`. |
| `scripts/*.ps1` | **New.** ESD patch, image-index resolver, split/join helpers. |
| `.github/workflows/build-win11-arm64.yml` | **New.** Automated ISO → vmpkg pipeline. |

Environment variables added: `DROIDVM_DEBLOAT` (0/off disables), `DROIDVM_DEBLOAT_LEVEL`,
`DROIDVM_KEEP_CJK`, `DROIDVM_LOCALE`, `DROIDVM_INPUT_LOCALE`.

---

## Caveats

- **Snapdragon 8 Gen 3 is a known-bad host** for DroidVM (host-side Gunyah kernel issue,
  independent of this image). The image builds and is valid; booting it is a separate problem.
- **Windows on Arm under a third-party hypervisor is not supported by Microsoft.** Activation and
  licensing remain yours.
- **Only DroidVM's modified VirtIO drivers work** in a protected VM; the stock upstream VirtIO
  drivers cause a bugcheck. The driver zip used here is the patched one.
- **`debloat_level=minimal` is a blunt instrument.** On an unfamiliar ISO it can remove something
  you wanted; `standard` is the curated, tested path.
- **`install.esd` fallback costs time and space** — exporting an edition needs several GB and a few
  minutes.
