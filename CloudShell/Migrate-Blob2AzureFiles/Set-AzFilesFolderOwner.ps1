#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Sets the owner (only) for each top-level folder on an Azure File Share to the SID
    encoded in the folder name (e.g. DTest_S-1-12-1-... -> owner S-1-12-1-...).

.DESCRIPTION
    Run this on a Windows machine. The Azure File Share must already be mounted (e.g. Z:\ or
    \\storageaccount.file.core.windows.net\share). The script checks that the path exists at
    the start and exits if it does not; it does not mount the share or prompt for storage
    account key.

    Folder names are expected to contain a SID after the first underscore (e.g. DTest_S-1-12-1-...).
    That SID is set as the owner of the folder and all contents. ACL permissions are not changed.

.NOTES
    - Run as Administrator (or with an account that has Storage File Data SMB Share Elevated Contributor).
    - Mount the share first (e.g. net use Z: \\storageaccount.file.core.windows.net\share).
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$SharePath = ''
)

$ErrorActionPreference = 'Stop'

# Get share path: prompt if not provided
if ([string]::IsNullOrWhiteSpace($SharePath)) {
    Write-Host "`nThis script sets the owner (only) for each top-level folder on the share" -ForegroundColor Cyan
    Write-Host "using the SID in the folder name (e.g. DTest_S-1-12-1-... -> owner S-1-12-1-...)." -ForegroundColor Cyan
    Write-Host "The Azure File Share must already be mounted.`n" -ForegroundColor Cyan
    $SharePath = Read-Host "Enter the path where the Azure File Share is mounted (e.g. Z:\ or \\storageaccount.file.core.windows.net\share)"
}
$SharePath = $SharePath.Trim().TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($SharePath)) {
    Write-Host "No path entered. Exiting." -ForegroundColor Yellow
    exit 1
}

# Check that the path exists; exit if not (do not prompt for storage account or key)
if (-not (Test-Path -LiteralPath $SharePath -PathType Container)) {
    Write-Host "Path not found or not a directory: $SharePath" -ForegroundColor Red
    Write-Host "Mount the Azure File Share first (e.g. net use Z: \\storageaccount.file.core.windows.net\share), then run this script again." -ForegroundColor Yellow
    exit 1
}

# SID is the part after the first underscore (e.g. DTest_S-1-12-1-458276005-... -> S-1-12-1-458276005-...)
$folders = Get-ChildItem -LiteralPath $SharePath -Directory -Force -ErrorAction SilentlyContinue
if (-not $folders) {
    Write-Host "No subfolders found under $SharePath" -ForegroundColor Yellow
    exit 0
}

foreach ($dir in $folders) {
    $name = $dir.Name
    $idx = $name.IndexOf('_')
    if ($idx -lt 0 -or $idx -eq $name.Length - 1) {
        Write-Host "Skipping '$name' (no underscore or SID after underscore)" -ForegroundColor Gray
        continue
    }
    $sidString = $name.Substring($idx + 1).Trim()
    if ($sidString -notmatch '^S-1-') {
        Write-Host "Skipping '$name' (part after underscore is not a SID: $sidString)" -ForegroundColor Gray
        continue
    }
    try {
        $sid = New-Object System.Security.Principal.SecurityIdentifier($sidString)
    }
    catch {
        Write-Host "Skipping '$name': invalid SID '$sidString' - $_" -ForegroundColor Gray
        continue
    }

    Write-Host "Setting owner to $sidString for folder: $name" -ForegroundColor Cyan
    $items = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue)
    $itemsByPath = $items | ForEach-Object { $_.FullName } | Sort-Object -Property Length -Descending
    $count = 0
    foreach ($itemPath in $itemsByPath) {
        try {
            $acl = Get-Acl -LiteralPath $itemPath -ErrorAction Stop
            $acl.SetOwner($sid)
            Set-Acl -LiteralPath $itemPath -AclObject $acl -ErrorAction Stop
            $count++
        }
        catch {
            Write-Host "  Error at $itemPath : $_" -ForegroundColor Red
        }
    }
    # Set the folder itself (top-level folder)
    try {
        $acl = Get-Acl -LiteralPath $dir.FullName -ErrorAction Stop
        $acl.SetOwner($sid)
        Set-Acl -LiteralPath $dir.FullName -AclObject $acl -ErrorAction Stop
        $count++
    }
    catch {
        Write-Host "  Error at $($dir.FullName): $_" -ForegroundColor Red
    }
    Write-Host "  Updated owner on $count item(s)." -ForegroundColor Green
}

Write-Host "`nDone." -ForegroundColor Cyan
$unmount = Read-Host "Unmount the share now? (Y/N)"
if ($unmount -match '^Y') {
    if ($SharePath.Length -le 3 -and $SharePath -match '^[A-Za-z]:?$') {
        $drive = $SharePath.TrimEnd(':').Trim()
        if ($drive.Length -eq 1) { $drive = "${drive}:" }
        Write-Host "Unmounting ${drive}..." -ForegroundColor Gray
        $result = & net use $drive /delete 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host "Share unmounted." -ForegroundColor Green } else { Write-Warning "Unmount failed: $result" }
    } elseif ($SharePath.StartsWith('\\')) {
        Write-Host "Unmounting $SharePath..." -ForegroundColor Gray
        $result = & net use $SharePath /delete 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Host "Share unmounted." -ForegroundColor Green } else { Write-Warning "Unmount failed: $result" }
    } else {
        Write-Host "Path is not a drive letter or UNC; skipping unmount." -ForegroundColor Gray
    }
}
