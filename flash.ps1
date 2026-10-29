<#
.SYNOPSIS
    Flash ZMK .uf2 firmware onto nice!nano controllers, one after another.

.DESCRIPTION
    1. Picks up the firmware: the .uf2 files in .\firmware, or - if it is newer -
       the latest firmware*.zip in your Downloads folder (the GitHub Actions
       artifact), which gets unpacked into .\firmware.
    2. Asks which .uf2 to flash (or takes it from -Firmware).
    3. Waits for a controller in bootloader mode, copies the .uf2 onto it and
       checks that it rebooted. Then waits for the next one; Ctrl+C to stop.

.PARAMETER Firmware
    Part of the .uf2 file name to flash, e.g. "left", "right", "reset".

.PARAMETER Zip
    Path to a firmware .zip to unpack instead of the newest one in Downloads.

.EXAMPLE
    .\flash.ps1 left
#>
param(
    [string]$Firmware,
    [string]$Zip
)

$ErrorActionPreference = 'Stop'
$fwDir = Join-Path $PSScriptRoot 'firmware'

function Get-DownloadsDir {
    try {
        $path = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
        if ($path -and (Test-Path $path)) { return $path }
    } catch {}
    return Join-Path $env:USERPROFILE 'Downloads'
}

function Get-Uf2Files {
    if (-not (Test-Path $fwDir)) { return @() }
    return @(Get-ChildItem -Path $fwDir -Filter '*.uf2' -Recurse | Sort-Object Name)
}

function Test-ZipHasUf2([string]$path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($path)
        try { return [bool]($archive.Entries | Where-Object { $_.Name -like '*.uf2' }) }
        finally { $archive.Dispose() }
    } catch {
        return $false
    }
}

function Update-FirmwareFromZip {
    if ($Zip) {
        $zipFile = Get-Item $Zip
        if (-not (Test-ZipHasUf2 $zipFile.FullName)) { throw "$Zip has no .uf2 files in it." }
    } else {
        # Newest firmware*.zip in Downloads that actually contains .uf2 files.
        $zipFile = Get-ChildItem -Path (Get-DownloadsDir) -Filter 'firmware*.zip' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Where-Object { Test-ZipHasUf2 $_.FullName } | Select-Object -First 1
    }
    if (-not $zipFile) { return }

    $current = Get-Uf2Files
    $newestUf2 = $current | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newestUf2 -and -not $Zip -and $newestUf2.LastWriteTime -ge $zipFile.LastWriteTime) { return }

    Write-Host "Unpacking $($zipFile.FullName)"
    if (Test-Path $fwDir) { Remove-Item -Path (Join-Path $fwDir '*') -Recurse -Force }
    Expand-Archive -Path $zipFile.FullName -DestinationPath $fwDir -Force
    # Stamp the files so a later run knows they are at least as new as the zip.
    Get-Uf2Files | ForEach-Object { $_.LastWriteTime = Get-Date }
}

function Select-Uf2 {
    $files = Get-Uf2Files
    if ($files.Count -eq 0) {
        Write-Host 'No .uf2 firmware found.' -ForegroundColor Red
        Write-Host 'Download the "firmware" artifact from the latest GitHub Actions run'
        Write-Host '(it lands in Downloads as firmware.zip) or put .uf2 files in .\firmware, then run this again.'
        exit 1
    }

    if ($Firmware) {
        $match = @($files | Where-Object { $_.Name -like "*$Firmware*" })
        if ($match.Count -eq 1) { return $match[0] }
        Write-Host "'$Firmware' matches $($match.Count) files, pick one:" -ForegroundColor Yellow
    }

    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $files[$i].Name)
    }
    while ($true) {
        $answer = Read-Host 'Firmware to flash'
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $files.Count) { return $files[$n - 1] }
    }
}

# UF2 bootloaders show up as a small removable drive with INFO_UF2.TXT in its root.
function Get-BootloaderDrive {
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'Removable') { continue }
        try {
            if ($drive.IsReady -and (Test-Path (Join-Path $drive.RootDirectory.FullName 'INFO_UF2.TXT'))) {
                return $drive.RootDirectory.FullName
            }
        } catch {}
    }
    return $null
}

function Wait-DriveGone([string]$root, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-Path (Join-Path $root 'INFO_UF2.TXT'))) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

Update-FirmwareFromZip
$uf2 = Select-Uf2
$count = 0

Write-Host ''
Write-Host "Flashing: $($uf2.Name)" -ForegroundColor Cyan
Write-Host 'Ctrl+C to stop.'

while ($true) {
    Write-Host ''
    Write-Host 'Waiting for a controller in bootloader mode...'
    Write-Host '  (new nice!nano: just plug it in; otherwise short RST to GND twice quickly)'
    $root = $null
    while (-not $root) {
        Start-Sleep -Milliseconds 300
        $root = Get-BootloaderDrive
    }

    $info = Get-Content (Join-Path $root 'INFO_UF2.TXT') -ErrorAction SilentlyContinue
    Write-Host "Found bootloader on $root" -ForegroundColor Green
    $info | ForEach-Object { Write-Host "    $_" }

    if (-not ($info -match 'nRF52840')) {
        Write-Host 'This does not look like an nRF52840 (nice!nano) bootloader - skipping it.' -ForegroundColor Yellow
        [void](Wait-DriveGone $root 3600)
        continue
    }

    try {
        Copy-Item -Path $uf2.FullName -Destination $root
    } catch {
        # The controller often reboots before Windows finishes closing the file; that is fine.
    }

    if (Wait-DriveGone $root 15) {
        $count++
        Write-Host "Flashed controller #$count - it rebooted into the new firmware." -ForegroundColor Green
        Write-Host 'Unplug it and plug in the next one.'
    } else {
        Write-Host 'The drive did not go away, so the bootloader rejected the file.' -ForegroundColor Red
        Write-Host 'Check that the firmware was built for nice_nano_v2. Unplug the controller to retry.'
        [void](Wait-DriveGone $root 3600)
    }
}
