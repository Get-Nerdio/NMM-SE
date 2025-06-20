<#
.SYNOPSIS
    Installs or updates the latest FSLogix Version.

.DESCRIPTION
    This script:
    1. Checks if FSLogix is installed
    2. Compares installed version to the current version in the ZIP
    3. Installs or upgrades if needed

.NOTES
    Credit: u/TheScream on Reddit
    https://www.reddit.com/r/fslogix/comments/137c9nm/fslogix_powershell_silent_install_script/
#>

$FSLogixURL = "https://aka.ms/fslogix/download"
$FSLogixDownload = "FSLogixSetup.zip"
$FSLogixInstallerName = "FSLogixAppsSetup.exe"
$ZipFileToExtract = "x64/Release/FSLogixAppsSetup.exe"
$ZipPath = "$env:TEMP\$FSLogixDownload"
$InstallerPath = "$env:TEMP\$FSLogixInstallerName"
$TempExtractedForVersionCheck = "$env:TEMP\fslogix_temp_version.exe"

$downloadAndInstall = $false

# STEP 1: Check installed version via registry
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
$installedVersion = Get-ChildItem $regPath |
    Where-Object {
        ($_ | Get-ItemProperty).DisplayName -like "*FSLogix*"
    } |
    ForEach-Object {
        ($_ | Get-ItemProperty).DisplayVersion
    } |
    Select-Object -First 1

if ($installedVersion) {
    $installedVersion = [System.Version]$installedVersion
    Write-Host "Installed FSLogix version: $installedVersion"
} else {
    Write-Host "FSLogix not installed."
    $installedVersion = [System.Version]"0.0.0.0"
    $downloadAndInstall = $true
}

# STEP 2: Download latest FSLogix ZIP to TEMP (clean if already exists)
if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}
Write-Host "Downloading FSLogix ZIP..."
Import-Module BitsTransfer
Start-BitsTransfer -Source $FSLogixURL -Destination $ZipPath

# STEP 3: Extract EXE for version checking
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipFile = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)

$entry = $zipFile.Entries | Where-Object { $_.FullName -eq $ZipFileToExtract }

if (-not $entry) {
    throw "Could not find $ZipFileToExtract in the ZIP archive."
}

[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $TempExtractedForVersionCheck, $true)

# Read version from the EXE
$zipVersion = [System.Version](Get-Item $TempExtractedForVersionCheck).VersionInfo.FileVersion
Write-Host "FSLogix version in ZIP: $zipVersion"

# Clean up version-check EXE and ZIP handle
Remove-Item $TempExtractedForVersionCheck -Force
$zipFile.Dispose()

# STEP 4: Compare versions
if ($zipVersion -gt $installedVersion) {
    Write-Host "A newer version is available. Preparing to install."
    $downloadAndInstall = $true
} else {
    Write-Host "FSLogix is up to date. No action required."
}

# STEP 5: Install new version if needed
if ($downloadAndInstall) {
    Write-Host "Extracting installer..."

    # Reopen the ZIP
    $zipFile = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    $entry = $zipFile.Entries | Where-Object { $_.FullName -eq $ZipFileToExtract }

    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $InstallerPath, $true)
    $zipFile.Dispose()

    Write-Host "Running installer: $InstallerPath /install /quiet /norestart"
    Start-Process $InstallerPath -Wait -ArgumentList "/install /quiet /norestart"

    # Delay for processes to finish (some FSLogix installers spawn child processes)
    Start-Sleep -Seconds 300

    Write-Host "Cleaning up temporary files..."
    Remove-Item $InstallerPath -Force
    Remove-Item $ZipPath -Force

    Write-Host "FSLogix installation complete."
}