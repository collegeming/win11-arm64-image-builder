<#
  patch-watermark.ps1 - remove the desktop "Test Mode" / build-lab watermark offline.

  Why this exists: the image must keep BCD testsigning on, because the DroidVM-modified
  VirtIO drivers are test-signed and Windows will not boot with testsigning off (verified:
  winload rejects the test-signed boot storage driver). Windows then paints a "Test Mode"
  watermark built from shell32.dll.mui resource strings. Instead of disabling testsigning,
  blank those resource strings in-place: the RT_STRING entries stay the same length, only
  their UTF-16 characters become spaces, so no file offset or PE checksum dependency moves.

  The strings below are the zh-CN shell32 string-table entries (block 2069/2070) that make
  up the watermark and its adjacent evaluation/test wording. Every shell32.dll.mui in the
  mounted image is patched, so an en-US or other-language image with the same wording is
  covered too.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MountDir
)

$ErrorActionPreference = 'Continue'
$W = $MountDir.TrimEnd('\')

$targets = @(
    # zh-CN watermark and licence/test wording
    '测试模式',
    '受测设备',
    '评估副本。',
    '仅用于测试。',
    '%ws Build %ws',
    '%wsMicrosoft (R) Windows (R) (Build %ws%0.0ws)  %ws',
    '%wsMicrosoft (R) Windows (R) (Build %ws: %ws)  %ws',
    '%wsMicrosoft (R) Windows (R) (Build %ws%0.0ws)',
    '%wsMicrosoft (R) Windows (R) (Build %ws: %ws)',
    # English variants (same RT_STRING block on en-US images)
    'Test Mode',
    'Test mode',
    'Test device',
    'Evaluation copy.',
    'For testing only.',
    'Microsoft (R) Windows (R) (Build %ws%0.0ws)  %ws',
    'Microsoft (R) Windows (R) (Build %ws: %ws)  %ws',
    'Microsoft (R) Windows (R) (Build %ws%0.0ws)',
    'Microsoft (R) Windows (R) (Build %ws: %ws)'
)

function Replace-Utf16([byte[]]$Bytes, [string]$Text) {
    # ISO-8859-1 maps every byte 0..255 to one char and back without loss, so the whole
    # file can be searched with a normal string Replace; no resource parsing is needed.
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $pattern = $latin1.GetString([Text.Encoding]::Unicode.GetBytes($Text))
    if ($pattern.Length -eq 0) { return $Bytes }
    $replacement = ([string]([char]0x20) + [char]0) * $Text.Length
    $haystack = $latin1.GetString($Bytes)
    return $latin1.GetBytes($haystack.Replace($pattern, $replacement))
}

$files = @(Get-ChildItem -LiteralPath $W -Recurse -Filter 'shell32.dll.mui' -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { Write-Host '[watermark] no shell32.dll.mui found; nothing to patch' -ForegroundColor DarkYellow; return }

foreach ($file in $files) {
    Write-Host "[watermark] $($file.FullName)"
    try {
        & takeown.exe /f $file.FullName *> $null
        & icacls.exe $file.FullName /grant '*S-1-5-32-544:F' *> $null
        if ($file.IsReadOnly) { $file.IsReadOnly = $false }
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $before = $bytes.Length
        foreach ($target in $targets) { $bytes = Replace-Utf16 $bytes $target }
        [IO.File]::WriteAllBytes($file.FullName, $bytes)
        Write-Host ("[watermark] patched {0} bytes (size unchanged: {1})" -f $file.Name, ($before -eq $bytes.Length)) -ForegroundColor DarkGray
    } catch {
        Write-Host "[watermark] patch failed for $($file.FullName): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}
Write-Host '[watermark] done' -ForegroundColor Green
