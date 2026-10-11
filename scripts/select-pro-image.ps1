function Select-ProImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Images,
        [int]$RequestedIndex = 0
    )

    $candidates = @($Images | Where-Object { $_.EditionId -eq 'Professional' -and [int]$_.Architecture -eq 12 })
    if ($RequestedIndex -gt 0) {
        $candidates = @($candidates | Where-Object { [int]$_.ImageIndex -eq $RequestedIndex })
    }
    if ($candidates.Count -ne 1) {
        $available = ($Images | ForEach-Object {
            '{0}: {1} (EditionId={2}, Architecture={3})' -f $_.ImageIndex, $_.ImageName, $_.EditionId, $_.Architecture
        }) -join '; '
        throw "Exactly one Windows 11 Pro ARM64 image is required (requested index=$RequestedIndex). Available: $available"
    }
    return $candidates[0]
}

function Get-ProImageIndex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ImagePath,
        [int]$RequestedIndex = 0
    )

    $images = @(Get-WindowsImage -ImagePath $ImagePath | ForEach-Object {
        Get-WindowsImage -ImagePath $ImagePath -Index $_.ImageIndex
    })
    $pick = Select-ProImage -Images $images -RequestedIndex $RequestedIndex
    Write-Host ('[image] Windows 11 Pro ARM64: index {0}, name={1}, EditionId={2}' -f $pick.ImageIndex, $pick.ImageName, $pick.EditionId)
    return [int]$pick.ImageIndex
}
