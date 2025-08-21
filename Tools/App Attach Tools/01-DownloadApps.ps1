<#
.SYNOPSIS
    Downloads Microsoft Store application packages using WinGet, extracts MSIX bundles and dependencies, and organizes them for installation.

.DESCRIPTION
    This script automates the download of selected Microsoft Store apps using WinGet's download functionality. 
    It saves the main MSIX bundles and any dependencies into organized folders, making them easy to install later (e.g., in offline environments).

.PARAMETER deleteDownloadedDirs
    Controls whether the temporary folders created during the download are deleted after copying the necessary files.
    - Set to $true (default) to clean up these folders after copying.
    - Set to $false to keep them for review or troubleshooting.

.CUSTOMIZATION Notes
    - Modify the `$packageIds` array to include or exclude app IDs.
        - Uncomment lines to enable specific apps.
        - App IDs (like "9MZ95KL8MR0L") can be found in the Microsoft Store URL or by using `winget search <app-name>`.
    - Change the `$downloadFolder`, `$msixDestination`, or `$dependenciesFolder` variables to control where files are stored.

.NOTES
    - Requires PowerShell 5.1+ and WinGet 1.4+ with `winget download` support.
    - You must be signed in to the Microsoft Store with a Microsoft account or Entra ID account that has permission to download packages.
        - In organizational environments, Entra ID permissions may be required to access Microsoft Store content.
        - If package downloads fail silently or with authentication errors, verify account sign-in status via the Store app or WinGet (`winget settings`).
    - No admin rights are required unless modifying protected system directories.
    - Useful for staging Store apps in enterprise, education, or offline environments.

#>





param(
    [bool]$deleteDownloadedDirs = $true #Change this to $false if you do not want to delete the directories before starting
)

# ======================= SETTINGS ===========================
$packageIds = @(
    "9MZ95KL8MR0L",  # SnippingTool
    #"9WZDNCRFHVN5",  # Calculator
    "9MSMLRH6LZF3",  # Notepad
    #"9WZDNCRFJBBG",  # Camera
    "9PCFS5B6T72H",  # Paint
    #"9WZDNCRFJ3PR",  # Clock
    #"9NBLGGH4QGHW",  # StickyNotes
    "9P1J8S7CCWWT",  # ClipChamp
    #"9WZDNCRFJB3H",  # ToDo
    "9WZDNCRFJBH4"  # Photos
    #"9N8G5RFZ9XK3"   # Terminal Preview
)

$downloadFolder     = "C:\Installs"
$msixDestination    = "$downloadFolder\MSIXBundles"
$dependenciesFolder = "$downloadFolder\Dependencies"
$failedPackages     = @()

# ======================= UTILITIES ==========================

function Confirm-Folder {
    param([string]$Path)
    if (Test-Path $Path -PathType Leaf) {
        Remove-Item $Path -Force
    }
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Confirm folders
Confirm-Folder $msixDestination
Confirm-Folder $dependenciesFolder

# Clear old contents
Remove-Item "$msixDestination\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$dependenciesFolder\*" -Recurse -Force -ErrorAction SilentlyContinue

# ======================= FUNCTIONS ==========================

function Get-PackageDownload {
    param($PackageId)

    $targetPath = Join-Path $downloadFolder $PackageId
    if (Test-Path $targetPath) {
        Remove-Item $targetPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`nDownloading $PackageId..."
    try {
        winget download --id $PackageId --accept-package-agreements --skip-microsoft-store-package-license --download-directory $targetPath | Out-Null
        return $targetPath
    } catch {
        Write-Warning "Failed to download $PackageId"
        return $null
    }
}

function Get-LatestMsixbundle {
    param($searchPath)

    $allBundles = Get-ChildItem -Path $searchPath -Recurse -Filter "*.msixbundle" -ErrorAction SilentlyContinue
    if ($allBundles.Count -eq 0) { return $null }

    $preferred = $allBundles | Where-Object { $_.Name -match "x64" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($preferred) { return $preferred }

    return $allBundles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Copy-Bundle-And-Dependencies {
    param($PackageId, $sourcePath)

    $bundle = Get-LatestMsixbundle -searchPath $sourcePath
    if (-not $bundle) {
        Write-Warning "No .msixbundle found for $PackageId"
        return $false
    }

    $destBundle = Join-Path $msixDestination $bundle.Name
    Copy-Item -Path $bundle.FullName -Destination $destBundle -Force
    Write-Host "Copied: $($bundle.Name)"

    # Dependencies (if they exist)
    $depSource = Get-ChildItem -Path $sourcePath -Recurse -Directory | Where-Object { $_.Name -eq "Dependencies" } | Select-Object -First 1
    if ($depSource) {
        $depTarget = Join-Path $dependenciesFolder $PackageId
        Confirm-Folder $depTarget
        Copy-Item -Path "$($depSource.FullName)\*" -Destination $depTarget -Recurse -Force
        Write-Host "Copied dependencies to $depTarget"
    } else {
        Write-Warning "No dependencies found for $PackageId"
    }

    return $true
}

# ======================= MAIN LOOP ==========================

foreach ($packageId in $packageIds) {
    Write-Host "`n=============================="
    Write-Host "Processing: $packageId"
    Write-Host "=============================="

    $downloadPath = Get-PackageDownload -PackageId $packageId
    if (-not $downloadPath -or -not (Test-Path $downloadPath)) {
        $failedPackages += $packageId
        continue
    }

    Start-Sleep -Milliseconds 500

    $copySuccess = Copy-Bundle-And-Dependencies -PackageId $packageId -sourcePath $downloadPath

    if ($copySuccess -and $deleteDownloadedDirs) {
        Remove-Item -Path $downloadPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned up: $downloadPath"
    } elseif (-not $copySuccess) {
        $failedPackages += $packageId
        Write-Warning "Skipped cleanup for $packageId due to copy failure."
    }
}

# ======================= SUMMARY ============================

Write-Host "`nScript complete."

if ($failedPackages.Count -gt 0) {
    Write-Host "`nThe following packages failed:"
    $failedPackages | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "`nAll packages downloaded and copied successfully."
}
