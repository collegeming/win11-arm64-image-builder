# Fork documentation entry point

Despite this file's historical name, it is an English compatibility entry point. The [Simplified Chinese README](README.md) is the authoritative fork overview, covering build requirements, Chinese preservation, split-file verification, credentials and licensing.

This fork builds Windows 11 ARM64 `.qcow2` disks and DroidVM `.vmpkg` packages from an official Microsoft ISO with modified Gunyah/VirtIO drivers. The Windows/DISM route is the primary path. The retained macOS route is experimental and unvalidated in this fork; equivalent outputs are not claimed.

## Targets are not test results

The new build targets **Windows 11 Pro 26H2, 26300.9550, with KB5124010**. This target has not yet been validated on the phone. Image selection must use `EditionID=Professional` and `Architecture=12`, fail unless the match is unique, and never silently fall back to index 1. Official update packages must be applied after the OS image and before `ResetBase`; `image-metadata.json` must report actual values and any pending servicing state rather than repeat the requested target.

The prior K70 Pro boot result was **Home 26H2, 26300.9457**, not Pro. See the [K70 Pro validation record](docs/k70pro.md) for the tested host, app and VM configuration, the old release's edition-selection issue, and the limits of that evidence.

## Navigation

- [Build, download, SHA256 verification and import](README.md#下载校验与导入): keep each output's parts and checksum in a separate directory; use the script's exact `-PartsDir` and `-OutFile` parameters.
- [Chinese preservation and debloat levels](README.md#中文保留与精简): `standard`, `minimal`, and `off`; do not equate app-removal settings with all first-logon service settings.
- [Phone configuration and safety](README.md#手机配置与安全): change the default `USER` / `DroidVM` credentials before networking. Networking is optional and untested in the recorded phone run; the target template has no network. RDP hosting requires Pro.
- [Upstream Windows implementation notes](windows/README.md): retained for technical detail, not evidence of this fork's measured size or validated defaults.
- [Retained macOS implementation](macos/): unvalidated experimental path.
- [Original upstream project](https://github.com/Droid-VM/win11-arm64-image-builder).

Driver certificates and test-signing settings are not an activation mechanism. This project includes neither firmware-flashing instructions nor piracy activators; Windows licensing remains the user's responsibility.
